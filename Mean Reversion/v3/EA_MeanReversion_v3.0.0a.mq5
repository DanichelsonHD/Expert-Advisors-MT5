//+------------------------------------------------------------------+
//|                                     EA_MeanReversion_v3.0.0a.mq5 |
//|               Structured Mean Reversion with Return Confirmation |
//|                                       ETAPA 1 — Indicator Engine |
//+------------------------------------------------------------------+
#property copyright "Daniel Pereira"
#property link      ""
#property version   "3.00a"
#property strict

//=============================================================================
// INPUTS — INDICATORS
//=============================================================================

input group "=== Time Filters ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H1;   // Trading Timeframe (M30 or H1)
input int    InpStartHour          = 8;           // Trading Start Hour (UTC)
input int    InpEndHour            = 17;          // Trading End Hour (UTC)

input group "=== RSI ==="
input int    InpRSIPeriod          = 14;          // RSI Period
input double InpRSIOverbought      = 75.0;        // RSI Overbought
input double InpRSIOversold        = 25.0;        // RSI Oversold

input group "=== Keltner Channel ==="
input int    InpKCPeriod           = 21;          // KC Period
input double InpKCMultiplier       = 2.5;         // KC Multiplier

input group "=== ATR ==="
input int    InpATRPeriod          = 14;          // ATR Period

input group "=== KAMA ==="
input int    InpKAMAPeriod         = 7;           // KAMA Period
input int    InpKAMAFast           = 3;           // KAMA Fast
input int    InpKAMASlow           = 30;          // KAMA Slow

//=============================================================================
// GLOBAL INDICATOR BUFFERS
//=============================================================================

MqlRates g_rates[];

double g_rsiBuffer[];
double g_atrBuffer[];
double g_kcUpper[];
double g_kcLower[];
double g_kamaBuffer[];

//=============================================================================
// OnInit / OnDeinit / OnTick
//=============================================================================

int OnInit()
  {
   ArraySetAsSeries(g_rates,     true);
   ArraySetAsSeries(g_rsiBuffer, true);
   ArraySetAsSeries(g_atrBuffer, true);
   ArraySetAsSeries(g_kcUpper,   true);
   ArraySetAsSeries(g_kcLower,   true);
   ArraySetAsSeries(g_kamaBuffer,true);

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   ArrayFree(g_rates);
   ArrayFree(g_rsiBuffer);
   ArrayFree(g_atrBuffer);
   ArrayFree(g_kcUpper);
   ArrayFree(g_kcLower);
   ArrayFree(g_kamaBuffer);
  }

void OnTick()
  {
   static datetime s_lastBarTime = 0;
   datetime        currentBarTime = iTime(_Symbol, _Period, 0);

   if(currentBarTime == s_lastBarTime)
      return;

   s_lastBarTime = currentBarTime;

   CalcIndicators();

   // TODO: State machine    (Etapa 2)
   // TODO: Entry conditions (Etapa 2)
   // TODO: Exit conditions  (Etapa 2)
   // TODO: Cooldown logic   (Etapa 2)
   // TODO: Loss tracking    (Etapa 2)
   // TODO: OrderSend        (Etapa 3)
   // TODO: Stop management  (Etapa 3)
   // TODO: Position sync    (Etapa 3)
  }

//=============================================================================
// INDICATOR ENGINE
//=============================================================================

void CalcIndicators()
  {
   int needed = MathMax(MathMax(InpRSIPeriod, InpATRPeriod),
                        MathMax(InpKCPeriod,  InpKAMAPeriod)) + 64;

   int copied = CopyRates(_Symbol, _Period, 0, needed, g_rates);
   if(copied < needed) return;

   CalcATR(copied);
   CalcRSI(copied);
   CalcKeltner(copied);
   CalcKAMA(copied);
  }

//-----------------------------------------------------------------------------
// CalcATR
// Uses Wilder smoothing (same as MT5 native iATR).
// g_atrBuffer[0] = forming bar, [1] = last closed, [2] = previous closed.
//-----------------------------------------------------------------------------
void CalcATR(const int count)
  {
   if(ArraySize(g_atrBuffer) != count)
      ArrayResize(g_atrBuffer, count);

   // g_rates is series: [0]=newest. Forward calc needs oldest-first.
   // Work array fwd[]: fwd[0] = oldest bar, fwd[count-1] = newest bar.
   double tr[];
   double atr_fwd[];
   ArrayResize(tr,      count);
   ArrayResize(atr_fwd, count);

   int period = InpATRPeriod;

   // True Range — fwd index i corresponds to g_rates[count-1-i]
   tr[0] = 0.0;
   for(int i = 1; i < count; i++)
     {
      double hi = g_rates[count - 1 - i].high;
      double lo = g_rates[count - 1 - i].low;
      double pc = g_rates[count - 1 - (i - 1)].close;
      tr[i] = MathMax(hi, pc) - MathMin(lo, pc);
     }

   // Seed: simple average of first `period` TR values
   double seed = 0.0;
   for(int i = 1; i <= period && i < count; i++)
      seed += tr[i];

   atr_fwd[0] = 0.0;
   for(int i = 1; i < period && i < count; i++)
      atr_fwd[i] = 0.0;

   if(period < count)
     {
      atr_fwd[period] = seed / period;
      for(int i = period + 1; i < count; i++)
         atr_fwd[i] = (atr_fwd[i - 1] * (period - 1) + tr[i]) / period;
     }

   // Map fwd → series output
   for(int i = 0; i < count; i++)
      g_atrBuffer[i] = atr_fwd[count - 1 - i];
  }

//-----------------------------------------------------------------------------
// CalcRSI
// Wilder smoothing. g_rsiBuffer[1] = last closed bar.
//-----------------------------------------------------------------------------
void CalcRSI(const int count)
  {
   if(ArraySize(g_rsiBuffer) != count)
      ArrayResize(g_rsiBuffer, count);

   int period = InpRSIPeriod;
   if(count <= period) return;

   // Close prices in forward order
   double close[];
   ArrayResize(close, count);
   for(int i = 0; i < count; i++)
      close[i] = g_rates[count - 1 - i].close;

   double rsi_fwd[];
   double avg_gain[];
   double avg_loss[];
   ArrayResize(rsi_fwd,  count);
   ArrayResize(avg_gain, count);
   ArrayResize(avg_loss, count);

   // Seed averages
   double sg = 0.0, sl = 0.0;
   for(int i = 1; i <= period; i++)
     {
      double d = close[i] - close[i - 1];
      if(d > 0.0) sg += d;
      else        sl += -d;
     }
   avg_gain[period] = sg / period;
   avg_loss[period] = sl / period;

   for(int i = 0; i < period; i++)
     {
      rsi_fwd[i]  = 0.0;
      avg_gain[i] = 0.0;
      avg_loss[i] = 0.0;
     }

   if(avg_loss[period] == 0.0)
      rsi_fwd[period] = (avg_gain[period] > 0.0) ? 100.0 : 50.0;
   else
      rsi_fwd[period] = 100.0 - 100.0 / (1.0 + avg_gain[period] / avg_loss[period]);

   for(int i = period + 1; i < count; i++)
     {
      double d = close[i] - close[i - 1];
      double g = (d > 0.0) ? d : 0.0;
      double l = (d < 0.0) ? -d : 0.0;
      avg_gain[i] = (avg_gain[i - 1] * (period - 1) + g) / period;
      avg_loss[i] = (avg_loss[i - 1] * (period - 1) + l) / period;
      if(avg_loss[i] == 0.0)
         rsi_fwd[i] = (avg_gain[i] > 0.0) ? 100.0 : 50.0;
      else
         rsi_fwd[i] = 100.0 - 100.0 / (1.0 + avg_gain[i] / avg_loss[i]);
     }

   for(int i = 0; i < count; i++)
      g_rsiBuffer[i] = rsi_fwd[count - 1 - i];
  }

//-----------------------------------------------------------------------------
// CalcKeltner
// EMA(close, InpKCPeriod) ± InpKCMultiplier * ATR(InpATRPeriod)
// Shares g_atrBuffer — must run after CalcATR.
//-----------------------------------------------------------------------------
void CalcKeltner(const int count)
  {
   if(ArraySize(g_kcUpper) != count) ArrayResize(g_kcUpper, count);
   if(ArraySize(g_kcLower) != count) ArrayResize(g_kcLower, count);

   int    period = InpKCPeriod;
   double k      = 2.0 / (period + 1.0);
   int    start  = MathMax(period, InpATRPeriod) + 1;

   // EMA in forward order
   double ema_fwd[];
   ArrayResize(ema_fwd, count);

   ema_fwd[0] = g_rates[count - 1].close; // oldest bar seed
   for(int i = 1; i < count; i++)
      ema_fwd[i] = g_rates[count - 1 - i].close * k + ema_fwd[i - 1] * (1.0 - k);

   // ATR is already in series mode — convert to fwd for alignment
   double atr_fwd[];
   ArrayResize(atr_fwd, count);
   for(int i = 0; i < count; i++)
      atr_fwd[i] = g_atrBuffer[count - 1 - i];

   // Map to series output
   for(int i = 0; i < count; i++)
     {
      int fwd = count - 1 - i;
      if(fwd < start)
        {
         g_kcUpper[i] = 0.0;
         g_kcLower[i] = 0.0;
        }
      else
        {
         g_kcUpper[i] = ema_fwd[fwd] + InpKCMultiplier * atr_fwd[fwd];
         g_kcLower[i] = ema_fwd[fwd] - InpKCMultiplier * atr_fwd[fwd];
        }
     }
  }

//-----------------------------------------------------------------------------
// CalcKAMA
// Kaufman Adaptive Moving Average.
// g_kamaBuffer[1] = last closed bar.
//-----------------------------------------------------------------------------
void CalcKAMA(const int count)
  {
   if(ArraySize(g_kamaBuffer) != count)
      ArrayResize(g_kamaBuffer, count);

   int    period  = InpKAMAPeriod;
   double fastEnd = 2.0 / (InpKAMAFast + 1.0);
   double slowEnd = 2.0 / (InpKAMASlow + 1.0);

   // Close prices in forward order
   double close[];
   ArrayResize(close, count);
   for(int i = 0; i < count; i++)
      close[i] = g_rates[count - 1 - i].close;

   double kama_fwd[];
   ArrayResize(kama_fwd, count);

   kama_fwd[0] = close[0];

   for(int i = 1; i < count; i++)
     {
      if(i < period)
        {
         kama_fwd[i] = kama_fwd[i - 1];
         continue;
        }

      double signal  = MathAbs(close[i] - close[i - period]);
      double noise   = 0.0;
      for(int j = 0; j < period; j++)
         noise += MathAbs(close[i - j] - close[i - j - 1]);

      double er     = (noise != 0.0) ? signal / noise : 0.0;
      double smooth = MathPow(er * (fastEnd - slowEnd) + slowEnd, 2.0);
      kama_fwd[i]   = kama_fwd[i - 1] + smooth * (close[i] - kama_fwd[i - 1]);
     }

   for(int i = 0; i < count; i++)
      g_kamaBuffer[i] = kama_fwd[count - 1 - i];
  }

//=============================================================================
// GETTERS
//=============================================================================

double GetRSI(const int shift)
  {
   if(shift < 0 || shift >= ArraySize(g_rsiBuffer)) return 50.0;
   return g_rsiBuffer[shift];
  }

double GetATR(const int shift)
  {
   if(shift < 0 || shift >= ArraySize(g_atrBuffer)) return 0.0;
   return g_atrBuffer[shift];
  }

double GetKCUpper(const int shift)
  {
   if(shift < 0 || shift >= ArraySize(g_kcUpper)) return 0.0;
   return g_kcUpper[shift];
  }

double GetKCLower(const int shift)
  {
   if(shift < 0 || shift >= ArraySize(g_kcLower)) return 0.0;
   return g_kcLower[shift];
  }

double GetKAMA(const int shift)
  {
   if(shift < 0 || shift >= ArraySize(g_kamaBuffer)) return 0.0;
   return g_kamaBuffer[shift];
  }
//+------------------------------------------------------------------+
