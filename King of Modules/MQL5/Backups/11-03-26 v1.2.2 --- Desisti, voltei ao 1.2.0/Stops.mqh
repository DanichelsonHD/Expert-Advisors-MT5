#ifndef __STOPS_MQH__
#define __STOPS_MQH__

#include "Indicators.mqh"
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//------------------------------------------------
// SWING TECHNICAL STOP
// Uses lookback and buffer specific to swing type.
// BUY  -> LowestLow(lookback)  - bufferPoints * _Point
// SELL -> HighestHigh(lookback) + bufferPoints * _Point
//------------------------------------------------

double CalculateSwingTechnicalStop(ENUM_ORDER_TYPE type, int lookback, int bufferPoints)
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double buffer = bufferPoints * point;

   int    stopLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int    freezeLevel= (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist    = MathMax(stopLevel, freezeLevel) * point + point;

   if(type == ORDER_TYPE_BUY)
   {
      double lowest = DBL_MAX;

      for(int i = 1; i <= lookback; i++)
      {
         double low = iLow(_Symbol, _Period, i);
         if(low < lowest)
            lowest = low;
      }

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(lowest - buffer, digits);

      if(ask - sl < minDist)
         sl = NormalizeDouble(ask - minDist, digits);

      return sl;
   }
   else
   {
      double highest = -DBL_MAX;

      for(int i = 1; i <= lookback; i++)
      {
         double high = iHigh(_Symbol, _Period, i);
         if(high > highest)
            highest = high;
      }

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(highest + buffer, digits);

      if(sl - bid < minDist)
         sl = NormalizeDouble(bid + minDist, digits);

      return sl;
   }
}


//------------------------------------------------
// ATR STOP CALCULATION (com broker safety)
//------------------------------------------------

double CalculateATRStop(ENUM_ORDER_TYPE orderType, double atr)
{
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int    stopLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int    freezeLevel= (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

   double stopDist = atr * InpStopMultiplier + (InpExtraPoints * point);
   double minDist  = MathMax(stopLevel, freezeLevel) * point + point;

   if(stopDist < minDist)
      stopDist = minDist;

   double entryPrice;
   double sl;

   if(orderType == ORDER_TYPE_BUY)
   {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl = NormalizeDouble(entryPrice - stopDist, digits);
   }
   else
   {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = NormalizeDouble(entryPrice + stopDist, digits);
   }

   return sl;
}


//------------------------------------------------
// GET STOP BASED ON MODE AND SWING TYPE
// STOP_FIXED     -> ATR-based (swing-agnostic)
// STOP_TECHNICAL -> swing-specific lookback + buffer
// TRAILING_STOP  -> initial ATR stop at entry; trailing managed separately
//------------------------------------------------

double GetStopLoss(ENUM_ORDER_TYPE orderType, double atr, long magic)
{
   if(InpStopMode == STOP_FIXED || InpStopMode == TRAILING_STOP)
      return CalculateATRStop(orderType, atr);

   // STOP_TECHNICAL
   if(IsShortSwingMagic(magic))
      return CalculateSwingTechnicalStop(orderType,
                                         InpShortSwingLookback,
                                         InpShortSwingBufferPoints);

   return CalculateSwingTechnicalStop(orderType,
                                      InpLongSwingLookback,
                                      InpLongSwingBufferPoints);
}


//------------------------------------------------
// TRAILING STOP
// Iterates all EA-owned positions on this symbol
// across all strategy magic numbers.
//------------------------------------------------

void ManageTrailingStop(double atr)
{
   if(InpStopMode != TRAILING_STOP)
      return;

   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int    stopLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int    freezeLevel= (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist    = MathMax(stopLevel, freezeLevel) * point + point;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      long magic = PositionGetInteger(POSITION_MAGIC);

      if(magic != InpMagicMR &&
         magic != InpMagicRE &&
         magic != InpMagicTP &&
         magic != InpMagicTB &&
         magic != InpMagicKT)
         continue;

      double trailDist = atr * InpStopMultiplier + (InpExtraPoints * point);
      if(trailDist < minDist)
         trailDist = minDist;

      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(posType == POSITION_TYPE_BUY)
      {
         double newSL = NormalizeDouble(bid - trailDist, digits);

         if(newSL > currentSL + point)
            g_trade.PositionModify(ticket, newSL, currentTP);
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double newSL = NormalizeDouble(ask + trailDist, digits);

         if(currentSL == 0.0 || newSL < currentSL - point)
            g_trade.PositionModify(ticket, newSL, currentTP);
      }
   }
}


#endif