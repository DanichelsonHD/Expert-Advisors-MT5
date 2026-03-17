import numpy as np
import pandas as pd
from typing import Tuple, Optional
 
from Config import cfg
 
 
# ---------------------------------------------------------------------------
# RSI  (mirrors iRSI / CopyBuffer → GetRSI)
# ---------------------------------------------------------------------------
 
def compute_rsi(close: pd.Series, period: int) -> pd.Series:
    """Wilder-smoothed RSI — matches MQL5 iRSI."""
    delta = close.diff()
    gain  = delta.clip(lower=0)
    loss  = -delta.clip(upper=0)
 
    # First average: simple mean over first `period` bars
    avg_gain = gain.ewm(alpha=1 / period, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1 / period, adjust=False).mean()
 
    rs  = avg_gain / avg_loss.replace(0, np.nan)
    rsi = 100 - (100 / (1 + rs))
    return rsi
 
 
def get_rsi(rates: pd.DataFrame) -> Optional[Tuple[float, float]]:
    """
    Returns (prev_rsi, current_rsi) — bars [1] and [2] relative to current.
    Mirrors GetRSI(prev, current): CopyBuffer offset=1, count=2.
    """
    rsi = compute_rsi(rates["close"], cfg.rsi_period)
    if len(rsi) < cfg.rsi_period + 2:
        return None
 
    # offset=1 → skip the live (forming) bar; take the last two closed bars
    prev    = rsi.iloc[-2]   # bar index 1 in MQL5 notation (older closed bar)
    current = rsi.iloc[-1]   # bar index 0 in MQL5 notation (last closed bar)
 
    # MQL5 GetRSI: CopyBuffer(handle, 0, 1, 2, rsi)
    # rsi[0] = bar shifted 1  → prev
    # rsi[1] = bar shifted 1+1? No: offset=1, count=2 fills indices newest-first
    # Actually in MQL5 with AS_SERIES=false default for CopyBuffer arrays:
    # index 0 = oldest, index 1 = newest of the 2 copied.
    # offset=1 means skip 0 (live bar), so bar1 and bar2.
    # GetRSI returns prev=rsi[0]=bar2, current=rsi[1]=bar1.
    # We match: prev=iloc[-3], current=iloc[-2] (both closed, skip live bar).
    if len(rsi) < cfg.rsi_period + 3:
        return None
 
    prev    = rsi.iloc[-3]   # bar[2] in MQL5 (older)
    current = rsi.iloc[-2]   # bar[1] in MQL5 (most recent closed)
    return prev, current
 
 
# ---------------------------------------------------------------------------
# ATR  (mirrors iATR / GetATR)
# ---------------------------------------------------------------------------
 
def compute_atr(rates: pd.DataFrame, period: int) -> pd.Series:
    """True Range → Wilder-smoothed ATR, matches MQL5 iATR."""
    high  = rates["high"]
    low   = rates["low"]
    close = rates["close"]
 
    prev_close = close.shift(1)
    tr = pd.concat(
        [high - low,
         (high - prev_close).abs(),
         (low  - prev_close).abs()],
        axis=1
    ).max(axis=1)
 
    atr = tr.ewm(alpha=1 / period, adjust=False).mean()
    return atr
 
 
def get_atr(rates: pd.DataFrame) -> Optional[Tuple[float, float]]:
    """
    Returns (current_atr, avg_atr).
    Mirrors GetATR: current = last closed bar; avg = mean of last N bars
    (same N=InpATRPeriod bars, offset=1 to skip live bar).
    """
    atr = compute_atr(rates, cfg.atr_period)
    if len(atr) < cfg.atr_period + 2:
        return None
 
    # offset=1: skip live bar → use iloc[-2] as 'most recent closed'
    window  = atr.iloc[-(cfg.atr_period + 1):-1]   # InpATRPeriod closed bars
    current = window.iloc[-1]
    avg     = window.mean()
    return current, avg
 
 
def get_atr_value(rates: pd.DataFrame, period: int) -> Optional[float]:
    """Single ATR value (last closed bar) for arbitrary period."""
    atr = compute_atr(rates, period)
    if len(atr) < period + 2:
        return None
    return atr.iloc[-2]   # offset=1
 
 
# ---------------------------------------------------------------------------
# Keltner Channel  (mirrors iCustom "Keltner Channel" / GetKeltner)
# ---------------------------------------------------------------------------
 
def compute_keltner(
    rates: pd.DataFrame,
    ema_period: int  = None,
    atr_period: int  = None,
    atr_factor: float = None
) -> Tuple[pd.Series, pd.Series]:
    """
    Standard Keltner Channel:
        Middle = EMA(close, ema_period)
        Upper  = Middle + atr_factor * ATR(atr_period)
        Lower  = Middle - atr_factor * ATR(atr_period)
 
    Matches the 'Keltner Channel' custom indicator used in the original EA
    (buffer 0 = upper, buffer 2 = lower).
    """
    ema_period = ema_period or cfg.keltner_ema_period
    atr_period = atr_period or cfg.atr_period
    atr_factor = atr_factor or cfg.keltner_atr_factor
 
    middle = rates["close"].ewm(span=ema_period, adjust=False).mean()
    atr    = compute_atr(rates, atr_period)
 
    upper = middle + atr_factor * atr
    lower = middle - atr_factor * atr
    return upper, lower
 
 
def get_keltner(rates: pd.DataFrame) -> Optional[Tuple[float, float]]:
    """
    Returns (upper, lower) for the last closed bar.
    Mirrors GetKeltner: CopyBuffer offset=1, count=2 → takes [1] = bar[1].
    """
    upper_s, lower_s = compute_keltner(rates)
 
    if len(upper_s) < 3:
        return None
 
    # offset=1, index [1] of the 2-element copy → bar[1] (last closed)
    upper = upper_s.iloc[-2]
    lower = lower_s.iloc[-2]
    return upper, lower
 
 
# ---------------------------------------------------------------------------
# KAMA  (mirrors iCustom "KAMA with filter" / GetKAMAColor)
# ---------------------------------------------------------------------------
 
def compute_kama(
    close: pd.Series,
    period: int      = None,
    fast_period: int = None,
    slow_period: int = None
) -> Tuple[pd.Series, pd.Series]:
    """
    Kaufman Adaptive Moving Average + colour/regime buffer.
 
    Returns:
        kama_values  : pd.Series  — KAMA line (buffer 0)
        kama_regime  : pd.Series  — regime codes 1=bearish, 2=bullish (buffer 1)
 
    Regime is determined by the slope of KAMA (rising → bullish=2,
    falling → bearish=1), which matches the 'KAMA with filter' custom
    indicator used in the original EA (buffer 1 = colour index).
    """
    period      = period      or cfg.kama_period
    fast_period = fast_period or cfg.kama_fast_period
    slow_period = slow_period or cfg.kama_slow_period
 
    fast_sc = 2 / (fast_period + 1)
    slow_sc = 2 / (slow_period + 1)
 
    close_arr = close.values.astype(float)
    n         = len(close_arr)
    kama_arr  = np.full(n, np.nan)
 
    # Seed: first valid KAMA = first close after warm-up
    kama_arr[period - 1] = close_arr[period - 1]
 
    for i in range(period, n):
        direction = abs(close_arr[i] - close_arr[i - period])
        volatility = sum(
            abs(close_arr[j] - close_arr[j - 1])
            for j in range(i - period + 1, i + 1)
        )
        er  = direction / volatility if volatility != 0 else 0
        sc  = (er * (fast_sc - slow_sc) + slow_sc) ** 2
        kama_arr[i] = kama_arr[i - 1] + sc * (close_arr[i] - kama_arr[i - 1])
 
    kama_series = pd.Series(kama_arr, index=close.index)
 
    # Regime: compare KAMA[i] vs KAMA[i-1]
    regime = pd.Series(0, index=close.index, dtype=int)
    diff   = kama_series.diff()
    regime[diff > 0]  = 2   # bullish
    regime[diff < 0]  = 1   # bearish
    regime[diff == 0] = 0   # none / flat
 
    return kama_series, regime
 
 
def get_kama_color(rates: pd.DataFrame) -> Optional[Tuple[int, int]]:
    """
    Returns (prev_regime_code, current_regime_code).
    Mirrors GetKAMAColor: CopyBuffer(handle, 1, offset=1, count=2).
    prev    = buf[0] = bar[2]
    current = buf[1] = bar[1]
    """
    _, regime = compute_kama(rates["close"])
 
    if len(regime) < 4:
        return None
 
    prev    = int(round(regime.iloc[-3]))   # bar[2]
    current = int(round(regime.iloc[-2]))   # bar[1]
    return prev, current
 
 
def get_kama_values(rates: pd.DataFrame, lookback: int) -> Optional[np.ndarray]:
    """
    Returns the last (lookback+1) closed KAMA values as a numpy array.
    Used by MeanReversion slope calculation.
    Mirrors: CopyBuffer(g_handleKAMA, 0, 1, InpKAMASlopeLookback+1, kamaBuf)
    """
    kama, _ = compute_kama(rates["close"])
    needed  = lookback + 2   # +1 for lookback, +1 to skip live bar
    if len(kama) < needed:
        return None
 
    # offset=1: skip live bar → iloc[-(needed):-1]
    arr = kama.iloc[-(needed):-1].values
    return arr