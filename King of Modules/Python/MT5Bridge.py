"""
KING QUANT 5.0 — MetaTrader 5 Bridge
In live mode, delegates signal, SL, and TP resolution to KOM's entries_engine().
"""

import pandas as pd
from typing import Optional

from Config import cfg
from logger import get_logger

logger = get_logger(__name__)

# ---------------------------------------------------------------------------
# MT5 connection config (bridge-local — not in KOM EAConfig)
# ---------------------------------------------------------------------------

MT5_LOGIN    = 0
MT5_PASSWORD = ""
MT5_SERVER   = ""
MT5_TIMEOUT  = 10000
MT5_PATH     = ""

MT5_TIMEFRAME_MAP = {
    "M1":  1,
    "M5":  5,
    "M15": 15,
    "M30": 30,
    "H1":  16385,
    "H4":  16388,
    "D1":  16408,
}

# ---------------------------------------------------------------------------
# Conditional MT5 import
# ---------------------------------------------------------------------------

try:
    import MetaTrader5 as mt5
    _MT5_AVAILABLE = True
except ImportError:
    _MT5_AVAILABLE = False
    logger.warning(
        "MetaTrader5 package not installed. "
        "Live trading and data feed will be unavailable."
    )


# ---------------------------------------------------------------------------
# Connection management
# ---------------------------------------------------------------------------

def connect() -> bool:
    if not _MT5_AVAILABLE:
        logger.error("Cannot connect: MetaTrader5 package is not installed.")
        return False

    if not cfg.enable_live_feed and not cfg.enable_trading:
        logger.info("Live feed and trading are DISABLED — skipping MT5 connection.")
        return False

    logger.info("Connecting to MetaTrader 5 ...")

    init_kwargs: dict = {"timeout": MT5_TIMEOUT}
    if MT5_PATH:
        init_kwargs["path"] = MT5_PATH

    if not mt5.initialize(**init_kwargs):
        logger.error("MT5 initialize() failed: %s", mt5.last_error())
        return False

    if MT5_LOGIN and MT5_PASSWORD and MT5_SERVER:
        if not mt5.login(login=MT5_LOGIN, password=MT5_PASSWORD, server=MT5_SERVER):
            logger.error("MT5 login failed: %s", mt5.last_error())
            mt5.shutdown()
            return False
        logger.info("MT5 login successful — account #%d on %s", MT5_LOGIN, MT5_SERVER)
    else:
        logger.info("No MT5 credentials configured — using open terminal session.")

    info = mt5.terminal_info()
    logger.info(
        "MT5 terminal connected | Build=%s | Path=%s",
        info.build if info else "?",
        info.path  if info else "?",
    )
    return True


def disconnect() -> None:
    if not _MT5_AVAILABLE:
        return
    mt5.shutdown()
    logger.info("MT5 terminal disconnected.")


# ---------------------------------------------------------------------------
# Data fetching
# ---------------------------------------------------------------------------

def fetch_ohlcv(
    symbol:        str = None,
    timeframe_str: str = "H1",
    n_bars:        int = None,
) -> pd.DataFrame:
    symbol = symbol or cfg.symbol
    n_bars = n_bars or cfg.bars_to_fetch

    if not cfg.enable_live_feed:
        logger.debug("Live feed is DISABLED — returning empty DataFrame.")
        return pd.DataFrame()

    if not _MT5_AVAILABLE:
        logger.error("MT5 package not available — cannot fetch OHLCV.")
        return pd.DataFrame()

    tf = MT5_TIMEFRAME_MAP.get(timeframe_str.upper())
    if tf is None:
        logger.error(
            "Unknown timeframe '%s'. Valid keys: %s",
            timeframe_str,
            list(MT5_TIMEFRAME_MAP),
        )
        return pd.DataFrame()

    logger.info("Fetching %d %s bars for %s ...", n_bars, timeframe_str, symbol)

    try:
        rates = mt5.copy_rates_from_pos(symbol, tf, 0, n_bars)
    except Exception as exc:
        logger.error("copy_rates_from_pos raised: %s", exc)
        return pd.DataFrame()

    if rates is None or len(rates) == 0:
        logger.warning("MT5 returned no bars for %s %s.", symbol, timeframe_str)
        return pd.DataFrame()

    df = pd.DataFrame(rates)
    df["time"] = pd.to_datetime(df["time"], unit="s", utc=True)
    df.set_index("time", inplace=True)
    df.sort_index(inplace=True)

    logger.info("Fetched %d bars | %s → %s", len(df), df.index[0], df.index[-1])
    return df


def get_account_info() -> dict:
    if not _MT5_AVAILABLE or not cfg.enable_live_feed:
        return {}

    info = mt5.account_info()
    if info is None:
        logger.error("Could not retrieve account info: %s", mt5.last_error())
        return {}

    return {
        "login":       info.login,
        "balance":     info.balance,
        "equity":      info.equity,
        "margin":      info.margin,
        "free_margin": info.margin_free,
        "currency":    info.currency,
        "leverage":    info.leverage,
    }


# ---------------------------------------------------------------------------
# Order execution — delegates SL/TP to KOM
# ---------------------------------------------------------------------------

def _clamp_lot(lot: float) -> float:
    steps   = round(lot / cfg.lot_step)
    clamped = max(cfg.min_lot_size, min(cfg.max_lot_size, steps * cfg.lot_step))
    return round(clamped, 2)


def send_order_from_kom_signal(
    kom_signal: dict,
    symbol:     str = None,
) -> Optional[int]:
    """
    Sends a market order using signal, SL, and TP sourced from KOM's entries_engine().

    Parameters
    ----------
    kom_signal : dict with keys "signal" (str), "sl" (float), "tp" (float)
    symbol     : instrument symbol; defaults to cfg.symbol

    Returns
    -------
    Optional[int]
        MT5 order ticket on success, None otherwise.
    """
    symbol = symbol or cfg.symbol

    if not cfg.enable_trading:
        logger.info(
            "[DRY RUN] Would send %s on %s | SL=%.5f | TP=%.5f",
            kom_signal["signal"], symbol, kom_signal["sl"], kom_signal["tp"],
        )
        return None

    if not _MT5_AVAILABLE:
        logger.error("Cannot send order: MetaTrader5 package not installed.")
        return None

    direction = kom_signal["signal"]
    sl        = kom_signal["sl"]
    tp        = kom_signal["tp"]

    if direction not in ("BUY", "SELL"):
        logger.error("Invalid signal direction '%s'.", direction)
        return None

    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        logger.error("Cannot get tick for %s: %s", symbol, mt5.last_error())
        return None

    price       = tick.ask if direction == "BUY" else tick.bid
    action_type = mt5.ORDER_TYPE_BUY if direction == "BUY" else mt5.ORDER_TYPE_SELL
    lot         = _clamp_lot(cfg.lot_size)

    request = {
        "action":       mt5.TRADE_ACTION_DEAL,
        "symbol":       symbol,
        "volume":       lot,
        "type":         action_type,
        "price":        price,
        "sl":           sl,
        "tp":           tp,
        "deviation":    10,
        "magic":        cfg.magic_number,
        "comment":      cfg.order_comment,
        "type_time":    mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_FOK,
    }

    logger.info(
        "Sending %s | Symbol=%s | Lot=%.2f | Price=%.5f | SL=%.5f | TP=%.5f",
        direction, symbol, lot, price, sl, tp,
    )

    try:
        result = mt5.order_send(request)
    except Exception as exc:
        logger.error("order_send raised exception: %s", exc)
        return None

    if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
        retcode = result.retcode if result else "None"
        comment = result.comment if result else "no result"
        logger.error("Order FAILED | retcode=%s | %s", retcode, comment)
        return None

    logger.info("Order FILLED | Ticket=%d | Executed=%.5f", result.order, result.price)
    return result.order


def close_position_by_ticket(ticket: int, symbol: str = None) -> bool:
    symbol = symbol or cfg.symbol

    if not cfg.enable_trading:
        logger.info("[DRY RUN] Would close ticket #%d on %s", ticket, symbol)
        return True

    if not _MT5_AVAILABLE:
        return False

    positions = mt5.positions_get(ticket=ticket)
    if not positions:
        logger.warning("No open position found with ticket #%d.", ticket)
        return False

    pos         = positions[0]
    action_type = mt5.ORDER_TYPE_SELL if pos.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY

    tick  = mt5.symbol_info_tick(symbol)
    price = tick.bid if action_type == mt5.ORDER_TYPE_SELL else tick.ask

    request = {
        "action":       mt5.TRADE_ACTION_DEAL,
        "symbol":       symbol,
        "volume":       pos.volume,
        "type":         action_type,
        "position":     ticket,
        "price":        price,
        "deviation":    10,
        "magic":        cfg.magic_number,
        "comment":      f"{cfg.order_comment}_CLOSE",
        "type_time":    mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_FOK,
    }

    result = mt5.order_send(request)
    if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
        retcode = result.retcode if result else "None"
        logger.error("Close FAILED | Ticket=%d | retcode=%s", ticket, retcode)
        return False

    logger.info("Position closed | Ticket=%d | Price=%.5f", ticket, result.price)
    return True


def close_all_positions(symbol: str = None) -> int:
    symbol = symbol or cfg.symbol

    if not _MT5_AVAILABLE:
        return 0

    positions = mt5.positions_get(symbol=symbol)
    if not positions:
        logger.info("No open positions on %s to close.", symbol)
        return 0

    closed = sum(
        1 for pos in positions
        if close_position_by_ticket(pos.ticket, symbol)
    )
    logger.info("Closed %d / %d positions on %s.", closed, len(positions), symbol)
    return closed
