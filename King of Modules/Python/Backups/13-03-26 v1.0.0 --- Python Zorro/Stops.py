import MetaTrader5 as mt5
import pandas as pd
 
from Config import cfg, Signal, StopMode
from Indicators import get_atr
 
 
# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
 
def _symbol_info(symbol: str):
    info = mt5.symbol_info(symbol)
    if info is None:
        raise RuntimeError(f"symbol_info failed for {symbol}")
    return info
 
 
def _min_stop_distance(symbol: str) -> float:
    """
    Equivalent to MQL5:
        minDist = MathMax(SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL)
                  * point + point
    """
    info       = _symbol_info(symbol)
    stop_lvl   = info.trade_stops_level
    freeze_lvl = info.trade_freeze_level
    point      = info.point
    return max(stop_lvl, freeze_lvl) * point + point
 
 
# ---------------------------------------------------------------------------
# STOP_FIXED — CalculateATRStop
# ---------------------------------------------------------------------------
 
def calculate_atr_stop(
    order_type: int,   # mt5.ORDER_TYPE_BUY / ORDER_TYPE_SELL
    atr: float,
    symbol: str
) -> float:
    """
    Mirror of CalculateATRStop().
    stopDist = ATR * multiplier + extra_points * point
    Enforces broker minimum distance.
    """
    info   = _symbol_info(symbol)
    point  = info.point
    digits = info.digits
 
    stop_dist = atr * cfg.stop_multiplier + cfg.extra_points * point
    min_dist  = _min_stop_distance(symbol)
 
    if stop_dist < min_dist:
        stop_dist = min_dist
 
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        return 0.0
 
    if order_type == mt5.ORDER_TYPE_BUY:
        sl = round(tick.ask - stop_dist, digits)
    else:
        sl = round(tick.bid + stop_dist, digits)
 
    return sl
 
 
# ---------------------------------------------------------------------------
# STOP_TECHNICAL — CalculateTechnicalStop
# ---------------------------------------------------------------------------
 
def calculate_technical_stop(
    order_type: int,
    symbol: str,
    rates: pd.DataFrame
) -> float:
    """
    Mirror of CalculateTechnicalStop().
    BUY  → SL below lowest low  of last N closed bars.
    SELL → SL above highest high of last N closed bars.
    N = cfg.technical_stop_lookback
    """
    info   = _symbol_info(symbol)
    point  = info.point
    digits = info.digits
    buffer = cfg.extra_points * point
    min_dist = _min_stop_distance(symbol)
 
    # MQL5: iLow/iHigh(_Symbol, _Period, i) for i in 1..lookback
    # = the last `lookback` closed bars (offset 1 = skip live)
    lookback_bars = rates.iloc[-(cfg.technical_stop_lookback + 1):-1]
 
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        return 0.0
 
    if order_type == mt5.ORDER_TYPE_BUY:
        lowest = lookback_bars["low"].min()
        sl     = round(lowest - buffer, digits)
        if tick.ask - sl < min_dist:
            sl = round(tick.ask - min_dist, digits)
        return sl
    else:
        highest = lookback_bars["high"].max()
        sl      = round(highest + buffer, digits)
        if sl - tick.bid < min_dist:
            sl = round(tick.bid + min_dist, digits)
        return sl
 
 
# ---------------------------------------------------------------------------
# Dispatcher — GetStopLoss
# ---------------------------------------------------------------------------
 
def get_stop_loss(
    order_type: int,
    atr: float,
    symbol: str,
    rates: pd.DataFrame
) -> float:
    """
    Mirror of GetStopLoss().
    TRAILING mode returns 0 here — the initial SL for a trailing trade
    is placed the same as FIXED (ATR-based); the trail is managed separately.
    """
    if cfg.stop_mode == StopMode.FIXED or cfg.stop_mode == StopMode.TRAILING:
        return calculate_atr_stop(order_type, atr, symbol)
 
    if cfg.stop_mode == StopMode.TECHNICAL:
        return calculate_technical_stop(order_type, symbol, rates)
 
    return 0.0
 
 
# ---------------------------------------------------------------------------
# Trailing Stop — ManageTrailingStop (called every tick)
# ---------------------------------------------------------------------------
 
def manage_trailing_stop(atr: float, symbol: str) -> None:
    """
    Mirror of ManageTrailingStop().
    Runs every tick (no bar filter).
    Only active when cfg.stop_mode == StopMode.TRAILING.
    """
    if cfg.stop_mode != StopMode.TRAILING:
        return
 
    positions = mt5.positions_get(symbol=symbol)
    if not positions:
        return
 
    info   = _symbol_info(symbol)
    point  = info.point
    digits = info.digits
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
                request = {
                    "action":   mt5.TRADE_ACTION_SLTP,
                    "symbol":   symbol,
                    "position": pos.ticket,
                    "sl":       new_sl,
                    "tp":       current_tp,
                    "magic":    cfg.magic_number,
                }
                mt5.order_send(request)
 
        elif pos.type == mt5.POSITION_TYPE_SELL:
            new_sl = round(tick.ask + trail_dist, digits)
            if current_sl == 0.0 or new_sl < current_sl - point:
                request = {
                    "action":   mt5.TRADE_ACTION_SLTP,
                    "symbol":   symbol,
                    "position": pos.ticket,
                    "sl":       new_sl,
                    "tp":       current_tp,
                    "magic":    cfg.magic_number,
                }
                mt5.order_send(request)