#ifndef __INDICATORS_MQH__
#define __INDICATORS_MQH__

#include "Inputs.mqh"

//================ KAMA COLOR CONSTANTS =================
// Used everywhere KAMA color codes appear — no more raw literals
const int KAMA_COLOR_BEARISH = 1;
const int KAMA_COLOR_BULLISH = 2;

//================ HANDLES =================
int g_handleRSI     = INVALID_HANDLE;
int g_handleKeltner = INVALID_HANDLE;
int g_handleATR     = INVALID_HANDLE;
int g_handleKAMA    = INVALID_HANDLE;
int g_handleATR50   = INVALID_HANDLE;  // shared ATR(50) — used by MR, RE, KT filters
int g_handleADX     = INVALID_HANDLE;  // shared ADX — used by KT filter


//================ INIT =================
bool IndicatorsInit()
{
   g_handleRSI = iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE);
   if(g_handleRSI==INVALID_HANDLE)
   {
      Print("RSI handle creation failed");
      return false;
   }

   g_handleKeltner = iCustom(_Symbol,_Period,"Keltner Channel",
                              InpKeltnerEMAPeriod,  // param 0: EMA period
                              InpATRPeriod,          // param 1: ATR period
                              InpKeltnerATRFactor,   // param 2: ATR multiplier
                              false);                // param 3: use EMA (false=SMA)

   if(g_handleKeltner==INVALID_HANDLE)
   {
      Print("Keltner handle creation failed");
      return false;
   }

   g_handleATR = iATR(_Symbol,_Period,InpATRPeriod);
   if(g_handleATR==INVALID_HANDLE)
   {
      Print("ATR handle creation failed");
      return false;
   }

   g_handleATR50 = iATR(_Symbol, _Period, 50);
   if(g_handleATR50 == INVALID_HANDLE)
   {
      Print("ATR50 handle creation failed");
      return false;
   }

   g_handleADX = iADX(_Symbol, _Period, InpADXPeriod);
   if(g_handleADX == INVALID_HANDLE)
   {
      Print("ADX handle creation failed");
      return false;
   }

   g_handleKAMA = iCustom(_Symbol,_Period,"KAMA with filter",
                           InpKAMAPeriod,      // param 0: KAMA period
                           InpKAMAFastPeriod,  // param 1: fast EMA period
                           InpKAMASlowPeriod,  // param 2: slow EMA period
                           2,                  // param 3: color mode
                           50,                 // param 4: color smoothing
                           4,                  // param 5: signal period
                           50.0,               // param 6: noise threshold
                           PRICE_CLOSE);       // param 7: applied price

   if(g_handleKAMA==INVALID_HANDLE)
   {
      Print("KAMA handle creation failed");
      return false;
   }

   return true;
}


//================ RELEASE =================
void IndicatorsRelease()
{
   if(g_handleRSI     != INVALID_HANDLE) IndicatorRelease(g_handleRSI);
   if(g_handleKeltner != INVALID_HANDLE) IndicatorRelease(g_handleKeltner);
   if(g_handleATR     != INVALID_HANDLE) IndicatorRelease(g_handleATR);
   if(g_handleATR50   != INVALID_HANDLE) IndicatorRelease(g_handleATR50);
   if(g_handleADX     != INVALID_HANDLE) IndicatorRelease(g_handleADX);
   if(g_handleKAMA    != INVALID_HANDLE) IndicatorRelease(g_handleKAMA);
}


//================ RSI =================
bool GetRSI(double &prev,double &current)
{
   double rsi[2];

   if(CopyBuffer(g_handleRSI,0,1,2,rsi)<2)
      return false;

   prev    = rsi[0];
   current = rsi[1];

   return true;
}


//================ KELTNER =================
// Buffer 0 = upper band, Buffer 2 = lower band
bool GetKeltner(double &upper,double &lower)
{
   double up[2],lo[2];

   if(CopyBuffer(g_handleKeltner,0,1,2,up)<2)
      return false;

   if(CopyBuffer(g_handleKeltner,2,1,2,lo)<2)
      return false;

   upper = up[1];
   lower = lo[1];

   return true;
}


//================ ATR =================
// Values are cached per bar so multiple callers on the same tick
// only trigger one CopyBuffer call.
bool GetATR(double &current,double &avg)
{
   static datetime s_cacheBar  = 0;
   static double   s_cacheCur  = 0.0;
   static double   s_cacheAvg  = 0.0;
   static double   atrBuf[];   // allocated once

   datetime bar = iTime(_Symbol, _Period, 0);

   if(bar != s_cacheBar)
   {
      ArrayResize(atrBuf, InpATRPeriod);

      if(CopyBuffer(g_handleATR, 0, 1, InpATRPeriod, atrBuf) < InpATRPeriod)
         return false;

      s_cacheCur = atrBuf[InpATRPeriod - 1];

      double sum = 0;
      for(int i = 0; i < InpATRPeriod; i++)
         sum += atrBuf[i];

      s_cacheAvg = sum / InpATRPeriod;
      s_cacheBar = bar;
   }

   current = s_cacheCur;
   avg     = s_cacheAvg;

   return true;
}


//================ KAMA =================
bool GetKAMAColor(int &prev,int &current)
{
   double buf[2];

   if(CopyBuffer(g_handleKAMA,1,1,2,buf)<2)
      return false;

   prev    = (int)MathRound(buf[0]);
   current = (int)MathRound(buf[1]);

   return true;
}


//================ SWING TYPE DETECTION =================
// Compares magic directly against known Short Swing magic inputs.
// Short Swing strategies: MR, RE
bool IsShortSwingMagic(long magic)
{
   return(magic == InpMagicMR || magic == InpMagicRE);
}


//================ SHARED INDICATOR SNAPSHOT =================
// Used by MeanReversion and RSIExhaustion.
// Fetches all values needed for both strategies in one place.
bool UpdateMRIndicators(double &curRSI,
                        double &prevRSI,
                        double &upperK,
                        double &lowerK,
                        int    &kamaColor,
                        double &close1,
                        double &kamaSlope)
{
   double prevRSIVal, curRSIVal;
   if(!GetRSI(prevRSIVal, curRSIVal))
      return false;

   double upperKVal, lowerKVal;
   if(!GetKeltner(upperKVal, lowerKVal))
      return false;

   int prevColor, curColor;
   if(!GetKAMAColor(prevColor, curColor))
      return false;

   // KAMA line values for slope calculation
   static double kamaBuf[];
   static bool   s_kamaBufInit = false;
   if(!s_kamaBufInit)
   {
      ArrayResize(kamaBuf, InpKAMASlopeLookback + 1);
      s_kamaBufInit = true;
   }
   if(CopyBuffer(g_handleKAMA, 0, 1, InpKAMASlopeLookback + 1, kamaBuf) < InpKAMASlopeLookback + 1)
      return false;

   curRSI    = curRSIVal;
   prevRSI   = prevRSIVal;
   upperK    = upperKVal;
   lowerK    = lowerKVal;
   kamaColor = curColor;
   close1    = iClose(_Symbol, _Period, 1);
   kamaSlope = MathAbs(kamaBuf[InpKAMASlopeLookback] - kamaBuf[0]);

   return true;
}

//================ RSI EXHAUSTION INDICATOR SNAPSHOT =================
// Lean variant for RSIExhaustion — skips slope computation.
bool UpdateREIndicators(double &curRSI,
                        double &upperK,
                        double &lowerK,
                        int    &kamaColor,
                        double &close1)
{
   double prevRSIVal, curRSIVal;
   if(!GetRSI(prevRSIVal, curRSIVal))
      return false;

   double upperKVal, lowerKVal;
   if(!GetKeltner(upperKVal, lowerKVal))
      return false;

   int prevColor, curColor;
   if(!GetKAMAColor(prevColor, curColor))
      return false;

   curRSI    = curRSIVal;
   upperK    = upperKVal;
   lowerK    = lowerKVal;
   kamaColor = curColor;
   close1    = iClose(_Symbol, _Period, 1);

   return true;
}

#endif