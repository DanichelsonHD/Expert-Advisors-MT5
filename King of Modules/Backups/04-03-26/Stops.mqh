#ifndef __STOPS_MQH__
#define __STOPS_MQH__

#include "Indicators.mqh"
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade stop_trade;
CPositionInfo stop_pos;


//------------------------------------------------
// CALCULATE STOP LOSS
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

   if(type==ORDER_TYPE_BUY)
      price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   else
      price = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double sl;

   if(type==ORDER_TYPE_BUY)
      sl = NormalizeDouble(price - stopDist,digits);
   else
      sl = NormalizeDouble(price + stopDist,digits);

   return sl;
}


//------------------------------------------------
// TECHNICAL STOP (KELTNER)
//------------------------------------------------

double CalculateTechnicalStop(ENUM_ORDER_TYPE type)
{
   double upper,lower;

   if(!GetKeltner(upper,lower))
      return 0;

   int digits = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);

   if(type==ORDER_TYPE_BUY)
      return NormalizeDouble(lower,digits);

   if(type==ORDER_TYPE_SELL)
      return NormalizeDouble(upper,digits);

   return 0;
}


//------------------------------------------------
// GET STOP BASED ON MODE
//------------------------------------------------

double GetStopLoss(ENUM_ORDER_TYPE type)
{
   if(InpStopMode==STOP_FIXED)
      return CalculateStopLoss(type);

   if(InpStopMode==STOP_TECHNICAL)
      return CalculateTechnicalStop(type);

   return 0;
}


//------------------------------------------------
// TRAILING STOP
//------------------------------------------------

void ManageTrailingStop()
{
   if(!stop_pos.Select(_Symbol))
      return;

   if(stop_pos.Magic()!=(ulong)InpMagicNumber)
      return;

   double atr,avg;

   if(!GetATR(atr,avg))
      return;

   double point = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   int digits   = (int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);

   double trailDist = atr * InpTrailingMultiplier + InpExtraPoints * point;

   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   double currentSL = stop_pos.StopLoss();
   double tp        = stop_pos.TakeProfit();

   ENUM_POSITION_TYPE type = stop_pos.PositionType();

   if(type==POSITION_TYPE_BUY)
   {
      double newSL = NormalizeDouble(bid - trailDist,digits);

      if(newSL > currentSL + point)
         stop_trade.PositionModify(_Symbol,newSL,tp);
   }

   if(type==POSITION_TYPE_SELL)
   {
      double newSL = NormalizeDouble(ask + trailDist,digits);

      if(currentSL==0 || newSL < currentSL - point)
         stop_trade.PositionModify(_Symbol,newSL,tp);
   }
}

#endif