//+------------------------------------------------------------------+
//|                          Strategies/KAMAColorInversion.mqh      |
//+------------------------------------------------------------------+
#ifndef KAMA_COLOR_INVERSION_MQH
#define KAMA_COLOR_INVERSION_MQH

#include "../Configs.mqh"
#include "../Indicators.mqh"
#include "../Entries.mqh"

//+------------------------------------------------------------------+
//| KAMA Color Inversion — Run on every bar close                   |
//+------------------------------------------------------------------+
void RunKCI()
{
   if (!InpEnableKCI) return;

   ManageStrategyPositions(STRATEGY_KCI, InpKCIStopType, InpKCITakeType);

   if (!isTrending()) return;

   //--- BUY: KAMA flips from bear (1) to bull (2)
   if (isKAMAFlipBull() && isAboveEMA50())
      OpenBuy(STRATEGY_KCI, InpKCIStopType, InpKCITakeType);

   //--- SELL: KAMA flips from bull (2) to bear (1)
   if (isKAMAFlipBear() && isBelowEMA50())
      OpenSell(STRATEGY_KCI, InpKCIStopType, InpKCITakeType);
}

#endif
