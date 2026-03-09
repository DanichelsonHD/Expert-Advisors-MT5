//+------------------------------------------------------------------+
//|                                   Strict_EA_M15_DayTrader.mq5    |
//|                                  Copyright 2024, Trading Robot   |
//|                                             STRICT EXECUTION MODE|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.05"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Arrays\ArrayLong.mqh>

//--- INPUT PARAMETERS
input int      InpMagic             = 123456;      // Magic Number
input int      InpEMA_Fast          = 21;          // EMA Fast Period
input int      InpEMA_Slow          = 50;          // EMA Slow Period
input int      InpATR_Period        = 14;          // ATR Period
input int      InpADX_Period        = 14;          // ADX Period
input double   InpADX_Level         = 20.0;        // ADX Minimum Level (Strict Filter)
input double   InpRiskPerTrade      = 0.5;         // Risk % per Trade
input double   InpDailyTargetPct    = 1.0;         // Daily Profit Target %
input double   InpDailyLossPct      = 1.0;         // Daily Loss Limit %
input double   InpMaxDailyLossPct   = 2.0;         // Hard Daily Loss Circuit Breaker %
input int      InpStartHour         = 6;           // Start Hour (Server Time)
input int      InpEndHour           = 22;          // End Hour (Server Time)
input double   InpTP_Mult           = 2.0;         // Take Profit ATR Multiplier
input double   InpSL_Mult           = 1.0;         // Stop Loss ATR Multiplier
input double   InpBE_Mult           = 1.5;         // Break Even ATR Multiplier (Delayed)
input double   InpMinATR_EURUSD     = 0.0004;      // Min ATR for EURUSD
input double   InpMinATR_GBPUSD     = 0.0006;      // Min ATR for GBPUSD
input double   InpMinDistanceATR    = 0.35;        // Min Distance from EMA50 (Compression Filter)
input int      InpMaxTradesPerDay   = 3;           // Max Trades Per Day

//--- GLOBAL VARIABLES
int      hEMA21, hEMA50, hATR, hADX;
CTrade   trade;
CSymbolInfo   symInfo;
datetime lastProcessedCandle = 0;
int      dailyTradeCount = 0;
double   dailyCurrentPnL = 0;
datetime lastDailyUpdate = 0;
double   dailyStartBalance = 0;

//--- INITIALIZATION
int OnInit()
{
   if(_Period != PERIOD_M15) { Print("Error: M15 only."); return(INIT_FAILED); }
   if(_Symbol != "EURUSD" && _Symbol != "GBPUSD") { Print("Error: EURUSD/GBPUSD only."); return(INIT_FAILED); }

   hEMA21 = iMA(_Symbol, PERIOD_M15, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50 = iMA(_Symbol, PERIOD_M15, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   hATR   = iATR(_Symbol, PERIOD_M15, InpATR_Period);
   hADX   = iADX(_Symbol, PERIOD_M15, InpADX_Period);

   if(hEMA21 == INVALID_HANDLE || hEMA50 == INVALID_HANDLE || hATR == INVALID_HANDLE || hADX == INVALID_HANDLE)
      return(INIT_FAILED);

   symInfo.Name(_Symbol);
   trade.SetExpertMagicNumber(InpMagic);
   dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
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

   if(PositionSelectByMagic(_Symbol, InpMagic)) ManageBreakEven();

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M15, 0, 2, rates) < 2) return;

   if(rates[1].time == lastProcessedCandle) return;

   UpdateDailyStats();
   
   // Hard Block: Daily Limits & Circuit Breaker
   if(IsDailyLimitReached()) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   bool allowed = (InpStartHour < InpEndHour) ? (dt.hour >= InpStartHour && dt.hour < InpEndHour) : (dt.hour >= InpStartHour || dt.hour < InpEndHour);
   if(!allowed) return;

   if(PositionSelectByMagic(_Symbol, InpMagic)) return;

   double ema21[1], ema50[1], atr[1], adx[1], pDI[1], mDI[1];
   ArraySetAsSeries(ema21, true); ArraySetAsSeries(ema50, true); ArraySetAsSeries(atr, true);
   ArraySetAsSeries(adx, true); ArraySetAsSeries(pDI, true); ArraySetAsSeries(mDI, true);

   if(CopyBuffer(hEMA21, 0, 1, 1, ema21) < 1) return;
   if(CopyBuffer(hEMA50, 0, 1, 1, ema50) < 1) return;
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1) return;
   if(CopyBuffer(hADX, 0, 1, 1, adx) < 1) return;
   if(CopyBuffer(hADX, 1, 1, 1, pDI) < 1) return;
   if(CopyBuffer(hADX, 2, 1, 1, mDI) < 1) return;

   double curATR = atr[0];
   double minATR = (_Symbol == "EURUSD") ? InpMinATR_EURUSD : InpMinATR_GBPUSD;
   if(curATR <= minATR) return;

   double close1 = rates[1].close;
   double open1  = rates[1].open;
   double ema21_1 = ema21[0];
   double ema50_1 = ema50[0];
   double dist = MathAbs(close1 - ema50_1);
   double bodySize = MathAbs(close1 - open1);

   // BUY Condition with Momentum and Compression Filters
   if(ema21_1 > ema50_1 && close1 > ema21_1 && adx[0] > InpADX_Level && pDI[0] > mDI[0] && 
      dist > (InpMinDistanceATR * curATR) && close1 > open1 && bodySize >= (0.4 * curATR))
   {
      double price = symInfo.Ask();
      double sl = price - (InpSL_Mult * curATR);
      double tp = price + (InpTP_Mult * curATR);
      if(ExecuteTrade(ORDER_TYPE_BUY, price, sl, tp))
         lastProcessedCandle = rates[1].time;
   }
   // SELL Condition with Momentum and Compression Filters
   else if(ema21_1 < ema50_1 && close1 < ema21_1 && adx[0] > InpADX_Level && mDI[0] > pDI[0] && 
           dist > (InpMinDistanceATR * curATR) && close1 < open1 && bodySize >= (0.4 * curATR))
   {
      double price = symInfo.Bid();
      double sl = price + (InpSL_Mult * curATR);
      double tp = price - (InpTP_Mult * curATR);
      if(ExecuteTrade(ORDER_TYPE_SELL, price, sl, tp))
         lastProcessedCandle = rates[1].time;
   }
}

//--- SUPPORT FUNCTIONS
bool ExecuteTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp)
{
   double lot = CalculateLot(price, sl);
   if(lot <= 0) return false;
   bool result = (type == ORDER_TYPE_BUY) ? trade.Buy(lot, _Symbol, price, sl, tp) : trade.Sell(lot, _Symbol, price, sl, tp);
   return result;
}

double CalculateLot(double price, double sl)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPerTrade / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double vStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vStep <= 0 || tickValue <= 0) return 0;
   double pointsAtRisk = MathAbs(price - sl) / tickSize;
   if(pointsAtRisk < 1.0) return 0;
   double lot = riskMoney / (pointsAtRisk * tickValue);
   lot = MathFloor(lot / vStep) * vStep;
   int digits = (int)MathCeil(MathLog10(1.0 / vStep));
   lot = NormalizeDouble(lot, digits);
   return NormalizeDouble(MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), lot)), digits);
}

void UpdateDailyStats()
{
   MqlDateTime dt_now, dt_start;
   datetime now = TimeCurrent();
   TimeToStruct(now, dt_now);
   dt_start = dt_now; dt_start.hour = 0; dt_start.min = 0; dt_start.sec = 0;
   datetime startOfDay = StructToTime(dt_start);

   if(lastDailyUpdate != startOfDay || dailyStartBalance <= 0)
   {
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDailyUpdate = startOfDay;
   }

   dailyTradeCount = 0; dailyCurrentPnL = 0;
   if(HistorySelect(startOfDay, now))
   {
      int totalDeals = HistoryDealsTotal();
      CArrayLong posIds;
      for(int i = 0; i < totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic || HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
         long posId = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         {
            bool existing = false;
            for(int j=0; j<posIds.Total(); j++) if(posIds.At(j) == posId) { existing = true; break; }
            if(!existing) { posIds.Add(posId); dailyTradeCount++; }
         }
         dailyCurrentPnL += HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }
}

bool IsDailyLimitReached()
{
   if(dailyStartBalance <= 0) return false;
   double floatingPnL = 0;
   if(PositionSelectByMagic(_Symbol, InpMagic)) floatingPnL = PositionGetDouble(POSITION_PROFIT);
   
   // Hard Circuit Breaker (Closed Loss + Floating Loss)
   if((dailyCurrentPnL + floatingPnL) <= -(dailyStartBalance * (InpMaxDailyLossPct / 100.0))) return true;
   
   // Soft Limits
   if(dailyCurrentPnL >= (dailyStartBalance * (InpDailyTargetPct / 100.0))) return true;
   if(dailyCurrentPnL <= -(dailyStartBalance * (InpDailyLossPct / 100.0))) return true;
   return (dailyTradeCount >= InpMaxTradesPerDay);
}

void ManageBreakEven()
{
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   double riskDist = MathAbs(entry - sl);
   if(riskDist <= 0) return;
   
   double targetDist = riskDist * InpBE_Mult;
   double spreadPoints = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      if(symInfo.Bid() >= (entry + targetDist) && sl < entry) trade.PositionModify(_Symbol, entry + spreadPoints, tp);
   }
   else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
   {
      if(symInfo.Ask() <= (entry - targetDist) && sl > entry) trade.PositionModify(_Symbol, entry - spreadPoints, tp);
   }
}

bool PositionSelectByMagic(string symbol, int magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == magic) return true;
   }
   return false;
}