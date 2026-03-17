#ifndef __TAKES_MQH__
#define __TAKES_MQH__

#include "Indicators.mqh"
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

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
   if(colorCode == KAMA_COLOR_BEARISH) return KAMA_REGIME_BEARISH;
   if(colorCode == KAMA_COLOR_BULLISH) return KAMA_REGIME_BULLISH;

   return KAMA_REGIME_NONE;
}

//------------------------------------------------
// SHORT SWING TP CALCULATION
// Mode TAKE_FIXED_POINTS : fixed point distance
// Mode TAKE_ATR_MULTIPLIER: ATR * InpShortTPMultiplier
//------------------------------------------------

double CalculateShortSwingTP(ENUM_ORDER_TYPE type, double entryPrice)
{
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tpDist = 0.0;

   if(InpShortTakeMode == TAKE_FIXED_POINTS)
   {
      tpDist = InpShortTakePoints * _Point;
   }
   else // TAKE_ATR_MULTIPLIER
   {
      double atr, avg;
      if(!GetATR(atr, avg))
         return 0;

      tpDist = atr * InpShortTPMultiplier;
   }

   double tp;

   if(type == ORDER_TYPE_BUY)
      tp = NormalizeDouble(entryPrice + tpDist, digits);
   else
      tp = NormalizeDouble(entryPrice - tpDist, digits);

   return tp;
}

//------------------------------------------------
// LONG SWING TP CALCULATION (ATR multiplier)
//------------------------------------------------

double CalculateLongSwingTP(ENUM_ORDER_TYPE type)
{
   if(!InpUseTakeProfit)
      return 0;

   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double tpDist = 0.0;

   if(InpTakeMode == TAKE_POINTS)
   {
      tpDist = InpTPPoints * _Point;
   }
   else // TAKE_MULTIPLIER or TAKE_KAMA (KAMA exits are managed at runtime; 0 TP at entry)
   {
      double atr, avg;
      if(!GetATR(atr, avg))
         return 0;

      tpDist = atr * InpTPMultiplier;
   }

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
// UNIFIED TP CALCULATOR
// Routes to short or long swing based on magic
//------------------------------------------------

double CalculateTakeProfit(ENUM_ORDER_TYPE type, long magic, double entryPrice)
{
   if(IsShortSwingMagic(magic))
      return CalculateShortSwingTP(type, entryPrice);

   return CalculateLongSwingTP(type);
}

//------------------------------------------------
// KAMA EXIT — scoped to a single ticket
// Closes position identified by ticket when
// KAMA regime flips against the trade direction
//------------------------------------------------

void TakeKAMAByTicket(ulong ticket, ENUM_POSITION_TYPE posType)
{
   int prev, cur;
   if(!GetKAMAColor(prev, cur))
      return;

   ENUM_KAMA_REGIME prevRegime = ResolveKAMARegime(prev);
   ENUM_KAMA_REGIME curRegime  = ResolveKAMARegime(cur);

   if(posType == POSITION_TYPE_BUY)
   {
      if(prevRegime == KAMA_REGIME_BULLISH && curRegime == KAMA_REGIME_BEARISH)
      {
         if(!g_tradeMgmt.PositionClose(ticket))
            Print("ERROR: TakeKAMA failed to close BUY ticket=", ticket,
                  " Code=", g_tradeMgmt.ResultRetcode());
         else
            Print("TakeKAMA: BUY closed (Bullish->Bearish) ticket=", ticket);
      }
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      if(prevRegime == KAMA_REGIME_BEARISH && curRegime == KAMA_REGIME_BULLISH)
      {
         if(!g_tradeMgmt.PositionClose(ticket))
            Print("ERROR: TakeKAMA failed to close SELL ticket=", ticket,
                  " Code=", g_tradeMgmt.ResultRetcode());
         else
            Print("TakeKAMA: SELL closed (Bearish->Bullish) ticket=", ticket);
      }
   }
}

//------------------------------------------------
// TAKE MANAGER
// Iterates all EA-owned positions on this symbol.
// Short Swing positions: TP already set at entry — no active management needed.
// Long Swing positions : managed by KAMA exit when InpTakeMode == TAKE_KAMA.
//------------------------------------------------

void ManageTakes()
{
   int total = PositionsTotal();
   if(total == 0)
      return;

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);

      // Skip positions not belonging to any strategy of this EA
      if(magic != InpMagicMR &&
         magic != InpMagicRE &&
         magic != InpMagicTP &&
         magic != InpMagicTB &&
         magic != InpMagicKT)
         continue;

      // Short Swing: TP is set at order placement — no runtime management
      if(IsShortSwingMagic(magic))
         continue;

      // Long Swing: apply KAMA flip exit when mode is TAKE_KAMA
      if(InpTakeMode == TAKE_KAMA)
      {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         TakeKAMAByTicket(ticket, posType);
      }
   }
}

#endif
