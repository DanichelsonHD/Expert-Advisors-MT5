//+------------------------------------------------------------------+
//|                                                       Main.mq5  |
//+------------------------------------------------------------------+
#property copyright "KING QUANT"
#property version   "1.00"
#property strict

#include "Configs.mqh"
#include "Indicators.mqh"
#include "Entries.mqh"
#include "Strategies/MeanReversion.mqh"
#include "Strategies/Pullback.mqh"
#include "Strategies/Breakout.mqh"
#include "Strategies/KAMAColorInversion.mqh"

//+------------------------------------------------------------------+
//| Bar tracking                                                     |
//+------------------------------------------------------------------+
static datetime _lastBarTime = 0;

//+------------------------------------------------------------------+
//| Returns true once per finalized bar                             |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if (currentBarTime != _lastBarTime)
   {
      _lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Central run function — called on every new bar                  |
//+------------------------------------------------------------------+
void Run()
{
   if (!IndicatorsUpdate()) return;

   RunMeanReversion();
   RunPullback();
   RunBreakout();
   RunKCI();
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if (!IndicatorsInit())
   {
      Print("ERROR: One or more indicator handles failed to initialize.");
      return INIT_FAILED;
   }

   _lastBarTime = 0;

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorsDeinit();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   if (!IsNewBar()) return;
   Run();
}

//+------------------------------------------------------------------+
