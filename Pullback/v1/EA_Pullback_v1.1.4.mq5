//+------------------------------------------------------------------+
//|                                   Strict_EA_M15_Final_Patch.mq5 |
//|                                  Copyright 2024, Trading Robot   |
//|                                             STRICT EXECUTION MODE|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.03"
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
input double   InpADX_Level         = 15.0;        // ADX Minimum Level
input double   InpRiskPerTrade      = 0.5;         // Risk % per Trade
input double   InpDailyTargetPct    = 1.0;         // Daily Profit Target %
input double   InpDailyLossPct      = 1.0;         // Daily Loss Limit %
input int      InpStartHour         = 6;           // Start Hour (Server Time)
input int      InpEndHour           = 22;          // End Hour (Server Time)
input double   InpTP_Mult           = 2.0;         // Take Profit ATR Multiplier
input double   InpSL_Mult           = 1.0;         // Stop Loss ATR Multiplier
input double   InpBE_Mult           = 1.0;         // Break Even ATR Multiplier
input double   InpMinATR_EURUSD     = 0.0004;      // Min ATR for EURUSD
input double   InpMinATR_GBPUSD     = 0.0006;      // Min ATR for GBPUSD
input int      InpMaxTradesPerDay   = 2;           // Max Trades Per Day

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
   
   // Initialize daily balance immediately
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

   // Manage Break-Even on every tick for open position
   if(PositionSelectByMagic(_Symbol, InpMagic)) ManageBreakEven();

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M15, 0, 3, rates) < 3) return;

   // 1. Logic lock: prevent reprocessing same closed candle
   if(rates[1].time == lastProcessedCandle) return;

   // 2. Daily boundary and limits update
   UpdateDailyStats();
   if(IsDailyLimitReached()) return;

   // 3. Time Filter
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   bool allowed;
   if(InpStartHour < InpEndHour)
      allowed = (dt.hour >= InpStartHour && dt.hour < InpEndHour);
   else
      allowed = (dt.hour >= InpStartHour || dt.hour < InpEndHour);
   if(!allowed) return;

   // 4. Position Check (strict magic-based filtering)
   if(PositionSelectByMagic(_Symbol, InpMagic)) return;

   // 5. Indicators Data
   double ema21[2], ema50[1], atr[1], adx[1], pDI[1], mDI[1];
   if(CopyBuffer(hEMA21, 0, 1, 2, ema21) < 2) return;
   if(CopyBuffer(hEMA50, 0, 1, 1, ema50) < 1) return;
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1) return;
   if(CopyBuffer(hADX, 0, 1, 1, adx) < 1) return;
   if(CopyBuffer(hADX, 1, 1, 1, pDI) < 1) return;
   if(CopyBuffer(hADX, 2, 1, 1, mDI) < 1) return;

   double curATR = atr[0];
   double minATR = (_Symbol == "EURUSD") ? InpMinATR_EURUSD : InpMinATR_GBPUSD;
   if(curATR <= minATR) return;

   double close1 = rates[1].close;
   double close2 = rates[2].close;
   double ema21_1 = ema21[1]; // Buffer index 1 is rates[1]
   double ema21_2 = ema21[0]; // Buffer index 0 is rates[2]
   double ema50_1 = ema50[0];
   double dist = MathAbs(close1 - ema50_1);

   // BUY LOGIC
   if(ema21_1 > ema50_1 && close1 > ema50_1 && adx[0] > InpADX_Level && pDI[0] > mDI[0])
   {
      if(close2 < ema21_2 && close1 > ema21_1 && dist > (0.5 * curATR))
      {
         double price = symInfo.Ask();
         double sl = price - (InpSL_Mult * curATR);
         double tp = price + (InpTP_Mult * curATR);
         if(ExecuteTrade(ORDER_TYPE_BUY, price, sl, tp))
            lastProcessedCandle = rates[1].time; // Lock only after successful execution
      }
   }
   // SELL LOGIC
   else if(ema21_1 < ema50_1 && close1 < ema50_1 && adx[0] > InpADX_Level && mDI[0] > pDI[0])
   {
      if(close2 > ema21_2 && close1 < ema21_1 && dist > (0.5 * curATR))
      {
         double price = symInfo.Bid();
         double sl = price + (InpSL_Mult * curATR);
         double tp = price - (InpTP_Mult * curATR);
         if(ExecuteTrade(ORDER_TYPE_SELL, price, sl, tp))
            lastProcessedCandle = rates[1].time; // Lock only after successful execution
      }
   }
}

//--- EXECUTION WRAPPER
bool ExecuteTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp)
{
   double lot = CalculateLot(price, sl);
   if(lot <= 0) return false;
   
   bool result;
   if(type == ORDER_TYPE_BUY)
      result = trade.Buy(lot, _Symbol, price, sl, tp);
   else
      result = trade.Sell(lot, _Symbol, price, sl, tp);
   
   if(!result)
   {
      Print("Trade failed. Retcode: ", trade.ResultRetcode(), " (", trade.ResultRetcodeDescription(), ")");
   }
   return result;
}

//--- LOT CALCULATION (REINTRODUCED NORMALIZATION)
double CalculateLot(double price, double sl)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPerTrade / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double vStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(vStep <= 0 || vMin <= 0 || tickValue <= 0) return 0;

   double pointsAtRisk = MathAbs(price - sl) / tickSize;
   if(pointsAtRisk < 1.0) return 0;

   double lot = riskMoney / (pointsAtRisk * tickValue);
   
   // Normalize to Volume Step and Precision
   lot = MathFloor(lot / vStep) * vStep;
   int digits = (int)MathCeil(MathLog10(1.0 / vStep));
   lot = NormalizeDouble(lot, digits);

   if(lot < vMin || lot > vMax) return (lot < vMin) ? 0 : vMax;
   return lot;
}

//--- DAILY STATS
void UpdateDailyStats()
{
   MqlDateTime dt_now, dt_start;
   datetime now = TimeCurrent();
   TimeToStruct(now, dt_now);
   
   dt_start = dt_now;
   dt_start.hour = 0; dt_start.min = 0; dt_start.sec = 0;
   datetime startOfDay = StructToTime(dt_start);

   // Update dailyStartBalance on day rollover or if first initialization
   if(lastDailyUpdate != startOfDay || dailyStartBalance <= 0)
   {
      dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastDailyUpdate = startOfDay;
   }

   dailyTradeCount = 0;
   dailyCurrentPnL = 0;
   
   if(HistorySelect(startOfDay, now))
   {
      int totalDeals = HistoryDealsTotal();
      CArrayLong posIds;

      for(int i = 0; i < totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;

         long posId = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
         {
            bool existing = false;
            for(int j=0; j<posIds.Total(); j++) if(posIds.At(j) == posId) { existing = true; break; }
            if(!existing) { posIds.Add(posId); dailyTradeCount++; }
         }
         
         dailyCurrentPnL += HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                            HistoryDealGetDouble(ticket, DEAL_SWAP) + 
                            HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }
}

bool IsDailyLimitReached()
{
   if(dailyStartBalance <= 0) return false;
   if(dailyCurrentPnL >= (dailyStartBalance * (InpDailyTargetPct / 100.0))) return true;
   if(dailyCurrentPnL <= -(dailyStartBalance * (InpDailyLossPct / 100.0))) return true;
   return (dailyTradeCount >= InpMaxTradesPerDay);
}

//--- BREAK-EVEN (REVERTED SPREAD CALCULATION)
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
      if(symInfo.Bid() >= (entry + targetDist) && sl < entry)
      {
         trade.PositionModify(_Symbol, entry + spreadPoints, tp);
      }
   }
   else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
   {
      if(symInfo.Ask() <= (entry - targetDist) && sl > entry)
      {
         trade.PositionModify(_Symbol, entry - spreadPoints, tp);
      }
   }
}

bool PositionSelectByMagic(string symbol, int magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == magic)
            return true;
   }
   return false;
}