#ifndef __INPUTS_MQH__
#define __INPUTS_MQH__

//================ RSI =================
input group "=== RSI Settings ==="
input int    InpRSIPeriod         = 14;                       // RSI Period
input double InpRSIOversold       = 30.0;                     // RSI Oversold
input double InpRSIOverbought     = 70.0;                     // RSI Overbought
input double InpRSIResetThreshold = 20.0;                     // RSI Reset Threshold

//================ Distance Filter =================
input group "=== Mean Distance Filter ==="
input bool   InpUseMeanDistanceFilter = false;
input double InpMeanDistanceATRMult   = 1.2;


//================ Keltner =================
input group "=== Keltner Channel Settings ==="
input int    InpKeltnerEMAPeriod  = 20;                       // Keltner EMA Period
input double InpKeltnerATRFactor  = 2.0;                      // Keltner ATR Factor


//================ ATR =================
input group "=== ATR Settings ==="
input int    InpATRPeriod                = 14;                // ATR Period
input bool   InpUseATRStrongTrendFilter  = false;             // Use ATR Strong Trend Filter
input double InpATRStrongTrendMultiplier = 1.0;               // ATR Strong Trend Multiplier


//================ KAMA Trend Filter =================
input group "=== KAMA Strong Trend Filter ==="
input bool   InpUseKAMAStrongTrendFilter = false;             // Use KAMA Strong Trend Filter
input int    InpKAMASlopeLookback        = 5;                 // KAMA Slope Lookback
input double InpKAMASlopeATRMultiplier   = 1.5;               // KAMA Slope ATR Multiplier


//================ KAMA =================
input group "=== KAMA Settings ==="
input int InpKAMAPeriod     = 14;                             // KAMA Period
input int InpKAMAFastPeriod = 2;                              // KAMA Fast Period
input int InpKAMASlowPeriod = 30;                             // KAMA Slow Period


//================ Stops =================
enum ENUM_STOP_MODE
{
   STOP_FIXED     = 0,
   STOP_TECHNICAL = 1,
   TRAILING_STOP  = 2
};
input group "=== Stop Loss & Trailing ==="
input ENUM_STOP_MODE InpStopMode              = STOP_FIXED;   // Stop Mode
input int            InpTechnicalStopLookback = 5;            // Technical Stop Lookback (Bars to look back for swing high/low)
input double         InpStopMultiplier        = 2.0;          // Stop Multiplier
input int            InpExtraPoints           = 5;            // Extra Points


//================ Take =================
enum ENUM_TAKE_MODE
{
    TAKE_FIXED = 0,
    TAKE_KAMA  = 1
};
input group "=== Take ==="
input bool           InpUseTakeProfit = false;                // Use Take Profit
input double         InpTPMultiplier  = 2.0;                  // TP Multiplier
input ENUM_TAKE_MODE InpTakeMode      = TAKE_FIXED;           // Take Mode


//================ Trading =================
input group "=== Trade Settings ==="
input double InpLotSize     = 0.1;                            // Lot Size
input int    InpMagicNumber = 123456;                         // Magic Number


//================ Time Filter =================
input group "=== Time Filter ==="
input bool InpUseTimeFilter = false;                          // Use Time Filter
input int  InpStartHour     = 8;                              // Start Hour
input int  InpEndHour       = 20;                             // End Hour


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