#ifndef __ENTRIES_MQH__
#define __ENTRIES_MQH__

#include "Indicators.mqh"
#include "Strategies/MeanReversion.mqh"
#include "Stops.mqh"
#include "Takes.mqh"

CTrade entry_trade;

bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(dt.hour >= InpStartHour && dt.hour < InpEndHour);
}

void EntriesEngine()
{
   ENUM_MARKET_REGIME regime = DetectMarketRegime();

   switch(regime)
   {
      case REGIME_LOW_VOL:

         RunLowVolStrategies();

         break;


      case REGIME_HIGH_VOL:

         RunHighVolStrategies();

         break;


      case REGIME_NEUTRAL:

         RunNeutralStrategies();

         break;
   }
}

void EntryBuy()
{
   
}

void EntrySell()
{
   
}

void RunLowVolStrategies()
{
   
}

void RunHighVolStrategies()
{
   
}

void RunNeutralStrategies()
{
   
}

ENUM_MARKET_REGIME DetectMarketRegime()
{
    double atr,avg;

    if(!GetATR(atr,avg))
        return REGIME_NEUTRAL;

    if(atr < avg * InpVolatilityMult)
        return REGIME_LOW_VOL;

    if(atr > avg * (InpVolatilityMult * 1.5))
        return REGIME_HIGH_VOL;

    return REGIME_NEUTRAL;
}

#endif