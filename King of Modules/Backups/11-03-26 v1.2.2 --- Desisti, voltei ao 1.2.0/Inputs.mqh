#ifndef __INPUTS_MQH__
#define __INPUTS_MQH__

//================ Trading =================
input group "=== Trade Settings ==="
input double InpLotSize               = 0.1;                  // Lot Size
input int    InpMagicNumber           = 123456;               // Magic Number (base — used by g_trade for management ops)


//================ Strategy Magic Numbers =================
// First digit encodes swing type:
//   Short Swing (MR, RE) -> starts with 1, 3, or 5
//   Long  Swing (KT, TB) -> starts with 2, 4, or 6
input group "=== Strategy Magic Numbers ==="
input int    InpMagicMR = 10001;                              // Magic — Mean Reversion    (Short Swing)
input int    InpMagicRE = 10002;                              // Magic — RSI Exhaustion    (Short Swing)
input int    InpMagicTP = 20001;                              // Magic — Trend Pullback    (Long Swing)
input int    InpMagicTB = 20002;                              // Magic — Trend Breakout    (Long Swing)
input int    InpMagicKT = 20003;                              // Magic — KAMA Trend        (Long Swing)


//================ Entries =================
input group "=== Entries ==="
input int    InpMaxSimultaneousTrades = 2;                    // Maximum simultaneous trades allowed
input bool   UseMRStrategy            = false;                // Use Mean Reversion Strategy
input bool   UseTBStrategy            = false;                // Use Trendline Breakout Strategy
input bool   UseTPStrategy            = false;                // Use Tend Pullback Strategy
input bool   UseKTStrategy            = false;                // Use KAMA Trend Strategy
input bool   UseREStrategy            = false;                // Use RSI Exhaustion Strategy


//================ Stops =================
enum ENUM_STOP_MODE
{
   STOP_FIXED     = 0,
   STOP_TECHNICAL = 1,
   TRAILING_STOP  = 2
};
input group "=== Stop Loss & Trailing ==="
input ENUM_STOP_MODE InpStopMode              = STOP_FIXED;   // Stop Mode
input double         InpStopMultiplier        = 2.0;          // Stop Multiplier (ATR mode)
input int            InpExtraPoints           = 5;            // Extra Points (ATR mode)


//================ Short Swing Stop =================
input group "=== Short Swing Stop ==="
input int InpShortSwingLookback      = 9;                     // Short Swing Stop Lookback (candles)
input int InpShortSwingBufferPoints  = 5500;                  // Short Swing Stop Buffer (points)


//================ Long Swing Stop =================
input group "=== Long Swing Stop ==="
input int InpLongSwingLookback       = 20;                    // Long Swing Stop Lookback (candles)
input int InpLongSwingBufferPoints   = 8000;                  // Long Swing Stop Buffer (points)


//================ Takes =================
enum ENUM_TAKE_MODE
{
    TAKE_MULTIPLIER = 0,
    TAKE_KAMA  = 1,
    TAKE_POINTS = 2
};
input group "=== Takes ==="
input bool           InpUseTakeProfit = false;                // Use Take Profit
input double         InpTPMultiplier  = 2.0;                  // TP Multiplier (ATR mode)
input int            InpTPPoints      = 10000;                // TP Fixed Points (TAKE_POINTS mode)
input ENUM_TAKE_MODE InpTakeMode      = TAKE_POINTS;           // Take Mode for Long Swing Strategies


//================ Short Swing Takes =================
enum ENUM_SHORT_TAKE_MODE
{
   TAKE_FIXED_POINTS    = 0,
   TAKE_ATR_MULTIPLIER  = 1
};
input group "=== Short Swing Take Profit ==="
input ENUM_SHORT_TAKE_MODE InpShortTakeMode   = TAKE_ATR_MULTIPLIER; // Short Swing TP Mode
input int                  InpShortTakePoints = 300;                  // Short Swing TP Fixed Points
input double               InpShortTPMultiplier = 1.5;               // Short Swing TP ATR Multiplier


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
input bool   InpUseATRREFilter       = true;                  // Use ATR RSI Exhaustion Compression Filter
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