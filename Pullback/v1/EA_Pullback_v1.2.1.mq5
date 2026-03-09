//EA_Pullback_v1.2.1.mq5

#property copyright "Daniel Pereira"
#property link      ""
#property version   "1.21"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

//--- INPUTS
input double InpRiskPerTrade = 0.5;      // Risk per trade (%)
input double InpDailyLossLimit = 1.0;    // Daily loss limit (%)
input double InpWeeklyLossLimit = 3.0;   // Weekly loss limit (%)
input int    InpStartHour = 7;           // Trading Start Hour (GMT)
input int    InpEndHour = 17;            // Trading End Hour (GMT)

//--- GLOBALS
int hEMA21, hEMA50, hATR, hADX;
CTrade Trade;
CSymbolInfo SymbolRef;
CPositionInfo PositionRef;

//--- DATA STRUCTURES
struct IndicatorData {
   double ema21[3];
   double ema50[10];
   double adx[2];
   double plusDI[2];
   double minusDI[2];
   double atr[21];
};

//--- INITIALIZATION
int OnInit() {
   if(_Symbol != "EURUSD" && _Symbol != "GBPUSD") {
      Print("EA restricted to EURUSD and GBPUSD only.");
      return INIT_FAILED;
   }
   if(_Period != PERIOD_M15) {
      Print("EA restricted to M15 timeframe only.");
      return INIT_FAILED;
   }

   hEMA21 = iMA(_Symbol, _Period, 21, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50 = iMA(_Symbol, _Period, 50, 0, MODE_EMA, PRICE_CLOSE);
   hATR   = iATR(_Symbol, _Period, 14);
   hADX   = iADX(_Symbol, _Period, 14);

   if(hEMA21 == INVALID_HANDLE || hEMA50 == INVALID_HANDLE || hATR == INVALID_HANDLE || hADX == INVALID_HANDLE)
      return INIT_FAILED;

   Trade.SetExpertMagicNumber(123456);
   SymbolRef.Name(_Symbol);
   
   return INIT_SUCCEEDED;
}

//--- DEINITIALIZATION
void OnDeinit(const int reason) {
   IndicatorRelease(hEMA21);
   IndicatorRelease(hEMA50);
   IndicatorRelease(hATR);
   IndicatorRelease(hADX);
}

//--- MAIN EXECUTION
void OnTick() {
   if(!IsNewCandle()) return;
   
   if(!CheckTimeWindow() || !CheckRiskLimits() || PositionSelect(_Symbol)) {
      ManageExistingPositions();
      return;
   }

   IndicatorData data;
   if(!FillData(data)) return;

   double avgATR = 0;
   for(int i=1; i<=20; i++) avgATR += data.atr[i];
   avgATR /= 20.0;

   MqlRates rates[3];
   CopyRates(_Symbol, _Period, 0, 3, rates);

   // LOGIC - TREND FILTERS
   bool trendUp = (data.ema21[1] > data.ema50[1]) && (data.ema50[1] > data.ema50[6]);
   bool trendDn = (data.ema21[1] < data.ema50[1]) && (data.ema50[1] < data.ema50[6]);
   bool adxFilter = (data.adx[1] > 20.0);
   bool atrFilter = (data.atr[1] > avgATR);

   if(!adxFilter || !atrFilter) return;

   // BUY SETUP
   if(trendUp && data.plusDI[1] > data.minusDI[1]) {
      if(rates[0].close <= data.ema21[2] && rates[1].close > rates[1].open && rates[1].close > data.ema21[1]) {
         double dist = MathAbs(rates[1].close - data.ema50[1]);
         if(dist >= 0.5 * data.atr[1]) {
            ExecuteOrder(ORDER_TYPE_BUY_STOP, rates[1].high + 20 * _Point, data.atr[1]);
         }
      }
   }

   // SELL SETUP
   if(trendDn && data.minusDI[1] > data.plusDI[1]) {
      if(rates[0].close >= data.ema21[2] && rates[1].close < rates[1].open && rates[1].close < data.ema21[1]) {
         double dist = MathAbs(rates[1].close - data.ema50[1]);
         if(dist >= 0.5 * data.atr[1]) {
            ExecuteOrder(ORDER_TYPE_SELL_STOP, rates[1].low - 20 * _Point, data.atr[1]);
         }
      }
   }
   
   ManageExistingPositions();
}

//--- HELPERS
bool FillData(IndicatorData &d) {
   if(CopyBuffer(hEMA21, 0, 0, 3, d.ema21) < 3) return false;
   if(CopyBuffer(hEMA50, 0, 0, 10, d.ema50) < 10) return false;
   if(CopyBuffer(hADX, 0, 0, 2, d.adx) < 2) return false;
   if(CopyBuffer(hADX, 1, 0, 2, d.plusDI) < 2) return false;
   if(CopyBuffer(hADX, 2, 0, 2, d.minusDI) < 2) return false;
   if(CopyBuffer(hATR, 0, 0, 21, d.atr) < 21) return false;
   return true;
}

bool CheckTimeWindow() {
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   return (dt.hour >= InpStartHour && dt.hour < InpEndHour);
}

bool CheckRiskLimits() {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dayProfit = AccountInfoDouble(ACCOUNT_PROFIT); // Simplified
   double weekProfit = 0; // Requires HistorySelect

   if(dayProfit <= -(balance * (InpDailyLossLimit/100.0))) return false;
   
   uint total = 0;
   HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent());
   total = HistoryDealsTotal();
   int tradesToday = 0;
   for(uint i=0; i<total; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) tradesToday++;
   }
   return (tradesToday < 2);
}

void ExecuteOrder(ENUM_ORDER_TYPE type, double price, double atr) {
   double slDist = 1.2 * atr;
   double tpDist = 2.0 * atr;
   double sl, tp;
   
   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPerTrade/100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot = riskMoney / (slDist / _Point * tickValue);
   lot = NormalizeDouble(lot, 2);

   if(type == ORDER_TYPE_BUY_STOP) {
      sl = price - slDist;
      tp = price + tpDist;
   } else {
      sl = price + slDist;
      tp = price - tpDist;
   }
   Trade.OrderOpen(_Symbol, type, lot, 0, price, sl, tp);
}

void ManageExistingPositions() {
   if(!PositionSelect(_Symbol)) return;
   
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL = PositionGetDouble(POSITION_SL);
   double curPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double atr = 0;
   double buf[1];
   CopyBuffer(hATR, 0, 1, 1, buf);
   atr = buf[0];

   double r1 = MathAbs(entry - currentSL) / 1.2; // Original 1R distance
   
   // Break Even (1R)
   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
      if(curPrice >= entry + r1 && currentSL < entry) {
         Trade.PositionModify(_Symbol, entry + (0.2 * r1), PositionGetDouble(POSITION_TP));
      }
      // Trailing (1.5R)
      if(curPrice >= entry + (1.5 * r1)) {
         double newSL = curPrice - atr;
         if(newSL > currentSL) Trade.PositionModify(_Symbol, newSL, PositionGetDouble(POSITION_TP));
      }
   } else {
      if(curPrice <= entry - r1 && currentSL > entry) {
         Trade.PositionModify(_Symbol, entry - (0.2 * r1), PositionGetDouble(POSITION_TP));
      }
      // Trailing (1.5R)
      if(curPrice <= entry - (1.5 * r1)) {
         double newSL = curPrice + atr;
         if(newSL < currentSL) Trade.PositionModify(_Symbol, newSL, PositionGetDouble(POSITION_TP));
      }
   }
}

bool IsNewCandle() {
   static datetime lastTime = 0;
   datetime currTime = iTime(_Symbol, _Period, 0);
   if(lastTime != currTime) {
      lastTime = currTime;
      return true;
   }
   return false;
}