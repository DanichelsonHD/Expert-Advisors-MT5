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

bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(dt.hour >= InpStartHour && dt.hour < InpEndHour);
}

//------------------------------------------------
// POSITION COUNTING
// Counts all open positions owned by this EA on this symbol
// (both long and short magic numbers)
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

      int magic = (int)PositionGetInteger(POSITION_MAGIC);
      if(magic != InpLongMagicNumber && magic != InpShortMagicNumber)
         continue;

      count++;
   }

   return count;
}

//------------------------------------------------
// TRADE EXECUTION
// swingMagic: InpLongMagicNumber or InpShortMagicNumber
// stopMode:   InpLongStopMode    or InpShortStopMode
//------------------------------------------------

void ExecuteEntry(ENUM_SIGNAL signal, double atr, int swingMagic, ENUM_STOP_MODE stopMode)
{
   if(signal == SIGNAL_NONE)
      return;

   if(CountOpenPositions() >= InpMaxSimultaneousTrades)
      return;

   ENUM_ORDER_TYPE orderType = (signal == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double sl  = GetStopLoss(orderType, atr, stopMode);
   double tp  = CalculateTakeProfit(orderType, atr);
   double lot = InpLotSize;

   if(swingMagic == InpLongMagicNumber)
   {
      g_trade.SetExpertMagicNumber(InpLongMagicNumber);

      if(orderType == ORDER_TYPE_BUY)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         g_trade.Buy(lot, _Symbol, ask, sl, tp);
      }
      else
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         g_trade.Sell(lot, _Symbol, bid, sl, tp);
      }
   }
   else
   {
      g_trade_short.SetExpertMagicNumber(InpShortMagicNumber);

      if(orderType == ORDER_TYPE_BUY)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         g_trade_short.Buy(lot, _Symbol, ask, sl, tp);
      }
      else
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         g_trade_short.Sell(lot, _Symbol, bid, sl, tp);
      }
   }
}

//------------------------------------------------
// ENTRIES ENGINE
// Each strategy is evaluated independently.
// Signal direction is validated against the strategy's swing mode.
// LONG signals go to the LONG engine; SHORT signals go to the SHORT engine.
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

   // --- Mean Reversion ---
   if(UseMRStrategy != OFF)
   {
      s = SignalMeanReversion();
      if(s == SIGNAL_BUY  && UseMRStrategy == LONG)
         ExecuteEntry(s, atrVal, InpLongMagicNumber,  InpLongStopMode);
      else if(s == SIGNAL_SELL && UseMRStrategy == SHORT)
         ExecuteEntry(s, atrVal, InpShortMagicNumber, InpShortStopMode);
   }

   // --- Pullback ---
   if(UseTPStrategy != OFF)
   {
      s = SignalPullback();
      if(s == SIGNAL_BUY  && UseTPStrategy == LONG)
         ExecuteEntry(s, atrVal, InpLongMagicNumber,  InpLongStopMode);
      else if(s == SIGNAL_SELL && UseTPStrategy == SHORT)
         ExecuteEntry(s, atrVal, InpShortMagicNumber, InpShortStopMode);
   }

   // --- Breakout ---
   if(UseTBStrategy != OFF)
   {
      s = SignalBreakout();
      if(s == SIGNAL_BUY  && UseTBStrategy == LONG)
         ExecuteEntry(s, atrVal, InpLongMagicNumber,  InpLongStopMode);
      else if(s == SIGNAL_SELL && UseTBStrategy == SHORT)
         ExecuteEntry(s, atrVal, InpShortMagicNumber, InpShortStopMode);
   }

   // --- KAMA Trend ---
   if(UseKTStrategy != OFF)
   {
      s = SignalKamaTrend();
      if(s == SIGNAL_BUY  && UseKTStrategy == LONG)
         ExecuteEntry(s, atrVal, InpLongMagicNumber,  InpLongStopMode);
      else if(s == SIGNAL_SELL && UseKTStrategy == SHORT)
         ExecuteEntry(s, atrVal, InpShortMagicNumber, InpShortStopMode);
   }

   // --- RSI Exhaustion ---
   if(UseREStrategy != OFF)
   {
      s = SignalRSIExhaustion();
      if(s == SIGNAL_BUY  && UseREStrategy == LONG)
         ExecuteEntry(s, atrVal, InpLongMagicNumber,  InpLongStopMode);
      else if(s == SIGNAL_SELL && UseREStrategy == SHORT)
         ExecuteEntry(s, atrVal, InpShortMagicNumber, InpShortStopMode);
   }
}

#endif
