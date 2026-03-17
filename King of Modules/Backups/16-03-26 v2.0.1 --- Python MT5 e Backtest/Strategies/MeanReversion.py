from enum import IntEnum
 
import pandas as pd
import numpy as np
 
from Config import cfg, Signal
from Indicators import (
    get_rsi,
    get_keltner,
    get_kama_color,
    get_kama_values,
    get_atr,
    get_atr_value,
    compute_atr,
    compute_kama,
)
 
 
# ---------------------------------------------------------------------------
# Entry state  (mirrors ENUM_ENTRY_STATE)
# ---------------------------------------------------------------------------
 
class EntryState(IntEnum):
    IDLE                 = 0
    OVERSOLD_CONFIRMED   = 1
    OVERBOUGHT_CONFIRMED = 2
 
 
# Module-level state — persists across ticks (mirrors 'static' in MQL5)
_mr_state: EntryState = EntryState.IDLE
 
 
# ---------------------------------------------------------------------------
# Indicator snapshot — UpdateMRIndicators
# ---------------------------------------------------------------------------
 
def _update_mr_indicators(rates: pd.DataFrame):
    """
    Returns a dict with all needed values, or None on failure.
    Mirrors UpdateMRIndicators().
    """
    rsi_result = get_rsi(rates)
    if rsi_result is None:
        return None
    prev_rsi, cur_rsi = rsi_result
 
    keltner_result = get_keltner(rates)
    if keltner_result is None:
        return None
    upper_k, lower_k = keltner_result
 
    kama_color_result = get_kama_color(rates)
    if kama_color_result is None:
        return None
    _, kama_color = kama_color_result   # we need 'current' colour = bar[1]
 
    kama_arr = get_kama_values(rates, cfg.kama_slope_lookback)
    if kama_arr is None:
        return None
 
    # kamaSlope = |kamaBuf[lookback] - kamaBuf[0]|
    # In MQL5: kamaBuf filled oldest→newest; index 0 = oldest, last = newest
    kama_slope = abs(kama_arr[-1] - kama_arr[0])
 
    close1 = float(rates["close"].iloc[-2])   # bar[1] = last closed
 
    return {
        "cur_rsi":   cur_rsi,
        "prev_rsi":  prev_rsi,
        "upper_k":   upper_k,
        "lower_k":   lower_k,
        "kama_color": kama_color,
        "close1":    close1,
        "kama_slope": kama_slope,
    }
 
 
# ---------------------------------------------------------------------------
# ATR Compression Filter — PassMRATRCompressionFilter
# ---------------------------------------------------------------------------
 
def _pass_atr_compression_filter(rates: pd.DataFrame) -> bool:
    """
    Allow entry only when ATR(14) < ATR(50) * multiplier.
    Mirrors PassMRATRCompressionFilter().
    """
    if not cfg.use_atr_mr_trend_filter:
        return True
 
    atr_fast = get_atr_value(rates, cfg.atr_period)
    atr_slow = get_atr_value(rates, 50)
    if atr_fast is None or atr_slow is None:
        return False
 
    return atr_fast < atr_slow * cfg.atr_mr_trend_multiplier
 
 
# ---------------------------------------------------------------------------
# KAMA Slope Filter — PassMRKAMASlopeFilter
# ---------------------------------------------------------------------------
 
def _pass_kama_slope_filter(slope: float, rates: pd.DataFrame) -> bool:
    """
    Block entry when KAMA slope > ATR * kama_slope_atr_multiplier.
    Mirrors PassMRKAMASlopeFilter().
    """
    if not cfg.use_kama_strong_trend_filter:
        return True
 
    result = get_atr(rates)
    if result is None:
        return False
 
    atr, _ = result
    threshold = atr * cfg.kama_slope_atr_multiplier
    return slope <= threshold
 
 
# ---------------------------------------------------------------------------
# Mean Distance Filter — PassMRMeanDistanceFilter
# ---------------------------------------------------------------------------
 
def _pass_mean_distance_filter(close1: float, rates: pd.DataFrame) -> bool:
    """
    Allow entry only when price is far enough from KAMA.
    Mirrors PassMRMeanDistanceFilter().
    """
    if not cfg.use_mean_distance_filter:
        return True
 
    kama_vals = get_kama_values(rates, 1)
    if kama_vals is None:
        return False
    kama_val = kama_vals[-1]
 
    atr_fast = get_atr_value(rates, cfg.atr_period)
    if atr_fast is None:
        return False
 
    distance  = abs(close1 - kama_val)
    threshold = atr_fast * cfg.mean_distance_atr_mult
    return distance >= threshold
 
 
# ---------------------------------------------------------------------------
# Extreme Detection — DetectMRExtreme
# ---------------------------------------------------------------------------
 
def _detect_mr_extreme(
    cur_rsi: float,
    close1:  float,
    upper_k: float,
    lower_k: float,
    kama_color: int
) -> None:
    """Mirrors DetectMRExtreme(). Mutates module-level _mr_state."""
    global _mr_state
 
    if _mr_state != EntryState.IDLE:
        return
 
    # Oversold: RSI below threshold + price below lower Keltner + KAMA bearish (1)
    if (cur_rsi < cfg.rsi_oversold and
            close1 < lower_k and
            kama_color == 1):
        _mr_state = EntryState.OVERSOLD_CONFIRMED
        return
 
    # Overbought: RSI above threshold + price above upper Keltner + KAMA bullish (2)
    if (cur_rsi > cfg.rsi_overbought and
            close1 > upper_k and
            kama_color == 2):
        _mr_state = EntryState.OVERBOUGHT_CONFIRMED
 
 
# ---------------------------------------------------------------------------
# Return Confirmation — ConfirmMRReturn
# ---------------------------------------------------------------------------
 
def _confirm_mr_return(cur_rsi: float, prev_rsi: float) -> Signal:
    """
    Detects RSI crossing back through the oversold/overbought threshold.
    Mirrors ConfirmMRReturn().
    """
    global _mr_state
 
    if _mr_state == EntryState.OVERSOLD_CONFIRMED:
        # RSI was ≤ oversold, now crossed above → BUY
        if prev_rsi <= cfg.rsi_oversold and cur_rsi > cfg.rsi_oversold:
            _mr_state = EntryState.IDLE
            return Signal.BUY
 
    if _mr_state == EntryState.OVERBOUGHT_CONFIRMED:
        # RSI was ≥ overbought, now crossed below → SELL
        if prev_rsi >= cfg.rsi_overbought and cur_rsi < cfg.rsi_overbought:
            _mr_state = EntryState.IDLE
            return Signal.SELL
 
    return Signal.NONE
 
 
# ---------------------------------------------------------------------------
# Stale Reset — ResetMRState
# ---------------------------------------------------------------------------
 
def _reset_mr_state(cur_rsi: float) -> None:
    """
    Cancels a confirmed-but-never-triggered state when RSI drifts too far.
    Mirrors ResetMRState().
    """
    global _mr_state
 
    if _mr_state == EntryState.OVERSOLD_CONFIRMED:
        if (cur_rsi > cfg.rsi_oversold and
                abs(cur_rsi - cfg.rsi_oversold) > cfg.rsi_reset_threshold):
            _mr_state = EntryState.IDLE
 
    if _mr_state == EntryState.OVERBOUGHT_CONFIRMED:
        if (cur_rsi < cfg.rsi_overbought and
                abs(cur_rsi - cfg.rsi_overbought) > cfg.rsi_reset_threshold):
            _mr_state = EntryState.IDLE
 
 
# ---------------------------------------------------------------------------
# Public signal function — SignalMeanReversion (orchestrator)
# ---------------------------------------------------------------------------
 
def signal_mean_reversion(rates: pd.DataFrame, current_bar_time) -> Signal:
    """
    Main entry point. Call once per new closed bar.
 
    Parameters
    ----------
    rates            : DataFrame with OHLCV data (enough history for all indicators)
    current_bar_time : datetime of the current bar (used as bar-gate, like
                       MQL5's 'static datetime lastBar' pattern — caller must
                       pass the same value per bar and advance it per new bar).
 
    Returns
    -------
    Signal.BUY / Signal.SELL / Signal.NONE
    """
    # Note: the bar-gate (static lastBar) is handled in entries.py to avoid
    # duplicate state in each strategy. signal_mean_reversion() is therefore
    # called only once per new bar by EntriesEngine.
 
    data = _update_mr_indicators(rates)
    if data is None:
        return Signal.NONE
 
    # Combined filter: ATR compression OR KAMA slope must pass
    # (mirrors: !(PassMRATRCompressionFilter() || PassMRKAMASlopeFilter(slope)))
    atr_ok  = _pass_atr_compression_filter(rates)
    slope_ok = _pass_kama_slope_filter(data["kama_slope"], rates)
    if not (atr_ok or slope_ok):
        return Signal.NONE
 
    if not _pass_mean_distance_filter(data["close1"], rates):
        return Signal.NONE
 
    _detect_mr_extreme(
        data["cur_rsi"],
        data["close1"],
        data["upper_k"],
        data["lower_k"],
        data["kama_color"],
    )
 
    signal = _confirm_mr_return(data["cur_rsi"], data["prev_rsi"])
 
    _reset_mr_state(data["cur_rsi"])
 
    return signal