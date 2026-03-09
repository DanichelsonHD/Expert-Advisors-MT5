#ifndef __TAKES_MQH__
#define __TAKES_MQH__

#include "Indicators.mqh"
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

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

   if(!InpUseTakeProfit)
      return 0;

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
   // Safety guard — re-select before any action
   if(!take_pos.Select(_Symbol))
      return;

   int prev, cur;
   if(!GetKAMAColor(prev, cur))
      return;

   ENUM_KAMA_REGIME prevRegime = ResolveKAMARegime(prev);
   ENUM_KAMA_REGIME curRegime  = ResolveKAMARegime(cur);

   ENUM_POSITION_TYPE type = take_pos.PositionType();

   // BUY exit: KAMA flips Bullish → Bearish
   if(type == POSITION_TYPE_BUY)
   {
      if(prevRegime == KAMA_REGIME_BULLISH && curRegime == KAMA_REGIME_BEARISH)
      {
         if(!g_trade.PositionClose(_Symbol))
            Print("ERROR: TakeKAMA failed to close BUY. Code=", g_trade.ResultRetcode());
         else
            Print("TakeKAMA: BUY closed (Bullish→Bearish).");
      }
   }

   // SELL exit: KAMA flips Bearish → Bullish
   if(type == POSITION_TYPE_SELL)
   {
      if(prevRegime == KAMA_REGIME_BEARISH && curRegime == KAMA_REGIME_BULLISH)
      {
         if(!g_trade.PositionClose(_Symbol))
            Print("ERROR: TakeKAMA failed to close SELL. Code=", g_trade.ResultRetcode());
         else
            Print("TakeKAMA: SELL closed (Bearish→Bullish).");
      }
   }
}


//------------------------------------------------
// TAKE MANAGER
//------------------------------------------------

void ManageTakes()
{
   Print("Take engine running");

   if(!take_pos.Select(_Symbol))
      return;

   if(take_pos.Magic() != (ulong)InpMagicNumber)
      return;

   if(InpTakeMode==TAKE_KAMA)
      TakeKAMA();
}

#endif