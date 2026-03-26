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
//| Loss streak cooldown state                                       |
//+------------------------------------------------------------------+
int      g_consecutive_losses = 0;
datetime g_cooldown_end_time  = 0;

//+------------------------------------------------------------------+
//| Returns true if trading is currently blocked by cooldown        |
//+------------------------------------------------------------------+
bool IsCooldownActive()
{
   if (!InpUseLossCooldown) return false;
   if (TimeCurrent() < g_cooldown_end_time) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Called on every trade close — updates loss streak state         |
//+------------------------------------------------------------------+
void OnTradeClosed(double profit)
{
   if (profit < 0)
      g_consecutive_losses++;
   else
      g_consecutive_losses = 0;

   if (InpUseLossCooldown && g_consecutive_losses >= InpMaxConsecutiveLosses)
   {
      g_cooldown_end_time   = TimeCurrent() + (int)(InpCooldownHours * 3600);
      g_consecutive_losses  = 0;
      Print("Loss cooldown triggered. Resumes: ", TimeToString(g_cooldown_end_time));
   }
}

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

   if (IsCooldownActive())
   {
      Print("Cooldown active until: ", TimeToString(g_cooldown_end_time));
      return;
   }

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
//| OnTradeTransaction — detects closed deals for loss tracking     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if (trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if (!HistoryDealSelect(dealTicket)) return;

   long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if (dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT) return;

   long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if (dealMagic < MAGIC_BASE || dealMagic >= MAGIC_BASE + 4) return;

   double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                 + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                 + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

   OnTradeClosed(profit);
}

//+------------------------------------------------------------------+
