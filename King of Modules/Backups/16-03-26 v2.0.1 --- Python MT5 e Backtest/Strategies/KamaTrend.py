import pandas as pd
 
import MetaTrader5 as mt5
 
from Config import cfg, Signal
from Indicators import (
    compute_kama,
    compute_atr,
    get_atr_value,
)
 
KAMA_FLIP_LOOKBACK = 3   # mirrors #define KAMA_FLIP_LOOKBACK 3
 
 
# ---------------------------------------------------------------------------
# KAMA Flip Detection — GetKamaFlip
# ---------------------------------------------------------------------------
 
def _get_kama_flip(rates: pd.DataFrame):
    """
    Scans the last KAMA_FLIP_LOOKBACK+1 closed regime values for a flip.
    Returns (bullish_flip, bearish_flip) booleans, or None on failure.
 
    Mirrors GetKamaFlip():
        CopyBuffer(g_handleKAMA, 1, offset=1, count=LOOKBACK+1)
        loop i=0..LOOKBACK-1:
          current  = regimeBuf[i]       (newer)
          previous = regimeBuf[i + 1]   (older)
    """
    _, regime = compute_kama(rates["close"])
 
    needed = KAMA_FLIP_LOOKBACK + 2   # +1 for lookback window, +1 to skip live bar
    if len(regime) < needed:
        return None
 
    # offset=1: skip the live (forming) bar
    # We take the last (KAMA_FLIP_LOOKBACK + 1) closed regime values
    window = regime.iloc[-(KAMA_FLIP_LOOKBACK + 2):-1].values
 
    # In MQL5 CopyBuffer with array filled oldest→newest:
    # index 0 = oldest, index LOOKBACK = newest of the window
    # Loop: i=0 → current=buf[0], previous=buf[1]  (MQL5 newest-first convention)
    # Python: we reverse so index 0 = newest, index -1 = oldest
    # Then: current = window_rev[i], previous = window_rev[i+1]
 
    window_rev = window[::-1]   # newest first
 
    bullish_flip = False
    bearish_flip = False
 
    for i in range(KAMA_FLIP_LOOKBACK):
        current  = int(round(window_rev[i]))
        previous = int(round(window_rev[i + 1]))
 
        if previous == 1 and current == 2:
            bullish_flip = True
        if previous == 2 and current == 1:
            bearish_flip = True
 
    return bullish_flip, bearish_flip
 
 
# ---------------------------------------------------------------------------
# ATR Expansion Filter — PassATRExpansionFilter
# ---------------------------------------------------------------------------
 
def _pass_atr_expansion_filter(rates: pd.DataFrame) -> bool:
    """
    Allow entry only when:
      ATR(14) is rising  (now > prev bar)
      AND ATR(14) > ATR(50) * multiplier
 
    Mirrors PassATRExpansionFilter().
    """
    if not cfg.use_atr_kt_trend_filter:
        return True
 
    atr_fast_series = compute_atr(rates, cfg.atr_period)
    if len(atr_fast_series) < 4:
        return False
 
    # offset=1: bar[1] and bar[2] (both closed)
    atr_fast_now  = atr_fast_series.iloc[-2]   # bar[1]
    atr_fast_prev = atr_fast_series.iloc[-3]   # bar[2]
 
    if atr_fast_now <= atr_fast_prev:
        return False
 
    atr_slow = get_atr_value(rates, 50)
    if atr_slow is None:
        return False
 
    return atr_fast_now > atr_slow * cfg.atr_kt_trend_multiplier
 
 
# ---------------------------------------------------------------------------
# ADX Trend Filter — PassADXTrendFilter
# ---------------------------------------------------------------------------
 
def _compute_adx(rates: pd.DataFrame, period: int) -> pd.Series:
    """
    Wilder-smoothed ADX matching MQL5 iADX.
    Returns the ADX line (buffer 0 in MQL5).
    """
    high  = rates["high"]
    low   = rates["low"]
    close = rates["close"]
 
    up_move   = high.diff()
    down_move = -low.diff()
 
    plus_dm  = up_move.where((up_move > down_move) & (up_move > 0), 0.0)
    minus_dm = down_move.where((down_move > up_move) & (down_move > 0), 0.0)
 
    tr = pd.concat(
        [(high - low),
         (high - close.shift()).abs(),
         (low  - close.shift()).abs()],
        axis=1
    ).max(axis=1)
 
    atr      = tr.ewm(alpha=1 / period, adjust=False).mean()
    plus_di  = 100 * plus_dm.ewm(alpha=1 / period, adjust=False).mean() / atr
    minus_di = 100 * minus_dm.ewm(alpha=1 / period, adjust=False).mean() / atr
 
    dx  = (100 * (plus_di - minus_di).abs() /
           (plus_di + minus_di).replace(0, float("nan")))
    adx = dx.ewm(alpha=1 / period, adjust=False).mean()
    return adx
 
 
def _pass_adx_trend_filter(rates: pd.DataFrame) -> bool:
    """
    Allow entry when ADX is rising AND ADX < cfg.adx_comparison.
    Note: the original comment shows experimentation (< 24 / > 19.5 / > 18).
    The active code is: adxNow < InpADXComparision.
 
    Mirrors PassADXTrendFilter().
    """
    if not cfg.use_adx_filter:
        return True
 
    adx = _compute_adx(rates, cfg.adx_period)
    if len(adx) < cfg.adx_period + 3:
        return False
 
    adx_now  = adx.iloc[-2]   # bar[1]
    adx_prev = adx.iloc[-3]   # bar[2]
 
    if adx_now <= adx_prev:
        return False
 
    return adx_now < cfg.adx_comparison
 
 
# ---------------------------------------------------------------------------
# Public signal function — SignalKamaTrend (orchestrator)
# ---------------------------------------------------------------------------
 
def signal_kama_trend(rates: pd.DataFrame) -> Signal:
    """
    Main entry point. Call once per new closed bar.
 
    Returns Signal.BUY / Signal.SELL / Signal.NONE.
    """
    flip_result = _get_kama_flip(rates)
    if flip_result is None:
        return Signal.NONE
 
    bullish_flip, bearish_flip = flip_result
 
    if not bearish_flip and not bullish_flip:
        return Signal.NONE
 
    if not _pass_atr_expansion_filter(rates):
        return Signal.NONE
 
    if not _pass_adx_trend_filter(rates):
        return Signal.NONE
 
    # Bearish flip takes priority (matches MQL5 evaluation order)
    if bearish_flip:
        return Signal.SELL
 
    if bullish_flip:
        return Signal.BUY
 
    return Signal.NONE