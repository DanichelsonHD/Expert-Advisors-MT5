//+------------------------------------------------------------------+
//|                                                      Entries.mqh |
//+------------------------------------------------------------------+
#ifndef ENTRIES_MQH
#define ENTRIES_MQH

#include "Configs.mqh"
#include "Indicators.mqh"
#include "Stops.mqh"
#include "Takes.mqh"

//+------------------------------------------------------------------+
//| Strategy identifiers                                             |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_ID
{
   STRATEGY_MR  = 0,
   STRATEGY_PB  = 1,
   STRATEGY_BO  = 2,
   STRATEGY_KCI = 3
};

//+------------------------------------------------------------------+
//| Strategy magic numbers (base + id)                              |
//+------------------------------------------------------------------+
#define MAGIC_BASE 100000
int GetMagic(ENUM_STRATEGY_ID id) { return MAGIC_BASE + (int)id; }

//+------------------------------------------------------------------+
//| Count open positions for a given strategy                       |
//+------------------------------------------------------------------+
int CountStrategyTrades(ENUM_STRATEGY_ID id)
{
   int count  = 0;
   int magic  = GetMagic(id);
   int total  = PositionsTotal();
   for (int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if ((int)PositionGetInteger(POSITION_MAGIC) != magic) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Count total open positions across all strategies                |
//+------------------------------------------------------------------+
int CountGlobalTrades()
{
   int count = 0;
   int total = PositionsTotal();
   for (int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if (magic >= MAGIC_BASE && magic < MAGIC_BASE + 4) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Lot size calculation                                             |
//+------------------------------------------------------------------+
double CalcLotSize(double stopDistancePrice)
{
   double lot = InpFixedLot;

   switch (InpLotMode)
   {
      case LOT_FIXED:
         lot = InpFixedLot;
         break;

      case LOT_STEP_SCALING:
      {
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         int    steps   = (int)MathFloor(balance / InpBalanceStep);
         lot = InpFixedLot + steps * InpLotStep;
         break;
      }

      case LOT_RISK_BASED:
      {
         if (stopDistancePrice <= 0.0)
         {
            lot = InpFixedLot;
            break;
         }
         double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
         double riskAmount   = balance * InpRiskPercent / 100.0;
         double tickValue    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double pointsRisk   = stopDistancePrice / _Point;
         double valuePerLot  = (tickValue / tickSize) * _Point * pointsRisk;
         if (valuePerLot <= 0.0) { lot = InpFixedLot; break; }
         lot = riskAmount / valuePerLot;
         break;
      }
   }

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(minLot, MathMin(maxLot, MathRound(lot / lotStep) * lotStep));

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Execute a BUY trade for a given strategy                        |
//+------------------------------------------------------------------+
bool OpenBuy(ENUM_STRATEGY_ID stratId, ENUM_STOP_TYPE stopType, ENUM_TAKE_TYPE takeType)
{
   if (CountGlobalTrades()    >= InpMaxGlobalTrades)     return false;
   if (CountStrategyTrades(stratId) >= InpMaxTradesPerStrategy) return false;

   double sl  = CalcStopBuy(stopType);
   double tp  = CalcTakeBuy(takeType);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopDist = MathAbs(ask - sl);
   double lot = CalcLotSize(stopDist);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = ORDER_TYPE_BUY;
   req.price     = ask;
   req.sl        = sl;
   req.tp        = tp;
   req.magic     = GetMagic(stratId);
   req.deviation = 10;
   req.comment   = "KQ_" + (string)stratId;

   return OrderSend(req, res);
}

//+------------------------------------------------------------------+
//| Execute a SELL trade for a given strategy                       |
//+------------------------------------------------------------------+
bool OpenSell(ENUM_STRATEGY_ID stratId, ENUM_STOP_TYPE stopType, ENUM_TAKE_TYPE takeType)
{
   if (CountGlobalTrades()    >= InpMaxGlobalTrades)     return false;
   if (CountStrategyTrades(stratId) >= InpMaxTradesPerStrategy) return false;

   double sl  = CalcStopSell(stopType);
   double tp  = CalcTakeSell(takeType);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopDist = MathAbs(bid - sl);
   double lot = CalcLotSize(stopDist);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = lot;
   req.type      = ORDER_TYPE_SELL;
   req.price     = bid;
   req.sl        = sl;
   req.tp        = tp;
   req.magic     = GetMagic(stratId);
   req.deviation = 10;
   req.comment   = "KQ_" + (string)stratId;

   return OrderSend(req, res);
}

//+------------------------------------------------------------------+
//| Manage all open positions for a strategy (stops + takes)        |
//+------------------------------------------------------------------+
void ManageStrategyPositions(ENUM_STRATEGY_ID stratId,
                             ENUM_STOP_TYPE   stopType,
                             ENUM_TAKE_TYPE   takeType)
{
   int magic = GetMagic(stratId);
   int total = PositionsTotal();

   for (int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(ticket)) continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if ((int)PositionGetInteger(POSITION_MAGIC) != magic) continue;

      long posType = PositionGetInteger(POSITION_TYPE);

      if (posType == POSITION_TYPE_BUY)
      {
         TrailStopBuy(ticket, stopType);
         ManageTakeBuy(ticket, takeType);
      }
      else if (posType == POSITION_TYPE_SELL)
      {
         TrailStopSell(ticket, stopType);
         ManageTakeSell(ticket, takeType);
      }
   }
}

#endif
