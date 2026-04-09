//+------------------------------------------------------------------+
//|                                      EA_MeanReversion_v5_0_4.mq5 |
//+------------------------------------------------------------------+
#property copyright   "Mean Reversion EA"
#property link        ""
#property description "Mean Reversion with RSI + BB"
#property version     "5.04"
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

input group      "=== BB Compression ==="
input bool       InpUseBBCompression   = true;
input double     InpBBMinWidthPoints   = 300; // in points
input int        InpCompressionLookback = 3;  // candles back to compare

input group      "=== Take Modes ==="
enum ENUM_TAKE_MODE
{
   TAKE_FIXED     = 0,
   TAKE_RSI       = 1,
   TAKE_MIDDLE_BB = 2,
   TAKE_NONE      = 3
};
input ENUM_TAKE_MODE InpTakeWithTrend    = TAKE_FIXED;
input ENUM_TAKE_MODE InpTakeAgainstTrend = TAKE_FIXED;
input double InpTakePointsWithTrend    = 300;
input double InpTakePointsAgainstTrend = 150;

input group      "=== SMA Settings ==="
input int        InpSMALong       = 200;

input group      "=== Stop Settings ==="
input int        InpStopLookback  = 4;
input double     InpStopBuffer    = 50.0;   // in points

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
   if(rsi > InpRSIOverbought || price > upper) return  1;
   if(rsi < InpRSIOversold   || price < lower) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| BB COMPRESSION HELPERS                                           |
//+------------------------------------------------------------------+

double GetBBWidthPoints(double upper, double lower)
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   return (upper - lower) / point;
  }

bool IsBBCompressedSmart(const double &upper[], const double &lower[])
  {
   if(!InpUseBBCompression) return false;

   double currentWidth = GetBBWidthPoints(upper[0], lower[0]);
   double pastWidth    = GetBBWidthPoints(upper[InpCompressionLookback], lower[InpCompressionLookback]);

   // Only valid compression if it SHRANK
   return (currentWidth < InpBBMinWidthPoints && pastWidth > currentWidth);
  }

//+------------------------------------------------------------------+
//| MODULE 2 — STATE MACHINE (ENTRY ONLY)                            |
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
//| MODULE 3 — EXIT ENGINE (STATELESS, IMMEDIATE)                    |
//+------------------------------------------------------------------+

bool ShouldExitTrade(const ENUM_POSITION_TYPE type, const int oppositeSignal)
  {
   if(type == POSITION_TYPE_BUY  && oppositeSignal ==  1) return true;
   if(type == POSITION_TYPE_SELL && oppositeSignal == -1) return true;
   return false;
  }

//+------------------------------------------------------------------+
//| MODULE 6 — RISK & TAKE PROFIT ENGINE                             |
//+------------------------------------------------------------------+

double CalculateTakeProfit(
   ENUM_POSITION_TYPE type,
   ENUM_TAKE_MODE mode,
   double entryPrice,
   double rsi,
   bool isLong,
   double points,
   double middleBB)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(mode == TAKE_FIXED)
   {
      if(isLong)
         return entryPrice + points * point;
      else
         return entryPrice - points * point;
   }

   if(mode == TAKE_RSI)
   {
      if(isLong && rsi > InpRSIOverbought + 5)
         return entryPrice; // force exit via BE-style TP

      if(!isLong && rsi < InpRSIOversold + 5)
         return entryPrice;
   }
   
   if(mode == TAKE_MIDDLE_BB)
   {
      return middleBB; // dynamic TP at BB middle
   }

   return 0.0; // TAKE_NONE
}

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
//| MODULE 4 — EXECUTION ENGINE                                      |
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
                    const double &upper[],
                    const double &lower[],
                    const double middleBB,
                    const double &high4[],
                    const double &low4[],
                    const bool isBull,
                    const bool isBear)
  {
   bool isCompressed = IsBBCompressedSmart(upper, lower);

   // NORMAL LOGIC
   bool normalLong  = ShouldEnterLong(state, rsi, price, lower[0]);
   bool normalShort = ShouldEnterShort(state, rsi, price, upper[0]);

   // --- BREAKOUT MODE ---
   if(isCompressed)
     {
      // Immediate breakout — NO WAITING
      normalLong  = (price > upper[0]); // breakout up
      normalShort = (price < lower[0]); // breakout down
     }

   if(normalLong)
     {
      if(!InpEnableLongs)                                           { state = STATE_IDLE; g_stateBarCount = 0; return; }
      if(!isCompressed && isBull && !InpEnableWithTrend)            { state = STATE_IDLE; g_stateBarCount = 0; return; }
      if(!isCompressed && isBear && !InpEnableAgainstTrend)         { state = STATE_IDLE; g_stateBarCount = 0; return; }
      if(isCompressed && !InpEnableWithTrend)                       { state = STATE_IDLE; g_stateBarCount = 0; return; } // Compression treated as with trend

      double sl  = CalculateStopLoss(ORDER_TYPE_BUY, high4, low4, InpStopLookback);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      ENUM_TAKE_MODE mode =
         isBull || isCompressed ? InpTakeWithTrend : InpTakeAgainstTrend;

      double tp = CalculateTakeProfit(
         POSITION_TYPE_BUY,
         mode,
         ask,
         rsi,
         true,
         isBull || isCompressed ? InpTakePointsWithTrend : InpTakePointsAgainstTrend,
         middleBB
      );

      if(g_trade.Buy(CalculateLotSize(), _Symbol, ask, sl, tp, "MR_BUY"))
         Print("BUY sent. Price=", ask, " SL=", sl, " TP=", tp);
      else
         Print("ERROR BUY. RetCode=", g_trade.ResultRetcode(),
               " Comment=", g_trade.ResultComment());

      state = STATE_IDLE;
      g_stateBarCount = 0;
      return;
     }

   if(normalShort)
     {
      if(!InpEnableShorts)                                          { state = STATE_IDLE; g_stateBarCount = 0; return; }
      if(!isCompressed && isBear && !InpEnableWithTrend)            { state = STATE_IDLE; g_stateBarCount = 0; return; }
      if(!isCompressed && isBull && !InpEnableAgainstTrend)         { state = STATE_IDLE; g_stateBarCount = 0; return; }
      if(isCompressed && !InpEnableWithTrend)                       { state = STATE_IDLE; g_stateBarCount = 0; return; } // Compression treated as with trend

      double sl  = CalculateStopLoss(ORDER_TYPE_SELL, high4, low4, InpStopLookback);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      ENUM_TAKE_MODE mode =
         isBear || isCompressed ? InpTakeWithTrend : InpTakeAgainstTrend;

      double tp = CalculateTakeProfit(
         POSITION_TYPE_SELL,
         mode,
         bid,
         rsi,
         false,
         isBear || isCompressed ? InpTakePointsWithTrend : InpTakePointsAgainstTrend,
         middleBB
      );

      if(g_trade.Sell(CalculateLotSize(), _Symbol, bid, sl, tp, "MR_SELL"))
         Print("SELL sent. Price=", bid, " SL=", sl, " TP=", tp);
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

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFillingBySymbol(_Symbol);

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
   double rsiBuf[1], middleBuf[10], upperBuf[10], lowerBuf[10], smaBuf[2];
   double highBuf[MAX_LOOKBACK], lowBuf[MAX_LOOKBACK];

   // --- SET ALL ARRAYS AS SERIES (MANDATORY FOR PROPER INDEXING) ---
   ArraySetAsSeries(rsiBuf, true);
   ArraySetAsSeries(middleBuf, true);
   ArraySetAsSeries(upperBuf, true);
   ArraySetAsSeries(lowerBuf, true);
   ArraySetAsSeries(smaBuf, true);
   ArraySetAsSeries(highBuf, true);
   ArraySetAsSeries(lowBuf, true);

   int copiedRSI = CopyBuffer(g_handleRSI, 0, 1, 1, rsiBuf);
   if(copiedRSI < 1) 
     { 
      Print("WARN: RSI copy failed. Copied=", copiedRSI); 
      return; 
     }

   int copiedBBMiddle = CopyBuffer(g_handleBB, 0, 1, InpCompressionLookback + 1, middleBuf);
   if(copiedBBMiddle < InpCompressionLookback + 1) 
     { 
      Print("WARN: BB middle copy failed. Copied=", copiedBBMiddle); 
      return; 
     }

   int copiedBBUpper = CopyBuffer(g_handleBB, 1, 1, InpCompressionLookback + 1, upperBuf);
   if(copiedBBUpper < InpCompressionLookback + 1) 
     { 
      Print("WARN: BB upper copy failed. Copied=", copiedBBUpper); 
      return; 
     }

   int copiedBBLower = CopyBuffer(g_handleBB, 2, 1, InpCompressionLookback + 1, lowerBuf);
   if(copiedBBLower < InpCompressionLookback + 1) 
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
   double sma200     = smaBuf[0];   // most recent bar
   double sma200prev = smaBuf[1];   // previous bar
   double closeBar1  = iClose(_Symbol, _Period, 1);

   // --- 2. Detect RSI event ---
   int rsiEvent = TrespassedRSI(currentRSI, InpRSIOverbought, InpRSIOversold);

   // --- 3. Detect BB event ---
   int bbEvent = TrespassedBollinger(closeBar1, upperBuf[0], lowerBuf[0]);

   // --- 4. Update state machine (ENTRY ONLY) ---
   g_entryState = UpdateEntryState(g_entryState, rsiEvent, bbEvent, g_stateBarCount);

   // --- 5. Generate opposite signal (EXIT — stateless, no confirmation) ---
   int oppSignal = OppositeSignal(currentRSI, closeBar1, upperBuf[0], lowerBuf[0]);

   // --- 6. Regime detection (mirrors v2.2.0/v2.3.0) ---
   bool priceAbove = closeBar1 > sma200;
   bool slopeUp    = sma200 > sma200prev;
   bool isBull     =  priceAbove &&  slopeUp;
   bool isBear     = !priceAbove && !slopeUp;

   // --- 8. Process exits ---
   ProcessExits(oppSignal);

   // --- 9. Process entries ---
   ProcessEntries(g_entryState, currentRSI, closeBar1, upperBuf, lowerBuf, middleBuf[0],
                  highBuf, lowBuf, isBull, isBear);
  }
//+------------------------------------------------------------------+