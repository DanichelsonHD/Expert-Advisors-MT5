//+------------------------------------------------------------------+
//|                                      EA_MeanReversion_v2.0.2.mq5 |
//|               Structured Mean Reversion with Return Confirmation |
//+------------------------------------------------------------------+
#property copyright "Daniel Pereira"
#property link      ""
#property version   "2.02"
#property strict

#include <Trade\Trade.mqh>

//=============================================================================
// INPUT PARAMETERS
//=============================================================================

//--- Timeframe
input group "=== Timeframe ==="
input ENUM_TIMEFRAMES InpTimeframe       = PERIOD_H1;   // Trading Timeframe (M30 or H1)

//--- RSI
input group "=== RSI ==="
input int    InpRSIPeriod                = 14;           // RSI Period
input double InpRSIOverbought            = 75.0;         // RSI Overbought Level
input double InpRSIOversold              = 25.0;         // RSI Oversold Level

//--- Keltner Channel
input group "=== Keltner Channel ==="
input int    InpKeltnerEMAPeriod         = 21;           // Keltner EMA Period
input int    InpKeltnerATRPeriod         = 7;            // Keltner ATR Period
input double InpKeltnerATRMult           = 2.5;          // Keltner ATR Multiplier

//--- KAMA
input group "=== KAMA ==="
input int    InpKAMAPeriod               = 21;           // KAMA Period
input int    InpKAMAFast                 = 3;            // KAMA Fast Period
input int    InpKAMASlow                 = 30;           // KAMA Slow Period
input double InpKAMAPower                = 2.0;          // KAMA Smooth Power
input int    InpKAMAFilter               = 50;           // KAMA Filter
input int    InpKAMAFilterPer            = 4;            // KAMA Filter Period
input double InpKAMAFilterDiff           = 50.0;         // KAMA Filter Difference

//--- ATR Stop
input group "=== Stop Management ==="
input int    InpATRStopPeriod            = 14;           // ATR Period
input double InpStopATRMult_M30          = 1.8;          // Stop ATR Multiplier (M30)
input double InpStopATRMult_H1           = 1.4;          // Stop ATR Multiplier (H1)
input double InpExtraPoints              = 10.0;         // Extra Points (stop buffer)
input double InpTrailATRMult             = 1.5;          // Trailing ATR Multiplier

//--- ATR Volatility Filter
input group "=== Volatility Filter ==="
input int    InpATRFilterPeriod          = 14;           // ATR average lookback (candles)
input double InpATRFilterMult            = 1.1;          // Min ATR ratio to allow entry

//--- Time Filter
input group "=== Time Filter ==="
input int    InpStartHour                = 8;            // Trading Start Hour (UTC)
input int    InpEndHour                  = 17;           // Trading End Hour (UTC)
input bool   InpBlockAsian               = true;         // Block Asian Session (<07:00 UTC)

//--- Risk / Trade Control
input group "=== Risk Controls ==="
input double InpLotSize                  = 1.0;          // Lot Size
input int    InpMagicNumber              = 20250101;     // Magic Number
input int    InpCooldownCandles          = 3;            // Cooldown Candles After Stop
input int    InpMaxConsecLoss            = 0;            // Max Consecutive Losses (0=off)

//=============================================================================
// INDICATOR HANDLES
//=============================================================================

int g_hRSI      = INVALID_HANDLE;
int g_hKC       = INVALID_HANDLE;
int g_hKAMA     = INVALID_HANDLE;
int g_hATR      = INVALID_HANDLE;

//=============================================================================
// INTERNAL STATE
//=============================================================================

enum EntryState
  {
   STATE_IDLE                 = 0,
   STATE_OVERSOLD_CONFIRMED   = 1,
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

CTrade     g_Trade;

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

   //--- RSI handle
   g_hRSI = iRSI(_Symbol, InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
   if(g_hRSI == INVALID_HANDLE)
     {
      Print("EA_MeanReversion: RSI handle failed.");
      return INIT_FAILED;
     }

   //--- Keltner Channel handle
   //    Buffer 0 = Upper, Buffer 1 = Middle EMA, Buffer 2 = Lower
   g_hKC = iCustom(_Symbol, InpTimeframe,
                   "Keltner Channel",
                   InpKeltnerEMAPeriod,
                   InpKeltnerATRPeriod,
                   InpKeltnerATRMult,
                   false);
   if(g_hKC == INVALID_HANDLE)
     {
      Print("EA_MeanReversion: Keltner Channel handle failed.");
      return INIT_FAILED;
     }

   //--- KAMA handle
   //    Buffer 0 = val (filtered KAMA line), Buffer 1 = color index
   g_hKAMA = iCustom(_Symbol, InpTimeframe,
                     "KAMA with filter",
                     InpKAMAPeriod,
                     InpKAMAFast,
                     InpKAMASlow,
                     InpKAMAPower,
                     InpKAMAFilter,
                     InpKAMAFilterPer,
                     InpKAMAFilterDiff,
                     PRICE_CLOSE);
   if(g_hKAMA == INVALID_HANDLE)
     {
      Print("EA_MeanReversion: KAMA handle failed.");
      return INIT_FAILED;
     }

   //--- ATR handle — single source of truth for stop, trailing and volatility filter
   g_hATR = iATR(_Symbol, InpTimeframe, InpATRStopPeriod);
   if(g_hATR == INVALID_HANDLE)
     {
      Print("EA_MeanReversion: ATR handle failed.");
      return INIT_FAILED;
     }

   g_Trade.SetExpertMagicNumber(InpMagicNumber);

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

   if(g_hRSI  != INVALID_HANDLE) { IndicatorRelease(g_hRSI);  g_hRSI  = INVALID_HANDLE; }
   if(g_hKC   != INVALID_HANDLE) { IndicatorRelease(g_hKC);   g_hKC   = INVALID_HANDLE; }
   if(g_hKAMA != INVALID_HANDLE) { IndicatorRelease(g_hKAMA); g_hKAMA = INVALID_HANDLE; }
   if(g_hATR  != INVALID_HANDLE) { IndicatorRelease(g_hATR);  g_hATR  = INVALID_HANDLE; }
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime currentBarTime = iTime(_Symbol, InpTimeframe, 0);
   bool     isNewBar       = (currentBarTime != g_lastBarTime);

   if(!isNewBar)
      return;

   g_lastBarTime = currentBarTime;

   SyncPositionState();

   if(g_inPosition)
     {
      StopManagement_Update();
      return;
     }

   if(!g_tradingLocked)
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
// INDICATOR ACCESSORS
// All use CopyBuffer with ArraySetAsSeries(true).
// shift 1 = last closed bar, shift 2 = previous closed bar.
// Identical indexing contract across all indicators.
//=============================================================================

bool GetRSI(const int shift, double &val)
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hRSI, 0, shift, 1, buf) < 1) return false;
   val = buf[0];
   return true;
  }

bool GetKeltnerUpper(const int shift, double &val)
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hKC, 0, shift, 1, buf) < 1) return false;
   val = buf[0];
   return true;
  }

bool GetKeltnerLower(const int shift, double &val)
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hKC, 2, shift, 1, buf) < 1) return false;
   val = buf[0];
   return true;
  }

bool GetKAMAVal(const int shift, double &val)
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hKAMA, 0, shift, 1, buf) < 1) return false;
   val = buf[0];
   return true;
  }

bool GetATR(const int shift, double &val)
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hATR, 0, shift, 1, buf) < 1) return false;
   val = buf[0];
   return true;
  }

bool GetATRAverage(double &avg)
  {
   int count = InpATRFilterPeriod;
   if(count <= 0) { avg = 0.0; return false; }
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_hATR, 0, 1, count, buf) < count) return false;
   double sum = 0.0;
   for(int i = 0; i < count; i++) sum += buf[i];
   avg = sum / count;
   return true;
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

   //--- Position no longer exists — determine exit reason via history
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
   double rsi1, rsi2, kLow1, kUpp1, atrCurr, atrAvg;

   if(!GetRSI(1, rsi1))           return;
   if(!GetRSI(2, rsi2))           return;
   if(!GetKeltnerLower(1, kLow1)) return;
   if(!GetKeltnerUpper(1, kUpp1)) return;
   if(!GetATR(1, atrCurr))        return;

   double close1 = iClose(_Symbol, InpTimeframe, 1);

   //--- Volatility filter
   if(GetATRAverage(atrAvg))
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
      //--- True RSI cross: was below oversold, now crosses back above
      if(rsi2 < InpRSIOversold && rsi1 >= InpRSIOversold)
        {
         if(close1 <= kLow1 * (1.0 + 0.002))
           {
            ExecuteEntry(ORDER_TYPE_BUY);
            g_entryState = STATE_IDLE;
            return;
           }
        }
      //--- State decay
      if(rsi1 > InpRSIOversold + 10.0)
         g_entryState = STATE_IDLE;
     }

   if(g_entryState == STATE_OVERBOUGHT_CONFIRMED)
     {
      //--- True RSI cross: was above overbought, now crosses back below
      if(rsi2 > InpRSIOverbought && rsi1 <= InpRSIOverbought)
        {
         if(close1 >= kUpp1 * (1.0 - 0.002))
           {
            ExecuteEntry(ORDER_TYPE_SELL);
            g_entryState = STATE_IDLE;
            return;
           }
        }
      //--- State decay
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

   double atr = 0.0;
   if(!GetATR(1, atr)) return;

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

   if(!PositionSelect(_Symbol))
      return;

   g_positionTicket = PositionGetInteger(POSITION_TICKET);
   g_inPosition     = true;
   g_positionType   = (int)orderType;
   g_entryPrice     = entryPrice;
   g_initialSL      = sl;
   g_currentSL      = sl;
   g_consecLosses   = 0;

   DrawInitialSL(sl);
  }

//=============================================================================
// MODULE 2 — STOP MANAGEMENT
//=============================================================================

void StopManagement_Update()
  {
   if(!g_inPosition) return;
   if(!PositionSelectByTicket(g_positionTicket)) return;

   double atr = 0.0;
   if(!GetATR(1, atr)) return;

   double close1 = iClose(_Symbol, InpTimeframe, 1);
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

   double kama1, kama2;
   if(!GetKAMAVal(1, kama1)) return;
   if(!GetKAMAVal(2, kama2)) return;

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
