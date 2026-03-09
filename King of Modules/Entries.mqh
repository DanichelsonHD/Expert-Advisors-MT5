#ifndef __ENTRIES_MQH__
#define __ENTRIES_MQH__

#include "Indicators.mqh"
#include "Stops.mqh"
#include "Takes.mqh"

#include "Strategies/MeanReversion.mqh"
#include "Strategies/Pullback.mqh"
#include "Strategies/Breakout.mqh"
#include "Strategies/KamaMomentumTrend.mqh"

CPositionInfo entry_pos;

bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(dt.hour >= InpStartHour && dt.hour < InpEndHour);
}

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

   ENUM_SIGNAL signal = GetSignal();

   if(signal == SIGNAL_NONE)
      return;

   ExecuteEntry(signal, atrVal);
}

//------------------------------------------------
// SIGNAL ENGINE
//------------------------------------------------

ENUM_SIGNAL GetSignal()
{
   ENUM_SIGNAL s;

   /*s = SignalMeanReversion();
   if(s != SIGNAL_NONE)
      return s;*/

   s = SignalPullback();
   if(s != SIGNAL_NONE)
      return s;

   s = SignalBreakout();
   if(s != SIGNAL_NONE)
      return s;
   
   s = SignalKamaMomentumTrend();
   if(s != SIGNAL_NONE)
      return s;

   return SIGNAL_NONE;
}

bool HasOpenPosition()
{
   if(!entry_pos.Select(_Symbol))
      return false;
   if(entry_pos.Magic() != (ulong)InpMagicNumber)
      return false;
   return true;
}

void ExecuteEntry(ENUM_SIGNAL signal, double atr)
{
   if(signal == SIGNAL_NONE)  return;
   if(HasOpenPosition())      return;

   ENUM_ORDER_TYPE orderType = (signal == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double sl  = GetStopLoss(orderType, atr);
   double lot = InpLotSize;

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

void EntryBuy(double atr)
{
   if(SelectEAPosition()) return;

   double sl  = GetStopLoss(ORDER_TYPE_BUY, atr);
   double tp  = (InpTakeMode == TAKE_FIXED) ? CalculateTakeProfit(ORDER_TYPE_BUY) : 0;
   double lot = InpUseStepLotScaling ? g_currentScaledLot : InpLotSize;

   g_trade.Buy(lot, _Symbol, 0, sl, tp);
}

void EntrySell(double atr)
{
   if(SelectEAPosition()) return;

   double sl  = GetStopLoss(ORDER_TYPE_SELL, atr);
   double tp  = (InpTakeMode == TAKE_FIXED) ? CalculateTakeProfit(ORDER_TYPE_SELL) : 0;
   double lot = InpUseStepLotScaling ? g_currentScaledLot : InpLotSize;

   g_trade.Sell(lot, _Symbol, 0, sl, tp);
}

#endif
