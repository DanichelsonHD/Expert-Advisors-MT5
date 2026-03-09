#ifndef __KAMA_MOMENTUM_TREND_MQH__
#define __KAMA_MOMENTUM_TREND_MQH__

#include "../Indicators.mqh"

//------------------------------------------------
// INDICATOR HANDLES
//------------------------------------------------

static int g_handleMomentum = INVALID_HANDLE;
static int g_handleATR50    = INVALID_HANDLE;

//------------------------------------------------
// INITIALIZATION
//------------------------------------------------

bool InitKamaMomentumTrend()
{
   if(g_handleMomentum == INVALID_HANDLE)
   {
      g_handleMomentum = iMomentum(_Symbol, _Period, 14, PRICE_CLOSE);
      if(g_handleMomentum == INVALID_HANDLE)
      {
         Print("KamaMomentumTrend: Momentum handle creation failed");
         return false;
      }
   }

   if(g_handleATR50 == INVALID_HANDLE)
   {
      g_handleATR50 = iATR(_Symbol, _Period, 50);
      if(g_handleATR50 == INVALID_HANDLE)
      {
         Print("KamaMomentumTrend: ATR(50) handle creation failed");
         return false;
      }
   }

   return true;
}

//------------------------------------------------
// INDICATOR DATA FETCH
//------------------------------------------------

bool GetKamaMomentumTrendData(int    &kamaColor,
                               double &momentum,
                               double &atr50)
{
   double kamaColorBuf[1];
   if(CopyBuffer(g_handleKAMA, 1, 1, 1, kamaColorBuf) < 1)
      return false;

   double momentumBuf[1];
   if(CopyBuffer(g_handleMomentum, 0, 1, 1, momentumBuf) < 1)
      return false;

   double atr50Buf[1];
   if(CopyBuffer(g_handleATR50, 0, 1, 1, atr50Buf) < 1)
      return false;

   kamaColor = (int)MathRound(kamaColorBuf[0]);
   momentum  = momentumBuf[0];
   atr50     = atr50Buf[0];

   return true;
}

//------------------------------------------------
// FILTER 1 — KAMA SLOPE FILTER
//------------------------------------------------

bool PassKamaSlopeFilter()
{
   const int lookback = 10;

   double kamaBuf[11];
   if(CopyBuffer(g_handleKAMA, 0, 1, lookback + 1, kamaBuf) < lookback + 1)
      return false;

   double atrVal, atrAvg;
   if(!GetATR(atrVal, atrAvg))
      return false;

   double slope     = MathAbs(kamaBuf[lookback] - kamaBuf[0]);
   double threshold = atrVal * 1.2;

   return(slope >= threshold);
}

//------------------------------------------------
// FILTER 2 — DISTANCE FROM KAMA FILTER
//------------------------------------------------

bool PassDistanceFromKamaFilter()
{
   double kamaBuf[1];
   if(CopyBuffer(g_handleKAMA, 0, 1, 1, kamaBuf) < 1)
      return false;

   double atrVal, atrAvg;
   if(!GetATR(atrVal, atrAvg))
      return false;

   double close     = iClose(_Symbol, _Period, 1);
   double distance  = MathAbs(close - kamaBuf[0]);
   double threshold = atrVal * 1.0;

   return(distance >= threshold);
}

//------------------------------------------------
// SIGNAL EVALUATION
//------------------------------------------------

ENUM_SIGNAL EvaluateKamaMomentumTrend(int kamaColor, double momentum, double atr50)
{
   if(kamaColor == 1 && momentum > atr50)
      return SIGNAL_SELL;

   if(kamaColor == 2 && atr50 > momentum)
      return SIGNAL_BUY;

   return SIGNAL_NONE;
}

//------------------------------------------------
// SIGNAL FUNCTION
//------------------------------------------------

ENUM_SIGNAL SignalKamaMomentumTrend()
{
   static datetime lastBar = 0;
   datetime bar = iTime(_Symbol, _Period, 0);

   if(bar == lastBar)
      return SIGNAL_NONE;

   lastBar = bar;

   if(!InitKamaMomentumTrend())
      return SIGNAL_NONE;

   int    kamaColor;
   double momentum;
   double atr50;

   if(!GetKamaMomentumTrendData(kamaColor, momentum, atr50))
      return SIGNAL_NONE;

   if(!PassKamaSlopeFilter())
      return SIGNAL_NONE;

   if(!PassDistanceFromKamaFilter())
      return SIGNAL_NONE;

   return EvaluateKamaMomentumTrend(kamaColor, momentum, atr50);
}

#endif