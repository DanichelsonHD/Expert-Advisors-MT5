import os
from dataclasses import dataclass
from enum import IntEnum

_HERE = os.path.dirname(os.path.abspath(__file__))


# ---------------------------------------------------------------------------
# Enumerations (mirror of MQL5 enums in Inputs.mqh)
# ---------------------------------------------------------------------------

class StopMode(IntEnum):
    FIXED     = 0
    TECHNICAL = 1
    TRAILING  = 2


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

    # --- Operational Mode Switches ---
    enable_trading:   bool = True
    enable_backtest:  bool = True
    enable_live_feed: bool = False

    # --- Symbol & Market ---
    symbol:        str = "XAUUSD"
    magic_number:  int = 123456
    order_comment: str = "KingOfModules"

    # --- Trade Settings ---
    lot_size:     float = 0.1
    min_lot_size: float = 0.01
    max_lot_size: float = 100.0
    lot_step:     float = 0.01

    # --- Entries ---
    max_simultaneous_trades: int  = 4
    use_mr_strategy:         bool = True
    use_tb_strategy:         bool = False
    use_tp_strategy:         bool = False
    use_kt_strategy:         bool = True

    # --- Stop Loss & Trailing ---
    stop_mode:               StopMode = StopMode.TRAILING
    technical_stop_lookback: int      = 9
    stop_multiplier:         float    = 5.0
    extra_points:            int      = 375

    # --- Take Profit ---
    use_take_profit: bool     = True
    tp_multiplier:   float    = 4.0
    take_mode:       TakeMode = TakeMode.KAMA

    # --- Time Filter ---
    use_time_filter: bool = True
    start_hour:      int  = 7
    end_hour:        int  = 21

    # --- RSI ---
    rsi_period:          int   = 14
    rsi_oversold:        float = 28.0
    rsi_overbought:      float = 72.0
    rsi_reset_threshold: float = 20.0

    # --- KAMA ---
    kama_period:      int = 14
    kama_fast_period: int = 2
    kama_slow_period: int = 30

    # --- Keltner Channel ---
    keltner_ema_period: int   = 14
    keltner_atr_factor: float = 2.5

    # --- ATR ---
    atr_period:              int   = 14
    use_atr_mr_trend_filter: bool  = True
    atr_mr_trend_multiplier: float = 1.01
    use_atr_kt_trend_filter: bool  = True
    atr_kt_trend_multiplier: float = 0.775

    # --- ADX ---
    adx_period:     int   = 14
    use_adx_filter: bool  = True
    adx_comparison: float = 24.0

    # --- Mean Distance Filter ---
    use_mean_distance_filter: bool  = True
    mean_distance_atr_mult:   float = 0.4

    # --- KAMA Strong Trend Filter ---
    use_kama_strong_trend_filter: bool  = True
    kama_slope_lookback:          int   = 8
    kama_slope_atr_multiplier:    float = 1.3

    # --- Equity Step Lot Scaling ---
    use_step_lot_scaling: bool  = False
    initial_lot:          float = 0.10
    step_capital:         float = 100.0
    step_lot:             float = 0.01

    # --- Data ---
    data_path_h1:      str = os.path.join(_HERE, "Data", "EURUSD_H1_2023-2026.csv")
    bars_to_fetch:     int = 500
    max_lookback_bars: int = 55

    # --- Symbol precision (used in backtest — no MT5 connection) ---
    symbol_point:  float = 0.01
    symbol_digits: int   = 2

    # --- Logging ---
    log_level:        str  = "INFO"
    log_to_file:      bool = True
    log_to_console:   bool = True
    log_file_path:    str  = os.path.join(_HERE, "Logs", "king_of_modules.log")
    log_max_bytes:    int  = 5 * 1024 * 1024
    log_backup_count: int  = 3


# ---------------------------------------------------------------------------
# Singleton
# ---------------------------------------------------------------------------
cfg = EAConfig()
