#ifndef __TAKES_MQH__
#define __TAKES_MQH__

#include "Indicators.mqh"
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade take_trade;
CPositionInfo take_pos;

//------------------------------------------------
// KAMA regime
//------------------------------------------------
enum ENUM_KAMA_REGIME
{
   KAMA_REGIME_NONE    = 0,
   KAMA_REGIME_BEARISH = 1,
   KAMA_REGIME_BULLISH = 2
};

ENUM_KAMA_REGIME ResolveKAMARegime(int colorCode)
{
   if(colorCode == 1) return KAMA_REGIME_BEARISH;
   if(colorCode == 2) return KAMA_REGIME_BULLISH;

   return KAMA_REGIME_NONE;
}

//------------------------------------------------
// CALCULATE TAKE PROFIT (FIXED ATR-BASED)
//------------------------------------------------

double CalculateTakeProfit(ENUM_ORDER_TYPE type)
{
   double atr, avg;

   if(!GetATR(atr, avg))
      return 0;

   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double tpDist = atr * InpTPMultiplier;

   double price;

   if(type == ORDER_TYPE_BUY)
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   else
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double tp;

   if(type == ORDER_TYPE_BUY)
      tp = NormalizeDouble(price + tpDist, digits);
   else
      tp = NormalizeDouble(price - tpDist, digits);

   return tp;
}

//------------------------------------------------
// TAKE KAMA REGIME
//------------------------------------------------

void TakeKAMA()
{
    int prev,cur;

    if(!GetKAMAColor(prev,cur))
        return;

    ENUM_KAMA_REGIME kamaPrev = ResolveKAMARegime(prev);
    ENUM_KAMA_REGIME kamaNow  = ResolveKAMARegime(cur);

    ENUM_POSITION_TYPE type = take_pos.PositionType();

    if(type==POSITION_TYPE_BUY)
    {
        if(kamaPrev==KAMA_REGIME_BULLISH && kamaNow==KAMA_REGIME_BEARISH)
        {
            take_trade.PositionClose(_Symbol);
        }
    }

    if(type==POSITION_TYPE_SELL)
    {
        if(kamaPrev==KAMA_REGIME_BEARISH && kamaNow==KAMA_REGIME_BULLISH)
        {
            take_trade.PositionClose(_Symbol);
        }
    }
}


//------------------------------------------------
// TAKE MANAGER
//------------------------------------------------

void ManageTakes()
{
    if(!take_pos.Select(_Symbol))
        return;

    if(take_pos.Magic() != (ulong)InpMagicNumber)
        return;

    if(InpTakeMode==TAKE_KAMA)
        TakeKAMA();
}

#endif