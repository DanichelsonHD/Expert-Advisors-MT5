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
// CALCULATE TAKE PROFIT
// If TAKE_FIXED: stop distance * InpTPMultiplier + extra points
// If TAKE_KAMA:  KAMA value offset from entry + extra points
// Returns 0 when InpUseTakeProfit is false or on data failure
//------------------------------------------------

double CalculateTakeProfit(ENUM_ORDER_TYPE type, double atr)
{
   if(!InpUseTakeProfit)
      return 0;

   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double extra  = InpTakeExtraPoints * point;

   if(InpTakeMode == TAKE_FIXED)
   {
      double stopDist = atr * InpStopMultiplier + (InpStopExtraPoints * point);
      double tpDist   = stopDist * InpTPMultiplier + extra;

      double price;

      if(type == ORDER_TYPE_BUY)
      {
         price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         return NormalizeDouble(price + tpDist, digits);
      }
      else
      {
         price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         return NormalizeDouble(price - tpDist, digits);
      }
   }

   if(InpTakeMode == TAKE_KAMA)
   {
      double kamaBuf[1];
      if(CopyBuffer(g_handleKAMA, 0, 1, 1, kamaBuf) < 1)
         return 0;

      double kamaVal = kamaBuf[0];

      if(type == ORDER_TYPE_BUY)
         return NormalizeDouble(kamaVal + extra, digits);
      else
         return NormalizeDouble(kamaVal - extra, digits);
   }

   Print(InpTakeMode);

   return 0;
}

//------------------------------------------------
// TAKE KAMA — manages all positions for one engine
// Closes position on KAMA color transition
//------------------------------------------------

void TakeKAMAForEngine(int swingMagic)
{
   int prev, cur;
   if(!GetKAMAColor(prev, cur))
      return;

   ENUM_KAMA_REGIME prevRegime = ResolveKAMARegime(prev);
   ENUM_KAMA_REGIME curRegime  = ResolveKAMARegime(cur);

   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!take_pos.SelectByTicket(ticket))
         continue;

      if(take_pos.Symbol() != _Symbol)
         continue;

      if((int)take_pos.Magic() != swingMagic)
         continue;

      ENUM_POSITION_TYPE type = take_pos.PositionType();

      // BUY exit: KAMA flips Bullish -> Bearish
      if(type == POSITION_TYPE_BUY)
      {
         if(prevRegime == KAMA_REGIME_BULLISH && curRegime == KAMA_REGIME_BEARISH)
         {
            if(swingMagic == InpLongMagicNumber)
            {
               if(!g_trade.PositionClose(ticket))
                  Print("ERROR: TakeKAMA LONG failed to close BUY ticket=", ticket,
                        " Code=", g_trade.ResultRetcode());
               else
                  Print("TakeKAMA LONG: BUY closed (Bullish->Bearish) ticket=", ticket);
            }
            else
            {
               if(!g_trade_short.PositionClose(ticket))
                  Print("ERROR: TakeKAMA SHORT failed to close BUY ticket=", ticket,
                        " Code=", g_trade_short.ResultRetcode());
               else
                  Print("TakeKAMA SHORT: BUY closed (Bullish->Bearish) ticket=", ticket);
            }
         }
      }

      // SELL exit: KAMA flips Bearish -> Bullish
      if(type == POSITION_TYPE_SELL)
      {
         if(prevRegime == KAMA_REGIME_BEARISH && curRegime == KAMA_REGIME_BULLISH)
         {
            if(swingMagic == InpLongMagicNumber)
            {
               if(!g_trade.PositionClose(ticket))
                  Print("ERROR: TakeKAMA LONG failed to close SELL ticket=", ticket,
                        " Code=", g_trade.ResultRetcode());
               else
                  Print("TakeKAMA LONG: SELL closed (Bearish->Bullish) ticket=", ticket);
            }
            else
            {
               if(!g_trade_short.PositionClose(ticket))
                  Print("ERROR: TakeKAMA SHORT failed to close SELL ticket=", ticket,
                        " Code=", g_trade_short.ResultRetcode());
               else
                  Print("TakeKAMA SHORT: SELL closed (Bearish->Bullish) ticket=", ticket);
            }
         }
      }
   }
}

//------------------------------------------------
// TAKE MANAGER — public entry point
// Called from OnTick; manages both engines
//------------------------------------------------

void ManageTakes()
{
   if(InpTakeMode == TAKE_KAMA)
   {
      TakeKAMAForEngine(InpLongMagicNumber);
      TakeKAMAForEngine(InpShortMagicNumber);
   }
}

#endif
