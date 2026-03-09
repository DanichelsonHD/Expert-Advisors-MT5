#ifndef __KAMA_MOMENTUM_TREND_MQH__
#define __KAMA_MOMENTUM_TREND_MQH__

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
// Get Momentum
//------------------------------------------------

bool GetMomentum(double &momNow, double &momPrev)
{
   static int hMomentum = INVALID_HANDLE;

   if(hMomentum == INVALID_HANDLE)
   {
      hMomentum = iMomentum(_Symbol, _Period, 14, PRICE_CLOSE);

      if(hMomentum == INVALID_HANDLE)
         return false;
   }

   double buf[2];

   if(CopyBuffer(hMomentum, 0, 1, 2, buf) < 2)
      return false;

   momNow  = buf[0];
   momPrev = buf[1];

   return true;
}

//------------------------------------------------
// SIGNAL FUNCTION (orchestrator)
//------------------------------------------------

ENUM_SIGNAL SignalKamaMomentumTrend()
{
   static datetime lastBar = 0;

   datetime bar = iTime(_Symbol, _Period, 0);

   if(bar == lastBar)
      return SIGNAL_NONE;

   lastBar = bar;

   //------------------------------------------------
   // KAMA flip
   //------------------------------------------------

   bool bullishFlip, bearishFlip;

   if(!GetKamaFlip(bullishFlip, bearishFlip))
      return SIGNAL_NONE;

   if(!bullishFlip && !bearishFlip)
      return SIGNAL_NONE;

   //------------------------------------------------
   // Signals
   //------------------------------------------------

   if(bullishFlip)
      return SIGNAL_SELL;

   if(bearishFlip)
      return SIGNAL_BUY;

   return SIGNAL_NONE;
}

#endif