//+------------------------------------------------------------------+
//|                                           EA_KingofModules.mq5   |
//+------------------------------------------------------------------+
#property copyright   "Daniel Pereira & Lucas Mattos"
#property link        ""
#property description "EA based on multiple modules of code, so it can operate with multiple strategies"
#property version     "1.30"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

#include "Indicators.mqh"
#include "Strategies/MeanReversion.mqh"
#include "Entries.mqh"
#include "Takes.mqh"
#include "Stops.mqh"

//--- Global trade objects (shared across all modules)
CTrade        g_trade;        // LONG engine trade object
CTrade        g_trade_short;  // SHORT engine trade object
CPositionInfo g_position;

//--- Lot scaling globals
double g_initialBalance    = 0.0;
double g_currentScaledLot  = 0.0;

//+------------------------------------------------------------------+
//| Syncs CPositionInfo and validates EA magic.                      |
//| Returns true only when a LONG-engine position exists on _Symbol. |
//+------------------------------------------------------------------+
bool SelectEAPosition()
{
   if(!g_position.Select(_Symbol))
      return false;
   if(g_position.Magic() != (ulong)InpLongMagicNumber)
      return false;
   return true;
}

int OnInit()
{
   if(!IndicatorsInit())
   {
      Print("Indicator initialization failed");
      return INIT_FAILED;
   }

   // Initialize globals of lot scaling
   g_initialBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
   g_currentScaledLot = InpInitialLot;

   // Configure g_trade (LONG engine)
   g_trade.SetExpertMagicNumber(InpLongMagicNumber);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Configure g_trade_short (SHORT engine)
   g_trade_short.SetExpertMagicNumber(InpShortMagicNumber);
   g_trade_short.SetDeviationInPoints(10);
   g_trade_short.SetTypeFilling(ORDER_FILLING_IOC);

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
