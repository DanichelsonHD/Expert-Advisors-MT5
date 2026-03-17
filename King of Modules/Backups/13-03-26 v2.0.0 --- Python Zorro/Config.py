from dataclasses import dataclass
from enum import IntEnum
 
 
# ---------------------------------------------------------------------------
# Enumerations (mirror of MQL5 enums in Inputs.mqh)
# ---------------------------------------------------------------------------
 
class StopMode(IntEnum):
    FIXED     = 0
    TECHNICAL = 1
    TRAILING  = 2   # handled at runtime via ManageTrailingStop()
 
 
class TakeMode(IntEnum):
    FIXED = 0
    KAMA  = 1
 
 
class Signal(IntEnum):
    NONE =  0
    BUY  =  1
    SELL = -1
 
 
class KamaRegime(IntEnum):
    NONE    = 0
    BEARISH = 1
    BULLISH = 2
 
 
# ---------------------------------------------------------------------------
# Main configuration dataclass
# ---------------------------------------------------------------------------
 
@dataclass
class EAConfig:
 
    # --- Trade Settings ---
    lot_size:     float = 0.1
    magic_number: int   = 123456
 
    # --- Entries ---
    max_simultaneous_trades: int  = 2
    use_mr_strategy:         bool = False   # Mean Reversion
    use_tb_strategy:         bool = False   # Trendline Breakout (stub)
    use_tp_strategy:         bool = False   # Trend Pullback (stub)
    use_kt_strategy:         bool = False   # KAMA Trend
 
    # --- Stop Loss & Trailing ---
    stop_mode:               StopMode = StopMode.FIXED
    technical_stop_lookback: int      = 5
    stop_multiplier:         float    = 2.0
    extra_points:            int      = 5
 
    # --- Take Profit ---
    use_take_profit: bool      = False
    tp_multiplier:   float     = 2.0
    take_mode:       TakeMode  = TakeMode.FIXED
 
    # --- Time Filter ---
    use_time_filter: bool = False
    start_hour:      int  = 8
    end_hour:        int  = 20
 
    # --- RSI ---
    rsi_period:          int   = 14
    rsi_oversold:        float = 30.0
    rsi_overbought:      float = 70.0
    rsi_reset_threshold: float = 20.0
 
    # --- KAMA ---
    kama_period:      int = 14
    kama_fast_period: int = 2
    kama_slow_period: int = 30
 
    # --- Keltner Channel ---
    keltner_ema_period: int   = 20
    keltner_atr_factor: float = 2.0
 
    # --- ATR ---
    atr_period:                 int   = 14
    use_atr_mr_trend_filter:    bool  = True
    atr_mr_trend_multiplier:    float = 1.01
    use_atr_kt_trend_filter:    bool  = True
    atr_kt_trend_multiplier:    float = 0.775
 
    # --- ADX ---
    adx_period:      int   = 14
    use_adx_filter:  bool  = True
    adx_comparison:  float = 22.0
 
    # --- Mean Distance Filter ---
    use_mean_distance_filter: bool  = False
    mean_distance_atr_mult:   float = 1.2
 
    # --- KAMA Strong Trend Filter ---
    use_kama_strong_trend_filter: bool  = False
    kama_slope_lookback:          int   = 5
    kama_slope_atr_multiplier:    float = 1.5
 
    # --- Equity Step Lot Scaling ---
    use_step_lot_scaling: bool  = False
    initial_lot:          float = 0.10
    step_capital:         float = 100.0
    step_lot:             float = 0.01
 
 
# ---------------------------------------------------------------------------
# Singleton used throughout the EA — replace with your desired values.
# ---------------------------------------------------------------------------
cfg = EAConfig()