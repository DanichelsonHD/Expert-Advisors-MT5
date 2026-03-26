//+------------------------------------------------------------------+
//|                              Strategies/MeanReversion.mqh       |
//+------------------------------------------------------------------+
#ifndef MEAN_REVERSION_MQH
#define MEAN_REVERSION_MQH

#include "../Configs.mqh"
#include "../Indicators.mqh"
#include "../Entries.mqh"

//+------------------------------------------------------------------+
//| Mean Reversion state tracking                                   |
//+------------------------------------------------------------------+
static bool _mrWaitBuyReentry  = false;
static bool _mrWaitSellReentry = false;

//+------------------------------------------------------------------+
//| Mean Reversion — Run on every bar close                         |
//+------------------------------------------------------------------+
void RunMeanReversion()
{
   if (!InpEnableMeanReversion) return;

   ManageStrategyPositions(STRATEGY_MR, InpMRStopType, InpMRTakeType);

   //if (!isRanging()) { _mrWaitBuyReentry = false; _mrWaitSellReentry = false; return; }

   double close1 = GetClosed();

   //--- Detect exhaustion: price moves outside bands, set wait flag
   if (isExhaustionBuy() && isOversold())
      _mrWaitBuyReentry = true;

   if (isExhaustionSell() && isOverbought())
      _mrWaitSellReentry = true;

   //--- BUY re-entry: price was below bands, now back inside
   if (_mrWaitBuyReentry)
   {
      bool reenteredInside = !isExhaustionBuy() && (close1 >= GetBBLower() && close1 >= GetKCLower());
      if (reenteredInside)
      {
         OpenBuy(STRATEGY_MR, InpMRStopType, InpMRTakeType);
         _mrWaitBuyReentry = false;
      }
   }

   //--- SELL re-entry: price was above bands, now back inside
   if (_mrWaitSellReentry)
   {
      bool reenteredInside = !isExhaustionSell() && (close1 <= GetBBUpper() && close1 <= GetKCUpper());
      if (reenteredInside)
      {
         OpenSell(STRATEGY_MR, InpMRStopType, InpMRTakeType);
         _mrWaitSellReentry = false;
      }
   }
}

#endif
