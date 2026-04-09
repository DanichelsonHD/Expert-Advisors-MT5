//+------------------------------------------------------------------+
//|                                      EA_MeanReversion_v2.0.1.mq5 |
//|               Structured Mean Reversion with Return Confirmation |
//+------------------------------------------------------------------+
#property copyright "Daniel Pereira"
#property link      ""
#property version   "2.01"
#property strict

//=============================================================================
// INPUT PARAMETERS
//=============================================================================

//--- Timeframe
input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H1; // Trading Timeframe (M30 or H1)

//--- RSI
input group "=== RSI ==="
input int    InpRSIPeriod        = 14;          // RSI Period
input double InpRSIOverbought    = 75.0;        // RSI Overbought Level
input double InpRSIOversold      = 25.0;        // RSI Oversold Level

//--- Keltner Channel
input group "=== Keltner Channel ==="
input int    InpKeltnerEMAPeriod = 21;          // Keltner EMA Period
input int    InpKeltnerATRPeriod = 7;           // Keltner ATR Period
input double InpKeltnerATRMult   = 2.5;         // Keltner ATR Multiplier

//--- KAMA
input group "=== KAMA ==="
input int    InpKAMAPeriod       = 21;          // KAMA Period
input int    InpKAMAFast         = 3;           // KAMA Fast Period
input int    InpKAMASlow         = 30;          // KAMA Slow Period
input double InpKAMAPower        = 2.0;         // KAMA Smooth Power
input int    InpKAMAFilter       = 50;          // KAMA Filter
input int    InpKAMAFilterPer    = 4;           // KAMA Filter Period
input double InpKAMAFilterDiff   = 50.0;        // KAMA Filter Difference

//--- ATR Stop
input group "=== Stop Management ==="
input int    InpATRStopPeriod    = 14;          // ATR Period (Stop)
input double InpStopATRMult_M30  = 1.8;         // Stop ATR Multiplier (M30)
input double InpStopATRMult_H1   = 1.4;         // Stop ATR Multiplier (H1)
input double InpExtraPoints      = 10.0;        // Extra Points (stop buffer)
input double InpTrailATRMult     = 1.5;         // Trailing ATR Multiplier

//--- ATR Volatility Filter
input group "=== Volatility Filter ==="
input int    InpATRFilterPeriod  = 14;          // ATR Filter Period
input double InpATRFilterMult    = 1.1;         // ATR Filter Multiplier (min ATR ratio)

//--- Time Filter
input group "=== Time Filter ==="
input int    InpStartHour        = 8;           // Trading Start Hour (UTC)
input int    InpEndHour          = 17;          // Trading End Hour (UTC)
input bool   InpBlockAsian       = true;        // Block Asian Session

//--- Risk / Trade Control
input group "=== Risk Controls ==="
input double InpLotSize          = 1.0;         // Lot Size
input int    InpMagicNumber      = 20250101;    // Magic Number
input int    InpCooldownCandles  = 3;           // Cooldown Candles After Stop
input int    InpMaxConsecLoss    = 0;           // Max Consecutive Losses (0=disabled)

//=============================================================================
// INTERNAL STATE
//=============================================================================

enum EntryState
  {
   STATE_IDLE               = 0,
   STATE_OVERSOLD_CONFIRMED = 1,
   STATE_OVERBOUGHT_CONFIRMED = 2
  };

EntryState g_entryState      = STATE_IDLE;

bool       g_inPosition      = false;
int        g_positionType    = -1;
double     g_entryPrice      = 0.0;
double     g_currentSL       = 0.0;
double     g_initialSL       = 0.0;
ulong      g_positionTicket  = 0;

int        g_cooldownCount   = 0;
datetime   g_lastBarTime     = 0;

int        g_consecLosses    = 0;
bool       g_tradingLocked   = false;

string     g_prefix          = "MRE_";

//=============================================================================
// INDICATOR ARRAYS — Series mode (index 0 = current bar, 1 = last closed, ...)
//=============================================================================

#define KAMA_INSTANCE_SIZE 3
#define KAMA_DIFF          0
#define KAMA_VAL           1
#define KAMA_PRICE         2

double g_kamaWork[][KAMA_INSTANCE_SIZE];
double g_kamaVal[];
double g_kamaAma[];

double g_keltnerUpper[];
double g_keltnerLower[];
double g_keltnerMid[];

double g_rsiBuffer[];
double g_rsiPos[];
double g_rsiNeg[];

double g_atrBuffer[];
double g_atrTR[];

//=============================================================================
// HELPERS
//=============================================================================

double ActiveStopATRMult()
  {
   return (InpTimeframe == PERIOD_M30) ? InpStopATRMult_M30 : InpStopATRMult_H1;
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpTimeframe != PERIOD_M30 && InpTimeframe != PERIOD_H1)
     {
      Print("EA_MeanReversion: InpTimeframe must be PERIOD_M30 or PERIOD_H1.");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_entryState     = STATE_IDLE;
   g_inPosition     = false;
   g_positionType   = -1;
   g_currentSL      = 0.0;
   g_initialSL      = 0.0;
   g_positionTicket = 0;
   g_cooldownCount  = 0;
   g_lastBarTime    = 0;
   g_consecLosses   = 0;
   g_tradingLocked  = false;

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, g_prefix);

   ArrayFree(g_kamaWork);
   ArrayFree(g_kamaVal);
   ArrayFree(g_kamaAma);
   ArrayFree(g_keltnerUpper);
   ArrayFree(g_keltnerLower);
   ArrayFree(g_keltnerMid);
   ArrayFree(g_rsiBuffer);
   ArrayFree(g_rsiPos);
   ArrayFree(g_rsiNeg);
   ArrayFree(g_atrBuffer);
   ArrayFree(g_atrTR);
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   int bars = Bars(_Symbol, InpTimeframe);
   if(bars < MathMax(MathMax(InpRSIPeriod, InpKeltnerEMAPeriod + InpKeltnerATRPeriod), InpKAMAPeriod) + 10)
      return;

   datetime currentBarTime = iTime(_Symbol, InpTimeframe, 0);
   bool     isNewBar       = (currentBarTime != g_lastBarTime);

   if(!isNewBar)
      return;

   g_lastBarTime = currentBarTime;

   RecalculateAll(bars);

   SyncPositionState();

   if(g_inPosition)
     {
      StopManagement_Update();
      return;
     }

   if(!g_inPosition && !g_tradingLocked)
     {
      if(!IsWithinTradingHours())
         return;

      if(g_cooldownCount > 0)
        {
         g_cooldownCount--;
         return;
        }

      EntryEngine_Process();
     }
  }

//=============================================================================
// INDICATOR RECALCULATION
//=============================================================================

void RecalculateAll(const int bars)
  {
   EnsureArraySizes(bars);
   CalcATR(bars);
   CalcRSI(bars);
   CalcKeltner(bars);
   CalcKAMA(bars);
  }

void EnsureArraySizes(const int bars)
  {
   if(ArraySize(g_rsiBuffer) != bars)
     {
      ArrayResize(g_rsiBuffer, bars);
      ArrayResize(g_rsiPos,    bars);
      ArrayResize(g_rsiNeg,    bars);
      ArraySetAsSeries(g_rsiBuffer, true);
      ArraySetAsSeries(g_rsiPos,    true);
      ArraySetAsSeries(g_rsiNeg,    true);
      ArrayInitialize(g_rsiBuffer,  0.0);
      ArrayInitialize(g_rsiPos,     0.0);
      ArrayInitialize(g_rsiNeg,     0.0);
     }

   if(ArraySize(g_keltnerUpper) != bars)
     {
      ArrayResize(g_keltnerUpper, bars);
      ArrayResize(g_keltnerLower, bars);
      ArrayResize(g_keltnerMid,   bars);
      ArraySetAsSeries(g_keltnerUpper, true);
      ArraySetAsSeries(g_keltnerLower, true);
      ArraySetAsSeries(g_keltnerMid,   true);
      ArrayInitialize(g_keltnerUpper,  0.0);
      ArrayInitialize(g_keltnerLower,  0.0);
      ArrayInitialize(g_keltnerMid,    0.0);
     }

   if(ArraySize(g_atrBuffer) != bars)
     {
      ArrayResize(g_atrBuffer, bars);
      ArrayResize(g_atrTR,     bars);
      ArraySetAsSeries(g_atrBuffer, true);
      ArraySetAsSeries(g_atrTR,     true);
      ArrayInitialize(g_atrBuffer,  0.0);
      ArrayInitialize(g_atrTR,      0.0);
     }

   if(ArraySize(g_kamaVal) != bars)
     {
      ArrayResize(g_kamaVal,  bars);
      ArrayResize(g_kamaAma,  bars);
      ArrayResize(g_kamaWork, bars);
      ArraySetAsSeries(g_kamaVal, true);
      ArraySetAsSeries(g_kamaAma, true);
      ArrayInitialize(g_kamaVal,  0.0);
      ArrayInitialize(g_kamaAma,  0.0);
     }
  }

//+------------------------------------------------------------------+
//| ATR — single unified implementation                              |
//| Fills g_atrBuffer in series mode (index 0 = current bar)         |
//+------------------------------------------------------------------+
void CalcATR(const int bars)
  {
   //--- Copy OHLC in series mode
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpTimeframe, 0, bars, rates) < bars) return;

   //--- Use a local forward array for calculation, then reverse-fill series output
   double tr_fwd[];
   double atr_fwd[];
   ArrayResize(tr_fwd,  bars);
   ArrayResize(atr_fwd, bars);

   tr_fwd[0] = 0.0;
   for(int i = 1; i < bars; i++)
     {
      double hi = rates[bars - 1 - i].high;
      double lo = rates[bars - 1 - i].low;
      double pc = rates[bars - 1 - (i - 1)].close;
      tr_fwd[i] = MathMax(hi, pc) - MathMin(lo, pc);
     }

   int period = InpATRStopPeriod;
   double first = 0.0;
   for(int i = 1; i <= period && i < bars; i++)
      first += tr_fwd[i];

   atr_fwd[0]      = 0.0;
   atr_fwd[period] = (period > 0) ? first / period : 0.0;
   for(int i = period + 1; i < bars; i++)
      atr_fwd[i] = atr_fwd[i-1] + (tr_fwd[i] - tr_fwd[i - period]) / period;

   //--- Write into series buffer (index 0 = newest)
   for(int i = 0; i < bars; i++)
      g_atrBuffer[i] = atr_fwd[bars - 1 - i];
  }

//+------------------------------------------------------------------+
//| RSI                                                              |
//+------------------------------------------------------------------+
void CalcRSI(const int bars)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpTimeframe, 0, bars, rates) < bars) return;

   int period = InpRSIPeriod;
   if(bars <= period) return;

   //--- Forward arrays for sequential calculation
   double close_fwd[];
   double pos_fwd[];
   double neg_fwd[];
   double rsi_fwd[];
   ArrayResize(close_fwd, bars);
   ArrayResize(pos_fwd,   bars);
   ArrayResize(neg_fwd,   bars);
   ArrayResize(rsi_fwd,   bars);

   for(int i = 0; i < bars; i++)
      close_fwd[i] = rates[bars - 1 - i].close;

   pos_fwd[0] = 0.0;
   neg_fwd[0] = 0.0;
   rsi_fwd[0] = 0.0;

   double sum_pos = 0.0, sum_neg = 0.0;
   for(int i = 1; i <= period; i++)
     {
      pos_fwd[i] = 0.0;
      neg_fwd[i] = 0.0;
      rsi_fwd[i] = 0.0;
      double diff = close_fwd[i] - close_fwd[i - 1];
      sum_pos += (diff > 0.0 ? diff : 0.0);
      sum_neg += (diff < 0.0 ? -diff : 0.0);
     }

   pos_fwd[period] = sum_pos / period;
   neg_fwd[period] = sum_neg / period;
   if(neg_fwd[period] != 0.0)
      rsi_fwd[period] = 100.0 - (100.0 / (1.0 + pos_fwd[period] / neg_fwd[period]));
   else
      rsi_fwd[period] = (pos_fwd[period] != 0.0) ? 100.0 : 50.0;

   for(int i = period + 1; i < bars; i++)
     {
      double diff = close_fwd[i] - close_fwd[i - 1];
      pos_fwd[i]  = (pos_fwd[i-1] * (period - 1) + (diff > 0.0 ? diff : 0.0)) / period;
      neg_fwd[i]  = (neg_fwd[i-1] * (period - 1) + (diff < 0.0 ? -diff : 0.0)) / period;
      if(neg_fwd[i] != 0.0)
         rsi_fwd[i] = 100.0 - 100.0 / (1.0 + pos_fwd[i] / neg_fwd[i]);
      else
         rsi_fwd[i] = (pos_fwd[i] != 0.0) ? 100.0 : 50.0;
     }

   for(int i = 0; i < bars; i++)
      g_rsiBuffer[i] = rsi_fwd[bars - 1 - i];
  }

//+------------------------------------------------------------------+
//| Keltner Channel                                                  |
//+------------------------------------------------------------------+
void CalcKeltner(const int bars)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpTimeframe, 0, bars, rates) < bars) return;

   int    emaPeriod = InpKeltnerEMAPeriod;
   int    atrPeriod = InpKeltnerATRPeriod;
   double mult      = InpKeltnerATRMult;
   int    start     = MathMax(emaPeriod, atrPeriod) + 1;

   //--- Forward arrays
   double ema_fwd[];
   double tr_fwd[];
   double atr_fwd[];
   ArrayResize(ema_fwd, bars);
   ArrayResize(tr_fwd,  bars);
   ArrayResize(atr_fwd, bars);

   double k = 2.0 / (emaPeriod + 1.0);
   ema_fwd[0] = rates[bars - 1].close;
   for(int i = 1; i < bars; i++)
      ema_fwd[i] = rates[bars - 1 - i].close * k + ema_fwd[i-1] * (1.0 - k);

   tr_fwd[0] = 0.0;
   for(int i = 1; i < bars; i++)
     {
      double hi = rates[bars - 1 - i].high;
      double lo = rates[bars - 1 - i].low;
      double pc = rates[bars - 1 - (i - 1)].close;
      tr_fwd[i] = MathMax(hi, pc) - MathMin(lo, pc);
     }

   double first = 0.0;
   for(int i = 1; i <= atrPeriod && i < bars; i++)
      first += tr_fwd[i];

   atr_fwd[0]         = 0.0;
   atr_fwd[atrPeriod] = (atrPeriod > 0) ? first / atrPeriod : 0.0;
   for(int i = atrPeriod + 1; i < bars; i++)
      atr_fwd[i] = atr_fwd[i-1] + (tr_fwd[i] - tr_fwd[i - atrPeriod]) / atrPeriod;

   //--- Write into series buffers
   for(int i = 0; i < bars; i++)
     {
      int fwd = bars - 1 - i;
      if(fwd >= start)
        {
         g_keltnerMid[i]   = ema_fwd[fwd];
         g_keltnerUpper[i] = ema_fwd[fwd] + mult * atr_fwd[fwd];
         g_keltnerLower[i] = ema_fwd[fwd] - mult * atr_fwd[fwd];
        }
      else
        {
         g_keltnerMid[i]   = 0.0;
         g_keltnerUpper[i] = 0.0;
         g_keltnerLower[i] = 0.0;
        }
     }
  }

//+------------------------------------------------------------------+
//| KAMA                                                             |
//+------------------------------------------------------------------+
void CalcKAMA(const int bars)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpTimeframe, 0, bars, rates) < bars) return;

   if(ArrayRange(g_kamaWork, 0) != bars)
      ArrayResize(g_kamaWork, bars);

   int    period  = InpKAMAPeriod;
   double fastEnd = 2.0 / (InpKAMAFast + 1.0);
   double slowEnd = 2.0 / (InpKAMASlow + 1.0);
   double power   = InpKAMAPower;

   //--- Forward arrays
   double kama_fwd[];
   double kamaAma_fwd[];
   ArrayResize(kama_fwd,    bars);
   ArrayResize(kamaAma_fwd, bars);

   double work_price[];
   double work_diff[];
   double work_kama[];
   ArrayResize(work_price, bars);
   ArrayResize(work_diff,  bars);
   ArrayResize(work_kama,  bars);

   for(int i = 0; i < bars; i++)
     {
      double price    = rates[bars - 1 - i].close;
      work_price[i]   = price;
      work_diff[i]    = (i > 0) ? MathAbs(price - work_price[i-1]) : 0.0;

      double signal   = (i >= period) ? MathAbs(price - work_price[i - period]) : 0.0;
      double noise    = 0.0;
      for(int k = 0; k < period && i - k >= 0; k++)
         noise += work_diff[i - k];

      double efratio  = (noise != 0.0) ? signal / noise : 1.0;
      double smooth   = MathPow(efratio * (fastEnd - slowEnd) + slowEnd, power);
      work_kama[i]    = (i > 0) ? work_kama[i-1] + smooth * (price - work_kama[i-1]) : price;
      kamaAma_fwd[i]  = work_kama[i];
      kama_fwd[i]     = kamaAma_fwd[i];
     }

   //--- Apply filter
   if(InpKAMAFilter > 0)
     {
      for(int i = 1; i < bars; i++)
        {
         double sAmaDiff = 0.0;
         for(int k = 0; k < InpKAMASlow && (i - k - 1) >= 0; k++)
            sAmaDiff += MathAbs(kamaAma_fwd[i-k] - kamaAma_fwd[i-k-1]);

         double cAmaDiff    = kamaAma_fwd[i] - kamaAma_fwd[i-1];
         double aAmaDiff    = MathAbs(cAmaDiff);
         double filterValue = NormalizeDouble(InpKAMAFilter * sAmaDiff / (100.0 * InpKAMASlow), _Digits);
         int    _start      = MathMax(i - InpKAMAFilterPer, 0);

         if(cAmaDiff > 0)
           {
            double maxHigh = 0.0;
            for(int k = _start; k < _start + InpKAMAFilterPer && k < bars; k++)
               maxHigh = MathMax(maxHigh, rates[bars - 1 - k].high);
            if(cAmaDiff < filterValue && rates[bars - 1 - i].high <= (maxHigh + InpKAMAFilterDiff * _Point))
               kama_fwd[i] = (i > 0) ? kama_fwd[i-1] : kamaAma_fwd[i];
           }
         if(cAmaDiff < 0)
           {
            double minLow = DBL_MAX;
            for(int k = _start; k < _start + InpKAMAFilterPer && k < bars; k++)
               minLow = MathMin(minLow, rates[bars - 1 - k].low);
            if(aAmaDiff < filterValue && rates[bars - 1 - i].low >= (minLow - InpKAMAFilterDiff * _Point))
               kama_fwd[i] = (i > 0) ? kama_fwd[i-1] : kamaAma_fwd[i];
           }
        }
     }

   //--- Write into series buffers
   for(int i = 0; i < bars; i++)
     {
      g_kamaVal[i] = kama_fwd[bars - 1 - i];
      g_kamaAma[i] = kamaAma_fwd[bars - 1 - i];
     }
  }

//=============================================================================
// ACCESSORS — series mode, shift 1 = last closed bar
//=============================================================================

double GetRSI(const int shift)
  {
   if(shift >= ArraySize(g_rsiBuffer)) return 50.0;
   return g_rsiBuffer[shift];
  }

double GetKeltnerUpper(const int shift)
  {
   if(shift >= ArraySize(g_keltnerUpper)) return 0.0;
   return g_keltnerUpper[shift];
  }

double GetKeltnerLower(const int shift)
  {
   if(shift >= ArraySize(g_keltnerLower)) return 0.0;
   return g_keltnerLower[shift];
  }

double GetATR(const int shift)
  {
   if(shift >= ArraySize(g_atrBuffer)) return 0.0;
   return g_atrBuffer[shift];
  }

double GetKAMAVal(const int shift)
  {
   if(shift >= ArraySize(g_kamaVal)) return 0.0;
   return g_kamaVal[shift];
  }

double GetATRAverage()
  {
   int    count = InpATRFilterPeriod;
   double sum   = 0.0;
   for(int i = 1; i <= count; i++)
      sum += GetATR(i);
   return (count > 0) ? sum / count : 0.0;
  }

//+------------------------------------------------------------------+
//| TIME FILTER                                                      |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hour = dt.hour;

   if(InpBlockAsian && hour < 7)
      return false;

   return (hour >= InpStartHour && hour < InpEndHour);
  }

//+------------------------------------------------------------------+
//| SYNC POSITION STATE                                              |
//+------------------------------------------------------------------+
void SyncPositionState()
  {
   if(!g_inPosition) return;

   if(g_positionTicket == 0)
     {
      g_inPosition   = false;
      g_positionType = -1;
      return;
     }

   if(PositionSelectByTicket(g_positionTicket))
     {
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
        {
         g_inPosition     = false;
         g_positionType   = -1;
         g_positionTicket = 0;
        }
      return;
     }

   //--- Position no longer exists — determine exit reason
   bool wasStopHit = false;

   if(HistorySelectByPosition(g_positionTicket))
     {
      int totalDeals = HistoryDealsTotal();
      for(int d = 0; d < totalDeals; d++)
        {
         ulong dealTicket = HistoryDealGetTicket(d);
         if(dealTicket == 0) continue;
         if((ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON) == DEAL_REASON_SL)
           {
            wasStopHit = true;
            break;
           }
        }
     }

   if(wasStopHit)
     {
      g_cooldownCount = InpCooldownCandles;
      g_consecLosses++;
      if(InpMaxConsecLoss > 0 && g_consecLosses >= InpMaxConsecLoss)
         g_tradingLocked = true;
     }

   g_inPosition     = false;
   g_positionType   = -1;
   g_positionTicket = 0;
   g_entryState     = STATE_IDLE;
  }

//=============================================================================
// MODULE 1 — ENTRY ENGINE
//=============================================================================

void EntryEngine_Process()
  {
   double rsi1   = GetRSI(1);
   double rsi2   = GetRSI(2);
   double close1 = iClose(_Symbol, InpTimeframe, 1);
   double kLow1  = GetKeltnerLower(1);
   double kUpp1  = GetKeltnerUpper(1);

   //--- Volatility filter
   double atrCurr = GetATR(1);
   double atrAvg  = GetATRAverage();
   if(atrAvg > 0.0 && atrCurr < atrAvg * InpATRFilterMult)
      return;

   //--- STATE 1 — Detect extreme
   if(g_entryState == STATE_IDLE)
     {
      if(rsi1 < InpRSIOversold && close1 < kLow1)
        {
         g_entryState = STATE_OVERSOLD_CONFIRMED;
         return;
        }
      if(rsi1 > InpRSIOverbought && close1 > kUpp1)
        {
         g_entryState = STATE_OVERBOUGHT_CONFIRMED;
         return;
        }
     }

   //--- STATE 2 — Return from extreme
   if(g_entryState == STATE_OVERSOLD_CONFIRMED)
     {
      if(rsi2 < InpRSIOversold && rsi1 >= InpRSIOversold)
        {
         if(close1 <= kLow1 * (1.0 + 0.002))
           {
            ExecuteEntry(ORDER_TYPE_BUY);
            g_entryState = STATE_IDLE;
            return;
           }
        }
      if(rsi1 > InpRSIOversold + 10.0)
         g_entryState = STATE_IDLE;
     }

   if(g_entryState == STATE_OVERBOUGHT_CONFIRMED)
     {
      if(rsi2 > InpRSIOverbought && rsi1 <= InpRSIOverbought)
        {
         if(close1 >= kUpp1 * (1.0 - 0.002))
           {
            ExecuteEntry(ORDER_TYPE_SELL);
            g_entryState = STATE_IDLE;
            return;
           }
        }
      if(rsi1 < InpRSIOverbought - 10.0)
         g_entryState = STATE_IDLE;
     }
  }

//+------------------------------------------------------------------+
//| Execute Entry Order                                              |
//+------------------------------------------------------------------+
void ExecuteEntry(const ENUM_ORDER_TYPE orderType)
  {
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
      return;

   double atr        = GetATR(1);
   double ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double extraPts   = InpExtraPoints * _Point;
   double stopMult   = ActiveStopATRMult();
   double sl         = 0.0;
   double entryPrice = 0.0;

   if(orderType == ORDER_TYPE_BUY)
     {
      entryPrice = ask;
      sl         = entryPrice - (atr * stopMult) - extraPts;
     }
   else
     {
      entryPrice = bid;
      sl         = entryPrice + (atr * stopMult) + extraPts;
     }

   sl = NormalizeDouble(sl, _Digits);

   double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double freeze  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;

   if(MathAbs(entryPrice - sl) < minStop) return;
   if(MathAbs(entryPrice - sl) < freeze)  return;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = InpLotSize;
   req.type      = orderType;
   req.price     = (orderType == ORDER_TYPE_BUY) ? ask : bid;
   req.sl        = sl;
   req.tp        = 0.0;
   req.magic     = InpMagicNumber;
   req.deviation = 10;
   req.comment   = "MRE_Entry";

   if(!OrderSend(req, res) || res.retcode != TRADE_RETCODE_DONE)
      return;

   if(PositionSelect(_Symbol))
      g_positionTicket = PositionGetInteger(POSITION_TICKET);
   else
      return;

   g_inPosition   = true;
   g_positionType = (int)orderType;
   g_entryPrice   = entryPrice;
   g_initialSL    = sl;
   g_currentSL    = sl;
   g_consecLosses = 0;

   DrawInitialSL(sl);
  }

//=============================================================================
// MODULE 2 — STOP MANAGEMENT
//=============================================================================

void StopManagement_Update()
  {
   if(!g_inPosition) return;
   if(!PositionSelectByTicket(g_positionTicket)) return;

   double close1 = iClose(_Symbol, InpTimeframe, 1);
   double atr    = GetATR(1);
   double newSL  = 0.0;

   if(g_positionType == POSITION_TYPE_BUY)
     {
      newSL = NormalizeDouble(close1 - (atr * InpTrailATRMult), _Digits);
      if(newSL > g_currentSL)
        {
         UpdatePositionSL(newSL);
         g_currentSL = newSL;
         DrawTrailSL(newSL);
        }
     }
   else if(g_positionType == POSITION_TYPE_SELL)
     {
      newSL = NormalizeDouble(close1 + (atr * InpTrailATRMult), _Digits);
      if(newSL < g_currentSL || g_currentSL == 0.0)
        {
         UpdatePositionSL(newSL);
         g_currentSL = newSL;
         DrawTrailSL(newSL);
        }
     }

   TakeManagement_Check();
  }

void UpdatePositionSL(const double newSL)
  {
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action   = TRADE_ACTION_SLTP;
   req.symbol   = _Symbol;
   req.position = g_positionTicket;
   req.sl       = newSL;
   req.tp       = 0.0;

   OrderSend(req, res);
  }

//=============================================================================
// MODULE 3 — TAKE MANAGEMENT (KAMA SLOPE INVERSION)
//=============================================================================

void TakeManagement_Check()
  {
   if(!g_inPosition) return;

   double kama1 = GetKAMAVal(1);
   double kama2 = GetKAMAVal(2);

   if(kama1 == 0.0 || kama2 == 0.0) return;

   bool closePosition = false;

   if(g_positionType == POSITION_TYPE_BUY)
     {
      if(kama1 < kama2)
         closePosition = true;
     }
   else if(g_positionType == POSITION_TYPE_SELL)
     {
      if(kama1 > kama2)
         closePosition = true;
     }

   if(closePosition)
      ClosePosition();
  }

void ClosePosition()
  {
   if(!PositionSelectByTicket(g_positionTicket)) return;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = _Symbol;
   req.volume    = PositionGetDouble(POSITION_VOLUME);
   req.position  = g_positionTicket;
   req.magic     = InpMagicNumber;
   req.deviation = 10;
   req.comment   = "MRE_KAMAExit";

   if(g_positionType == POSITION_TYPE_BUY)
     {
      req.type  = ORDER_TYPE_SELL;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
     }
   else
     {
      req.type  = ORDER_TYPE_BUY;
      req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
     }

   if(!OrderSend(req, res) || res.retcode != TRADE_RETCODE_DONE)
      return;

   DrawKAMAExit(iTime(_Symbol, InpTimeframe, 1), iClose(_Symbol, InpTimeframe, 1));

   g_inPosition     = false;
   g_positionType   = -1;
   g_positionTicket = 0;
   g_currentSL      = 0.0;
   g_initialSL      = 0.0;
   g_entryPrice     = 0.0;
   g_consecLosses   = 0;
   g_entryState     = STATE_IDLE;
  }

//=============================================================================
// VISUALIZATION
//=============================================================================

void DrawInitialSL(const double sl)
  {
   string   name = g_prefix + "InitSL";
   datetime t1   = iTime(_Symbol, InpTimeframe, 1);
   datetime t2   = iTime(_Symbol, InpTimeframe, 0);

   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_TREND, 0, t1, sl, t2, sl);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clrOrange);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      2);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString (0, name, OBJPROP_TEXT,       "Initial SL");
  }

void DrawTrailSL(const double sl)
  {
   string   name = g_prefix + "TrailSL";
   datetime t1   = iTime(_Symbol, InpTimeframe, 1);
   datetime t2   = iTime(_Symbol, InpTimeframe, 0);

   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_TREND, 0, t1, sl, t2, sl);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clrDeepSkyBlue);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString (0, name, OBJPROP_TEXT,       "ATR SL");
  }

void DrawKAMAExit(const datetime t, const double price)
  {
   static int exitCount = 0;
   exitCount++;
   string name = g_prefix + "KAMAExit_" + (string)exitCount;

   ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE,  251);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clrMagenta);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      2);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString (0, name, OBJPROP_TEXT,       "KAMA Regime Exit");
  }
//+------------------------------------------------------------------+
