import pandas as pd

from Config import cfg, Signal, StopMode

# ---------------------------------------------------------------------------
# MT5 conditional import
# ---------------------------------------------------------------------------
try:
    import MetaTrader5 as mt5
    _MT5_AVAILABLE = True
except ImportError:
    _MT5_AVAILABLE = False


# ---------------------------------------------------------------------------
# Symbol info helpers — live vs backtest
# ---------------------------------------------------------------------------

def _get_point(symbol: str) -> float:
    if _MT5_AVAILABLE and (cfg.enable_live_feed or cfg.enable_trading):
        info = mt5.symbol_info(symbol)
        if info is not None:
            return info.point
    return cfg.symbol_point


def _get_digits(symbol: str) -> int:
    if _MT5_AVAILABLE and (cfg.enable_live_feed or cfg.enable_trading):
        info = mt5.symbol_info(symbol)
        if info is not None:
            return info.digits
    return cfg.symbol_digits


def _get_ask_bid(symbol: str, rates: pd.DataFrame) -> tuple[float, float]:
    """
    Returns (ask, bid).
    Live: from MT5 tick.
    Backtest: both equal to the last closed bar's close price.
    """
    if _MT5_AVAILABLE and (cfg.enable_live_feed or cfg.enable_trading):
        tick = mt5.symbol_info_tick(symbol)
        if tick is not None:
            return tick.ask, tick.bid
    close = float(rates["close"].iloc[-2])
    return close, close


def _min_stop_distance(symbol: str) -> float:
    if _MT5_AVAILABLE and (cfg.enable_live_feed or cfg.enable_trading):
        info = mt5.symbol_info(symbol)
        if info is not None:
            point      = info.point
            stop_lvl   = info.trade_stops_level
            freeze_lvl = info.trade_freeze_level
            return max(stop_lvl, freeze_lvl) * point + point
    return cfg.symbol_point * 10


# ---------------------------------------------------------------------------
# STOP_FIXED — CalculateATRStop
# ---------------------------------------------------------------------------

def calculate_atr_stop(
    order_type: int,
    atr: float,
    symbol: str,
    rates: pd.DataFrame,
) -> float:
    point    = _get_point(symbol)
    digits   = _get_digits(symbol)
    ask, bid = _get_ask_bid(symbol, rates)
    min_dist = _min_stop_distance(symbol)

    stop_dist = atr * cfg.stop_multiplier + cfg.extra_points * point
    if stop_dist < min_dist:
        stop_dist = min_dist

    # ORDER_TYPE_BUY == 0
    if order_type == 0:
        return round(ask - stop_dist, digits)
    else:
        return round(bid + stop_dist, digits)


# ---------------------------------------------------------------------------
# STOP_TECHNICAL — CalculateTechnicalStop
# ---------------------------------------------------------------------------

def calculate_technical_stop(
    order_type: int,
    symbol: str,
    rates: pd.DataFrame,
) -> float:
    point    = _get_point(symbol)
    digits   = _get_digits(symbol)
    ask, bid = _get_ask_bid(symbol, rates)
    buffer   = cfg.extra_points * point
    min_dist = _min_stop_distance(symbol)

    lookback_bars = rates.iloc[-(cfg.technical_stop_lookback + 1):-1]

    if order_type == 0:  # BUY
        lowest = lookback_bars["low"].min()
        sl     = round(lowest - buffer, digits)
        if ask - sl < min_dist:
            sl = round(ask - min_dist, digits)
        return sl
    else:
        highest = lookback_bars["high"].max()
        sl      = round(highest + buffer, digits)
        if sl - bid < min_dist:
            sl = round(bid + min_dist, digits)
        return sl


# ---------------------------------------------------------------------------
# Dispatcher — get_stop_loss
# ---------------------------------------------------------------------------

def get_stop_loss(
    order_type: int,
    atr: float,
    symbol: str,
    rates: pd.DataFrame,
) -> float:
    if cfg.stop_mode == StopMode.FIXED or cfg.stop_mode == StopMode.TRAILING:
        return calculate_atr_stop(order_type, atr, symbol, rates)

    if cfg.stop_mode == StopMode.TECHNICAL:
        return calculate_technical_stop(order_type, symbol, rates)

    return 0.0


# ---------------------------------------------------------------------------
# Trailing Stop — manage_trailing_stop (live only)
# ---------------------------------------------------------------------------

def manage_trailing_stop(atr: float, symbol: str, rates: pd.DataFrame) -> None:
    if cfg.stop_mode != StopMode.TRAILING:
        return

    if not _MT5_AVAILABLE or not (cfg.enable_live_feed or cfg.enable_trading):
        return

    positions = mt5.positions_get(symbol=symbol)
    if not positions:
        return

    point    = _get_point(symbol)
    digits   = _get_digits(symbol)
    min_dist = _min_stop_distance(symbol)

    trail_dist = atr * cfg.stop_multiplier + cfg.extra_points * point
    if trail_dist < min_dist:
        trail_dist = min_dist

    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        return

    for pos in positions:
        if pos.magic != cfg.magic_number:
            continue

        current_sl = pos.sl
        current_tp = pos.tp

        if pos.type == mt5.POSITION_TYPE_BUY:
            new_sl = round(tick.bid - trail_dist, digits)
            if new_sl > current_sl + point:
                mt5.order_send({
                    "action":   mt5.TRADE_ACTION_SLTP,
                    "symbol":   symbol,
                    "position": pos.ticket,
                    "sl":       new_sl,
                    "tp":       current_tp,
                    "magic":    cfg.magic_number,
                })

        elif pos.type == mt5.POSITION_TYPE_SELL:
            new_sl = round(tick.ask + trail_dist, digits)
            if current_sl == 0.0 or new_sl < current_sl - point:
                mt5.order_send({
                    "action":   mt5.TRADE_ACTION_SLTP,
                    "symbol":   symbol,
                    "position": pos.ticket,
                    "sl":       new_sl,
                    "tp":       current_tp,
                    "magic":    cfg.magic_number,
                })
