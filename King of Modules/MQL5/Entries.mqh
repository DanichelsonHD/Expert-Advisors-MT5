#ifndef __ENTRIES_MQH__
#define __ENTRIES_MQH__

#include "Indicators.mqh"
#include "Stops.mqh"
#include "Takes.mqh"

#include "Strategies/MeanReversion.mqh"
#include "Strategies/Pullback.mqh"
#include "Strategies/Breakout.mqh"
#include "Strategies/KamaTrend.mqh"

bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(dt.hour >= InpStartHour && dt.hour < InpEndHour);
}

//------------------------------------------------
// POSITION COUNTING
// Counts open positions owned by this EA on this symbol
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

      if((int)PositionGetInteger(POSITION_MAGIC) != InpLongMagicNumber)
         continue;

      count++;
   }

   return count;
}

//------------------------------------------------
// TRADE EXECUTION
// Respects global simultaneous trade limit
//------------------------------------------------

void ExecuteEntry(ENUM_SIGNAL signal, double atr)
{
   if(signal == SIGNAL_NONE)
      return;

   if(CountOpenPositions() >= InpMaxSimultaneousTrades)
      return;

   ENUM_ORDER_TYPE orderType = (signal == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double sl  = GetStopLoss(orderType, atr);
   double lot = CalculateLotSize();

   if(orderType == ORDER_TYPE_BUY)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      g_trade.Buy(lot, _Symbol, ask, sl, 0);
   }
   else
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      g_trade.Sell(lot, _Symbol, bid, sl, 0);
   }
}

double CalculateLotSize()
{
   if(!InpUseStepLotScaling)
      return g_currentScaledLot;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   double steps = MathFloor(balance / InpStepCapital);

   double lot = InpLotSize + steps * InpStepLot;

   double minLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);

   lot = MathMax(lot,minLot);
   lot = MathMin(lot,maxLot);

   return NormalizeDouble(lot,2);
}

//------------------------------------------------
// ENTRIES ENGINE
// Each strategy is evaluated independently
// Each signal attempts execution against the global limit
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
      ExecuteEntry(s, atrVal);

   s = SignalPullback();
   if(s != SIGNAL_NONE && UseTPStrategy)
      ExecuteEntry(s, atrVal);

   s = SignalBreakout();
   if(s != SIGNAL_NONE && UseTBStrategy)
      ExecuteEntry(s, atrVal);

   s = SignalKamaTrend();
   if(s != SIGNAL_NONE && UseKTStrategy)
      ExecuteEntry(s, atrVal);
}

#endif