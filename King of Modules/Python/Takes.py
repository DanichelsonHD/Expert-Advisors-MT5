import pandas as pd

from Config import cfg, KamaRegime, TakeMode
from Indicators import get_atr, get_kama_color

try:
    import MetaTrader5 as mt5
    _MT5_AVAILABLE = True
except ImportError:
    _MT5_AVAILABLE = False


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_digits(symbol: str) -> int:
    if _MT5_AVAILABLE and (cfg.enable_live_feed or cfg.enable_trading):
        info = mt5.symbol_info(symbol)
        if info is not None:
            return info.digits
    return cfg.symbol_digits


def _get_ask_bid(symbol: str, rates: pd.DataFrame) -> tuple[float, float]:
    if _MT5_AVAILABLE and (cfg.enable_live_feed or cfg.enable_trading):
        tick = mt5.symbol_info_tick(symbol)
        if tick is not None:
            return tick.ask, tick.bid
    close = float(rates["close"].iloc[-2])
    return close, close


def _resolve_kama_regime(color_code: int) -> KamaRegime:
    if color_code == 1:
        return KamaRegime.BEARISH
    if color_code == 2:
        return KamaRegime.BULLISH
    return KamaRegime.NONE


# ---------------------------------------------------------------------------
# FIXED ATR-BASED TP — calculate_take_profit
# ---------------------------------------------------------------------------

def calculate_take_profit(
    order_type: int,
    rates: pd.DataFrame,
    symbol: str,
) -> float:
    if not cfg.use_take_profit:
        return 0.0

    result = get_atr(rates)
    if result is None:
        return 0.0

    atr, _   = result
    digits   = _get_digits(symbol)
    ask, bid = _get_ask_bid(symbol, rates)
    tp_dist  = atr * cfg.tp_multiplier

    if order_type == 0:  # BUY
        return round(ask + tp_dist, digits)
    else:
        return round(bid - tp_dist, digits)


# ---------------------------------------------------------------------------
# KAMA REGIME EXIT — take_kama (live only)
# ---------------------------------------------------------------------------

def take_kama(rates: pd.DataFrame, symbol: str) -> None:
    if not _MT5_AVAILABLE or not (cfg.enable_live_feed or cfg.enable_trading):
        return

    positions = mt5.positions_get(symbol=symbol)
    if not positions:
        return

    result = get_kama_color(rates)
    if result is None:
        return

    prev_code, cur_code = result
    prev_regime = _resolve_kama_regime(prev_code)
    cur_regime  = _resolve_kama_regime(cur_code)

    for pos in positions:
        if pos.magic != cfg.magic_number:
            continue

        if pos.type == mt5.POSITION_TYPE_BUY:
            if prev_regime == KamaRegime.BULLISH and cur_regime == KamaRegime.BEARISH:
                req = {
                    "action":       mt5.TRADE_ACTION_DEAL,
                    "symbol":       symbol,
                    "volume":       pos.volume,
                    "type":         mt5.ORDER_TYPE_SELL,
                    "position":     pos.ticket,
                    "price":        mt5.symbol_info_tick(symbol).bid,
                    "deviation":    10,
                    "magic":        cfg.magic_number,
                    "type_filling": mt5.ORDER_FILLING_IOC,
                }
                result_send = mt5.order_send(req)
                if result_send and result_send.retcode == mt5.TRADE_RETCODE_DONE:
                    print("TakeKAMA: BUY closed (Bullish→Bearish).")
                else:
                    code = result_send.retcode if result_send else "N/A"
                    print(f"ERROR: TakeKAMA failed to close BUY. Code={code}")

        elif pos.type == mt5.POSITION_TYPE_SELL:
            if prev_regime == KamaRegime.BEARISH and cur_regime == KamaRegime.BULLISH:
                req = {
                    "action":       mt5.TRADE_ACTION_DEAL,
                    "symbol":       symbol,
                    "volume":       pos.volume,
                    "type":         mt5.ORDER_TYPE_BUY,
                    "position":     pos.ticket,
                    "price":        mt5.symbol_info_tick(symbol).ask,
                    "deviation":    10,
                    "magic":        cfg.magic_number,
                    "type_filling": mt5.ORDER_FILLING_IOC,
                }
                result_send = mt5.order_send(req)
                if result_send and result_send.retcode == mt5.TRADE_RETCODE_DONE:
                    print("TakeKAMA: SELL closed (Bearish→Bullish).")
                else:
                    code = result_send.retcode if result_send else "N/A"
                    print(f"ERROR: TakeKAMA failed to close SELL. Code={code}")


# ---------------------------------------------------------------------------
# manage_takes — called every tick (live only)
# ---------------------------------------------------------------------------

def manage_takes(rates: pd.DataFrame, symbol: str) -> None:
    if not _MT5_AVAILABLE or not (cfg.enable_live_feed or cfg.enable_trading):
        return

    positions = mt5.positions_get(symbol=symbol)
    if not positions:
        return

    if not any(p.magic == cfg.magic_number for p in positions):
        return

    if cfg.take_mode == TakeMode.KAMA:
        take_kama(rates, symbol)
