//+------------------------------------------------------------------+
//|                                           EA_KingofModules.mq5   |
//+------------------------------------------------------------------+
#property copyright   "Daniel Pereira & Lucas Mattos"
#property link        ""
#property description "EA based on multiple modules of code, so it can operate with multiple strategies"
#property version     "1.31"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

#include "Indicators.mqh"
#include "Strategies/MeanReversion.mqh"
#include "Entries.mqh"
#include "Takes.mqh"
#include "Stops.mqh"

//--- Global trade objects (shared across all modules)
CTrade        g_trade;
CPositionInfo g_position;

//--- Lot scaling: initial balance captured at OnInit for step scaling
double g_initialBalance = 0.0;

int OnInit()
{
   if(!IndicatorsInit())
   {
      Print("Indicator initialization failed");
      return INIT_FAILED;
   }

   // Capture starting balance for step lot scaling
   g_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   // Initialize per-strategy CTrade objects and g_tradeMgmt
   InitStrategyTrades();

   // g_trade: used for trailing stop management (iterates by magic, not symbol)
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(GetSymbolFillMode());

   Print("OnInit OK");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    IndicatorsRelease();
    Print("OnDeinit OK");
}

void OnTick()
{
   // Position management runs on every tick (no time filter)
   double atr, avg;
   if(GetATR(atr, avg))
      ManageTrailingStop(atr);
   ManageTakes();

   // Entries respect time filter
   if(InpUseTimeFilter && !IsWithinTradingHours()) return;

   EntriesEngine();
}

//+------------------------------------------------------------------+