#ifndef __MEAN_REVERSION_MQH__
#define __MEAN_REVERSION_MQH__

#include "../Indicators.mqh"

//------------------------------------------------
// ENTRY STATE
//------------------------------------------------

enum ENUM_ENTRY_STATE
{
   STATE_IDLE                 = 0,
   STATE_OVERSOLD_CONFIRMED   = 1,
   STATE_OVERBOUGHT_CONFIRMED = 2
};

static ENUM_ENTRY_STATE g_mr_state = STATE_IDLE;

//------------------------------------------------
// KAMA SLOPE FILTER
//------------------------------------------------

bool PassMRKAMASlopeFilter(double slope)
{
   if(!InpUseKAMAStrongTrendFilter)
      return true;

   double atr, avg;
   if(!GetATR(atr, avg))
      return false;

   double threshold = atr * InpKAMASlopeATRMultiplier;

   if(slope > threshold)
      return false;

   return true;
}

//------------------------------------------------
// ATR COMPRESSION FILTER
// Allows entry only when ATR(14) < ATR(50)
// Handle is created once and reused
//------------------------------------------------

bool PassMRATRCompressionFilter()
{
    if(!InpUseATRMRTrendFilter)
      return true;

   double atrFast, atrFastAvg;
   if(!GetATR(atrFast, atrFastAvg))
      return false;

   double atrSlow[1];
   if(CopyBuffer(g_handleATR50, 0, 1, 1, atrSlow) < 1) return false;

   return(atrFast < atrSlow[0] * InpATRMRTrendMultiplier);
}

//------------------------------------------------
// MEAN DISTANCE FILTER
// Ensures price is far enough from KAMA
//------------------------------------------------

bool PassMRMeanDistanceFilter(double close1)
{
   if(!InpUseMeanDistanceFilter)
      return true;

   double kama[1];
   if(CopyBuffer(g_handleKAMA, 0, 1, 1, kama) < 1)
      return false;

   double atrFast[1];
   if(CopyBuffer(g_handleATR, 0, 1, 1, atrFast) < 1)
      return false;

   double distance  = MathAbs(close1 - kama[0]);
   double threshold = atrFast[0] * InpMeanDistanceATRMult;

   return(distance >= threshold);
}

//------------------------------------------------
// EXTREME DETECTION
//------------------------------------------------

void DetectMRExtreme(double curRSI,
                     double close1,
                     double upperK,
                     double lowerK,
                     int    kamaColor)
{
   if(g_mr_state != STATE_IDLE)
      return;

   if(curRSI < InpRSIOversold &&
      close1  < lowerK        &&
      kamaColor == KAMA_COLOR_BEARISH)
   {
      g_mr_state = STATE_OVERSOLD_CONFIRMED;
      return;
   }

   if(curRSI > InpRSIOverbought &&
      close1  > upperK          &&
      kamaColor == KAMA_COLOR_BULLISH)
   {
      g_mr_state = STATE_OVERBOUGHT_CONFIRMED;
      return;
   }
}

//------------------------------------------------
// RETURN CONFIRMATION
//------------------------------------------------

ENUM_SIGNAL ConfirmMRReturn(double curRSI, double prevRSI)
{
   if(g_mr_state == STATE_OVERSOLD_CONFIRMED)
   {
      if(prevRSI <= InpRSIOversold &&
         curRSI   > InpRSIOversold)
      {
         g_mr_state = STATE_IDLE;
         return SIGNAL_BUY;
      }
   }

   if(g_mr_state == STATE_OVERBOUGHT_CONFIRMED)
   {
      if(prevRSI >= InpRSIOverbought &&
         curRSI   < InpRSIOverbought)
      {
         g_mr_state = STATE_IDLE;
         return SIGNAL_SELL;
      }
   }

   return SIGNAL_NONE;
}

//------------------------------------------------
// STALE RESET
//------------------------------------------------

void ResetMRState(double curRSI)
{
   if(g_mr_state == STATE_OVERSOLD_CONFIRMED)
   {
      if(curRSI > InpRSIOversold &&
         MathAbs(curRSI - InpRSIOversold) > InpRSIResetThreshold)
      {
         g_mr_state = STATE_IDLE;
      }
   }

   if(g_mr_state == STATE_OVERBOUGHT_CONFIRMED)
   {
      if(curRSI < InpRSIOverbought &&
         MathAbs(curRSI - InpRSIOverbought) > InpRSIResetThreshold)
      {
         g_mr_state = STATE_IDLE;
      }
   }
}

//------------------------------------------------
// SIGNAL FUNCTION — orchestrator only
//------------------------------------------------

ENUM_SIGNAL SignalMeanReversion()
{
   double curRSI, prevRSI;
   double upperK, lowerK;
   int    kamaColor;
   double close1;
   double slope;

   if(!UpdateMRIndicators(curRSI, prevRSI, upperK, lowerK, kamaColor, close1, slope))
      return SIGNAL_NONE;

   if(!(PassMRATRCompressionFilter() && PassMRKAMASlopeFilter(slope)))
      return SIGNAL_NONE;

    if(!PassMRMeanDistanceFilter(close1))
      return SIGNAL_NONE;

   DetectMRExtreme(curRSI, close1, upperK, lowerK, kamaColor);

   ENUM_SIGNAL signal = ConfirmMRReturn(curRSI, prevRSI);

   ResetMRState(curRSI);

   return signal;
}

#endif
