#ifndef __RSI_EXHAUSTION_MQH__
#define __RSI_EXHAUSTION_MQH__

#include "../Indicators.mqh"

//------------------------------------------------
// EXHAUSTION DETECTION
// Oversold : RSI at extreme OR price below lower Keltner, AND KAMA bearish
// Overbought: RSI at extreme OR price above upper Keltner, AND KAMA bullish
//------------------------------------------------

ENUM_SIGNAL DetectRSIExhaustion(double curRSI,
                                 double upperK,
                                 double lowerK,
                                 int    kamaColor,
                                 double close1)
{
   if((curRSI < InpRSIOversold || close1 < lowerK) && kamaColor == KAMA_COLOR_BEARISH)
      return SIGNAL_SELL;

   if((curRSI > InpRSIOverbought || close1 > upperK) && kamaColor == KAMA_COLOR_BULLISH)
      return SIGNAL_BUY;

   return SIGNAL_NONE;
}


bool PassREATRCompressionFilter()
{
   if(!InpUseATRREFilter)
      return true;

   double atrFast, atrFastAvg;
   if(!GetATR(atrFast, atrFastAvg))
      return false;

   double atrSlow[1];
   if(CopyBuffer(g_handleATR50, 0, 1, 1, atrSlow) < 1) return false;

   return(atrFast * InpATRRETrendMultiplier < atrSlow[0]);
}

//------------------------------------------------
// SIGNAL FUNCTION — orchestrator
//------------------------------------------------

ENUM_SIGNAL SignalRSIExhaustion()
{
   double curRSI;
   double upperK, lowerK;
   int    kamaColor;
   double close1;

   if(!UpdateREIndicators(curRSI, upperK, lowerK, kamaColor, close1))
      return SIGNAL_NONE;

   if(!PassREATRCompressionFilter())
      return SIGNAL_NONE;

   return DetectRSIExhaustion(curRSI, upperK, lowerK, kamaColor, close1);
}

#endif