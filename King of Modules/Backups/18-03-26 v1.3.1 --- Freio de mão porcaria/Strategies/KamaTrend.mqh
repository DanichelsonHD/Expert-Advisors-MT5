#ifndef __KAMA_TREND_MQH__
#define __KAMA_TREND_MQH__

#include "../Indicators.mqh"

#define KAMA_FLIP_LOOKBACK 3

//------------------------------------------------
// Detect KAMA regime flip within last N candles
//------------------------------------------------

bool GetKamaFlip(bool &bullishFlip, bool &bearishFlip)
{
   double regimeBuf[KAMA_FLIP_LOOKBACK + 1];

   if(CopyBuffer(g_handleKAMA, 1, 1, KAMA_FLIP_LOOKBACK + 1, regimeBuf) < KAMA_FLIP_LOOKBACK + 1)
      return false;

   bullishFlip = false;
   bearishFlip = false;

   for(int i = 0; i < KAMA_FLIP_LOOKBACK; i++)
   {
      int current  = (int)MathRound(regimeBuf[i]);
      int previous = (int)MathRound(regimeBuf[i + 1]);

      if(previous == 1 && current == 2) bullishFlip = true;
      if(previous == 2 && current == 1) bearishFlip = true;
   }

   return true;
}

//------------------------------------------------
// ATR COMPRESSION FILTER
// Allows entry only when ATR(14) > ATR(50) * multiplier
// AND ATR(14) is rising versus previous candle
// Handles are created once and reused
//------------------------------------------------

bool PassATRExpansionFilter()
{
   if(!InpUseATRKTTrendFilter)
      return true;

   static int hATR50 = INVALID_HANDLE;

   if(hATR50 == INVALID_HANDLE)
   {
      hATR50 = iATR(_Symbol, _Period, 50);
      if(hATR50 == INVALID_HANDLE)
         return false;
   }

   double atrFast[2];
   double atrSlow[1];

   if(CopyBuffer(g_handleATR, 0, 1, 2, atrFast) < 2) return false;
   if(CopyBuffer(hATR50,      0, 1, 1, atrSlow) < 1) return false;

   double atrFastNow  = atrFast[0];
   double atrFastPrev = atrFast[1];

   if(atrFastNow <= atrFastPrev)
      return false;

   return(atrFastNow > atrSlow[0] * InpATRKTTrendMultiplier);
}

//------------------------------------------------
// ADX TREND STRENGTH FILTER
// Allows entry only when ADX > threshold AND ADX is rising
// Handle is created once and reused
//------------------------------------------------

bool PassADXTrendFilter()
{
   if(!InpUseADXFilter)
      return true;

   static int hADX = INVALID_HANDLE;

   if(hADX == INVALID_HANDLE)
   {
      hADX = iADX(_Symbol, _Period, InpADXPeriod);
      if(hADX == INVALID_HANDLE)
         return false;
   }

   double adx[2];

   if(CopyBuffer(hADX, 0, 1, 2, adx) < 2)
      return false;

   double adxNow  = adx[1];
   double adxPrev = adx[0];

   if(adxNow <= adxPrev)
      return false;

   return(adxNow < InpADXComparision); // < 24.0 // > 19.5 / > 18.0
}

//------------------------------------------------
// SIGNAL FUNCTION (orchestrator)
//------------------------------------------------

ENUM_SIGNAL SignalKamaTrend()
{
   static datetime lastBar = 0;

   datetime bar = iTime(_Symbol, _Period, 0);

   if(bar == lastBar)
      return SIGNAL_NONE;

   lastBar = bar;



   bool bearishFlip, bullishFlip;

   if(!GetKamaFlip(bearishFlip, bullishFlip))
      return SIGNAL_NONE;

   if(!bearishFlip && !bullishFlip)
      return SIGNAL_NONE;

   if(!PassATRExpansionFilter())
      return SIGNAL_NONE;

   if(!PassADXTrendFilter())
      return SIGNAL_NONE;

   if(bearishFlip)
      return SIGNAL_SELL;

   if(bullishFlip)
      return SIGNAL_BUY;

   return SIGNAL_NONE;
}

#endif