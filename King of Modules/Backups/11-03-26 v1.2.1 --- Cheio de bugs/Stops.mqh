#ifndef __STOPS_MQH__
#define __STOPS_MQH__

#include "Indicators.mqh"
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CPositionInfo stop_pos;


//------------------------------------------------
// CALCULATE STOP LOSS (ATR-based, legacy)
//------------------------------------------------

double CalculateStopLoss(ENUM_ORDER_TYPE type)
{
   double atr,avg;

   if(!GetATR(atr,avg))
      return 0;

   double point  = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits    = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);

   double extraDist = InpExtraPoints * point;
   double stopDist  = atr * InpStopMultiplier + extraDist;

   double price;
   double sl;

   if(type==ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      sl = NormalizeDouble(price - stopDist,digits);
   }
   else
   {
      price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      sl = NormalizeDouble(price + stopDist,digits);
   }

   return sl;
}


//------------------------------------------------
// TECHNICAL STOP (Highest High & Lowest Low)
// Generic version — uses legacy InpTechnicalStopLookback
//------------------------------------------------

double CalculateTechnicalStop(ENUM_ORDER_TYPE type)
{
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double buffer = InpExtraPoints * point;

   if(type == ORDER_TYPE_BUY)
   {
      double lowest = iLow(_Symbol, _Period, 1);

      for(int i = 1; i <= InpTechnicalStopLookback; i++)
      {
         double low = iLow(_Symbol, _Period, i);
         if(low < lowest)
            lowest = low;
      }

      int    stopLevel2  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      int    freezeLevel2= (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      double minDist2    = MathMax(stopLevel2, freezeLevel2) * point + point;

      double ask2        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl2         = NormalizeDouble(lowest - buffer, digits);

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

      int    stopLevel3  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      int    freezeLevel3= (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      double minDist3    = MathMax(stopLevel3, freezeLevel3) * point + point;

      double bid3        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl3         = NormalizeDouble(highest + buffer, digits);

      if(sl3 - bid3 < minDist3)
         sl3 = NormalizeDouble(bid3 + minDist3, digits);

      return sl3;
   }
}


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
      double lowest = iLow(_Symbol, _Period, 1);

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
      double highest = iHigh(_Symbol, _Period, 1);

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
// magic parameter drives short vs long swing stop.
// STOP_FIXED     -> ATR-based (swing-agnostic)
// STOP_TECHNICAL -> swing-specific lookback + buffer
//------------------------------------------------

double GetStopLoss(ENUM_ORDER_TYPE orderType, double atr, long magic)
{
   if(InpStopMode == STOP_FIXED)
      return CalculateATRStop(orderType, atr);

   if(InpStopMode == STOP_TECHNICAL)
   {
      if(IsShortSwingMagic(magic))
         return CalculateSwingTechnicalStop(orderType,
                                            InpShortSwingLookback,
                                            InpShortSwingBufferPoints);

      else
         return CalculateSwingTechnicalStop(orderType,
                                            InpLongSwingLookback,
                                            InpLongSwingBufferPoints);

      return CalculateTechnicalStop(orderType);
   }

   return 0;
}


//------------------------------------------------
// TRAILING STOP
//------------------------------------------------

void ManageTrailingStop(double atr)
{
   if(!g_position.Select(_Symbol))
      return;

   if(g_position.Magic() != (ulong)InpMagicNumber)
      return;

   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int    stopLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int    freezeLevel= (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

   double trailDist = atr * InpStopMultiplier + (InpExtraPoints * point);
   double minDist   = MathMax(stopLevel, freezeLevel) * point + point;

   if(trailDist < minDist)
      trailDist = minDist;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double currentSL = g_position.StopLoss();
   double currentTP = g_position.TakeProfit();

   ENUM_POSITION_TYPE posType = g_position.PositionType();

   if(posType == POSITION_TYPE_BUY)
   {
      double newSL = NormalizeDouble(bid - trailDist, digits);

      if(newSL > currentSL + point)
         g_trade.PositionModify(_Symbol, newSL, currentTP);
   }
   else if(posType == POSITION_TYPE_SELL)
   {
      double newSL = NormalizeDouble(ask + trailDist, digits);

      if(currentSL == 0.0 || newSL < currentSL - point)
         g_trade.PositionModify(_Symbol, newSL, currentTP);
   }
}


#endif