#ifndef __INDICATORS_MQH__
#define __INDICATORS_MQH__

#include "Inputs.mqh"

//================ HANDLES =================
int g_handleRSI     = INVALID_HANDLE;
int g_handleKeltner = INVALID_HANDLE;
int g_handleATR     = INVALID_HANDLE;
int g_handleKAMA    = INVALID_HANDLE;


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
                              InpKeltnerEMAPeriod,
                              InpATRPeriod,
                              InpKeltnerATRFactor,
                              false);

   if(g_handleKeltner==INVALID_HANDLE)
   {
      Print("Keltner handle creation failed");
      return false;
   }

   g_handleATR = iATR(_Symbol,_Period,InpATRPeriod);
   if(g_handleATR==INVALID_HANDLE)
      return false;

   g_handleKAMA = iCustom(_Symbol,_Period,"KAMA with filter",
                           InpKAMAPeriod,
                           InpKAMAFastPeriod,
                           InpKAMASlowPeriod,
                           2,
                           50,
                           4,
                           50.0,
                           PRICE_CLOSE);

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
bool GetATR(double &current,double &avg)
{
   double atrBuf[];

   ArrayResize(atrBuf,InpATRPeriod);

   if(CopyBuffer(g_handleATR,0,1,InpATRPeriod,atrBuf)<InpATRPeriod)
      return false;

   current = atrBuf[InpATRPeriod-1];

   double sum=0;

   for(int i=0;i<InpATRPeriod;i++)
      sum+=atrBuf[i];

   avg=sum/InpATRPeriod;

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


bool IsShortSwingMagic(long magic)
{
   if(magic <= 0)
      return false;

   while(magic >= 10)
      magic /= 10;

   return(magic % 2 == 1);
}

#endif