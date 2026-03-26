//+------------------------------------------------------------------+
//|                                    Strategies/Breakout.mqh      |
//+------------------------------------------------------------------+
#ifndef BREAKOUT_MQH
#define BREAKOUT_MQH

#include "../Configs.mqh"
#include "../Indicators.mqh"
#include "../Entries.mqh"

//+------------------------------------------------------------------+
//| Breakout state: track squeeze release and structure break       |
//+------------------------------------------------------------------+
static bool _boWasSqueeze        = false;
static bool _boExpansionDetected = false;

//+------------------------------------------------------------------+
//| Breakout — Run on every bar close                               |
//+------------------------------------------------------------------+
void RunBreakout()
{
   if (!InpEnableBreakout) return;

   ManageStrategyPositions(STRATEGY_BO, InpBOStopType, InpBOTakeType);

   //--- Track squeeze state: once squeeze is confirmed, arm the strategy
   if (isSqueeze())
   {
      _boWasSqueeze = true;
      _boExpansionDetected = false;
      return;
   }

   //--- After squeeze ends, wait for ADX rising + expansion
   if (!_boWasSqueeze) return;

   if (!isTransition() && !isTrending()) return;

   if (isExpansion())
      _boExpansionDetected = true;

   if (!_boExpansionDetected) return;

   double close1 = GetClosed();

   //--- Bullish breakout: price breaks above BB upper
   if (close1 > GetBBUpper() && isAboveEMA50())
   {
      OpenBuy(STRATEGY_BO, InpBOStopType, InpBOTakeType);
      _boWasSqueeze        = false;
      _boExpansionDetected = false;
   }

   //--- Bearish breakout: price breaks below BB lower
   if (close1 < GetBBLower() && isBelowEMA50())
   {
      OpenSell(STRATEGY_BO, InpBOStopType, InpBOTakeType);
      _boWasSqueeze        = false;
      _boExpansionDetected = false;
   }
}

#endif
