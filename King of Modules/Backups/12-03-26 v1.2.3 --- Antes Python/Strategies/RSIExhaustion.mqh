#ifndef __RSI_EXHAUSTION_MQH__
#define __RSI_EXHAUSTION_MQH__

#include "../Indicators.mqh"
#include "MeanReversion.mqh"

//------------------------------------------------
// EXHAUSTION DETECTION
// Oversold: RSI at extreme AND price below lower Keltner AND KAMA bearish
// Overbought: RSI at extreme AND price above upper Keltner AND KAMA bullish
//------------------------------------------------

ENUM_SIGNAL DetectRSIExhaustion(double curRSI,
                                 double upperK,
                                 double lowerK,
                                 int    kamaColor,
                                 double close1)
{
   if((curRSI < InpRSIOversold || close1 < lowerK) && kamaColor == 1)
      return SIGNAL_SELL;

   if((curRSI > InpRSIOverbought || close1 > upperK) && kamaColor == 2)
      return SIGNAL_BUY;

   return SIGNAL_NONE;
}


bool PassREATRCompressionFilter()
{
   static int hATR50 = INVALID_HANDLE;

   // Initialize handle once
   if(hATR50 == INVALID_HANDLE)
   {
      hATR50 = iATR(_Symbol, _Period, 50);
      if(hATR50 == INVALID_HANDLE)
         return false;
   }

   double atrFast[1];
   double atrSlow[1];

   if(CopyBuffer(g_handleATR, 0, 1, 1, atrFast) < 1) return false;
   if(CopyBuffer(hATR50,      0, 1, 1, atrSlow) < 1) return false;

   return(atrFast[0] * InpATRRETrendMultiplier < atrSlow[0]);
}

//------------------------------------------------
// SIGNAL FUNCTION — orchestrator
//------------------------------------------------

ENUM_SIGNAL SignalRSIExhaustion()
{
   static datetime lastBar = 0;
   datetime bar = iTime(_Symbol, _Period, 0);

   if(bar == lastBar)
      return SIGNAL_NONE;

   lastBar = bar;

   double curRSI, prevRSI;
   double upperK, lowerK;
   int    kamaColor;
   double close1;
   double kamaSlope;

   if(!UpdateMRIndicators(curRSI, prevRSI, upperK, lowerK, kamaColor, close1, kamaSlope))
      return SIGNAL_NONE;
   
   if(!(PassREATRCompressionFilter()))// && PassMRKAMASlopeFilter(kamaSlope)))
      return SIGNAL_NONE;

   return DetectRSIExhaustion(curRSI, upperK, lowerK, kamaColor, close1);
}

#endif