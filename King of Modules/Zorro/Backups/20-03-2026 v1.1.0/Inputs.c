#ifndef INPUTS_C
#define INPUTS_C

// ── SWING MODE ────────────────────────────────────────────────
#define SWING_OFF   0
#define SWING_LONG  1
#define SWING_SHORT 2

// ── STOP MODE ─────────────────────────────────────────────────
#define STOP_FIXED     0
#define STOP_TECHNICAL 1
#define TRAILING_STOP  2

// ── TAKE MODE ─────────────────────────────────────────────────
#define TAKE_FIXED  0
#define TAKE_POINTS 1
#define TAKE_KAMA   2

// ── SIGNAL ────────────────────────────────────────────────────
#define SIGNAL_NONE  0
#define SIGNAL_BUY   1
#define SIGNAL_SELL -1

// ── Trade settings ────────────────────────────────────────────
int    InpLongMagicNumber  = 123456;
int    InpShortMagicNumber = 987654;
double InpLotSize          = 0.1;

// ── Equity step lot scaling ───────────────────────────────────
int    InpUseStepLotScaling = 0;
double InpStepCapital       = 1050.0;
double InpStepLot           = 0.05;

// ── Entries ───────────────────────────────────────────────────
int InpMaxSimultaneousTrades = 4;
int UseMRStrategy            = SWING_LONG;
int UseTBStrategy            = SWING_OFF;
int UseTPStrategy            = SWING_OFF;
int UseKTStrategy            = SWING_LONG;
int UseREStrategy            = SWING_OFF;

// ── Stop loss & trailing ──────────────────────────────────────
int    InpLongStopMode          = STOP_FIXED;
int    InpShortStopMode         = STOP_FIXED;
int    InpTechnicalStopLookback = 9;
double InpStopMultiplier        = 5.0;
int    InpStopExtraPoints       = 375;

// ── Take profit ───────────────────────────────────────────────
int    InpUseTakeProfit   = 1;
double InpTPMultiplier    = 4.0;
int    InpTakeExtraPoints = 50;
int    InpTakePoints      = 300;
int    InpLongTakeMode    = TAKE_KAMA;
int    InpShortTakeMode   = TAKE_KAMA;

// ── Time filter ───────────────────────────────────────────────
int InpUseTimeFilter = 1;
int InpStartHour     = 8;
int InpEndHour       = 20;

// ── RSI ───────────────────────────────────────────────────────
int    InpRSIPeriod         = 14;
double InpRSIOversold       = 28.0;
double InpRSIOverbought     = 72.0;
double InpRSIResetThreshold = 20.0;

// ── KAMA ──────────────────────────────────────────────────────
int InpKAMAPeriod     = 14;
int InpKAMAFastPeriod = 2;
int InpKAMASlowPeriod = 30;

// ── Keltner channel ───────────────────────────────────────────
int    InpKeltnerEMAPeriod = 14;
double InpKeltnerATRFactor = 2.5;

// ── ATR ───────────────────────────────────────────────────────
int    InpATRPeriod            = 14;
int    InpUseATRMRTrendFilter  = 1;
double InpATRMRTrendMultiplier = 1.01;
int    InpUseATRKTTrendFilter  = 1;
double InpATRKTTrendMultiplier = 0.775;
double InpATRRETrendMultiplier = 1.01;

// ── ADX ───────────────────────────────────────────────────────
int    InpADXPeriod      = 14;
int    InpUseADXFilter   = 1;
double InpADXComparision = 24.0;

// ── Mean distance filter ──────────────────────────────────────
int    InpUseMeanDistanceFilter = 1;
double InpMeanDistanceATRMult   = 0.4;

// ── KAMA strong trend filter ──────────────────────────────────
int    InpUseKAMAStrongTrendFilter = 1;
int    InpKAMASlopeLookback        = 8;
double InpKAMASlopeATRMultiplier   = 1.3;

// ── Globals ───────────────────────────────────────────────────
double g_initialBalance = 0.0;

#endif // INPUTS_C