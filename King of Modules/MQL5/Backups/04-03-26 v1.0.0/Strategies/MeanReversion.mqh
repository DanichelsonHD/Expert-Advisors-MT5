#ifndef __MEAN_REVERSION_MQH__
#define __MEAN_REVERSION_MQH__

#include "../Indicators.mqh"

//--- Entry state: persists across candles, reset only on explicit transitions
enum ENUM_ENTRY_STATE
{
   STATE_IDLE                 = 0,
   STATE_OVERSOLD_CONFIRMED   = 1,
   STATE_OVERBOUGHT_CONFIRMED = 2
};

ENUM_ENTRY_STATE g_entryState = STATE_IDLE;

//+------------------------------------------------------------------+
//| Condition checkers — pure signal detection, no side effects      |
//+------------------------------------------------------------------+
bool IsOversoldCondition(const double curRSI, const double close1, const double lowerK)
{
   double kamaColor[2];
   if(CopyBuffer(g_handleKAMA, 1, 1, 2, kamaColor) < 2)
      return false;
   int colorNow = (int)MathRound(kamaColor[1]);
   return(curRSI < InpRSIOversold && close1 < lowerK && colorNow == 1); // 1 = REGIME_BEARISH
}

bool IsOverboughtCondition(const double curRSI, const double close1, const double upperK)
{
   double kamaColor[2];
   if(CopyBuffer(g_handleKAMA, 1, 1, 2, kamaColor) < 2)
      return false;
   int colorNow = (int)MathRound(kamaColor[1]);
   return(curRSI > InpRSIOverbought && close1 > upperK && colorNow == 2); // 2 = REGIME_BULLISH
}

bool MeanReversionBuy()
{
    double rsiPrev,rsiCur;

    if(!GetRSI(rsiPrev,rsiCur))
        return false;

    double upper,lower;

    if(!GetKeltner(upper,lower))
        return false;

    double close = iClose(_Symbol,_Period,1);

    if(rsiCur < InpRSIOversold && close < lower)
        return true;

    return false;
}


bool MeanReversionSell()
{
    double rsiPrev,rsiCur;

    if(!GetRSI(rsiPrev,rsiCur))
        return false;

    double upper,lower;

    if(!GetKeltner(upper,lower))
        return false;

    double close = iClose(_Symbol,_Period,1);

    if(rsiCur > InpRSIOverbought && close > upper)
        return true;

    return false;
}

#endif