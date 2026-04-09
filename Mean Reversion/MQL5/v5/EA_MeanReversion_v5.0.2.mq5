//+------------------------------------------------------------------+
//|                                      EA_MeanReversion_v5_0_2.mq5 |
//+------------------------------------------------------------------+
#property copyright   "Mean Reversion EA"
#property link        ""
#property description "Mean Reversion with RSI + BB"
#property version     "5.02"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Preprocessor Defines                                             |
//+------------------------------------------------------------------+
#define MAX_STATE_BARS  3
#define MAX_LOOKBACK    20
enum ENUM_ENTRY_STATE
  {
   STATE_IDLE             = 0,
   STATE_OVERSOLD_ARMED   = 1,
   STATE_OVERBOUGHT_ARMED = 2
  };

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group      "=== RSI Settings ==="
input int        InpRSIPeriod     = 4;
input double     InpRSIOversold   = 25.0;
input double     InpRSIOverbought = 75.0;

input group      "=== Bollinger Bands Settings ==="
input int        InpBBPeriod      = 21;
input double     InpBBDeviation   = 2.0;

input group      "=== SMA Settings ==="
input int        InpSMALong       = 200;

input group      "=== Stop Settings ==="
input int        InpStopLookback  = 4;
input double     InpStopBuffer    = 13.0;   // in points

input group      "=== Trade Settings ==="
input double     InpLotSize       = 0.1;
input int        InpMagicNumber   = 123456;

input group      "=== Execution Toggles ==="
input bool       InpEnableLongs        = true;
input bool       InpEnableShorts       = true;
input bool       InpEnableWithTrend    = true;
input bool       InpEnableAgainstTrend = false;

input group      "=== Time Filter ==="
input bool       InpUseTimeFilter = false;
input int        InpStartHour     = 8;
input int        InpEndHour       = 20;

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
int              g_handleRSI      = INVALID_HANDLE;
int              g_handleBB       = INVALID_HANDLE;
int              g_handleSMA      = INVALID_HANDLE;
//int              g_handleATR      = INVALID_HANDLE;

ENUM_ENTRY_STATE g_entryState     = STATE_IDLE;
int              g_stateBarCount  = 0;

CTrade           g_trade;

//+------------------------------------------------------------------+
//| MODULE 1 — SIGNAL DETECTION                                      |
//+------------------------------------------------------------------+

int TrespassedRSI(const double rsi, const double overbought, const double oversold)
  {
   if(rsi > overbought) return  1;
   if(rsi < oversold)   return -1;
   return 0;
  }

int TrespassedBollinger(const double price, const double upper, const double lower)
  {
   if(price > upper) return  1;
   if(price < lower) return -1;
   return 0;
  }

int OppositeSignal(const double rsi,   const double price,
                   const double upper, const double lower)
  {
   if(rsi > InpRSIOverbought + 5 || price > upper) return  1;
   if(rsi < InpRSIOversold + 5   || price < lower) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| MODULE 2 — STATE MACHINE (ENTRY ONLY)                           |
//+------------------------------------------------------------------+

ENUM_ENTRY_STATE UpdateEntryState(const ENUM_ENTRY_STATE currentState,
                                  const int rsiEvent,
                                  const int bbEvent,
                                  int &barCount)
  {
   switch(currentState)
     {
      case STATE_IDLE:
        {
         barCount = 0;
         if(rsiEvent == -1 && bbEvent == -1) return STATE_OVERSOLD_ARMED;
         if(rsiEvent ==  1 && bbEvent ==  1) return STATE_OVERBOUGHT_ARMED;
         return STATE_IDLE;
        }

      case STATE_OVERSOLD_ARMED:
        {
         barCount++;
         if(barCount > MAX_STATE_BARS)
           {
            barCount = 0;
            return STATE_IDLE;
           }
         return STATE_OVERSOLD_ARMED;
        }

      case STATE_OVERBOUGHT_ARMED:
        {
         barCount++;
         if(barCount > MAX_STATE_BARS)
           {
            barCount = 0;
            return STATE_IDLE;
           }
         return STATE_OVERBOUGHT_ARMED;
        }
     }
   return STATE_IDLE;
  }

bool ShouldEnterLong(const ENUM_ENTRY_STATE state,
                     const double rsi,
                     const double price,
                     const double lower)
  {
   return (state == STATE_OVERSOLD_ARMED &&
           rsi   > InpRSIOversold        &&
           price >= lower);
  }

bool ShouldEnterShort(const ENUM_ENTRY_STATE state,
                      const double rsi,
                      const double price,
                      const double upper)
  {
   return (state == STATE_OVERBOUGHT_ARMED &&
           rsi   < InpRSIOverbought        &&
           price <= upper);
  }

//+------------------------------------------------------------------+
//| MODULE 3 — EXIT ENGINE (STATELESS, IMMEDIATE)                   |
//+------------------------------------------------------------------+

bool ShouldExitTrade(const ENUM_POSITION_TYPE type, const int oppositeSignal)
  {
   if(type == POSITION_TYPE_BUY  && oppositeSignal ==  1) return true;
   if(type == POSITION_TYPE_SELL && oppositeSignal == -1) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| MODULE 6 — RISK ENGINE                                          |
//+------------------------------------------------------------------+

double CalculateStopLoss(const ENUM_ORDER_TYPE type,
                         const double &high4[],
                         const double &low4[],
                         const int count)
  {
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double stopBuffer = InpStopBuffer * point;
   int    digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   if(type == ORDER_TYPE_BUY)
     {
      double minLow = low4[0];
      for(int i = 1; i < count; i++)
         if(low4[i] < minLow) minLow = low4[i];
      return NormalizeDouble(minLow - stopBuffer, digits);
     }
   else
     {
      double maxHigh = high4[0];
      for(int i = 1; i < count; i++)
         if(high4[i] > maxHigh) maxHigh = high4[i];
      return NormalizeDouble(maxHigh + stopBuffer, digits);
     }
  }

double CalculateLotSize()
  {
   return InpLotSize;
  }

//+------------------------------------------------------------------+
//| MODULE 5 — ADAPTIVE BREAKEVEN                                   |
//+------------------------------------------------------------------+

void ApplyAdaptiveBreakEven(const double middleBand)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagicNumber) continue;

      string symbol;
      if(!PositionGetString(POSITION_SYMBOL, symbol)) continue;
      if(symbol != _Symbol) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL  = PositionGetDouble(POSITION_SL);
      double currentTP  = PositionGetDouble(POSITION_TP);
      double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // --- LONG positions: trigger when bid reaches middle band ---
      if(type == POSITION_TYPE_BUY)
        {
         if(bid >= middleBand)
           {
            double newSL = (entryPrice + middleBand) / 2.0;

            if(newSL > currentSL)
              {
               g_trade.PositionModify(symbol, newSL, currentTP);
              }
           }
        }
      // --- SHORT positions: trigger when ask reaches middle band ---
      else if(type == POSITION_TYPE_SELL)
        {
         if(ask <= middleBand)
           {
            double newSL = (entryPrice + middleBand) / 2.0;

            if(currentSL == 0.0 || newSL < currentSL)
              {
               g_trade.PositionModify(symbol, newSL, currentTP);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| MODULE 4 — EXECUTION ENGINE                                     |
//+------------------------------------------------------------------+

void ProcessExits(const int oppositeSignal)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      
      string symbol;
      if(!PositionGetString(POSITION_SYMBOL, symbol)) continue;
      if(symbol != _Symbol) continue;
      
      if((ulong)PositionGetInteger(POSITION_MAGIC) != (ulong)InpMagicNumber) continue;

      ENUM_POSITION_TYPE posType =
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(ShouldExitTrade(posType, oppositeSignal))
         g_trade.PositionClose(ticket);
     }
  }

void ProcessEntries(ENUM_ENTRY_STATE &state,
                    const double rsi,
                    const double price,
                    const double upper,
                    const double lower,
                    const double &high4[],
                    const double &low4[],
                    const bool isBull,
                    const bool isBear)
  {
   if(ShouldEnterLong(state, rsi, price, lower))
     {
      if(!InpEnableLongs)                           { state = STATE_IDLE; g_stateBarCount = 0; return; }
      if(isBull && !InpEnableWithTrend)             { state = STATE_IDLE; g_stateBarCount = 0; return; }
      if(isBear && !InpEnableAgainstTrend)          { state = STATE_IDLE; g_stateBarCount = 0; return; }

      double sl  = CalculateStopLoss(ORDER_TYPE_BUY, high4, low4, InpStopLookback);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(g_trade.Buy(CalculateLotSize(), _Symbol, ask, sl, 0.0, "MR_BUY"))
         Print("BUY sent. Price=", ask, " SL=", sl);
      else
         Print("ERROR BUY. RetCode=", g_trade.ResultRetcode(),
               " Comment=", g_trade.ResultComment());

      state = STATE_IDLE;
      g_stateBarCount = 0;
      return;
     }

   if(ShouldEnterShort(state, rsi, price, upper))
     {
      if(!InpEnableShorts)                          { state = STATE_IDLE; g_stateBarCount = 0; return; }
      if(isBear && !InpEnableWithTrend)             { state = STATE_IDLE; g_stateBarCount = 0; return; }
      if(isBull && !InpEnableAgainstTrend)          { state = STATE_IDLE; g_stateBarCount = 0; return; }

      double sl  = CalculateStopLoss(ORDER_TYPE_SELL, high4, low4, InpStopLookback);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(g_trade.Sell(CalculateLotSize(), _Symbol, bid, sl, 0.0, "MR_SELL"))
         Print("SELL sent. Price=", bid, " SL=", sl);
      else
         Print("ERROR SELL. RetCode=", g_trade.ResultRetcode(),
               " Comment=", g_trade.ResultComment());

      state = STATE_IDLE;
      g_stateBarCount = 0;
      return;
     }
  }

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+

bool IsWithinTradingHours()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.hour >= InpStartHour && dt.hour < InpEndHour);
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_handleRSI = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   if(g_handleRSI == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create RSI handle.");
      return INIT_FAILED;
     }

   g_handleBB = iBands(_Symbol, _Period, InpBBPeriod, 2, InpBBDeviation, PRICE_CLOSE);
   if(g_handleBB == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create BB handle.");
      return INIT_FAILED;
     }

   g_handleSMA = iMA(_Symbol, _Period, InpSMALong, 0, MODE_SMA, PRICE_CLOSE);
   if(g_handleSMA == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create SMA handle.");
      return INIT_FAILED;
     }

   //g_handleATR = iATR(_Symbol, _Period, 14);
   //if(g_handleATR == INVALID_HANDLE)
   //  {
   //   Print("ERROR: Failed to create ATR handle.");
   //   return INIT_FAILED;
   //  }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

   g_entryState    = STATE_IDLE;
   g_stateBarCount = 0;

   Print("EA initialized. Symbol=", _Symbol, " TF=", EnumToString(_Period),
         " Magic=", InpMagicNumber);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_handleRSI != INVALID_HANDLE) IndicatorRelease(g_handleRSI);
   if(g_handleBB  != INVALID_HANDLE) IndicatorRelease(g_handleBB);
   if(g_handleSMA != INVALID_HANDLE) IndicatorRelease(g_handleSMA);
   //if(g_handleATR != INVALID_HANDLE) IndicatorRelease(g_handleATR);
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   // New candle gate
   static datetime s_lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == s_lastBarTime) return;
   s_lastBarTime = currentBarTime;

   if(InpUseTimeFilter && !IsWithinTradingHours()) return;

   // --- SAFETY: Ensure sufficient historical data before proceeding ---
   int requiredBars = MathMax(InpStopLookback, MathMax(InpRSIPeriod, InpBBPeriod));
   int totalBars    = Bars(_Symbol, _Period);
   
   if(totalBars < requiredBars + 10)
     {
      Print("INFO: Not enough bars yet. Have=", totalBars, " Need=", requiredBars + 10);
      return;
     }

   // --- 1. Load indicators (bar 1 = last closed bar, mirrors Zorro [0]) ---
   double rsiBuf[1], middleBuf[1], upperBuf[1], lowerBuf[1], smaBuf[2];
   double highBuf[MAX_LOOKBACK], lowBuf[MAX_LOOKBACK];

   int copiedRSI = CopyBuffer(g_handleRSI, 0, 1, 1, rsiBuf);
   if(copiedRSI < 1) 
     { 
      Print("WARN: RSI copy failed. Copied=", copiedRSI); 
      return; 
     }

   int copiedBBMiddle = CopyBuffer(g_handleBB, 0, 1, 1, middleBuf);
   if(copiedBBMiddle < 1) 
     { 
      Print("WARN: BB middle copy failed. Copied=", copiedBBMiddle); 
      return; 
     }

   int copiedBBUpper = CopyBuffer(g_handleBB, 1, 1, 1, upperBuf);
   if(copiedBBUpper < 1) 
     { 
      Print("WARN: BB upper copy failed. Copied=", copiedBBUpper); 
      return; 
     }

   int copiedBBLower = CopyBuffer(g_handleBB, 2, 1, 1, lowerBuf);
   if(copiedBBLower < 1) 
     { 
      Print("WARN: BB lower copy failed. Copied=", copiedBBLower); 
      return; 
     }

   int copiedSMA = CopyBuffer(g_handleSMA, 0, 1, 2, smaBuf);
   if(copiedSMA < 2) 
     { 
      Print("WARN: SMA copy failed. Needed=2 Got=", copiedSMA); 
      return; 
     }

   int copiedHigh = CopyHigh(_Symbol, _Period, 1, InpStopLookback, highBuf);
   if(copiedHigh < InpStopLookback)
     { 
      Print("WARN: High copy failed. Needed=", InpStopLookback, " Got=", copiedHigh); 
      return; 
     }

   int copiedLow = CopyLow(_Symbol, _Period, 1, InpStopLookback, lowBuf);
   if(copiedLow < InpStopLookback)
     { 
      Print("WARN: Low copy failed. Needed=", InpStopLookback, " Got=", copiedLow); 
      return; 
     }

   double currentRSI = rsiBuf[0];
   double middleBB   = middleBuf[0];
   double upperBB    = upperBuf[0];
   double lowerBB    = lowerBuf[0];
   double sma200     = smaBuf[1];   // bar1
   double sma200prev = smaBuf[0];   // bar2
   double closeBar1  = iClose(_Symbol, _Period, 1);

   // --- 2. Detect RSI event ---
   int rsiEvent = TrespassedRSI(currentRSI, InpRSIOverbought, InpRSIOversold);

   // --- 3. Detect BB event ---
   int bbEvent = TrespassedBollinger(closeBar1, upperBB, lowerBB);

   // --- 4. Update state machine (ENTRY ONLY) ---
   g_entryState = UpdateEntryState(g_entryState, rsiEvent, bbEvent, g_stateBarCount);

   // --- 5. Generate opposite signal (EXIT — stateless, no confirmation) ---
   int oppSignal = OppositeSignal(currentRSI, closeBar1, upperBB, lowerBB);

   // --- 6. Regime detection (mirrors v2.2.0/v2.3.0) ---
   bool priceAbove = closeBar1 > sma200;
   bool slopeUp    = sma200 > sma200prev;
   bool isBull     =  priceAbove &&  slopeUp;
   bool isBear     = !priceAbove && !slopeUp;

   // --- 7. Apply adaptive breakeven (BEFORE exits) ---
   //ApplyAdaptiveBreakEven(middleBB);

   // --- 8. Process exits AFTER breakeven ---
   ProcessExits(oppSignal);

   // --- 9. Process entries AFTER ---
   ProcessEntries(g_entryState, currentRSI, closeBar1, upperBB, lowerBB,
                  highBuf, lowBuf, isBull, isBear);
  }
