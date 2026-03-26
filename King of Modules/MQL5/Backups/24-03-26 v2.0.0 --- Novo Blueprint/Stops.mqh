//+------------------------------------------------------------------+
//|                                                        Stops.mqh |
//+------------------------------------------------------------------+
#ifndef STOPS_MQH
#define STOPS_MQH

#include "Configs.mqh"
#include "Indicators.mqh"

//+------------------------------------------------------------------+
//| Calculate stop loss price for a BUY order                       |
//+------------------------------------------------------------------+
double CalcStopBuy(ENUM_STOP_TYPE stopType)
{
   double sl = 0.0;

   switch (stopType)
   {
      case STOP_TECHNICAL:
      {
         double lowestLow = DBL_MAX;
         for (int i = 1; i <= InpTechLookbackBars; i++)
         {
            double low = iLow(_Symbol, _Period, i);
            if (low < lowestLow) lowestLow = low;
         }
         sl = lowestLow - InpTechStopBufferPoints * _Point;
         break;
      }
      case STOP_FIXED:
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         sl = ask - InpFixedStopPoints * _Point;
         break;
      }
      case STOP_ATR:
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         sl = ask - InpATRStopMultiplier * GetATR14();
         break;
      }
   }

   return NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
//| Calculate stop loss price for a SELL order                      |
//+------------------------------------------------------------------+
double CalcStopSell(ENUM_STOP_TYPE stopType)
{
   double sl = 0.0;

   switch (stopType)
   {
      case STOP_TECHNICAL:
      {
         double highestHigh = -DBL_MAX;
         for (int i = 1; i <= InpTechLookbackBars; i++)
         {
            double high = iHigh(_Symbol, _Period, i);
            if (high > highestHigh) highestHigh = high;
         }
         sl = highestHigh + InpTechStopBufferPoints * _Point;
         break;
      }
      case STOP_FIXED:
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         sl = bid + InpFixedStopPoints * _Point;
         break;
      }
      case STOP_ATR:
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         sl = bid + InpATRStopMultiplier * GetATR14();
         break;
      }
   }

   return NormalizeDouble(sl, _Digits);
}

//+------------------------------------------------------------------+
//| Trail stop for open BUY positions (called on bar close)         |
//+------------------------------------------------------------------+
void TrailStopBuy(ulong ticket, ENUM_STOP_TYPE stopType)
{
   if (stopType != STOP_ATR) return;
   if (!PositionSelectByTicket(ticket)) return;
   if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) return;

   double currentSL  = PositionGetDouble(POSITION_SL);
   double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double newSL      = NormalizeDouble(bid - InpATRStopMultiplier * GetATR14(), _Digits);

   if (newSL > currentSL)
   {
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action    = TRADE_ACTION_SLTP;
      req.position  = ticket;
      req.symbol    = _Symbol;
      req.sl        = newSL;
      req.tp        = PositionGetDouble(POSITION_TP);
      OrderSend(req, res);
   }
}

//+------------------------------------------------------------------+
//| Trail stop for open SELL positions (called on bar close)        |
//+------------------------------------------------------------------+
void TrailStopSell(ulong ticket, ENUM_STOP_TYPE stopType)
{
   if (stopType != STOP_ATR) return;
   if (!PositionSelectByTicket(ticket)) return;
   if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) return;

   double currentSL  = PositionGetDouble(POSITION_SL);
   double ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double newSL      = NormalizeDouble(ask + InpATRStopMultiplier * GetATR14(), _Digits);

   if (newSL < currentSL || currentSL == 0.0)
   {
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action    = TRADE_ACTION_SLTP;
      req.position  = ticket;
      req.symbol    = _Symbol;
      req.sl        = newSL;
      req.tp        = PositionGetDouble(POSITION_TP);
      OrderSend(req, res);
   }
}

#endif
