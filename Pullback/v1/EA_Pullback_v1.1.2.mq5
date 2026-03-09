//+------------------------------------------------------------------+
//|                                         Strict_EA_M15_Patch.mq5 |
//|                                  Copyright 2024, Trading Robot   |
//|                                             STRICT EXECUTION MODE|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.01"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>

//--- INPUT PARAMETERS
input int      InpMagic             = 123456;      // Magic Number
input int      InpEMA_Fast          = 21;          // EMA Fast Period
input int      InpEMA_Slow          = 50;          // EMA Slow Period
input int      InpATR_Period        = 14;          // ATR Period
input int      InpADX_Period        = 14;          // ADX Period
input double   InpADX_Level         = 20.0;        // ADX Minimum Level
input double   InpRiskPerTrade      = 0.5;         // Risk % per Trade
input double   InpDailyTargetPct    = 1.0;         // Daily Profit Target %
input double   InpDailyLossPct      = 1.0;         // Daily Loss Limit %
input int      InpStartHour         = 6;           // Start Hour (Server Time)
input int      InpEndHour           = 22;          // End Hour (Server Time)
input double   InpTP_Mult           = 2.0;         // Take Profit ATR Multiplier
input double   InpSL_Mult           = 1.0;         // Stop Loss ATR Multiplier
input double   InpBE_Mult           = 1.0;         // Break Even ATR Multiplier (1R = 1.0)

//--- GLOBAL VARIABLES
int      hEMA21, hEMA50, hATR, hADX;
CTrade   trade;
CPositionInfo posInfo;
CSymbolInfo   symInfo;
datetime lastBarTime = 0;
datetime lastTradeTime = 0;

//--- INITIALIZATION
int OnInit()
{
   if(_Period != PERIOD_M15)
   {
      Print("Error: This EA must run on M15 timeframe only.");
      return(INIT_FAILED);
   }

   string sym = _Symbol;
   if(sym != "EURUSD" && sym != "GBPUSD")
   {
      Print("Error: This EA only supports EURUSD or GBPUSD.");
      return(INIT_FAILED);
   }

   hEMA21 = iMA(sym, PERIOD_M15, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50 = iMA(sym, PERIOD_M15, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   hATR   = iATR(sym, PERIOD_M15, InpATR_Period);
   hADX   = iADX(sym, PERIOD_M15, InpADX_Period);

   if(hEMA21 == INVALID_HANDLE || hEMA50 == INVALID_HANDLE || hATR == INVALID_HANDLE || hADX == INVALID_HANDLE)
      return(INIT_FAILED);

   symInfo.Name(sym);
   trade.SetExpertMagicNumber(InpMagic);
   
   return(INIT_SUCCEEDED);
}

//--- DEINITIALIZATION
void OnDeinit(const int reason)
{
   IndicatorRelease(hEMA21);
   IndicatorRelease(hEMA50);
   IndicatorRelease(hATR);
   IndicatorRelease(hADX);
}

//--- MAIN LOGIC
void OnTick()
{
   if(!symInfo.RefreshRates()) return;
   
   // Handle Break-Even for existing position using live Bid/Ask (No Index 0 close reliance)
   if(PositionSelectByMagic(_Symbol, InpMagic))
   {
      ManageBreakEven();
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M15, 0, 3, rates) < 3) return;

   // Closed Candle Rule: Only evaluate logic when a new bar appears
   if(rates[0].time == lastBarTime) return;
   
   // Logic check: only proceed if we haven't already attempted a trade on this specific closed bar
   // Index 1 is the most recently closed candle
   datetime closedCandleTime = rates[1].time;

   // Time Filter
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return;

   // Daily Limit Check (Profit/Loss/Trade Count)
   if(IsDailyLimitReached()) return;

   // Ensure one trade per symbol
   if(PositionSelectByMagic(_Symbol, InpMagic)) return;

   // Indicators Data (Index 1 = Last Closed)
   double ema21[2], ema50[2], atr[1], adx[1], pDI[1], mDI[1];
   if(CopyBuffer(hEMA21, 0, 1, 2, ema21) < 2) return;
   if(CopyBuffer(hEMA50, 0, 1, 2, ema50) < 2) return;
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1) return;
   if(CopyBuffer(hADX, 0, 1, 1, adx) < 1) return;
   if(CopyBuffer(hADX, 1, 1, 1, pDI) < 1) return;
   if(CopyBuffer(hADX, 2, 1, 1, mDI) < 1) return;

   double curATR = atr[0];
   double close1 = rates[1].close;
   double close2 = rates[2].close;
   double minATR = (_Symbol == "EURUSD") ? 0.0008 : 0.0012;

   if(curATR <= minATR) return;

   double dist = MathAbs(close1 - ema50[0]);

   // BUY LOGIC
   if(ema21[0] > ema50[0] && close1 > ema50[0] && adx[0] > InpADX_Level && pDI[0] > mDI[0])
   {
      if(close2 < ema21[1] && close1 > ema21[0] && dist > (0.5 * curATR))
      {
         double price = symInfo.Ask();
         double sl = price - (InpSL_Mult * curATR);
         double tp = price + (InpTP_Mult * curATR);
         double lot = CalculateLot(price, sl);
         if(trade.Buy(lot, _Symbol, price, sl, tp))
         {
            lastBarTime = rates[0].time;
         }
      }
   }
   // SELL LOGIC
   else if(ema21[0] < ema50[0] && close1 < ema50[0] && adx[0] > InpADX_Level && mDI[0] > pDI[0])
   {
      if(close2 > ema21[1] && close1 < ema21[0] && dist > (0.5 * curATR))
      {
         double price = symInfo.Bid();
         double sl = price + (InpSL_Mult * curATR);
         double tp = price - (InpTP_Mult * curATR);
         double lot = CalculateLot(price, sl);
         if(trade.Sell(lot, _Symbol, price, sl, tp))
         {
            lastBarTime = rates[0].time;
         }
      }
   }
}

//--- HELPERS
double CalculateLot(double price, double sl)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPerTrade / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   double stopLossPoints = MathAbs(price - sl) / tickSize;
   if(stopLossPoints <= 0 || tickValue <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   double lot = riskAmount / (stopLossPoints * tickValue);
   
   // Normalize to volume step
   lot = MathFloor(lot / volumeStep) * volumeStep;
   
   return NormalizeDouble(MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), 
                          MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), lot)), 2);
}

bool IsDailyLimitReached()
{
   double dailyProfit = 0;
   int tradesToday = 0;
   
   datetime startOfDay = (TimeCurrent() / 86400) * 86400; // Server midnight
   
   if(!HistorySelect(startOfDay, TimeCurrent())) return false;
   
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      
      dailyProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                     HistoryDealGetDouble(ticket, DEAL_SWAP) + 
                     HistoryDealGetDouble(ticket, DEAL_COMMISSION);
                     
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         tradesToday++;
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(dailyProfit >= (balance * (InpDailyTargetPct / 100.0))) return true;
   if(dailyProfit <= -(balance * (InpDailyLossPct / 100.0))) return true;
   if(tradesToday >= 2) return true;
   
   return false;
}

void ManageBreakEven()
{
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   double currentBid = symInfo.Bid();
   double currentAsk = symInfo.Ask();
   
   // Calculate 1R distance based on actual SL/Entry gap
   double riskDist = MathAbs(entry - sl);
   if(riskDist <= 0) return;
   
   double targetDist = riskDist * InpBE_Mult;
   double spread = symInfo.Spread() * _Point;

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      if(currentBid >= (entry + targetDist) && sl < entry)
         trade.PositionModify(_Symbol, entry + spread, tp);
   }
   else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
   {
      if(currentAsk <= (entry - targetDist) && sl > entry)
         trade.PositionModify(_Symbol, entry - spread, tp);
   }
}

bool PositionSelectByMagic(string symbol, int magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == magic)
            return true;
      }
   }
   return false;
}