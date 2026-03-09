//EA_Pullback_v1.2.2.mq5

#property copyright "Daniel Pereira"
#property link      ""
#property version   "1.22"
#property strict

#include <Trade\Trade.mqh>

//--- GLOBALS
int hEMA21, hEMA50, hATR, hADX;
CTrade Trade;
int Magic = 123456;

//--- DATA STRUCTURES
struct IndicatorData {
   double ema21[3];
   double ema50[3];
   double adx[2];
   double plusDI[2];
   double minusDI[2];
   double atr[3];
};

//--- INITIALIZATION
int OnInit() {
   if(_Symbol != "EURUSD" && _Symbol != "GBPUSD") return INIT_FAILED;
   if(_Period != PERIOD_M15) return INIT_FAILED;

   hEMA21 = iMA(_Symbol, _Period, 21, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50 = iMA(_Symbol, _Period, 50, 0, MODE_EMA, PRICE_CLOSE);
   hATR   = iATR(_Symbol, _Period, 14);
   hADX   = iADX(_Symbol, _Period, 14);

   if(hEMA21 == INVALID_HANDLE || hEMA50 == INVALID_HANDLE || hATR == INVALID_HANDLE || hADX == INVALID_HANDLE)
      return INIT_FAILED;

   Trade.SetExpertMagicNumber(Magic);
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

   // Manage Break Even for existing position
   if(PositionSelect(_Symbol)) {
      ManageBreakEven();
      return;
   }

   // 1. Time Filter (06:00 <= time < 22:00 Server Time)
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   if(dt.hour < 6 || dt.hour >= 22) return;

   // 2. Daily Limits (Trades and Profit/Loss)
   if(!CheckDailyLimits()) return;

   // 3. Data Collection
   IndicatorData data;
   if(!FillData(data)) return;

   MqlRates rates[3];
   if(CopyRates(_Symbol, _Period, 1, 2, rates) < 2) return; // Index 0 is Candle[1], Index 1 is Candle[2] in this array

   // 4. ATR Symbol Specific Threshold
   double atrThreshold = (_Symbol == "EURUSD") ? 0.0008 : 0.0012;
   if(data.atr[1] <= atrThreshold) return;

   // 5. Common Filters
   bool adxFilter = (data.adx[1] > 20.0);
   if(!adxFilter) return;

   double dist = MathAbs(rates[1].close - data.ema50[1]);
   bool distFilter = (dist > (0.5 * data.atr[1]));
   if(!distFilter) return;

   // 6. BUY SETUP
   if(data.ema21[1] > data.ema50[1] && data.plusDI[1] > data.minusDI[1]) {
      if(rates[0].close <= data.ema21[2] && rates[1].close > rates[1].open && rates[1].close > data.ema21[1]) {
         ExecuteMarketOrder(ORDER_TYPE_BUY, data.atr[1]);
      }
   }

   // 7. SELL SETUP
   if(data.ema21[1] < data.ema50[1] && data.minusDI[1] > data.plusDI[1]) {
      if(rates[0].close >= data.ema21[2] && rates[1].close < rates[1].open && rates[1].close < data.ema21[1]) {
         ExecuteMarketOrder(ORDER_TYPE_SELL, data.atr[1]);
      }
   }
}

//--- LOGIC HELPERS
bool FillData(IndicatorData &d) {
   if(CopyBuffer(hEMA21, 0, 0, 3, d.ema21) < 3) return false;
   if(CopyBuffer(hEMA50, 0, 0, 3, d.ema50) < 3) return false;
   if(CopyBuffer(hADX, 0, 0, 2, d.adx) < 2) return false;
   if(CopyBuffer(hADX, 1, 0, 2, d.plusDI) < 2) return false;
   if(CopyBuffer(hADX, 2, 0, 2, d.minusDI) < 2) return false;
   if(CopyBuffer(hATR, 0, 0, 3, d.atr) < 3) return false;
   return true;
}

bool CheckDailyLimits() {
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
   HistorySelect(dayStart, TimeCurrent());
   
   double dailyProfit = 0;
   int tradesToday = 0;
   uint total = HistoryDealsTotal();

   for(uint i=0; i<total; i++) {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic && HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol) {
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
            dailyProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            tradesToday++;
         }
      }
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(dailyProfit >= (balance * 0.01) || dailyProfit <= -(balance * 0.01)) return false;
   if(tradesToday >= 2) return false;

   return true;
}

void ExecuteMarketOrder(ENUM_ORDER_TYPE type, double atr) {
   double slDist = atr; 
   double tpDist = 2.0 * atr;
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double sl = (type == ORDER_TYPE_BUY) ? price - slDist : price + slDist;
   double tp = (type == ORDER_TYPE_BUY) ? price + tpDist : price - tpDist;

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * 0.005;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lot = riskMoney / (slDist / _Point * tickValue);
   
   lot = MathFloor(lot / SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)) * SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathMax(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   lot = MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));

   Trade.PositionOpen(_Symbol, type, lot, price, sl, tp);
}

void ManageBreakEven() {
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl = PositionGetDouble(POSITION_SL);
   double tp = PositionGetDouble(POSITION_TP);
   double curPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   
   double r1 = MathAbs(entry - sl); 

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
      if(curPrice >= entry + r1 && sl < entry) {
         Trade.PositionModify(_Symbol, entry + spread, tp);
      }
   } else {
      if(curPrice <= entry - r1 && sl > entry) {
         Trade.PositionModify(_Symbol, entry - spread, tp);
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