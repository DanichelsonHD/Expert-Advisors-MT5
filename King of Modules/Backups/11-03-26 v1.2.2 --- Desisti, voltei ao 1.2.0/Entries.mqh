#ifndef __ENTRIES_MQH__
#define __ENTRIES_MQH__

#include "Indicators.mqh"
#include "Stops.mqh"
#include "Takes.mqh"

#include "Strategies/MeanReversion.mqh"
#include "Strategies/Pullback.mqh"
#include "Strategies/Breakout.mqh"
#include "Strategies/KamaTrend.mqh"
#include "Strategies/RSIExhaustion.mqh"

//------------------------------------------------
// PER-STRATEGY TRADE OBJECTS
// Each strategy has its own CTrade instance so
// magic numbers are encoded per-strategy.
//------------------------------------------------

CTrade g_tradeMR;
CTrade g_tradeRE;
CTrade g_tradeTP;
CTrade g_tradeTB;
CTrade g_tradeKT;

// Dedicated trade object for position management (KAMA exits, etc.)
// Uses no magic validation — closes by ticket only.
CTrade g_tradeMgmt;

//------------------------------------------------
// FILL MODE QUERY
// Returns the correct fill type for the current symbol.
//------------------------------------------------

ENUM_ORDER_TYPE_FILLING GetSymbolFillMode()
{
   uint fillMode = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

   if((fillMode & SYMBOL_FILLING_FOK) != 0)
      return ORDER_FILLING_FOK;

   if((fillMode & SYMBOL_FILLING_IOC) != 0)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}

void InitStrategyTrades()
{
   ENUM_ORDER_TYPE_FILLING fill = GetSymbolFillMode();

   g_tradeMR.SetExpertMagicNumber(InpMagicMR);
   g_tradeMR.SetDeviationInPoints(10);
   g_tradeMR.SetTypeFilling(fill);

   g_tradeRE.SetExpertMagicNumber(InpMagicRE);
   g_tradeRE.SetDeviationInPoints(10);
   g_tradeRE.SetTypeFilling(fill);

   g_tradeTP.SetExpertMagicNumber(InpMagicTP);
   g_tradeTP.SetDeviationInPoints(10);
   g_tradeTP.SetTypeFilling(fill);

   g_tradeTB.SetExpertMagicNumber(InpMagicTB);
   g_tradeTB.SetDeviationInPoints(10);
   g_tradeTB.SetTypeFilling(fill);

   g_tradeKT.SetExpertMagicNumber(InpMagicKT);
   g_tradeKT.SetDeviationInPoints(10);
   g_tradeKT.SetTypeFilling(fill);

   g_tradeMgmt.SetExpertMagicNumber(InpMagicNumber);
   g_tradeMgmt.SetDeviationInPoints(10);
   g_tradeMgmt.SetTypeFilling(fill);
}

//------------------------------------------------
// TRADING HOURS GUARD
//------------------------------------------------

bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(dt.hour >= InpStartHour && dt.hour < InpEndHour);
}

//------------------------------------------------
// POSITION COUNTING
// Counts all EA-owned positions on this symbol
// across all strategy magic numbers.
//------------------------------------------------

int CountOpenPositions()
{
   int count = 0;
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

      count++;
   }

   return count;
}

//------------------------------------------------
// TRADE EXECUTION
// Routes to the correct CTrade instance.
// Calculates TP based on swing type encoded in magic.
//------------------------------------------------

void ExecuteEntry(ENUM_SIGNAL signal, double atr, CTrade &trade, int magic)
{
   if(signal == SIGNAL_NONE)
      return;

   if(CountOpenPositions() >= InpMaxSimultaneousTrades)
      return;

   ENUM_ORDER_TYPE orderType = (signal == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double sl  = GetStopLoss(orderType, atr, magic);

   // Lot size: step scaling when enabled, fixed lot otherwise
   double lot;
   if(InpUseStepLotScaling)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      // steps clamped to minimum of 0 — no negative lot scaling when balance drops below initial
      double steps   = MathMax(0.0, MathFloor((balance - g_initialBalance) / InpStepCapital));
      double rawLot  = InpInitialLot + steps * InpStepLot;
      double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      lot = MathRound(rawLot / step) * step;
      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      lot = MathMax(minLot, MathMin(maxLot, lot));
   }
   else
   {
      lot = InpLotSize;
   }

   if(orderType == ORDER_TYPE_BUY)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double tp  = CalculateTakeProfit(ORDER_TYPE_BUY, magic, ask);
      trade.Buy(lot, _Symbol, ask, sl, tp);
   }
   else
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double tp  = CalculateTakeProfit(ORDER_TYPE_SELL, magic, bid);
      trade.Sell(lot, _Symbol, bid, sl, tp);
   }
}

//------------------------------------------------
// ENTRIES ENGINE
// Each strategy is evaluated independently.
// Each call uses the strategy's own CTrade and magic.
//------------------------------------------------

void EntriesEngine()
{
   static datetime s_lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == s_lastBarTime)
      return;

   s_lastBarTime = currentBarTime;

   double atrVal, atrAvg;
   if(!GetATR(atrVal, atrAvg))
      return;

   ENUM_SIGNAL s;

   if(UseMRStrategy)
   {
      s = SignalMeanReversion();
      if(s != SIGNAL_NONE)
         ExecuteEntry(s, atrVal, g_tradeMR, InpMagicMR);
   }

   if(UseTPStrategy)
   {
      s = SignalPullback();
      if(s != SIGNAL_NONE)
         ExecuteEntry(s, atrVal, g_tradeTP, InpMagicTP);
   }

   if(UseTBStrategy)
   {
      s = SignalBreakout();
      if(s != SIGNAL_NONE)
         ExecuteEntry(s, atrVal, g_tradeTB, InpMagicTB);
   }

   if(UseKTStrategy)
   {
      s = SignalKamaTrend();
      if(s != SIGNAL_NONE)
         ExecuteEntry(s, atrVal, g_tradeKT, InpMagicKT);
   }

   if(UseREStrategy)
   {
      s = SignalRSIExhaustion();
      if(s != SIGNAL_NONE)
         ExecuteEntry(s, atrVal, g_tradeRE, InpMagicRE);
   }
}

#endif
