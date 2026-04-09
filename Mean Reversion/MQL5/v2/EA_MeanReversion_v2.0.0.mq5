//+------------------------------------------------------------------+
//|                                      EA_MeanReversion_v2.0.0.mq5 |
//|               Structured Mean Reversion with Return Confirmation |
//+------------------------------------------------------------------+
#property copyright "Daniel Pereira"
#property link      ""
#property version   "2.00"
#property strict

//=============================================================================
// INPUT PARAMETERS
//=============================================================================

//--- RSI
input group "=== RSI ==="
input int    InpRSIPeriod       = 14;    // RSI Period
input double InpRSIOverbought   = 75.0;  // RSI Overbought Level
input double InpRSIOversold     = 25.0;  // RSI Oversold Level

//--- Keltner Channel
input group "=== Keltner Channel ==="
input int    InpKeltnerEMAPeriod = 21;   // Keltner EMA Period
input int    InpKeltnerATRPeriod = 7;   // Keltner ATR Period
input double InpKeltnerATRMult   = 2.5;  // Keltner ATR Multiplier

//--- KAMA
input group "=== KAMA ==="
input int    InpKAMAPeriod      = 21;    // KAMA Period
input int    InpKAMAFast        = 3;     // KAMA Fast Period
input int    InpKAMASlow        = 30;    // KAMA Slow Period
input double InpKAMAPower       = 2.0;   // KAMA Smooth Power
input int    InpKAMAFilter      = 50;    // KAMA Filter
input int    InpKAMAFilterPer   = 4;     // KAMA Filter Period
input double InpKAMAFilterDiff  = 50.0;  // KAMA Filter Difference

//--- ATR Stop
input group "=== Stop Management ==="
input int    InpATRStopPeriod   = 14;    // ATR Period (Stop)
input double InpStopATRMult     = 1.5;   // Stop ATR Multiplier
input double InpExtraPoints     = 10.0;  // Extra Points (stop buffer)
input double InpTrailATRMult    = 1.5;   // Trailing ATR Multiplier

//--- ATR Volatility Filter
input group "=== Volatility Filter ==="
input int    InpATRFilterPeriod = 14;    // ATR Filter Period (for average)
input double InpATRFilterMult   = 1.1;   // ATR Filter Multiplier (min ATR ratio)

//--- Time Filter
input group "=== Time Filter ==="
input int    InpStartHour       = 8;     // Trading Start Hour (UTC)
input int    InpEndHour         = 17;    // Trading End Hour (UTC)
input bool   InpBlockAsian      = true;  // Block Asian Session

//--- Risk / Trade Control
input group "=== Risk Controls ==="
input double InpLotSize         = 1.0;   // Lot Size
input int    InpMagicNumber     = 20250101; // Magic Number
input int    InpCooldownCandles = 3;     // Cooldown Candles After Stop
input int    InpMaxConsecLoss   = 0;     // Max Consecutive Losses (0=disabled)

//=============================================================================
// INTERNAL STATE
//=============================================================================

enum EntryState
  {
   STATE_IDLE              = 0,
   STATE_OVERSOLD_CONFIRMED = 1,
   STATE_OVERBOUGHT_CONFIRMED = 2
  };

//--- State Machine
EntryState g_entryState         = STATE_IDLE;

//--- Position context
bool       g_inPosition         = false;
int        g_positionType       = -1; // POSITION_TYPE_BUY or POSITION_TYPE_SELL
double     g_entryPrice         = 0.0;
double     g_currentSL          = 0.0;
double     g_initialSL          = 0.0;
ulong      g_positionTicket     = 0;

//--- Cooldown
int        g_cooldownCount      = 0;
datetime   g_lastBarTime        = 0;

//--- Consecutive loss tracking
int        g_consecLosses       = 0;
bool       g_tradingLocked      = false;

//--- KAMA previous color state
int        g_prevKamaColor      = -1; // -1=uninit, 0=gray, 1=red, 2=green

//--- Indicator handles
int        h_RSI                = INVALID_HANDLE;
int        h_KeltnerEMA         = INVALID_HANDLE;
int        h_KeltnerATR         = INVALID_HANDLE;
int        h_ATRStop            = INVALID_HANDLE;
int        h_ATRFilter          = INVALID_HANDLE;

//--- Object prefix
string     g_prefix             = "MRE_";

//=============================================================================
// EMBEDDED KAMA CALCULATION (from mladen source — no external handle)
//=============================================================================

#define KAMA_INSTANCES      1
#define KAMA_INSTANCE_SIZE  3
#define KAMA_DIFF           0
#define KAMA_VAL            1
#define KAMA_PRICE          2

double g_kamaWork[][KAMA_INSTANCES * KAMA_INSTANCE_SIZE];
double g_kamaVal[];
double g_kamaColor[]; // 0=gray, 1=red, 2=green
double g_kamaAma[];
int    g_kamaBars = 0;

//=============================================================================
// EMBEDDED KELTNER CHANNEL (inline, no external indicator file needed)
//=============================================================================

double g_keltnerUpper[];
double g_keltnerLower[];
double g_keltnerMid[];

//=============================================================================
// EMBEDDED RSI CALCULATION
//=============================================================================

double g_rsiBuffer[];
double g_rsiPos[];
double g_rsiNeg[];

//=============================================================================
// EMBEDDED ATR CALCULATION
//=============================================================================

double g_atrStopBuffer[];
double g_atrStopTR[];
double g_atrFilterBuffer[];
double g_atrFilterTR[];

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_entryState    = STATE_IDLE;
   g_inPosition    = false;
   g_positionType  = -1;
   g_currentSL     = 0.0;
   g_initialSL     = 0.0;
   g_positionTicket= 0;
   g_cooldownCount = 0;
   g_lastBarTime   = 0;
   g_consecLosses  = 0;
   g_tradingLocked = false;
   g_prevKamaColor = -1;
   g_kamaBars      = 0;

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, g_prefix);
   ChartRedraw(0);

   ArrayFree(g_kamaWork);
   ArrayFree(g_kamaVal);
   ArrayFree(g_kamaColor);
   ArrayFree(g_kamaAma);
   ArrayFree(g_keltnerUpper);
   ArrayFree(g_keltnerLower);
   ArrayFree(g_keltnerMid);
   ArrayFree(g_rsiBuffer);
   ArrayFree(g_rsiPos);
   ArrayFree(g_rsiNeg);
   ArrayFree(g_atrStopBuffer);
   ArrayFree(g_atrStopTR);
   ArrayFree(g_atrFilterBuffer);
   ArrayFree(g_atrFilterTR);
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   int bars = Bars(_Symbol, _Period);
   if(bars < MathMax(MathMax(InpRSIPeriod, InpKeltnerEMAPeriod + InpKeltnerATRPeriod), InpKAMAPeriod) + 10)
      return;

   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   bool     isNewBar       = (currentBarTime != g_lastBarTime);

   if(isNewBar)
      g_lastBarTime = currentBarTime;

   //--- Recalculate all indicators on new bar
   if(isNewBar)
     {
      RecalculateAll(bars);
     }

   if(!isNewBar)
      return;

   //--- Confirm position still exists
   SyncPositionState();

   //--- STOP MANAGEMENT (runs before entry logic)
   if(g_inPosition)
     {
      StopManagement_Update(bars);
      return; // one module at a time per tick
     }

   //--- TAKE MANAGEMENT
   // (only when in position — handled inside TakeManagement_Check)

   //--- ENTRY ENGINE
   if(!g_inPosition && !g_tradingLocked)
     {
      if(!IsWithinTradingHours())
         return;

      if(g_cooldownCount > 0)
        {
         g_cooldownCount--;
         return;
        }

      EntryEngine_Process(bars);
     }

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| INDICATOR RECALCULATION                                          |
//+------------------------------------------------------------------+
void RecalculateAll(const int bars)
  {
   EnsureArraySizes(bars);
   CalcRSI(bars);
   CalcKeltner(bars);
   CalcATR(g_atrStopBuffer, g_atrStopTR, InpATRStopPeriod, bars);
   CalcATR(g_atrFilterBuffer, g_atrFilterTR, InpATRFilterPeriod, bars);
   CalcKAMA(bars);
  }

//+------------------------------------------------------------------+
//| Ensure all arrays are sized correctly                            |
//+------------------------------------------------------------------+
void EnsureArraySizes(const int bars)
  {
   if(ArraySize(g_rsiBuffer) != bars)
     {
      ArrayResize(g_rsiBuffer,       bars);
      ArrayResize(g_rsiPos,          bars);
      ArrayResize(g_rsiNeg,          bars);
      ArrayInitialize(g_rsiBuffer,   0.0);
      ArrayInitialize(g_rsiPos,      0.0);
      ArrayInitialize(g_rsiNeg,      0.0);
     }

   if(ArraySize(g_keltnerUpper) != bars)
     {
      ArrayResize(g_keltnerUpper, bars);
      ArrayResize(g_keltnerLower, bars);
      ArrayResize(g_keltnerMid,   bars);
      ArrayInitialize(g_keltnerUpper, 0.0);
      ArrayInitialize(g_keltnerLower, 0.0);
      ArrayInitialize(g_keltnerMid,   0.0);
     }

   if(ArraySize(g_atrStopBuffer) != bars)
     {
      ArrayResize(g_atrStopBuffer,  bars);
      ArrayResize(g_atrStopTR,      bars);
      ArrayInitialize(g_atrStopBuffer, 0.0);
      ArrayInitialize(g_atrStopTR,     0.0);
     }

   if(ArraySize(g_atrFilterBuffer) != bars)
     {
      ArrayResize(g_atrFilterBuffer, bars);
      ArrayResize(g_atrFilterTR,     bars);
      ArrayInitialize(g_atrFilterBuffer, 0.0);
      ArrayInitialize(g_atrFilterTR,     0.0);
     }

   if(ArraySize(g_kamaVal) != bars)
     {
      ArrayResize(g_kamaVal,   bars);
      ArrayResize(g_kamaColor, bars);
      ArrayResize(g_kamaAma,   bars);
      ArrayInitialize(g_kamaVal,   0.0);
      ArrayInitialize(g_kamaColor, 0.0);
      ArrayInitialize(g_kamaAma,   0.0);
      g_kamaBars = 0; // force full recalc
     }
  }

//+------------------------------------------------------------------+
//| RSI Calculation (embedded)                                       |
//+------------------------------------------------------------------+
void CalcRSI(const int bars)
  {
   double close[];
   ArrayResize(close, bars);
   for(int i = 0; i < bars; i++)
      close[i] = iClose(_Symbol, _Period, bars - 1 - i);

   int period = InpRSIPeriod;
   if(bars <= period) return;

   g_rsiBuffer[0] = 0.0;
   g_rsiPos[0]    = 0.0;
   g_rsiNeg[0]    = 0.0;

   double sum_pos = 0.0, sum_neg = 0.0;
   for(int i = 1; i <= period; i++)
     {
      g_rsiBuffer[i] = 0.0;
      g_rsiPos[i]    = 0.0;
      g_rsiNeg[i]    = 0.0;
      double diff = close[i] - close[i - 1];
      sum_pos += (diff > 0 ? diff : 0.0);
      sum_neg += (diff < 0 ? -diff : 0.0);
     }
   g_rsiPos[period] = sum_pos / period;
   g_rsiNeg[period] = sum_neg / period;
   if(g_rsiNeg[period] != 0.0)
      g_rsiBuffer[period] = 100.0 - (100.0 / (1.0 + g_rsiPos[period] / g_rsiNeg[period]));
   else
      g_rsiBuffer[period] = (g_rsiPos[period] != 0.0) ? 100.0 : 50.0;

   for(int i = period + 1; i < bars; i++)
     {
      double diff = close[i] - close[i - 1];
      g_rsiPos[i] = (g_rsiPos[i-1] * (period - 1) + (diff > 0.0 ? diff : 0.0)) / period;
      g_rsiNeg[i] = (g_rsiNeg[i-1] * (period - 1) + (diff < 0.0 ? -diff : 0.0)) / period;
      if(g_rsiNeg[i] != 0.0)
         g_rsiBuffer[i] = 100.0 - 100.0 / (1.0 + g_rsiPos[i] / g_rsiNeg[i]);
      else
         g_rsiBuffer[i] = (g_rsiPos[i] != 0.0) ? 100.0 : 50.0;
     }
  }

//+------------------------------------------------------------------+
//| Keltner Channel Calculation (embedded)                           |
//+------------------------------------------------------------------+
void CalcKeltner(const int bars)
  {
   int emaPeriod = InpKeltnerEMAPeriod;
   int atrPeriod = InpKeltnerATRPeriod;
   double mult   = InpKeltnerATRMult;
   int start     = MathMax(emaPeriod, atrPeriod) + 1;

   //--- EMA of close
   double ema[];
   ArrayResize(ema, bars);
   ArrayInitialize(ema, 0.0);

   double k = 2.0 / (emaPeriod + 1);
   ema[0] = iClose(_Symbol, _Period, bars - 1);
   for(int i = 1; i < bars; i++)
      ema[i] = iClose(_Symbol, _Period, bars - 1 - i) * k + ema[i-1] * (1.0 - k);

   //--- ATR
   double atr[];
   ArrayResize(atr, bars);
   ArrayInitialize(atr, 0.0);
   CalcATRInline(atr, atrPeriod, bars);

   for(int i = start; i < bars; i++)
     {
      g_keltnerMid[i]   = ema[i];
      g_keltnerUpper[i] = ema[i] + mult * atr[i];
      g_keltnerLower[i] = ema[i] - mult * atr[i];
     }
  }

//+------------------------------------------------------------------+
//| ATR inline (for Keltner internal use)                            |
//+------------------------------------------------------------------+
void CalcATRInline(double &atr[], const int period, const int bars)
  {
   double tr[];
   ArrayResize(tr, bars);
   tr[0] = 0.0;
   for(int i = 1; i < bars; i++)
     {
      double hi   = iHigh (_Symbol, _Period, bars - 1 - i);
      double lo   = iLow  (_Symbol, _Period, bars - 1 - i);
      double pc   = iClose(_Symbol, _Period, bars - 1 - (i-1));
      tr[i] = MathMax(hi, pc) - MathMin(lo, pc);
     }

   double first = 0.0;
   for(int i = 1; i <= period && i < bars; i++)
      first += tr[i];
   if(period > 0 && bars > period)
     {
      atr[period] = first / period;
      for(int i = period + 1; i < bars; i++)
         atr[i] = atr[i-1] + (tr[i] - tr[i - period]) / period;
     }
  }

//+------------------------------------------------------------------+
//| ATR Calculation (generic, for stop / filter arrays)              |
//+------------------------------------------------------------------+
void CalcATR(double &buf[], double &trBuf[], const int period, const int bars)
  {
   if(ArraySize(buf) != bars) return;

   trBuf[0] = 0.0;
   buf[0]   = 0.0;

   for(int i = 1; i < bars; i++)
     {
      double hi = iHigh (_Symbol, _Period, bars - 1 - i);
      double lo = iLow  (_Symbol, _Period, bars - 1 - i);
      double pc = iClose(_Symbol, _Period, bars - 1 - (i-1));
      trBuf[i] = MathMax(hi, pc) - MathMin(lo, pc);
     }

   double first = 0.0;
   for(int i = 1; i <= period && i < bars; i++)
      first += trBuf[i];

   if(period > 0 && bars > period)
     {
      buf[period] = first / period;
      for(int i = period + 1; i < bars; i++)
         buf[i] = buf[i-1] + (trBuf[i] - trBuf[i - period]) / period;
     }
  }

//+------------------------------------------------------------------+
//| KAMA Calculation (embedded from mladen)                          |
//+------------------------------------------------------------------+
void CalcKAMA(const int bars)
  {
   if(g_kamaBars == bars) return; // already current
   g_kamaBars = bars;

   if(ArrayRange(g_kamaWork, 0) != bars)
      ArrayResize(g_kamaWork, bars);

   int    period   = InpKAMAPeriod;
   double fastEnd  = 2.0 / (InpKAMAFast + 1.0);
   double slowEnd  = 2.0 / (InpKAMASlow + 1.0);
   double power    = InpKAMAPower;

   for(int i = 0; i < bars; i++)
     {
      double price = iClose(_Symbol, _Period, bars - 1 - i);
      g_kamaWork[i][KAMA_PRICE] = price;
      g_kamaWork[i][KAMA_DIFF]  = (i > 0) ? MathAbs(price - g_kamaWork[i-1][KAMA_PRICE]) : 0.0;

      double signal = (i >= period) ? MathAbs(price - g_kamaWork[i - period][KAMA_PRICE]) : 0.0;
      double noise  = 0.0;
      for(int k = 0; k < period && i - k >= 0; k++)
         noise += g_kamaWork[i - k][KAMA_DIFF];

      double efratio = (noise != 0.0) ? signal / noise : 1.0;
      double smooth  = MathPow(efratio * (fastEnd - slowEnd) + slowEnd, power);
      g_kamaWork[i][KAMA_VAL] = (i > 0) ? g_kamaWork[i-1][KAMA_VAL] + smooth * (price - g_kamaWork[i-1][KAMA_VAL]) : price;
      g_kamaAma[i] = g_kamaWork[i][KAMA_VAL];
      g_kamaVal[i] = g_kamaAma[i];
     }

   //--- Apply filter
   if(InpKAMAFilter > 0)
     {
      for(int i = 1; i < bars; i++)
        {
         double sAmaDiff = 0.0;
         for(int k = 0; k < InpKAMASlow && (i - k - 1) >= 0; k++)
            sAmaDiff += MathAbs(g_kamaAma[i-k] - g_kamaAma[i-k-1]);

         double cAmaDiff    = g_kamaAma[i] - g_kamaAma[i-1];
         double aAmaDiff    = MathAbs(cAmaDiff);
         double filterValue = NormalizeDouble(InpKAMAFilter * sAmaDiff / (100.0 * InpKAMASlow), _Digits);

         int _start = MathMax(i - InpKAMAFilterPer, 0);

         if(cAmaDiff > 0)
           {
            double maxHigh = 0.0;
            for(int k = _start; k < _start + InpKAMAFilterPer && k < bars; k++)
               maxHigh = MathMax(maxHigh, iHigh(_Symbol, _Period, bars - 1 - k));
            double hiBar = iHigh(_Symbol, _Period, bars - 1 - i);
            if(cAmaDiff < filterValue && hiBar <= (maxHigh + InpKAMAFilterDiff * _Point))
               g_kamaVal[i] = (i > 0) ? g_kamaVal[i-1] : g_kamaAma[i];
           }
         if(cAmaDiff < 0)
           {
            double minLow = DBL_MAX;
            for(int k = _start; k < _start + InpKAMAFilterPer && k < bars; k++)
               minLow = MathMin(minLow, iLow(_Symbol, _Period, bars - 1 - k));
            double loBar = iLow(_Symbol, _Period, bars - 1 - i);
            if(aAmaDiff < filterValue && loBar >= (minLow - InpKAMAFilterDiff * _Point))
               g_kamaVal[i] = (i > 0) ? g_kamaVal[i-1] : g_kamaAma[i];
           }
        }
     }

   //--- Color: 2=green (rising), 1=red (falling), 0=gray (flat)
   g_kamaColor[0] = 0;
   for(int i = 1; i < bars; i++)
     {
      if(g_kamaVal[i] > g_kamaVal[i-1])
         g_kamaColor[i] = 2.0;
      else if(g_kamaVal[i] < g_kamaVal[i-1])
         g_kamaColor[i] = 1.0;
      else
         g_kamaColor[i] = g_kamaColor[i-1];
     }
  }

//+------------------------------------------------------------------+
//| UTILITY — bar-indexed accessors (0 = current closed bar)         |
//+------------------------------------------------------------------+
double GetRSI(const int shift, const int bars)
  {
   int idx = bars - 1 - shift;
   if(idx < 0 || idx >= bars) return 50.0;
   return g_rsiBuffer[idx];
  }

double GetKeltnerUpper(const int shift, const int bars)
  {
   int idx = bars - 1 - shift;
   if(idx < 0 || idx >= bars) return 0.0;
   return g_keltnerUpper[idx];
  }

double GetKeltnerLower(const int shift, const int bars)
  {
   int idx = bars - 1 - shift;
   if(idx < 0 || idx >= bars) return 0.0;
   return g_keltnerLower[idx];
  }

double GetATRStop(const int shift, const int bars)
  {
   int idx = bars - 1 - shift;
   if(idx < 0 || idx >= bars) return 0.0;
   return g_atrStopBuffer[idx];
  }

double GetATRFilter(const int shift, const int bars)
  {
   int idx = bars - 1 - shift;
   if(idx < 0 || idx >= bars) return 0.0;
   return g_atrFilterBuffer[idx];
  }

double GetKAMAVal(const int shift, const int bars)
  {
   int idx = bars - 1 - shift;
   if(idx < 0 || idx >= bars) return 0.0;
   return g_kamaVal[idx];
  }

int GetKAMAColor(const int shift, const int bars)
  {
   int idx = bars - 1 - shift;
   if(idx < 0 || idx >= bars) return 0;
   return (int)g_kamaColor[idx];
  }

//+------------------------------------------------------------------+
//| UTILITY — ATR average over N bars                                |
//+------------------------------------------------------------------+
double GetATRAverage(const int bars)
  {
   int count = InpATRFilterPeriod;
   double sum = 0.0;
   for(int i = 1; i <= count; i++)
      sum += GetATRFilter(i, bars);
   return (count > 0) ? sum / count : 0.0;
  }

//+------------------------------------------------------------------+
//| TIME FILTER                                                       |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hour = dt.hour;

   if(InpBlockAsian && (hour < 7))
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
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
        {
         g_inPosition   = false;
         g_positionType = -1;
         g_positionTicket = 0;
        }
     }
   else
     {
      // Position closed — check if it was a stop-out
      // We determine this heuristically: SL was hit
      g_inPosition   = false;
      g_positionType = -1;
      g_positionTicket = 0;

      // Assume stop hit — trigger cooldown
      g_cooldownCount = InpCooldownCandles;

      // Consecutive loss tracking
      g_consecLosses++;
      if(InpMaxConsecLoss > 0 && g_consecLosses >= InpMaxConsecLoss)
         g_tradingLocked = true;

      g_entryState = STATE_IDLE;
      g_prevKamaColor = -1;
     }
  }

//=============================================================================
// MODULE 1 — ENTRY ENGINE
//=============================================================================

void EntryEngine_Process(const int bars)
  {
   double rsi1   = GetRSI(1, bars); // prev closed bar
   double close1 = iClose(_Symbol, _Period, 1);
   double kLow1  = GetKeltnerLower(1, bars);
   double kUpp1  = GetKeltnerUpper(1, bars);

   //--- Volatility filter
   double atrCurr = GetATRStop(1, bars);
   double atrAvg  = GetATRAverage(bars);
   if(atrAvg > 0.0 && atrCurr < atrAvg * InpATRFilterMult)
      return;

   //--- STATE MACHINE

   // STATE 1 — Detect extreme (no entry)
   if(g_entryState == STATE_IDLE)
     {
      // Oversold: RSI broke below oversold AND close below lower keltner
      if(rsi1 < InpRSIOversold && close1 < kLow1)
        {
         g_entryState = STATE_OVERSOLD_CONFIRMED;
         return;
        }
      // Overbought: RSI broke above overbought AND close above upper keltner
      if(rsi1 > InpRSIOverbought && close1 > kUpp1)
        {
         g_entryState = STATE_OVERBOUGHT_CONFIRMED;
         return;
        }
     }

   // STATE 2 — Return from extreme (real trigger)
   if(g_entryState == STATE_OVERSOLD_CONFIRMED)
     {
      // BUY: RSI was < oversold, now touches oversold, current candle closes back below oversold
      // Price still outside or very close to lower keltner band
      double rsi2   = GetRSI(2, bars);
      double close2 = iClose(_Symbol, _Period, 2);

      // Confirm previous state was truly oversold
      if(rsi2 < InpRSIOversold)
        {
         // RSI rose back to touch oversold level and closes back below
         if(rsi1 >= InpRSIOversold && rsi1 < InpRSIOversold + 5.0)
           {
            if(close1 <= kLow1 * (1.0 + 0.002)) // close still near/below lower band
              {
               ExecuteEntry(ORDER_TYPE_BUY, bars);
               g_entryState = STATE_IDLE;
              }
           }
         // State decay: if RSI climbs far from extreme, reset
         if(rsi1 > InpRSIOversold + 10.0)
            g_entryState = STATE_IDLE;
        }
     }

   if(g_entryState == STATE_OVERBOUGHT_CONFIRMED)
     {
      // SELL: RSI was > overbought, now falls back to touch overbought, closes back above
      double rsi2 = GetRSI(2, bars);

      if(rsi2 > InpRSIOverbought)
        {
         // RSI fell back to touch overbought level
         if(rsi1 <= InpRSIOverbought && rsi1 > InpRSIOverbought - 5.0)
           {
            double close1_ = iClose(_Symbol, _Period, 1);
            double kUpp1_  = GetKeltnerUpper(1, bars);
            if(close1_ >= kUpp1_ * (1.0 - 0.002)) // close still near/above upper band
              {
               ExecuteEntry(ORDER_TYPE_SELL, bars);
               g_entryState = STATE_IDLE;
              }
           }
         if(rsi1 < InpRSIOverbought - 10.0)
            g_entryState = STATE_IDLE;
        }
     }
  }

//+------------------------------------------------------------------+
//| Execute Entry Order                                              |
//+------------------------------------------------------------------+
void ExecuteEntry(const ENUM_ORDER_TYPE orderType, const int bars)
  {
   double atr       = GetATRStop(1, bars);
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double extraPts  = InpExtraPoints * _Point;
   double sl        = 0.0;
   double entryPrice= 0.0;

   if(orderType == ORDER_TYPE_BUY)
     {
      entryPrice = ask;
      sl         = entryPrice - (atr * InpStopATRMult) - extraPts;
     }
   else
     {
      entryPrice = bid;
      sl         = entryPrice + (atr * InpStopATRMult) + extraPts;
     }

   sl = NormalizeDouble(sl, _Digits);

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

   if(OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
     {
      g_inPosition     = true;
      g_positionType   = (int)orderType;
      g_positionTicket = res.deal;
      g_entryPrice     = entryPrice;
      g_initialSL      = sl;
      g_currentSL      = sl;
      g_consecLosses   = 0; // reset on successful entry

      // Find actual position ticket
      if(PositionSelect(_Symbol))
         g_positionTicket = PositionGetInteger(POSITION_TICKET);

      DrawInitialSL(sl);
      g_prevKamaColor = -1; // reset KAMA tracking
     }
  }

//=============================================================================
// MODULE 2 — STOP MANAGEMENT
//=============================================================================

void StopManagement_Update(const int bars)
  {
   if(!g_inPosition) return;
   if(!PositionSelectByTicket(g_positionTicket)) return;

   double close1  = iClose(_Symbol, _Period, 1);
   double atr     = GetATRStop(1, bars);
   double newSL   = 0.0;

   if(g_positionType == POSITION_TYPE_BUY)
     {
      newSL = close1 - (atr * InpTrailATRMult);
      newSL = NormalizeDouble(newSL, _Digits);
      // Only move in favor
      if(newSL > g_currentSL)
        {
         UpdatePositionSL(newSL);
         g_currentSL = newSL;
         DrawTrailSL(newSL);
        }
     }
   else if(g_positionType == POSITION_TYPE_SELL)
     {
      newSL = close1 + (atr * InpTrailATRMult);
      newSL = NormalizeDouble(newSL, _Digits);
      // Only move in favor (for sell, SL moves down)
      if(newSL < g_currentSL || g_currentSL == 0.0)
        {
         UpdatePositionSL(newSL);
         g_currentSL = newSL;
         DrawTrailSL(newSL);
        }
     }

   //--- Also check KAMA exit
   TakeManagement_Check(bars);
  }

//+------------------------------------------------------------------+
//| Update Position SL via trade request                             |
//+------------------------------------------------------------------+
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
// MODULE 3 — TAKE MANAGEMENT (KAMA COLOR TRANSITION)
//=============================================================================

void TakeManagement_Check(const int bars)
  {
   if(!g_inPosition) return;

   int currColor = GetKAMAColor(1, bars); // current closed bar
   int prevColor = GetKAMAColor(2, bars); // previous closed bar

   if(g_prevKamaColor == -1)
     {
      g_prevKamaColor = prevColor;
      return;
     }

   bool closePosition = false;

   if(g_positionType == POSITION_TYPE_BUY)
     {
      // Exit on GREEN → RED transition
      if(prevColor == 2 && currColor == 1)
         closePosition = true;
     }
   else if(g_positionType == POSITION_TYPE_SELL)
     {
      // Exit on RED → GREEN transition
      if(prevColor == 1 && currColor == 2)
         closePosition = true;
     }

   g_prevKamaColor = currColor;

   if(closePosition)
      ClosePosition(bars);
  }

//+------------------------------------------------------------------+
//| Close Position                                                   |
//+------------------------------------------------------------------+
void ClosePosition(const int bars)
  {
   if(!PositionSelectByTicket(g_positionTicket)) return;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

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
      req.price = bid;
     }
   else
     {
      req.type  = ORDER_TYPE_BUY;
      req.price = ask;
     }

   if(OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
     {
      DrawKAMAExit(iTime(_Symbol, _Period, 1), iClose(_Symbol, _Period, 1));

      g_inPosition     = false;
      g_positionType   = -1;
      g_positionTicket = 0;
      g_currentSL      = 0.0;
      g_initialSL      = 0.0;
      g_entryPrice     = 0.0;
      g_prevKamaColor  = -1;
      g_consecLosses   = 0; // KAMA exit = clean exit, not a loss
      g_entryState     = STATE_IDLE;
     }
  }

//=============================================================================
// VISUALIZATION
//=============================================================================

void DrawInitialSL(const double sl)
  {
   string name = g_prefix + "InitSL";
   datetime t1 = iTime(_Symbol, _Period, 1);
   datetime t2 = iTime(_Symbol, _Period, 0);

   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_TREND, 0, t1, sl, t2, sl);
   ObjectSetInteger(0, name, OBJPROP_COLOR,    clrOrange);
   ObjectSetInteger(0, name, OBJPROP_STYLE,    STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,    2);
   ObjectSetInteger(0, name, OBJPROP_BACK,     false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString (0, name, OBJPROP_TEXT,     "Initial SL");
  }

void DrawTrailSL(const double sl)
  {
   string name = g_prefix + "TrailSL";
   datetime t1 = iTime(_Symbol, _Period, 1);
   datetime t2 = iTime(_Symbol, _Period, 0);

   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_TREND, 0, t1, sl, t2, sl);
   ObjectSetInteger(0, name, OBJPROP_COLOR,    clrDeepSkyBlue);
   ObjectSetInteger(0, name, OBJPROP_STYLE,    STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,    1);
   ObjectSetInteger(0, name, OBJPROP_BACK,     false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString (0, name, OBJPROP_TEXT,     "ATR SL");
  }

void DrawKAMAExit(const datetime t, const double price)
  {
   static int exitCount = 0;
   exitCount++;
   string name = g_prefix + "KAMAExit_" + (string)exitCount;

   ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 251);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clrMagenta);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     2);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   ObjectSetString (0, name, OBJPROP_TEXT,      "KAMA Regime Exit");
  }
//+------------------------------------------------------------------+