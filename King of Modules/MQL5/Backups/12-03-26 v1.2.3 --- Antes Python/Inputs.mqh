#ifndef __INPUTS_MQH__
#define __INPUTS_MQH__

//================ Trading =================
input group "=== Trade Settings ==="
input double InpLotSize               = 0.1;                  // Lot Size
input int    InpLongMagicNumber       = 123456;               // Long Swings Magic Number
input int    InpShortMagicNumber      = 987654;               // Short Swings Magic Number


//================ Entries =================
input group "=== Entries ==="
enum ENUM_SWING_MODE
{
   OFF     = 0,
   LONG = 1,
   SHORT  = 2
};
input int             InpMaxSimultaneousTrades = 2;           // Maximum simultaneous trades allowed
input ENUM_SWING_MODE UseMRStrategy            = LONG;        // Use Mean Reversion Strategy
input ENUM_SWING_MODE UseTBStrategy            = SHORT;       // Use Trendline Breakout Strategy
input ENUM_SWING_MODE UseTPStrategy            = LONG;        // Use Tend Pullback Strategy
input ENUM_SWING_MODE UseKTStrategy            = LONG;        // Use KAMA Trend Strategy
input ENUM_SWING_MODE UseREStrategy            = SHORT;       // Use RSI Exhaustion Strategy


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
input int            InpTechnicalStopLookback = 5;            // Technical Stop Lookback (Bars to look back for swing high/low)
input double         InpStopMultiplier        = 2.0;          // Stop Multiplier
input int            InpStopExtraPoints       = 5;            // Extra Points


//================ Takes =================
enum ENUM_TAKE_MODE
{
    TAKE_FIXED = 0,
    TAKE_KAMA  = 1
};
input group "=== Takes ==="
input bool           InpUseTakeProfit   = false;              // Use Take Profit
input double         InpTPMultiplier    = 2.0;                // TP Multiplier
input int            InpTakeExtraPoints = 5;                  // Extra Points
input ENUM_TAKE_MODE InpTakeMode        = TAKE_FIXED;         // Take Mode


//================ Time Filter =================
input group "=== Time Filter ==="
input bool InpUseTimeFilter = false;                          // Use Time Filter
input int  InpStartHour     = 8;                              // Start Hour
input int  InpEndHour       = 20;                             // End Hour


//================ RSI =================
input group "=== RSI Settings ==="
input int    InpRSIPeriod         = 14;                       // RSI Period
input double InpRSIOversold       = 30.0;                     // RSI Oversold
input double InpRSIOverbought     = 70.0;                     // RSI Overbought
input double InpRSIResetThreshold = 20.0;                     // RSI Reset Threshold


//================ KAMA =================
input group "=== KAMA Settings ==="
input int InpKAMAPeriod     = 14;                             // KAMA Period
input int InpKAMAFastPeriod = 2;                              // KAMA Fast Period
input int InpKAMASlowPeriod = 30;                             // KAMA Slow Period


//================ Keltner =================
input group "=== Keltner Channel Settings ==="
input int    InpKeltnerEMAPeriod  = 20;                       // Keltner EMA Period
input double InpKeltnerATRFactor  = 2.0;                      // Keltner ATR Factor


//================ ATR =================
input group "=== ATR Settings ==="
input int    InpATRPeriod                = 14;                // ATR Period
input bool   InpUseATRMRTrendFilter  = true;                  // Use ATR Mean Reversion Strong Trend Filter
input double InpATRMRTrendMultiplier = 1.01;                  // ATR Mean Reversion Strong Trend Multiplier
input bool   InpUseATRKTTrendFilter  = true;                  // Use ATR Kama Trend Strong Trend Filter
input double InpATRKTTrendMultiplier = 0.775;                 // ATR Kama Trend Strong Trend Multiplier
input double InpATRRETrendMultiplier = 1.01;                  // ATR RSI Exhaustion Strong Trend Multiplier


//================ ADX =================
input group "=== ADX Settings ==="
input int    InpADXPeriod                = 14;                // ADX Period
input bool   InpUseADXFilter             = true;              // Use ADX Filter
input double InpADXComparision           = 22;                // ADX Comparision


//================ Distance Filter =================
input group "=== Mean Distance Filter ==="
input bool   InpUseMeanDistanceFilter = false;
input double InpMeanDistanceATRMult   = 1.2;


//================ KAMA Trend Filter =================
input group "=== KAMA Strong Trend Filter ==="
input bool   InpUseKAMAStrongTrendFilter = false;             // Use KAMA Strong Trend Filter
input int    InpKAMASlopeLookback        = 5;                 // KAMA Slope Lookback
input double InpKAMASlopeATRMultiplier   = 1.5;               // KAMA Slope ATR Multiplier


//================ Equity Step Lot Scaling =================
input group "=== Equity Step Lot Scaling ==="
input bool   InpUseStepLotScaling = false;                    // Use Step Lot Scaling
input double InpInitialLot        = 0.10;                     // Initial Lot
input double InpStepCapital       = 100.0;                    // Step Capital
input double InpStepLot           = 0.01;                     // Step Lot

enum ENUM_SIGNAL
{
   SIGNAL_NONE =  0,
   SIGNAL_BUY  =  1,
   SIGNAL_SELL = -1
};

#endif