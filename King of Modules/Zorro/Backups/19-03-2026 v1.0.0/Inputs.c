// ============================================================
//  Inputs.c  –  Zorro translation of Inputs.mqh
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
// ============================================================

#ifndef INPUTS_C
#define INPUTS_C

// ============================================================
//  ENUMS
// ============================================================

// ENUM_SWING_MODE
// NOTE: 'LONG' and 'SHORT' conflict with C / Lite-C builtins.
//       Renamed to SWING_LONG / SWING_SHORT / SWING_OFF.
//       Update all usages in every module accordingly.
typedef enum {
    SWING_OFF   = 0,
    SWING_LONG  = 1,
    SWING_SHORT = 2
} ENUM_SWING_MODE;

typedef enum {
    STOP_FIXED     = 0,
    STOP_TECHNICAL = 1,
    TRAILING_STOP  = 2
} ENUM_STOP_MODE;

typedef enum {
    TAKE_FIXED  = 0,
    TAKE_POINTS = 1,
    TAKE_KAMA   = 2
} ENUM_TAKE_MODE;

typedef enum {
    SIGNAL_NONE =  0,
    SIGNAL_BUY  =  1,
    SIGNAL_SELL = -1
} ENUM_SIGNAL;


// ============================================================
//  TRADE SETTINGS
// ============================================================
int    InpLongMagicNumber  = 123456;    // Long Swings Magic Number  [not used – Zorro isolates trades per script]
int    InpShortMagicNumber = 987654;    // Short Swings Magic Number [same note]
double InpLotSize          = 0.1;       // Lot Size


// ============================================================
//  EQUITY STEP LOT SCALING
// ============================================================
int    InpUseStepLotScaling = 0;        // Use Step Lot Scaling (0=false / 1=true)
double InpStepCapital       = 100.0;    // Capital step that triggers a lot increment
double InpStepLot           = 0.01;     // Lot increment per step


// ============================================================
//  ENTRIES
// ============================================================
int             InpMaxSimultaneousTrades = 4;           // Maximum simultaneous trades allowed
ENUM_SWING_MODE UseMRStrategy            = SWING_LONG;  // Mean Reversion Strategy
ENUM_SWING_MODE UseTBStrategy            = SWING_SHORT; // Trendline Breakout Strategy (Not Implemented)
ENUM_SWING_MODE UseTPStrategy            = SWING_LONG;  // Trend Pullback Strategy (Not Implemented)
ENUM_SWING_MODE UseKTStrategy            = SWING_LONG;  // KAMA Trend Strategy
ENUM_SWING_MODE UseREStrategy            = SWING_SHORT; // RSI Exhaustion Strategy (Partial)


// ============================================================
//  STOP LOSS & TRAILING
// ============================================================
ENUM_STOP_MODE InpLongStopMode          = STOP_FIXED;  // Long stop mode
ENUM_STOP_MODE InpShortStopMode         = STOP_FIXED;  // Short stop mode
int            InpTechnicalStopLookback = 9;            // Bars to look back for swing high/low
double         InpStopMultiplier        = 5.0;          // Stop multiplier (ATR-based)
int            InpStopExtraPoints       = 375;          // Extra points added to stop distance


// ============================================================
//  TAKE PROFIT
// ============================================================
int            InpUseTakeProfit   = 1;              // Use Take Profit (0=false / 1=true)
double         InpTPMultiplier    = 4.0;            // TP multiplier (ATR-based)
int            InpTakeExtraPoints = 50;             // Extra points added to TP distance
int            InpTakePoints      = 300;            // Fixed TP in points (TAKE_POINTS mode)
ENUM_TAKE_MODE InpLongTakeMode    = TAKE_KAMA;      // Long take mode
ENUM_TAKE_MODE InpShortTakeMode   = TAKE_KAMA;      // Short take mode


// ============================================================
//  TIME FILTER
// ============================================================
int InpUseTimeFilter = 1;    // Use Time Filter (0=false / 1=true)
int InpStartHour     = 8;    // Trading window start hour (server time)
int InpEndHour       = 20;   // Trading window end hour   (server time)


// ============================================================
//  RSI
// ============================================================
int    InpRSIPeriod         = 14;    // RSI period
double InpRSIOversold       = 28.0;  // RSI oversold threshold
double InpRSIOverbought     = 72.0;  // RSI overbought threshold
double InpRSIResetThreshold = 20.0;  // RSI reset threshold


// ============================================================
//  KAMA
// ============================================================
int InpKAMAPeriod     = 14;  // KAMA period
int InpKAMAFastPeriod = 2;   // KAMA fast EMA period
int InpKAMASlowPeriod = 30;  // KAMA slow EMA period


// ============================================================
//  KELTNER CHANNEL
// ============================================================
int    InpKeltnerEMAPeriod = 14;   // Keltner EMA period
double InpKeltnerATRFactor = 2.5;  // Keltner ATR multiplier


// ============================================================
//  ATR
// ============================================================
int    InpATRPeriod            = 14;    // ATR period
int    InpUseATRMRTrendFilter  = 1;     // ATR Mean Reversion strong-trend filter (0/1)
double InpATRMRTrendMultiplier = 1.01;  // ATR MR multiplier
int    InpUseATRKTTrendFilter  = 1;     // ATR KAMA Trend strong-trend filter (0/1)
double InpATRKTTrendMultiplier = 0.775; // ATR KT multiplier
double InpATRRETrendMultiplier = 1.01;  // ATR RSI Exhaustion multiplier


// ============================================================
//  ADX
// ============================================================
int    InpADXPeriod      = 14;    // ADX period
int    InpUseADXFilter   = 1;     // Use ADX filter (0/1)
double InpADXComparision = 24.0;  // ADX threshold for filter


// ============================================================
//  MEAN DISTANCE FILTER
// ============================================================
int    InpUseMeanDistanceFilter = 1;    // Use Mean Distance Filter (0/1)
double InpMeanDistanceATRMult   = 0.4;  // Distance multiplier (ATR-based)


// ============================================================
//  KAMA STRONG TREND FILTER
// ============================================================
int    InpUseKAMAStrongTrendFilter = 1;    // Use KAMA Strong Trend Filter (0/1)
int    InpKAMASlopeLookback        = 8;    // KAMA slope lookback bars
double InpKAMASlopeATRMultiplier   = 1.3;  // KAMA slope ATR multiplier


// ============================================================
//  LOT SCALING GLOBALS
// ============================================================
double g_initialBalance   = 0.0;  // Captured at init; used for step-lot scaling
double g_currentScaledLot = 0.0;  // Current computed lot size

#endif // INPUTS_C
