// =========================================================
// FILE: Configs.c
// ROLE: Centralized configuration — NO logic allowed
// =========================================================

#ifndef CONFIGS_C
#define CONFIGS_C

// ------- Signal constants -------
#define SIGNAL_NONE   0
#define SIGNAL_BUY    1
#define SIGNAL_SELL  -1

// ------- Lot modes -------
#define LOT_FIXED    0
#define LOT_EQUITY   1
#define LOT_STEP     2

// ------- Stop modes -------
#define STOP_FIXED      0
#define STOP_TECHNICAL  1
#define STOP_TRAILING   2

// ------- Take modes -------
#define TAKE_FIXED      0
#define TAKE_SUPERTREND 1
#define TAKE_TRAILING   2

// ------- Strategy toggles -------
int UseMR  = 1;
int UsePB  = 1;
int UseBO  = 1;
int UseSCI = 1;

// ------- Time filter -------
int TimeFilterActive = 0;
int TradingHourStart = 8;
int TradingHourEnd   = 20;

// ------- Risk / lot model -------
int LotMode      = LOT_FIXED;
var RiskPercent  = 1.0;
var FixedLot     = 0.01;

// ------- Stop / take modes -------
int StopMode = STOP_FIXED;
int TakeMode = TAKE_FIXED;

// ------- Stop parameters -------
var FixedStopPoints  = 50.0;
var StopATRMult      = 1.5;
var StopBufferPoints = 5.0;
int StopLookback     = 10;

// ------- Take parameters -------
var FixedTakePoints = 100.0;
var TakeATRMult     = 2.0;

// ------- Core indicator parameters -------
int ATR_Period_1 = 14;
int ATR_Period_2 = 50;
int EMA_Fast     = 20;
int EMA_Slow     = 50;
int RSI_Period   = 14;
int ADX_Period   = 14;

// ------- Bollinger Bands -------
int BB_Period = 20;
var BB_StdDev = 2.0;

// ------- Keltner Channel -------
int KC_Period = 20;
var KC_Mult   = 1.5;

// ------- SuperTrend -------
int ST_Period = 10;
var ST_Mult   = 3.0;

// ------- RSI thresholds -------
var RSI_Overbought_Default = 70.0;
var RSI_Oversold_Default   = 30.0;

// ------- ADX thresholds -------
var ADX_Ranging_Max  = 20.0;
var ADX_Trending_Min = 25.0;

// ------- Strategy-specific: MR -------
var MR_RSI_Overbought = 65.0;
var MR_RSI_Oversold   = 35.0;

// ------- Strategy-specific: PB -------
var PB_RSI_Low         = 40.0;
var PB_RSI_High        = 60.0;
var PB_EMAProximityPct = 0.3;   // max % distance from EMA20

// ------- Strategy-specific: BO -------
int BO_StructureLookback = 20;  // bars for HH/LL structure

// ------- Equity tracking -------
var g_EquityStart = 0.0;

#endif // CONFIGS_C
