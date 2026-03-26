//+------------------------------------------------------------------+
//|                                                        Takes.mqh |
//+------------------------------------------------------------------+
#ifndef TAKES_MQH
#define TAKES_MQH

#include "Configs.mqh"
#include "Indicators.mqh"

//+------------------------------------------------------------------+
//| Calculate take profit price for a BUY order                     |
//| Returns 0.0 for TAKE_KAMA_FLIP and TAKE_ATR_TRAILING            |
//| (managed dynamically, not set at entry)                         |
//+------------------------------------------------------------------+
double CalcTakeBuy(ENUM_TAKE_TYPE takeType)
{
   double tp = 0.0;

   switch (takeType)
   {
      case TAKE_FIXED:
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         tp = NormalizeDouble(ask + InpFixedTakePoints * _Point, _Digits);
         break;
      }
      case TAKE_KAMA_FLIP:
      case TAKE_ATR_TRAILING:
         tp = 0.0;
         break;
   }

   return tp;
}

//+------------------------------------------------------------------+
//| Calculate take profit price for a SELL order                    |
//+------------------------------------------------------------------+
double CalcTakeSell(ENUM_TAKE_TYPE takeType)
{
   double tp = 0.0;

   switch (takeType)
   {
      case TAKE_FIXED:
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         tp = NormalizeDouble(bid - InpFixedTakePoints * _Point, _Digits);
         break;
      }
      case TAKE_KAMA_FLIP:
      case TAKE_ATR_TRAILING:
         tp = 0.0;
         break;
   }

   return tp;
}

//+------------------------------------------------------------------+
//| Manage take for open BUY position (called on bar close)         |
//+------------------------------------------------------------------+
bool ManageTakeBuy(ulong ticket, ENUM_TAKE_TYPE takeType)
{
   if (!PositionSelectByTicket(ticket)) return false;
   if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) return false;

   switch (takeType)
   {
      case TAKE_KAMA_FLIP:
      {
         if (isKAMAFlipBear())
         {
            MqlTradeRequest req = {};
            MqlTradeResult  res = {};
            req.action   = TRADE_ACTION_DEAL;
            req.position = ticket;
            req.symbol   = _Symbol;
            req.volume   = PositionGetDouble(POSITION_VOLUME);
            req.type     = ORDER_TYPE_SELL;
            req.price    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            req.deviation= 10;
            OrderSend(req, res);
            return true;
         }
         break;
      }
      case TAKE_ATR_TRAILING:
      {
         double currentTP = PositionGetDouble(POSITION_TP);
         double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double newTP     = NormalizeDouble(bid + InpATRTakeMultiplier * GetATR14(), _Digits);

         if (newTP > currentTP || currentTP == 0.0)
         {
            MqlTradeRequest req = {};
            MqlTradeResult  res = {};
            req.action   = TRADE_ACTION_SLTP;
            req.position = ticket;
            req.symbol   = _Symbol;
            req.sl       = PositionGetDouble(POSITION_SL);
            req.tp       = newTP;
            OrderSend(req, res);
         }
         break;
      }
      case TAKE_FIXED:
         break;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Manage take for open SELL position (called on bar close)        |
//+------------------------------------------------------------------+
bool ManageTakeSell(ulong ticket, ENUM_TAKE_TYPE takeType)
{
   if (!PositionSelectByTicket(ticket)) return false;
   if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) return false;

   switch (takeType)
   {
      case TAKE_KAMA_FLIP:
      {
         if (isKAMAFlipBull())
         {
            MqlTradeRequest req = {};
            MqlTradeResult  res = {};
            req.action   = TRADE_ACTION_DEAL;
            req.position = ticket;
            req.symbol   = _Symbol;
            req.volume   = PositionGetDouble(POSITION_VOLUME);
            req.type     = ORDER_TYPE_BUY;
            req.price    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            req.deviation= 10;
            OrderSend(req, res);
            return true;
         }
         break;
      }
      case TAKE_ATR_TRAILING:
      {
         double currentTP = PositionGetDouble(POSITION_TP);
         double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newTP     = NormalizeDouble(ask - InpATRTakeMultiplier * GetATR14(), _Digits);

         if (newTP < currentTP || currentTP == 0.0)
         {
            MqlTradeRequest req = {};
            MqlTradeResult  res = {};
            req.action   = TRADE_ACTION_SLTP;
            req.position = ticket;
            req.symbol   = _Symbol;
            req.sl       = PositionGetDouble(POSITION_SL);
            req.tp       = newTP;
            OrderSend(req, res);
         }
         break;
      }
      case TAKE_FIXED:
         break;
   }

   return false;
}

#endif
