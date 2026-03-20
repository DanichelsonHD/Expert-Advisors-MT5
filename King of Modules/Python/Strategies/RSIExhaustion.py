import pandas as pd
 
from Config import cfg, Signal
from Indicators import (
    get_rsi,
    get_keltner,
    get_kama_color,
    get_kama_values,
    get_atr_value,
)
from MeanReversion import _update_mr_indicators   # shared helper
 
 
# Default multiplier (not in Inputs.mqh in the original source)
_ATR_RE_TREND_MULTIPLIER: float = 1.0
 
 
# ---------------------------------------------------------------------------
# ATR Compression Filter — PassREATRCompressionFilter
# ---------------------------------------------------------------------------
 
def _pass_re_atr_compression_filter(rates: pd.DataFrame) -> bool:
    """
    Allow entry when ATR(14) * multiplier < ATR(50).
    Mirrors PassREATRCompressionFilter().
    """
    atr_fast = get_atr_value(rates, cfg.atr_period)
    atr_slow = get_atr_value(rates, 50)
    if atr_fast is None or atr_slow is None:
        return False
 
    return atr_fast * _ATR_RE_TREND_MULTIPLIER < atr_slow
 
 
# ---------------------------------------------------------------------------
# Exhaustion Detection — DetectRSIExhaustion
# ---------------------------------------------------------------------------
 
def _detect_rsi_exhaustion(
    cur_rsi:    float,
    upper_k:    float,
    lower_k:    float,
    kama_color: int,
    close1:     float,
) -> Signal:
    """
    Mirrors DetectRSIExhaustion().
 
    Note: the logic uses OR between RSI and Keltner conditions (not AND
    as in Mean Reversion). This is preserved exactly as written in the source.
 
    Oversold  + KAMA bearish(1) → SELL  (fading exhausted move down)
    Overbought + KAMA bullish(2) → BUY  (fading exhausted move up)
    """
    if (cur_rsi < cfg.rsi_oversold or close1 < lower_k) and kama_color == 1:
        return Signal.SELL
 
    if (cur_rsi > cfg.rsi_overbought or close1 > upper_k) and kama_color == 2:
        return Signal.BUY
 
    return Signal.NONE
 
 
# ---------------------------------------------------------------------------
# Public signal function — SignalRSIExhaustion (orchestrator)
# ---------------------------------------------------------------------------
 
def signal_rsi_exhaustion(rates: pd.DataFrame) -> Signal:
    """
    Main entry point. Call once per new closed bar.
 
    Returns Signal.BUY / Signal.SELL / Signal.NONE.
    """
    data = _update_mr_indicators(rates)
    if data is None:
        return Signal.NONE
 
    if not _pass_re_atr_compression_filter(rates):
        return Signal.NONE
 
    return _detect_rsi_exhaustion(
        data["cur_rsi"],
        data["upper_k"],
        data["lower_k"],
        data["kama_color"],
        data["close1"],
    )