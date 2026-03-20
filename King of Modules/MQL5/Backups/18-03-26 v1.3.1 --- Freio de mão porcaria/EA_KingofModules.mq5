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


//+------------------------------------------------------------------+
//| Syncs CPositionInfo and validates EA magic.                      |
//| Returns true only when an EA-owned position exists on _Symbol.   |
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
   g_currentScaledLot = InpLotSize;

   // Initialize drawdown globals
   g_dailyStartBalance = g_initialBalance;
   g_lastDay           = TimeCurrent();

   // Configure g_trade (magic, slippage, filling)
   g_trade.SetExpertMagicNumber(InpLongMagicNumber);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

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
   // Gestão de posições roda SEMPRE (sem filtro de horário)
   double atr, avg;
   if(GetATR(atr, avg))
      ManageTrailingStop(atr);
   ManageTakes();

   // Entradas respeitam filtro de horário
   if(InpUseTimeFilter && !IsWithinTradingHours()) return;


   EntriesEngine();
}

//+------------------------------------------------------------------+
