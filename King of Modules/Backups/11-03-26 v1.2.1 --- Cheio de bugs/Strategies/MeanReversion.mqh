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
// INDICATOR UPDATE
//------------------------------------------------

bool UpdateMRIndicators(double &curRSI,
                        double &prevRSI,
                        double &upperK,
                        double &lowerK,
                        int    &kamaColor,
                        double &close1,
                        double &kamaSlope)
{
   double rsi[2];
   if(CopyBuffer(g_handleRSI, 0, 1, 2, rsi) < 2)
      return false;

   double kcUpper[2];
   double kcLower[2];
   if(CopyBuffer(g_handleKeltner, 0, 1, 2, kcUpper) < 2)
      return false;
   if(CopyBuffer(g_handleKeltner, 2, 1, 2, kcLower) < 2)
      return false;

   double kamaColorBuf[2];
   if(CopyBuffer(g_handleKAMA, 1, 1, 2, kamaColorBuf) < 2)
      return false;

   double kamaBuf[];
   ArrayResize(kamaBuf, InpKAMASlopeLookback + 1);
   if(CopyBuffer(g_handleKAMA, 0, 1, InpKAMASlopeLookback + 1, kamaBuf) < InpKAMASlopeLookback + 1)
      return false;

   curRSI    = rsi[1];
   prevRSI   = rsi[0];
   upperK    = kcUpper[1];
   lowerK    = kcLower[1];
   kamaColor = (int)MathRound(kamaColorBuf[1]);
   close1    = iClose(_Symbol, _Period, 1);
   kamaSlope = MathAbs(kamaBuf[InpKAMASlopeLookback] - kamaBuf[0]);

   return true;
}

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

   return(atrFast[0] < atrSlow[0] * InpATRMRTrendMultiplier);
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
      kamaColor == 1)
   {
      g_mr_state = STATE_OVERSOLD_CONFIRMED;
      return;
   }

   if(curRSI > InpRSIOverbought &&
      close1  > upperK          &&
      kamaColor == 2)
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
   static datetime lastBar = 0;
   datetime bar = iTime(_Symbol, _Period, 0);

   if(bar == lastBar)
      return SIGNAL_NONE;

   lastBar = bar;

   double curRSI, prevRSI;
   double upperK, lowerK;
   int    kamaColor;
   double close1;
   double slope;

   if(!UpdateMRIndicators(curRSI, prevRSI, upperK, lowerK, kamaColor, close1, slope))
      return SIGNAL_NONE;

   if(!(PassMRATRCompressionFilter() || PassMRKAMASlopeFilter(slope)))
      return SIGNAL_NONE;

    if(!PassMRMeanDistanceFilter(close1))
      return SIGNAL_NONE;

   DetectMRExtreme(curRSI, close1, upperK, lowerK, kamaColor);

   ENUM_SIGNAL signal = ConfirmMRReturn(curRSI, prevRSI);

   ResetMRState(curRSI);

   return signal;
}

#endif
