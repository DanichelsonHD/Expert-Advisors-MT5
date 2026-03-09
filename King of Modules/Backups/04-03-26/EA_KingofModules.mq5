//+------------------------------------------------------------------+
//|                                           EA_KingofModules.mq5   |
//+------------------------------------------------------------------+
#property copyright   "Daniel Pereira"
#property link        ""
#property description "EA based on multiple modules of code, so it can operate with multiple strategies"
#property version     "1.00"
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

//--- Lot scaling globals
double g_initialBalance    = 0.0;
double g_currentScaledLot  = 0.0;

//+------------------------------------------------------------------+
//| Syncs CPositionInfo and validates EA magic.                      |
//| Returns true only when an EA-owned position exists on _Symbol.   |
//+------------------------------------------------------------------+
bool SelectEAPosition()
{
   if(!g_position.Select(_Symbol))
      return false;
   if(g_position.Magic() != (ulong)InpMagicNumber)
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
    
    // Inicializar globals de lot scaling
    g_initialBalance   = AccountInfoDouble(ACCOUNT_BALANCE);
    g_currentScaledLot = InpInitialLot;

    // Configurar entry_trade (magic, slippage, filling)
    entry_trade.SetExpertMagicNumber(InpMagicNumber);
    entry_trade.SetDeviationInPoints(10);
    entry_trade.SetTypeFilling(ORDER_FILLING_IOC);

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
   static datetime s_lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == s_lastBarTime)
      return;
   s_lastBarTime = currentBarTime;

   // Gestão de posições roda SEMPRE (sem filtro de horário)
   ManageTrailingStop();
   ManageTakes();

   // Entradas respeitam filtro de horário
   if(InpUseTimeFilter && !IsWithinTradingHours())
   {
      Print("INFO: Fora do horário de trading.");
      return;
   }

   EntriesEngine();
}

//+------------------------------------------------------------------+