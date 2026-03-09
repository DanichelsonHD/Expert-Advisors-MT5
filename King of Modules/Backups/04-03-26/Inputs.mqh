#ifndef __INPUTS_MQH__
#define __INPUTS_MQH__

//================ RSI =================
input group "=== RSI Settings ==="
input int    InpRSIPeriod         = 14;
input double InpRSIOversold       = 30.0;
input double InpRSIOverbought     = 70.0;
input double InpRSIResetThreshold = 20.0;


//================ Keltner =================
input group "=== Keltner Channel Settings ==="
input int    InpKeltnerEMAPeriod  = 20;
input double InpKeltnerATRFactor  = 2.0;


//================ ATR =================
input group "=== ATR Settings ==="
input int InpATRPeriod = 14;


//================ Volatility =================
input group "=== Volatility Filter ==="
input double InpVolatilityMult = 0.8;


//================ KAMA Trend Filter =================
input group "=== KAMA Strong Trend Filter ==="
input bool   InpUseKAMAStrongTrendFilter = false;
input int    InpKAMASlopeLookback        = 5;
input double InpKAMASlopeATRMultiplier   = 1.5;


//================ KAMA =================
input group "=== KAMA Settings ==="
input int InpKAMAPeriod     = 14;
input int InpKAMAFastPeriod = 2;
input int InpKAMASlowPeriod = 30;


//================ Stops =================
enum ENUM_STOP_MODE
{
   STOP_FIXED = 0,
   STOP_TECHNICAL = 1
};
input group "=== Stop Loss & Trailing ==="
input ENUM_STOP_MODE InpStopMode = STOP_FIXED;
input double InpStopMultiplier     = 2.0;
input double InpTrailingMultiplier = 2.0;
input int    InpExtraPoints        = 5;


//================ Take =================
enum ENUM_TAKE_MODE
{
    TAKE_FIXED = 0,
    TAKE_KAMA  = 1
};
input group "=== Take==="
input bool   InpUseTakeProfit = false;
input double InpTPMultiplier  = 2.0;
input ENUM_TAKE_MODE InpTakeMode = TAKE_FIXED;


//================ Trading =================
input group "=== Trade Settings ==="
input double InpLotSize     = 0.1;
input int    InpMagicNumber = 123456;


//================ Time Filter =================
input group "=== Time Filter ==="
input bool InpUseTimeFilter = false;
input int  InpStartHour     = 8;
input int  InpEndHour       = 20;


//================ Equity Step Lot Scaling =================
input group "=== Equity Step Lot Scaling ==="
input bool   InpUseStepLotScaling = false;
input double InpInitialLot        = 0.10;
input double InpStepCapital       = 100.0;
input double InpStepLot           = 0.01;

#endif