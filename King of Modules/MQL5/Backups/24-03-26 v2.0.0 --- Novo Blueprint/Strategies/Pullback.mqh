//+------------------------------------------------------------------+
//|                                    Strategies/Pullback.mqh      |
//+------------------------------------------------------------------+
#ifndef PULLBACK_MQH
#define PULLBACK_MQH

#include "../Configs.mqh"
#include "../Indicators.mqh"
#include "../Entries.mqh"

//+------------------------------------------------------------------+
//| Pullback — Run on every bar close                               |
//+------------------------------------------------------------------+
void RunPullback()
{
   if (!InpEnablePullback) return;

   ManageStrategyPositions(STRATEGY_PB, InpPBStopType, InpPBTakeType);

   if (!isTrending()) return;
   if (!isRSIPullbackZone()) return;
   if (!isPriceNearEMA20()) return;

   //--- BUY: trending up, price pulls back near EMA20 from above
   if (isAboveEMA50())
   {
      double close1 = GetClosed();
      double ema20  = GetEMA20();
      //--- Price is at or just below EMA20 (within ATR tolerance)
      if (close1 <= ema20 + GetATR14() && close1 >= ema20 - GetATR14())
         OpenBuy(STRATEGY_PB, InpPBStopType, InpPBTakeType);
   }

   //--- SELL: trending down, price pulls back near EMA20 from below
   if (isBelowEMA50())
   {
      double close1 = GetClosed();
      double ema20  = GetEMA20();
      if (close1 >= ema20 - GetATR14() && close1 <= ema20 + GetATR14())
         OpenSell(STRATEGY_PB, InpPBStopType, InpPBTakeType);
   }
}

#endif
