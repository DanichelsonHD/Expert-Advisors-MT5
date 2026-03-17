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

void InitStrategyTrades()
{
   g_tradeMR.SetExpertMagicNumber(InpMagicMR);
   g_tradeMR.SetDeviationInPoints(10);
   g_tradeMR.SetTypeFilling(ORDER_FILLING_IOC);

   g_tradeRE.SetExpertMagicNumber(InpMagicRE);
   g_tradeRE.SetDeviationInPoints(10);
   g_tradeRE.SetTypeFilling(ORDER_FILLING_IOC);

   g_tradeTP.SetExpertMagicNumber(InpMagicTP);
   g_tradeTP.SetDeviationInPoints(10);
   g_tradeTP.SetTypeFilling(ORDER_FILLING_IOC);

   g_tradeTB.SetExpertMagicNumber(InpMagicTB);
   g_tradeTB.SetDeviationInPoints(10);
   g_tradeTB.SetTypeFilling(ORDER_FILLING_IOC);

   g_tradeKT.SetExpertMagicNumber(InpMagicKT);
   g_tradeKT.SetDeviationInPoints(10);
   g_tradeKT.SetTypeFilling(ORDER_FILLING_IOC);
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
   double lot = InpLotSize;

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

   s = SignalMeanReversion();
   if(s != SIGNAL_NONE && UseMRStrategy)
      ExecuteEntry(s, atrVal, g_tradeMR, InpMagicMR);

   s = SignalPullback();
   if(s != SIGNAL_NONE && UseTPStrategy)
      ExecuteEntry(s, atrVal, g_tradeTP, InpMagicTP);

   s = SignalBreakout();
   if(s != SIGNAL_NONE && UseTBStrategy)
      ExecuteEntry(s, atrVal, g_tradeTB, InpMagicTB);

   s = SignalKamaTrend();
   if(s != SIGNAL_NONE && UseKTStrategy)
      ExecuteEntry(s, atrVal, g_tradeKT, InpMagicKT);

   s = SignalRSIExhaustion();
   if(s != SIGNAL_NONE && UseREStrategy)
      ExecuteEntry(s, atrVal, g_tradeRE, InpMagicRE);
}

#endif
