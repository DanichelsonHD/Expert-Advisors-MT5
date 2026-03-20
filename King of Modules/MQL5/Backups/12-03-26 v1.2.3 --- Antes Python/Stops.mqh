#ifndef __STOPS_MQH__
#define __STOPS_MQH__

#include "Indicators.mqh"
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CPositionInfo stop_pos;


//------------------------------------------------
// CALCULATE ATR STOP (with broker safety)
//------------------------------------------------

double CalculateATRStop(ENUM_ORDER_TYPE orderType, double atr)
{
   double point       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits      = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int    stopLevel   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int    freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

   double stopDist = atr * InpStopMultiplier + (InpStopExtraPoints * point);
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
// TECHNICAL STOP (Highest High & Lowest Low)
//------------------------------------------------

double CalculateTechnicalStop(ENUM_ORDER_TYPE type)
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double buffer = InpStopExtraPoints * point;

   if(type == ORDER_TYPE_BUY)
   {
      double lowest = iLow(_Symbol, _Period, 1);

      for(int i = 1; i <= InpTechnicalStopLookback; i++)
      {
         double low = iLow(_Symbol, _Period, i);
         if(low < lowest)
            lowest = low;
      }

      int    stopLevel2   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      int    freezeLevel2 = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      double minDist2     = MathMax(stopLevel2, freezeLevel2) * point + point;

      double ask2 = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl2  = NormalizeDouble(lowest - buffer, digits);

      if(ask2 - sl2 < minDist2)
         sl2 = NormalizeDouble(ask2 - minDist2, digits);

      return sl2;
   }
   else
   {
      double highest = iHigh(_Symbol, _Period, 1);

      for(int i = 1; i <= InpTechnicalStopLookback; i++)
      {
         double high = iHigh(_Symbol, _Period, i);
         if(high > highest)
            highest = high;
      }

      int    stopLevel3   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      int    freezeLevel3 = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      double minDist3     = MathMax(stopLevel3, freezeLevel3) * point + point;

      double bid3 = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl3  = NormalizeDouble(highest + buffer, digits);

      if(sl3 - bid3 < minDist3)
         sl3 = NormalizeDouble(bid3 + minDist3, digits);

      return sl3;
   }
}


//------------------------------------------------
// GET STOP BASED ON MODE
// stopMode is passed explicitly per engine
//------------------------------------------------

double GetStopLoss(ENUM_ORDER_TYPE orderType, double atr, ENUM_STOP_MODE stopMode)
{
   if(stopMode == STOP_FIXED)
      return CalculateATRStop(orderType, atr);

   if(stopMode == STOP_TECHNICAL)
      return CalculateTechnicalStop(orderType);

   // TRAILING_STOP: initial SL uses ATR stop; trail is managed in ManageTrailingStop
   return CalculateATRStop(orderType, atr);
}


//------------------------------------------------
// TRAILING STOP — manages all positions for one engine
// Iterates all open positions matching swingMagic
//------------------------------------------------

void ManageTrailingStopForEngine(double atr, int swingMagic, ENUM_STOP_MODE stopMode)
{
   if(stopMode != TRAILING_STOP)
      return;

   double point       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits      = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int    stopLevel   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int    freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

   double trailDist = atr * InpStopMultiplier + (InpStopExtraPoints * point);
   double minDist   = MathMax(stopLevel, freezeLevel) * point + point;

   if(trailDist < minDist)
      trailDist = minDist;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!stop_pos.SelectByTicket(ticket))
         continue;

      if(stop_pos.Symbol() != _Symbol)
         continue;

      if((int)stop_pos.Magic() != swingMagic)
         continue;

      double currentSL = stop_pos.StopLoss();
      double currentTP = stop_pos.TakeProfit();

      ENUM_POSITION_TYPE posType = stop_pos.PositionType();

      if(posType == POSITION_TYPE_BUY)
      {
         double newSL = NormalizeDouble(bid - trailDist, digits);

         if(newSL > currentSL + point)
         {
            if(swingMagic == InpLongMagicNumber)
               g_trade.PositionModify(ticket, newSL, currentTP);
            else
               g_trade_short.PositionModify(ticket, newSL, currentTP);
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double newSL = NormalizeDouble(ask + trailDist, digits);

         if(currentSL == 0.0 || newSL < currentSL - point)
         {
            if(swingMagic == InpLongMagicNumber)
               g_trade.PositionModify(ticket, newSL, currentTP);
            else
               g_trade_short.PositionModify(ticket, newSL, currentTP);
         }
      }
   }
}


//------------------------------------------------
// TRAILING STOP — public entry point
// Called from OnTick; manages both engines
//------------------------------------------------

void ManageTrailingStop(double atr)
{
   ManageTrailingStopForEngine(atr, InpLongMagicNumber,  InpLongStopMode);
   ManageTrailingStopForEngine(atr, InpShortMagicNumber, InpShortStopMode);
}


#endif
