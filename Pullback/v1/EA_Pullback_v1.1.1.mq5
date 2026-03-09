//+------------------------------------------------------------------+
//|                                              Strict_EA_M15.mq5   |
//|                                  Copyright 2024, Trading Robot   |
//|                                             STRICT EXECUTION MODE|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- INPUT PARAMETERS
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
input double   InpBE_Mult           = 1.0;         // Break Even ATR Multiplier

//--- GLOBAL VARIABLES
int      hEMA21, hEMA50, hATR, hADX;
CTrade   trade;
CPositionInfo posInfo;
CSymbolInfo   symInfo;
datetime lastBarTime = 0;

//--- INITIALIZATION
int OnInit()
{
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
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M15, 0, 3, rates) < 3) return;

   // New Bar Check (Closed Candles Only)
   if(rates[0].time == lastBarTime) 
   {
      ManageBreakEven(rates[0].close);
      return;
   }
   lastBarTime = rates[0].time;

   // Time Filter
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return;

   // Daily Limit Check
   if(IsDailyLimitReached()) return;

   // Position Check (One per symbol)
   if(PositionSelect(_Symbol)) 
   {
      ManageBreakEven(rates[1].close);
      return;
   }

   // Indicators Data
   double ema21[], ema50[], atr[], adx[], pDI[], mDI[];
   ArraySetAsSeries(ema21, true); ArraySetAsSeries(ema50, true);
   ArraySetAsSeries(atr, true);   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(pDI, true);   ArraySetAsSeries(mDI, true);

   if(CopyBuffer(hEMA21, 0, 1, 2, ema21) < 2) return;
   if(CopyBuffer(hEMA50, 0, 1, 2, ema50) < 2) return;
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1) return;
   if(CopyBuffer(hADX, 0, 1, 1, adx) < 1) return;
   if(CopyBuffer(hADX, 1, 1, 1, pDI) < 1) return;
   if(CopyBuffer(hADX, 2, 1, 1, mDI) < 1) return;

   double curATR = atr[0];
   double close1 = rates[1].close;
   double close2 = rates[2].close;

   // ATR Threshold Check
   double minATR = (_Symbol == "EURUSD") ? 0.0008 : 0.0012;
   if(curATR <= minATR) return;

   double dist = MathAbs(close1 - ema50[0]);
   double lot = CalculateLot(curATR);

   // BUY LOGIC
   if(ema21[0] > ema50[0] && close1 > ema50[0] && adx[0] > InpADX_Level && pDI[0] > mDI[0])
   {
      if(close2 < ema21[1] && close1 > ema21[0] && dist > (0.5 * curATR))
      {
         double sl = close1 - (InpSL_Mult * curATR);
         double tp = close1 + (InpTP_Mult * curATR);
         trade.Buy(lot, _Symbol, symInfo.Ask(), sl, tp);
      }
   }
   // SELL LOGIC
   else if(ema21[0] < ema50[0] && close1 < ema50[0] && adx[0] > InpADX_Level && mDI[0] > pDI[0])
   {
      if(close2 > ema21[1] && close1 < ema21[0] && dist > (0.5 * curATR))
      {
         double sl = close1 + (InpSL_Mult * curATR);
         double tp = close1 - (InpTP_Mult * curATR);
         trade.Sell(lot, _Symbol, symInfo.Bid(), sl, tp);
      }
   }
}

//--- HELPERS
double CalculateLot(double atr)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (InpRiskPerTrade / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue == 0 || tickSize == 0) return 0.01;
   
   double pointsAtRisk = atr / tickSize;
   double lot = riskAmount / (pointsAtRisk * tickValue);
   
   return NormalizeDouble(MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), 
                          MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), lot)), 2);
}

bool IsDailyLimitReached()
{
   double dailyProfit = 0;
   HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent());
   int total = HistoryDealsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
         dailyProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(dailyProfit >= (balance * (InpDailyTargetPct / 100.0))) return true;
   if(dailyProfit <= -(balance * (InpDailyLossPct / 100.0))) return true;
   
   // Trade count check
   int tradesToday = 0;
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol && HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         tradesToday++;
   }
   return (tradesToday >= 2);
}

void ManageBreakEven(double currentClose)
{
   if(!PositionSelect(_Symbol)) return;
   
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   double atrVal[];
   CopyBuffer(hATR, 0, 0, 1, atrVal);
   
   double targetDist = MathAbs(tp - entry) / 2.0; // 1R (since TP is 2R)
   double spread = symInfo.Spread() * _Point;

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      if(currentClose >= (entry + targetDist) && sl < entry)
         trade.PositionModify(_Symbol, entry + spread, tp);
   }
   else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
   {
      if(currentClose <= (entry - targetDist) && sl > entry)
         trade.PositionModify(_Symbol, entry - spread, tp);
   }
}