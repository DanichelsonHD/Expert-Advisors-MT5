//+------------------------------------------------------------------+
//|                                     EA_MeanReversion_v3.0.0c.mq5 |
//|               Structured Mean Reversion with Return Confirmation |
//|          ETAPA 1 (patched) + ETAPA 2 (State) + ETAPA 3 (Execute) |
//+------------------------------------------------------------------+
#property copyright "Daniel Pereira"
#property link      ""
#property version   "3.00c"
#property strict

#include <Trade\Trade.mqh>

//=============================================================================
// INPUTS
//=============================================================================

input group "=== Time Filters ==="
input ENUM_TIMEFRAMES InpTimeframe  = PERIOD_H1;  // Trading Timeframe (M30 or H1)
input int             InpStartHour  = 8;           // Trading Start Hour (UTC)
input int             InpEndHour    = 17;          // Trading End Hour (UTC)

input group "=== RSI ==="
input int    InpRSIPeriod        = 14;
input double InpRSIOverbought    = 75.0;
input double InpRSIOversold      = 25.0;

input group "=== Keltner Channel ==="
input int    InpKCPeriod         = 21;
input double InpKCMultiplier     = 2.5;

input group "=== ATR ==="
input int    InpATRPeriod        = 14;

input group "=== KAMA ==="
input int    InpKAMAPeriod       = 7;
input int    InpKAMAFast         = 3;
input int    InpKAMASlow         = 30;

input group "=== Trade execution ==="
input double InpLotSize        = 0.10;
input int    InpSlippagePoints = 20;
input ulong  InpMagicNumber    = 30001;

input group "=== ATR-based Stop ==="
input double InpATR_StopMult   = 2.0;   // ATR multiplier for SL
input double InpSL_ExtraPoints = 5.0;   // Extra points added to SL

input group "=== Trailing ATR ==="
input bool   InpUseTrailingATR = true;

input group "=== Exit mode ==="
enum ENUM_ExitMode
{
   EXIT_KAMA_COLOR = 0,   // Swing exit via KAMA color inversion
   EXIT_TRAILING_ONLY     // No take, exit only via SL
};
input ENUM_ExitMode InpExitMode = EXIT_KAMA_COLOR;

input group "=== Debug ==="
input bool InpShowDebug  = true;

//=============================================================================
// GLOBAL INDICATOR BUFFERS
//=============================================================================

MqlRates g_rates[];

double g_rsiBuffer[];
double g_atrBuffer[];
double g_kcUpper[];
double g_kcLower[];
double g_kamaBuffer[];
double g_kamaColorBuffer[]; // 1 = Bullish, 2 = Bearish

//=============================================================================
// ETAPA 2 — STATE
//=============================================================================

enum EntryState
  {
   STATE_IDLE                 = 0,
   STATE_OVERSOLD_CONFIRMED   = 1,
   STATE_OVERBOUGHT_CONFIRMED = 2
  };

enum EntrySignal
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = 2
  };

EntryState  g_entryState = STATE_IDLE;
EntrySignal g_lastSignal = SIGNAL_NONE;

//=============================================================
// STAGE 3 — GLOBAL TRADE STATE
//=============================================================

bool   g_hasPosition = false;
ulong  g_ticket      = 0;
double g_entryPrice  = 0.0;
double g_currentSL   = 0.0;

CTrade trade;

//=============================================================================
// OnInit / OnDeinit / OnTick
//=============================================================================

int OnInit()
  {
   ArraySetAsSeries(g_rates,           true);
   ArraySetAsSeries(g_rsiBuffer,       true);
   ArraySetAsSeries(g_atrBuffer,       true);
   ArraySetAsSeries(g_kcUpper,         true);
   ArraySetAsSeries(g_kcLower,         true);
   ArraySetAsSeries(g_kamaBuffer,      true);
   ArraySetAsSeries(g_kamaColorBuffer, true);

   g_entryState = STATE_IDLE;
   g_lastSignal = SIGNAL_NONE;
   
   trade.SetExpertMagicNumber(InpMagicNumber);

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
   ArrayFree(g_kamaColorBuffer);
  }

void OnTick()
  {
   static datetime s_lastBarTime = 0;

   // PATCH 1: use InpTimeframe everywhere
   datetime currentBarTime = iTime(_Symbol, InpTimeframe, 0);

   if(currentBarTime == s_lastBarTime)
      return;

   s_lastBarTime = currentBarTime;

   CalcIndicators();
   
   // Position Sync
   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
   {
      g_hasPosition = true;
      g_ticket = PositionGetInteger(POSITION_TICKET);
   }
   else
   {
      g_hasPosition = false;
      g_ticket = 0;
   }

   EvaluateEntrySignal();

   // Stage 3 — Execution Flow
   if(!g_hasPosition)
   {
      if(g_lastSignal == SIGNAL_BUY)
      {
         OpenPosition(ORDER_TYPE_BUY);
         if(g_hasPosition) DrawEntryArrow(true);
      }
      else if(g_lastSignal == SIGNAL_SELL)
      {
         OpenPosition(ORDER_TYPE_SELL);
         if(g_hasPosition) DrawEntryArrow(false);
      }
   }
   else
   {
      UpdateTrailingStop();
      RunExitLogic();
      DrawStopLine();
   }
  }

//=============================================================================
// ETAPA 1 — INDICATOR ENGINE (PATCHED)
//=============================================================================

void CalcIndicators()
  {
   int needed = MathMax(MathMax(InpRSIPeriod, InpATRPeriod),
                        MathMax(InpKCPeriod,  InpKAMAPeriod)) + 64;

   // PATCH 1: use InpTimeframe
   int copied = CopyRates(_Symbol, InpTimeframe, 0, needed, g_rates);
   if(copied < needed) return;

   // IMPORTANT: CalcATR() MUST run before CalcKeltner()
   // g_atrBuffer is assumed to be valid and aligned when CalcKeltner() runs
   CalcATR(copied);
   CalcRSI(copied);
   CalcKeltner(copied);
   CalcKAMA(copied);
  }

//-----------------------------------------------------------------------------
// CalcATR — Wilder smoothing (matches MT5 native iATR)
// g_atrBuffer[0] = forming bar, [1] = last closed, [2] = previous closed.
//-----------------------------------------------------------------------------
void CalcATR(const int count)
  {
   if(ArraySize(g_atrBuffer) != count)
      ArrayResize(g_atrBuffer, count);

   double tr[];
   double atr_fwd[];
   ArrayResize(tr,      count);
   ArrayResize(atr_fwd, count);

   int period = InpATRPeriod;

   tr[0] = 0.0;
   for(int i = 1; i < count; i++)
     {
      double hi = g_rates[count - 1 - i].high;
      double lo = g_rates[count - 1 - i].low;
      double pc = g_rates[count - 1 - (i - 1)].close;
      tr[i] = MathMax(hi, pc) - MathMin(lo, pc);
     }

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

   for(int i = 0; i < count; i++)
      g_atrBuffer[i] = atr_fwd[count - 1 - i];
  }

//-----------------------------------------------------------------------------
// CalcRSI — Wilder smoothing
// g_rsiBuffer[1] = last closed bar.
//-----------------------------------------------------------------------------
void CalcRSI(const int count)
  {
   if(ArraySize(g_rsiBuffer) != count)
      ArrayResize(g_rsiBuffer, count);

   int period = InpRSIPeriod;
   if(count <= period) return;

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

   double sg = 0.0, sl_acc = 0.0;
   for(int i = 1; i <= period; i++)
     {
      double d = close[i] - close[i - 1];
      if(d > 0.0) sg     += d;
      else        sl_acc += -d;
     }
   avg_gain[period] = sg     / period;
   avg_loss[period] = sl_acc / period;

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
      double d   = close[i] - close[i - 1];
      double gn  = (d > 0.0) ? d  : 0.0;
      double ls  = (d < 0.0) ? -d : 0.0;
      avg_gain[i] = (avg_gain[i - 1] * (period - 1) + gn) / period;
      avg_loss[i] = (avg_loss[i - 1] * (period - 1) + ls) / period;
      if(avg_loss[i] == 0.0)
         rsi_fwd[i] = (avg_gain[i] > 0.0) ? 100.0 : 50.0;
      else
         rsi_fwd[i] = 100.0 - 100.0 / (1.0 + avg_gain[i] / avg_loss[i]);
     }

   for(int i = 0; i < count; i++)
      g_rsiBuffer[i] = rsi_fwd[count - 1 - i];
  }

//-----------------------------------------------------------------------------
// CalcKeltner — EMA(close, InpKCPeriod) ± InpKCMultiplier * ATR
// IMPORTANT: CalcATR() must run first. g_atrBuffer must be valid and aligned.
//-----------------------------------------------------------------------------
void CalcKeltner(const int count)
  {
   if(ArraySize(g_kcUpper) != count) ArrayResize(g_kcUpper, count);
   if(ArraySize(g_kcLower) != count) ArrayResize(g_kcLower, count);

   int    period = InpKCPeriod;
   double k      = 2.0 / (period + 1.0);
   int    start  = MathMax(period, InpATRPeriod) + 1;

   double ema_fwd[];
   ArrayResize(ema_fwd, count);

   ema_fwd[0] = g_rates[count - 1].close;
   for(int i = 1; i < count; i++)
      ema_fwd[i] = g_rates[count - 1 - i].close * k + ema_fwd[i - 1] * (1.0 - k);

   // Convert series ATR buffer to forward order for alignment
   double atr_fwd[];
   ArrayResize(atr_fwd, count);
   for(int i = 0; i < count; i++)
      atr_fwd[i] = g_atrBuffer[count - 1 - i];

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
// CalcKAMA — Kaufman Adaptive Moving Average
// PATCH 2: noise == 0 → er = 1.0  (flat market = max efficiency)
// PATCH 3: smoothing power declared as explicit constant
// g_kamaBuffer[1] = last closed bar.
// g_kamaColorBuffer extracts KAMA regime directly (1 = Bullish, 2 = Bearish)
//-----------------------------------------------------------------------------
void CalcKAMA(const int count)
  {
   if(ArraySize(g_kamaBuffer) != count)
      ArrayResize(g_kamaBuffer, count);
   if(ArraySize(g_kamaColorBuffer) != count)
      ArrayResize(g_kamaColorBuffer, count);

   int    period  = InpKAMAPeriod;
   double fastEnd = 2.0 / (InpKAMAFast + 1.0);
   double slowEnd = 2.0 / (InpKAMASlow + 1.0);

   // KAMA smoothing power (explicit, fixed by design)
   const double KAMA_POWER = 2.0;

   double close[];
   ArrayResize(close, count);
   for(int i = 0; i < count; i++)
      close[i] = g_rates[count - 1 - i].close;

   double kama_fwd[];
   double color_fwd[];
   ArrayResize(kama_fwd, count);
   ArrayResize(color_fwd, count);

   kama_fwd[0] = close[0];
   color_fwd[0] = 0.0;

   for(int i = 1; i < count; i++)
     {
      if(i < period)
        {
         kama_fwd[i] = kama_fwd[i - 1];
         color_fwd[i] = color_fwd[i - 1];
         continue;
        }

      double signal = MathAbs(close[i] - close[i - period]);
      double noise  = 0.0;
      for(int j = 0; j < period; j++)
         noise += MathAbs(close[i - j] - close[i - j - 1]);

      // PATCH 2: flat market = max efficiency → er = 1.0
      double er     = (noise != 0.0) ? signal / noise : 1.0;
      double smooth = MathPow(er * (fastEnd - slowEnd) + slowEnd, KAMA_POWER);
      kama_fwd[i]   = kama_fwd[i - 1] + smooth * (close[i] - kama_fwd[i - 1]);

      // Calculate state for Stage 3 exit (Regime state)
      if (kama_fwd[i] > kama_fwd[i - 1])
         color_fwd[i] = 1.0;
      else if (kama_fwd[i] < kama_fwd[i - 1])
         color_fwd[i] = 2.0;
      else
         color_fwd[i] = color_fwd[i - 1];
     }

   for(int i = 0; i < count; i++)
     {
      g_kamaBuffer[i]      = kama_fwd[count - 1 - i];
      g_kamaColorBuffer[i] = color_fwd[count - 1 - i];
     }
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

//=============================================================================
// ETAPA 2 — STATE MACHINE & LOGIC
//=============================================================================

bool PassesVolatilityFilter()
  {
   double atrCurr = GetATR(1);
   if(atrCurr <= 0.0) return false;

   double sum = 0.0;
   for(int i = 1; i <= InpATRPeriod; i++)
      sum += GetATR(i);

   double atrAvg = sum / InpATRPeriod;
   if(atrAvg <= 0.0) return false;

   return (atrCurr >= atrAvg * 1.1);
  }

void EvaluateEntrySignal()
  {
   g_lastSignal = SIGNAL_NONE;

   double rsi1   = GetRSI(1);
   double rsi2   = GetRSI(2);
   double close1 = g_rates[1].close;
   double kcLow1 = GetKCLower(1);
   double kcUpp1 = GetKCUpper(1);

   if(!PassesVolatilityFilter())
      return;

   //--- STATE 1: detect extremes
   if(g_entryState == STATE_IDLE)
     {
      if(rsi1 < InpRSIOversold && close1 < kcLow1)
        {
         g_entryState = STATE_OVERSOLD_CONFIRMED;
         return;
        }
      if(rsi1 > InpRSIOverbought && close1 > kcUpp1)
        {
         g_entryState = STATE_OVERBOUGHT_CONFIRMED;
         return;
        }
     }

   //--- STATE 2: return confirmation
   if(g_entryState == STATE_OVERSOLD_CONFIRMED)
     {
      if(rsi2 < InpRSIOversold && rsi1 >= InpRSIOversold)
        {
         g_lastSignal = SIGNAL_BUY;
         g_entryState = STATE_IDLE;
        }
     }

   if(g_entryState == STATE_OVERBOUGHT_CONFIRMED)
     {
      if(rsi2 > InpRSIOverbought && rsi1 <= InpRSIOverbought)
        {
         g_lastSignal = SIGNAL_SELL;
         g_entryState = STATE_IDLE;
        }
     }
  }

//=============================================================
// STAGE 3 — EXECUTION FUNCTIONS
//=============================================================

void OpenPosition(ENUM_ORDER_TYPE orderType)
{
   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   double price = (orderType == ORDER_TYPE_BUY)
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // ATR from Stage 1 buffer (series, shift = 1)
   double atr   = g_atrBuffer[1] * InpATR_StopMult;
   double extra = InpSL_ExtraPoints * _Point;

   double sl = (orderType == ORDER_TYPE_BUY)
               ? price - atr - extra
               : price + atr + extra;

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = InpLotSize;
   req.type         = orderType;
   req.price        = price;
   req.sl           = NormalizeDouble(sl, _Digits);
   req.magic        = InpMagicNumber;
   req.deviation    = InpSlippagePoints;
   req.type_filling = ORDER_FILLING_FOK;

   if(!OrderSend(req, res) || res.retcode != TRADE_RETCODE_DONE)
   {
      if(InpShowDebug)
         Print("[EXEC] OrderSend failed: ", res.retcode);
      return;
   }

   if(PositionSelect(_Symbol))
      g_ticket = PositionGetInteger(POSITION_TICKET);

   g_entryPrice  = price;
   g_currentSL   = req.sl;
   g_hasPosition = true;

   if(InpShowDebug)
      Print("[EXEC] Position opened | Ticket: ", g_ticket);
}

void UpdateTrailingStop()
{
   if(!g_hasPosition || !InpUseTrailingATR)
      return;

   if(!PositionSelect(_Symbol))
      return;

   double atr   = g_atrBuffer[1] * InpATR_StopMult;
   double extra = InpSL_ExtraPoints * _Point;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double newSL = g_currentSL;

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
   {
      double candidate = bid - atr - extra;
      if(candidate > g_currentSL)
         newSL = candidate;
   }
   else
   {
      double candidate = ask + atr + extra;
      if(candidate < g_currentSL)
         newSL = candidate;
   }

   if(newSL == g_currentSL)
      return;

   MqlTradeRequest req;
   MqlTradeResult  res;
   ZeroMemory(req);
   ZeroMemory(res);

   req.action   = TRADE_ACTION_SLTP;
   req.position = PositionGetInteger(POSITION_TICKET);
   req.sl       = NormalizeDouble(newSL, _Digits);
   req.tp       = PositionGetDouble(POSITION_TP);

   if(OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
   {
      g_currentSL = req.sl;
      if(InpShowDebug)
         Print("[TRAIL] SL updated to ", g_currentSL);
   }
}

//=============================================================
// STAGE 3 — EXIT LOGIC
//=============================================================

bool ShouldExitByKAMAColor()
{
   if(!PositionSelect(_Symbol))
      return false;

   int color0 = (int)g_kamaColorBuffer[1]; // last closed candle
   int color1 = (int)g_kamaColorBuffer[2]; // previous closed candle

   bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

   // BUY: bullish → bearish
   if(isBuy && color1 == 1 && color0 == 2)
      return true;

   // SELL: bearish → bullish
   if(!isBuy && color1 == 2 && color0 == 1)
      return true;

   return false;
}

void RunExitLogic()
{
   if(!g_hasPosition)
      return;

   bool exitSignal = false;

   if(InpExitMode == EXIT_KAMA_COLOR)
      exitSignal = ShouldExitByKAMAColor();

   if(exitSignal)
   {
      if(InpShowDebug)
         Print("[EXIT] Exit triggered by KAMA color inversion");

      trade.PositionClose(_Symbol);
      g_hasPosition = false;
   }
}
//+------------------------------------------------------------------+