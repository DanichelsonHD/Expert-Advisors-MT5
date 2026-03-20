import MetaTrader5 as mt5
 
from Config import cfg, KamaRegime, TakeMode
from Indicators import get_atr, get_kama_color
 
 
# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
 
def _resolve_kama_regime(color_code: int) -> KamaRegime:
    """Mirror of ResolveKAMARegime()."""
    if color_code == 1:
        return KamaRegime.BEARISH
    if color_code == 2:
        return KamaRegime.BULLISH
    return KamaRegime.NONE
 
 
# ---------------------------------------------------------------------------
# FIXED ATR-BASED TP — CalculateTakeProfit
# ---------------------------------------------------------------------------
 
def calculate_take_profit(
    order_type: int,   # mt5.ORDER_TYPE_BUY / ORDER_TYPE_SELL
    rates,
    symbol: str
) -> float:
    """
    Mirror of CalculateTakeProfit().
    Returns 0.0 when InpUseTakeProfit is False or ATR unavailable.
    """
    if not cfg.use_take_profit:
        return 0.0
 
    result = get_atr(rates)
    if result is None:
        return 0.0
 
    atr, _ = result
 
    info   = mt5.symbol_info(symbol)
    digits = info.digits
 
    tp_dist = atr * cfg.tp_multiplier
 
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        return 0.0
 
    if order_type == mt5.ORDER_TYPE_BUY:
        return round(tick.ask + tp_dist, digits)
    else:
        return round(tick.bid - tp_dist, digits)
 
 
# ---------------------------------------------------------------------------
# KAMA REGIME EXIT — TakeKAMA
# ---------------------------------------------------------------------------
 
def take_kama(rates, symbol: str) -> None:
    """
    Mirror of TakeKAMA().
    BUY  position → close when KAMA flips Bullish → Bearish.
    SELL position → close when KAMA flips Bearish → Bullish.
    """
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
            if (prev_regime == KamaRegime.BULLISH and
                    cur_regime == KamaRegime.BEARISH):
                req = {
                    "action":   mt5.TRADE_ACTION_DEAL,
                    "symbol":   symbol,
                    "volume":   pos.volume,
                    "type":     mt5.ORDER_TYPE_SELL,
                    "position": pos.ticket,
                    "price":    mt5.symbol_info_tick(symbol).bid,
                    "deviation": 10,
                    "magic":    cfg.magic_number,
                    "type_filling": mt5.ORDER_FILLING_IOC,
                }
                result_send = mt5.order_send(req)
                if result_send and result_send.retcode == mt5.TRADE_RETCODE_DONE:
                    print("TakeKAMA: BUY closed (Bullish→Bearish).")
                else:
                    code = result_send.retcode if result_send else "N/A"
                    print(f"ERROR: TakeKAMA failed to close BUY. Code={code}")
 
        elif pos.type == mt5.POSITION_TYPE_SELL:
            if (prev_regime == KamaRegime.BEARISH and
                    cur_regime == KamaRegime.BULLISH):
                req = {
                    "action":   mt5.TRADE_ACTION_DEAL,
                    "symbol":   symbol,
                    "volume":   pos.volume,
                    "type":     mt5.ORDER_TYPE_BUY,
                    "position": pos.ticket,
                    "price":    mt5.symbol_info_tick(symbol).ask,
                    "deviation": 10,
                    "magic":    cfg.magic_number,
                    "type_filling": mt5.ORDER_FILLING_IOC,
                }
                result_send = mt5.order_send(req)
                if result_send and result_send.retcode == mt5.TRADE_RETCODE_DONE:
                    print("TakeKAMA: SELL closed (Bearish→Bullish).")
                else:
                    code = result_send.retcode if result_send else "N/A"
                    print(f"ERROR: TakeKAMA failed to close SELL. Code={code}")
 
 
# ---------------------------------------------------------------------------
# ManageTakes — called every tick
# ---------------------------------------------------------------------------
 
def manage_takes(rates, symbol: str) -> None:
    """
    Mirror of ManageTakes().
    Validates magic number then dispatches to the active take mode.
    """
    positions = mt5.positions_get(symbol=symbol)
    if not positions:
        return
 
    # At least one EA-owned position must exist
    if not any(p.magic == cfg.magic_number for p in positions):
        return
 
    if cfg.take_mode == TakeMode.KAMA:
        take_kama(rates, symbol)
    # TakeMode.FIXED → no action needed here;
    # TP price level is set at entry and managed by the broker.