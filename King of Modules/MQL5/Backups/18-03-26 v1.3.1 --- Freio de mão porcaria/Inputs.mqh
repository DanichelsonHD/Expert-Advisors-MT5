#ifndef __INPUTS_MQH__
#define __INPUTS_MQH__

//================ Trading =================
input group "=== Trade Settings ==="
input int    InpLongMagicNumber       = 123456;               // Long Swings Magic Number
input int    InpShortMagicNumber      = 987654;               // Short Swings Magic Number
input double InpLotSize               = 0.1;                  // Lot Size


//================ Equity Step Lot Scaling =================
input group "=== Equity Step Lot Scaling ==="
input bool   InpUseStepLotScaling = false;                    // Use Step Lot Scaling
input double InpStepCapital       = 100.0;                    // Step Capital
input double InpStepLot           = 0.01;                     // Step Lot


//================ Time Filter =================
input group "=== Time Filter ==="
input bool InpUseTimeFilter = true;                           // Use Time Filter
input int  InpStartHour     = 8;                              // Start Hour
input int  InpEndHour       = 20;                             // End Hour


//================ Drawdown Protection =================
input group "=== Drawdown Protection ==="
input bool   InpUseMaxDDPercent     = true;  // Activate Max DD Percent Manager
input double InpMaxDailyDDPercent   = 3.0;   // Max daily DD (%)
input double InpMaxGlobalDDPercent  = 8.0;   // Max total DD (%)


//================ Lot Reduction During Drawdown =================
input group "=== DD Lot Reduction ==="
input bool   InpUseDDLotReduction   = true;  // Active Lot Reduction by DD
input double InpDDLevel1            = 5.0;   // DD threshold 1 (%)
input double InpDDReduction1        = 0.5;   // Lot multiplier at level 1
input double InpDDLevel2            = 10.0;  // DD threshold 2 (%)
input double InpDDReduction2        = 0.25;  // Lot multiplier at level 2


//================ Entries =================
input group "=== Entries ==="
enum ENUM_SWING_MODE
{
   OFF     = 0,
   LONG = 1,
   SHORT  = 2
};
input int             InpMaxSimultaneousTrades = 4;           // Maximum simultaneous trades allowed
input ENUM_SWING_MODE UseMRStrategy            = LONG;        // Use Mean Reversion Strategy
input ENUM_SWING_MODE UseTBStrategy            = SHORT;       // Use Trendline Breakout Strategy - Not Implemented
input ENUM_SWING_MODE UseTPStrategy            = LONG;        // Use Tend Pullback Strategy - Not Implemented
input ENUM_SWING_MODE UseKTStrategy            = LONG;        // Use KAMA Trend Strategy
input ENUM_SWING_MODE UseREStrategy            = SHORT;       // Use RSI Exhaustion Strategy - Half-way Implemented


//================ Stops =================
enum ENUM_STOP_MODE
{
   STOP_FIXED     = 0,
   STOP_TECHNICAL = 1,
   TRAILING_STOP  = 2
};
input group "=== Stop Loss & Trailing ==="
input ENUM_STOP_MODE InpLongStopMode          = STOP_FIXED;   // Long Swing Stop Mode
input ENUM_STOP_MODE InpShortStopMode         = STOP_FIXED;   // Short Swing Stop Mode
input int            InpTechnicalStopLookback = 9;            // Technical Stop Lookback (Bars to look back for swing high/low)
input double         InpStopMultiplier        = 5.0;          // Stop Multiplier
input int            InpStopExtraPoints       = 375;          // Extra Points


//================ Takes =================
enum ENUM_TAKE_MODE
{
    TAKE_FIXED  = 0,
    TAKE_POINTS = 1,
    TAKE_KAMA   = 2
};
input group "=== Takes ==="
input bool           InpUseTakeProfit   = true;               // Use Take Profit
input double         InpTPMultiplier    = 4.0;                // TP Multiplier
input int            InpTakeExtraPoints = 50;                 // Extra Points
input int            InpTakePoints      = 300;                // Take Based by Points
input ENUM_TAKE_MODE InpLongTakeMode    = TAKE_KAMA;          // Long Take Mode
input ENUM_TAKE_MODE InpShortTakeMode   = TAKE_KAMA;          // Short Take Mode


//================ RSI =================
input group "=== RSI Settings ==="
input int    InpRSIPeriod         = 14;                       // RSI Period
input double InpRSIOversold       = 28.0;                     // RSI Oversold
input double InpRSIOverbought     = 72.0;                     // RSI Overbought
input double InpRSIResetThreshold = 20.0;                     // RSI Reset Threshold


//================ KAMA =================
input group "=== KAMA Settings ==="
input int InpKAMAPeriod     = 14;                             // KAMA Period
input int InpKAMAFastPeriod = 2;                              // KAMA Fast Period
input int InpKAMASlowPeriod = 30;                             // KAMA Slow Period


//================ Keltner =================
input group "=== Keltner Channel Settings ==="
input int    InpKeltnerEMAPeriod  = 14;                       // Keltner EMA Period
input double InpKeltnerATRFactor  = 2.5;                      // Keltner ATR Factor


//================ ATR =================
input group "=== ATR Settings ==="
input int    InpATRPeriod            = 14;                    // ATR Period
input bool   InpUseATRMRTrendFilter  = true;                  // Use ATR Mean Reversion Strong Trend Filter
input double InpATRMRTrendMultiplier = 1.01;                  // ATR Mean Reversion Strong Trend Multiplier
input bool   InpUseATRKTTrendFilter  = true;                  // Use ATR Kama Trend Strong Trend Filter
input double InpATRKTTrendMultiplier = 0.775;                 // ATR Kama Trend Strong Trend Multiplier
input double InpATRRETrendMultiplier = 1.01;                  // ATR RSI Exhaustion Strong Trend Multiplier


//================ ADX =================
input group "=== ADX Settings ==="
input int    InpADXPeriod                = 14;                // ADX Period
input bool   InpUseADXFilter             = true;              // Use ADX Filter
input double InpADXComparision           = 24;                // ADX Comparision


//================ Distance Filter =================
input group "=== Mean Distance Filter ==="
input bool   InpUseMeanDistanceFilter = true;                 // Use Mean Distance Filter
input double InpMeanDistanceATRMult   = 0.4;                  // Mean Distance Multiplier


//================ KAMA Trend Filter =================
input group "=== KAMA Strong Trend Filter ==="
input bool   InpUseKAMAStrongTrendFilter = true;              // Use KAMA Strong Trend Filter
input int    InpKAMASlopeLookback        = 8;                 // KAMA Slope Lookback
input double InpKAMASlopeATRMultiplier   = 1.3;               // KAMA Slope ATR Multiplier


enum ENUM_SIGNAL
{
   SIGNAL_NONE =  0,
   SIGNAL_BUY  =  1,
   SIGNAL_SELL = -1
};


//--- Lot scaling globals
double g_initialBalance    = 0.0;
double g_currentScaledLot  = 0.0;

//--- Drawdown globals
double   g_dailyStartBalance = 0.0;
datetime g_lastDay           = 0;

//--- Global trade objects
CTrade        g_trade;
CPositionInfo g_position;

#endif