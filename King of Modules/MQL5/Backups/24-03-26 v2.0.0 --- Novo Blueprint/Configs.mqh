//+------------------------------------------------------------------+
//|                                                      Configs.mqh |
//+------------------------------------------------------------------+
#ifndef CONFIGS_MQH
#define CONFIGS_MQH

//--- Risk & Lot Sizing
input group "=== Risk Management ==="
input double   InpFixedLot              = 0.10;   // Fixed lot size (base)
input double   InpRiskPercent           = 1.0;    // Risk % per trade (risk-based mode)
input double   InpBalanceStep           = 1000.0; // Balance step for step scaling ($)
input double   InpLotStep               = 0.01;   // Lot increment per balance step
enum ENUM_LOT_MODE { LOT_FIXED, LOT_STEP_SCALING, LOT_RISK_BASED };
input ENUM_LOT_MODE InpLotMode          = LOT_FIXED; // Lot sizing mode

//--- Global Trade Limits
input group "=== Trade Limits ==="
input int      InpMaxGlobalTrades       = 4;      // Max total open trades (all strategies)
input int      InpMaxTradesPerStrategy  = 1;      // Max open trades per strategy

//--- Strategy Enable Flags
input group "=== Strategy Enable/Disable ==="
input bool     InpEnableMeanReversion   = true;   // Enable Mean Reversion strategy
input bool     InpEnablePullback        = true;   // Enable Pullback strategy
input bool     InpEnableBreakout        = true;   // Enable Breakout strategy
input bool     InpEnableKCI             = true;   // Enable KAMA Color Inversion strategy

//--- EMA Parameters
input group "=== EMA Settings ==="
input int      InpEMA20Period           = 20;     // EMA 20 period
input int      InpEMA50Period           = 50;     // EMA 50 period

//--- RSI Parameters
input group "=== RSI Settings ==="
input int      InpRSIPeriod             = 14;     // RSI period
input double   InpRSIOverbought         = 70.0;   // RSI overbought level
input double   InpRSIOversold           = 30.0;   // RSI oversold level
input double   InpRSIPullbackHigh       = 60.0;   // RSI pullback upper level
input double   InpRSIPullbackLow        = 40.0;   // RSI pullback lower level

//--- ATR Parameters
input group "=== ATR Settings ==="
input int      InpATR14Period           = 14;     // ATR 14 period
input int      InpATR50Period           = 50;     // ATR 50 period

//--- ADX Parameters
input group "=== ADX Settings ==="
input int      InpADXPeriod             = 14;     // ADX period
input double   InpADXTrending           = 25.0;   // ADX trending threshold
input double   InpADXRanging            = 23.0;   // ADX ranging threshold

//--- Bollinger Bands Parameters
input group "=== Bollinger Bands Settings ==="
input int      InpBBPeriod              = 20;     // BB period
input double   InpBBDeviation           = 2.0;    // BB deviation

//--- Keltner Channel Parameters
input group "=== Keltner Channel Settings ==="
input int      InpKCPeriod              = 20;     // KC EMA period
input int      InpKCATRPeriod           = 14;     // KC ATR period
input double   InpKCMultiplier          = 1.5;    // KC ATR multiplier

//--- KAMA Parameters
input group "=== KAMA Settings ==="
input int      InpKAMAPeriod            = 14;     // KAMA period
input int      InpKAMAFastPeriod        = 2;      // KAMA fast end period
input int      InpKAMASlowPeriod        = 30;     // KAMA slow end period
input double   InpKAMAPower             = 2.0;    // KAMA smooth power
input int      InpKAMAFilter            = 50;     // KAMA filter
input int      InpKAMAFilterPeriod      = 4;      // KAMA filter period
input double   InpKAMAFilterDiff        = 50.0;   // KAMA filter difference

//--- Stop Types
input group "=== Stop Settings ==="
input double   InpATRStopMultiplier     = 1.5;    // ATR stop multiplier
input double   InpFixedStopPoints       = 200.0;  // Fixed stop (points)
input double   InpTechStopBufferPoints  = 50.0;   // Technical stop buffer (points)
input int      InpTechLookbackBars      = 10;     // Technical lookback bars

//--- Take Types
input group "=== Take Settings ==="
input double   InpATRTakeMultiplier     = 2.0;    // ATR take multiplier
input double   InpFixedTakePoints       = 400.0;  // Fixed take (points)

//--- Stop/Take Selection Per Strategy
enum ENUM_STOP_TYPE { STOP_TECHNICAL, STOP_FIXED, STOP_ATR };
enum ENUM_TAKE_TYPE { TAKE_FIXED, TAKE_KAMA_FLIP, TAKE_ATR_TRAILING };

input group "=== Mean Reversion Stop/Take ==="
input ENUM_STOP_TYPE InpMRStopType      = STOP_ATR;        // MR stop type
input ENUM_TAKE_TYPE InpMRTakeType      = TAKE_FIXED;      // MR take type

input group "=== Pullback Stop/Take ==="
input ENUM_STOP_TYPE InpPBStopType      = STOP_ATR;        // PB stop type
input ENUM_TAKE_TYPE InpPBTakeType      = TAKE_ATR_TRAILING; // PB take type

input group "=== Breakout Stop/Take ==="
input ENUM_STOP_TYPE InpBOStopType      = STOP_TECHNICAL;  // BO stop type
input ENUM_TAKE_TYPE InpBOTakeType      = TAKE_ATR_TRAILING; // BO take type

input group "=== KCI Stop/Take ==="
input ENUM_STOP_TYPE InpKCIStopType     = STOP_ATR;        // KCI stop type
input ENUM_TAKE_TYPE InpKCITakeType     = TAKE_KAMA_FLIP;  // KCI take type

#endif
