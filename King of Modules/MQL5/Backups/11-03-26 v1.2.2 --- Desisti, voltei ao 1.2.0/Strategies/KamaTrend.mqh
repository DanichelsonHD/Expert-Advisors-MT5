#ifndef __KAMA_TREND_MQH__
#define __KAMA_TREND_MQH__

#include "../Indicators.mqh"

const int KAMA_FLIP_LOOKBACK = 3;

//------------------------------------------------
// Detect KAMA regime flip within last N candles
//------------------------------------------------

bool GetKamaFlip(bool &bullishFlip, bool &bearishFlip)
{
   int    count = KAMA_FLIP_LOOKBACK + 1;
   double regimeBuf[];
   ArrayResize(regimeBuf, count);
   ArraySetAsSeries(regimeBuf, true);

   if(CopyBuffer(g_handleKAMA, 1, 1, count, regimeBuf) < count)
      return false;

   bullishFlip = false;
   bearishFlip = false;

   // ArraySetAsSeries(true): index 0 = newest candle, index i+1 = older candle
   for(int i = 0; i < KAMA_FLIP_LOOKBACK; i++)
   {
      int current  = (int)MathRound(regimeBuf[i]);     // newer bar
      int previous = (int)MathRound(regimeBuf[i + 1]); // older bar

      if(previous == KAMA_COLOR_BEARISH && current == KAMA_COLOR_BULLISH) bullishFlip = true;
      if(previous == KAMA_COLOR_BULLISH && current == KAMA_COLOR_BEARISH) bearishFlip = true;
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

   double atrFast[2];
   double atrSlow[1];

   if(CopyBuffer(g_handleATR,   0, 1, 2, atrFast) < 2) return false;
   if(CopyBuffer(g_handleATR50, 0, 1, 1, atrSlow) < 1) return false;

   double atrFastNow  = atrFast[1]; // index 1 = newer bar (CopyBuffer: 0=oldest)
   double atrFastPrev = atrFast[0]; // index 0 = older bar

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

   double adx[2];

   if(CopyBuffer(g_handleADX, 0, 1, 2, adx) < 2)
      return false;

   double adxNow  = adx[1]; // index 1 = newer bar
   double adxPrev = adx[0]; // index 0 = older bar

   if(adxNow <= adxPrev)
      return false;

   // ADX must be above threshold to confirm sufficient trend strength
   return(adxNow > InpADXComparision);
}

//------------------------------------------------
// SIGNAL FUNCTION (orchestrator)
//------------------------------------------------

ENUM_SIGNAL SignalKamaTrend()
{
   bool bullishFlip, bearishFlip;

   if(!GetKamaFlip(bullishFlip, bearishFlip))
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