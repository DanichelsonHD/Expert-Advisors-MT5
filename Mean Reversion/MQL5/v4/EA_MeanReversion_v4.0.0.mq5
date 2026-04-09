//+------------------------------------------------------------------+
//|                                          MeanReversionKAMA.mq5  |
//+------------------------------------------------------------------+
#property copyright   "Mean Reversion EA"
#property link        ""
#property description "Mean Reversion with RSI + Keltner + ATR + KAMA Regime Exit"
#property version     "4.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Enumerations
enum ENUM_EXIT_MODE
  {
   EXIT_KAMA_REGIME   = 0,  // KAMA Regime Exit
   EXIT_TRAILING_ONLY = 1   // Trailing Stop Only
  };

enum ENUM_KAMA_REGIME
  {
   REGIME_NONE    = 0,
   REGIME_BEARISH = 1,
   REGIME_BULLISH = 2
  };

enum ENUM_ENTRY_STATE
  {
   STATE_IDLE                 = 0,
   STATE_OVERSOLD_CONFIRMED   = 1,
   STATE_OVERBOUGHT_CONFIRMED = 2
  };

//--- Input Parameters: RSI
input group              "=== RSI Settings ==="
input int                InpRSIPeriod         = 14;     // RSI Period
input double             InpRSIOversold       = 30.0;   // RSI Oversold Level
input double             InpRSIOverbought     = 70.0;   // RSI Overbought Level
input double             InpRSIResetThreshold = 20.0;   // RSI Reset Threshold (points)

//--- Input Parameters: Keltner Channel
input group              "=== Keltner Channel Settings ==="
input int                InpKeltnerEMAPeriod  = 20;     // Keltner EMA Period
input double             InpKeltnerATRFactor  = 2.0;    // Keltner ATR Multiplier

//--- Input Parameters: ATR
input group              "=== ATR Settings ==="
input int                InpATRPeriod         = 14;     // ATR Period

//--- Input Parameters: Volatility Filter
input group              "=== Volatility Filter ==="
input double             InpVolatilityMult    = 0.8;    // Volatility Multiplier (ATR >= avg * mult)

//--- Input Parameters: KAMA
input group              "=== KAMA Settings ==="
input int                InpKAMAPeriod        = 14;     // KAMA Period
input int                InpKAMAFastPeriod    = 2;      // KAMA Fast Period
input int                InpKAMASlowPeriod    = 30;     // KAMA Slow Period

//--- Input Parameters: Stop & Trailing
input group              "=== Stop Loss & Trailing ==="
input double             InpStopMultiplier    = 2.0;    // Stop Loss ATR Multiplier
input double             InpTrailingMultiplier = 1.5;   // Trailing Stop ATR Multiplier
input int                InpExtraPoints       = 5;      // Extra Buffer Points

//--- Input Parameters: Take Profit
input group              "=== Take Profit ==="
input bool               InpUseTakeProfit     = false;  // Enable Take Profit
input double             InpTPMultiplier      = 2.0;    // TP = StopDistance * Multiplier

//--- Input Parameters: Exit Mode
input group              "=== Exit Mode ==="
input ENUM_EXIT_MODE     InpExitMode          = EXIT_KAMA_REGIME; // Exit Mode

//--- Input Parameters: Trade
input group              "=== Trade Settings ==="
input double             InpLotSize           = 0.1;    // Lot Size
input int                InpMagicNumber       = 123456; // Magic Number

//--- Time Filter
input group              "=== Time Filter ==="
input bool               InpUseTimeFilter     = false;  // Enable Time Filter
input int                InpStartHour         = 8;      // Start Hour (Server Time)
input int                InpEndHour           = 20;     // End Hour (Server Time)

//--- Indicator Handles
int    g_handleRSI     = INVALID_HANDLE;
int    g_handleKeltner = INVALID_HANDLE;
int    g_handleATR     = INVALID_HANDLE;
int    g_handleKAMA    = INVALID_HANDLE;

//--- State
ENUM_ENTRY_STATE g_entryState = STATE_IDLE;

//--- Trade objects
CTrade        g_trade;
CPositionInfo g_position;

//+------------------------------------------------------------------+
//| Helper: sync CPositionInfo and validate EA magic.                |
//| Returns true only when an EA-owned position exists on _Symbol.   |
//+------------------------------------------------------------------+
bool SelectEAPosition()
  {
   if(!g_position.Select(_Symbol))
      return(false);
   if(g_position.Magic() != (ulong)InpMagicNumber)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Validate timeframe
   if(_Period != PERIOD_M30 && _Period != PERIOD_H1)
     {
      Print("ERROR: Unsupported timeframe. EA supports M30 and H1 only.");
      return(INIT_FAILED);
     }

//--- RSI handle
   g_handleRSI = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   if(g_handleRSI == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create RSI handle.");
      return(INIT_FAILED);
     }

//--- Keltner Channel handle (external .ex5)
   g_handleKeltner = iCustom(_Symbol, _Period, "Keltner Channel",
                              InpKeltnerEMAPeriod,
                              InpATRPeriod,
                              InpKeltnerATRFactor,
                              false);
   if(g_handleKeltner == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create Keltner Channel handle. Ensure 'Keltner Channel.ex5' is installed.");
      return(INIT_FAILED);
     }

//--- ATR handle (dedicated EA handle, independent of Keltner internals)
   g_handleATR = iATR(_Symbol, _Period, InpATRPeriod);
   if(g_handleATR == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create ATR handle.");
      return(INIT_FAILED);
     }

//--- KAMA handle (external .ex5)
//    Fixed internal params: Power=2, Filter=50, FilterPeriod=4, FilterDifference=50, Price=CLOSE
   g_handleKAMA = iCustom(_Symbol, _Period, "KAMA with filter",
                           InpKAMAPeriod,
                           InpKAMAFastPeriod,
                           InpKAMASlowPeriod,
                           2,
                           50,
                           4,
                           50.0,
                           PRICE_CLOSE);
   if(g_handleKAMA == INVALID_HANDLE)
     {
      Print("ERROR: Failed to create KAMA handle. Ensure 'KAMA with filter.ex5' is installed.");
      return(INIT_FAILED);
     }

//--- Configure trade object
//    ORDER_FILLING_IOC: compatible with most brokers; avoids silent FOK rejections
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(10);
   g_trade.SetTypeFilling(ORDER_FILLING_IOC);

//--- Reset state
   g_entryState = STATE_IDLE;

   Print("EA initialized. Symbol=", _Symbol, " TF=", EnumToString(_Period),
         " Magic=", InpMagicNumber);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_handleRSI     != INVALID_HANDLE) IndicatorRelease(g_handleRSI);
   if(g_handleKeltner != INVALID_HANDLE) IndicatorRelease(g_handleKeltner);
   if(g_handleATR     != INVALID_HANDLE) IndicatorRelease(g_handleATR);
   if(g_handleKAMA    != INVALID_HANDLE) IndicatorRelease(g_handleKAMA);
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- New candle detection
   static datetime s_lastBarTime = 0;
   datetime        currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == s_lastBarTime)
      return;
   s_lastBarTime = currentBarTime;

//--- Time filter
   if(InpUseTimeFilter && !IsWithinTradingHours())
      return;

//--- Fetch RSI: 2 values from bar 1 → [0]=bar2, [1]=bar1
   double rsi[2];
   if(CopyBuffer(g_handleRSI, 0, 1, 2, rsi) < 2)
      return;

//--- Fetch Keltner upper/lower: 2 values from bar 1 → [0]=bar2, [1]=bar1
   double keltUpper[2], keltLower[2];
   if(CopyBuffer(g_handleKeltner, 0, 1, 2, keltUpper) < 2)
      return;
   if(CopyBuffer(g_handleKeltner, 2, 1, 2, keltLower) < 2)
      return;

//--- Fetch ATR: InpATRPeriod values from bar 1 for proper average
//    [0]=oldest, [InpATRPeriod-1]=bar1
   double atrBuf[];
   ArrayResize(atrBuf, InpATRPeriod);
   if(CopyBuffer(g_handleATR, 0, 1, InpATRPeriod, atrBuf) < InpATRPeriod)
      return;

//--- Fetch KAMA color buffer: 2 values from bar 1 → [0]=bar2, [1]=bar1
   double kamaColor[2];
   if(CopyBuffer(g_handleKAMA, 1, 1, 2, kamaColor) < 2)
      return;

//--- Extract named values
   double currentRSI   = rsi[1];
   double prevRSI      = rsi[0];
   double upperKeltner = keltUpper[1];
   double lowerKeltner = keltLower[1];
   double currentATR   = atrBuf[InpATRPeriod - 1];

//--- Compute ATR average over InpATRPeriod bars
   double sumATR = 0.0;
   for(int k = 0; k < InpATRPeriod; k++)
      sumATR += atrBuf[k];
   double avgATR = sumATR / (double)InpATRPeriod;

//--- Resolve KAMA regime from color buffer
   ENUM_KAMA_REGIME kamaNow  = ResolveKAMARegime((int)MathRound(kamaColor[1]));
   ENUM_KAMA_REGIME kamaPrev = ResolveKAMARegime((int)MathRound(kamaColor[0]));

   double closeBar1 = iClose(_Symbol, _Period, 1);

//--- Derive position state from platform via CPositionInfo
   bool hasPosition = SelectEAPosition();

   if(hasPosition)
     {
      ManageTrailingStop(currentATR);
      CheckExitConditions(kamaNow, kamaPrev);
      return;
     }

//--- No EA-owned position: reset state and run entry machine
   g_entryState = STATE_IDLE;
   RunEntryStateMachine(currentRSI, prevRSI, closeBar1,
                        upperKeltner, lowerKeltner,
                        currentATR, avgATR);
  }

//+------------------------------------------------------------------+
//| Resolve KAMA color buffer integer to regime enum                 |
//| KAMA with filter color mapping:                                  |
//|   0 = no regime  (clrDarkGray)                                   |
//|   1 = bearish    (clrDeepPink)                                   |
//|   2 = bullish    (clrLimeGreen)                                  |
//+------------------------------------------------------------------+
ENUM_KAMA_REGIME ResolveKAMARegime(const int colorIndex)
  {
   if(colorIndex == 1) return(REGIME_BEARISH);
   if(colorIndex == 2) return(REGIME_BULLISH);
   return(REGIME_NONE);
  }

//+------------------------------------------------------------------+
//| Time filter check                                                |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(dt.hour >= InpStartHour && dt.hour < InpEndHour);
  }

//+------------------------------------------------------------------+
//| Volatility filter                                                |
//| Pass condition: currentATR >= avgATR * InpVolatilityMult         |
//+------------------------------------------------------------------+
bool PassesVolatilityFilter(const double currentATR, const double avgATR)
  {
   return(currentATR >= avgATR * InpVolatilityMult);
  }

//+------------------------------------------------------------------+
//| Entry State Machine                                              |
//+------------------------------------------------------------------+
void RunEntryStateMachine(const double curRSI,  const double prevRSI,
                          const double close1,
                          const double upperK,  const double lowerK,
                          const double curATR,  const double avgATR)
  {
   switch(g_entryState)
     {
      case STATE_IDLE:
        {
         if(curRSI < InpRSIOversold && close1 < lowerK)
           {
            g_entryState = STATE_OVERSOLD_CONFIRMED;
            break;
           }
         if(curRSI > InpRSIOverbought && close1 > upperK)
           {
            g_entryState = STATE_OVERBOUGHT_CONFIRMED;
            break;
           }
         break;
        }

      case STATE_OVERSOLD_CONFIRMED:
        {
         //--- RSI cross above oversold is checked FIRST (takes priority over reset)
         if(prevRSI <= InpRSIOversold && curRSI > InpRSIOversold)
           {
            g_entryState = STATE_IDLE;
            if(PassesVolatilityFilter(curATR, avgATR))
               ExecuteEntry(ORDER_TYPE_BUY, curATR);
            break;
           }
         //--- Stale state reset: only when RSI is above oversold without a cross on this bar
         //    i.e., it rose above oversold on a prior bar and kept moving away
         if(curRSI > InpRSIOversold &&
            MathAbs(curRSI - InpRSIOversold) > InpRSIResetThreshold)
           {
            g_entryState = STATE_IDLE;
           }
         break;
        }

      case STATE_OVERBOUGHT_CONFIRMED:
        {
         //--- RSI cross below overbought is checked FIRST (takes priority over reset)
         if(prevRSI >= InpRSIOverbought && curRSI < InpRSIOverbought)
           {
            g_entryState = STATE_IDLE;
            if(PassesVolatilityFilter(curATR, avgATR))
               ExecuteEntry(ORDER_TYPE_SELL, curATR);
            break;
           }
         //--- Stale state reset: only when RSI is below overbought without a cross on this bar
         if(curRSI < InpRSIOverbought &&
            MathAbs(curRSI - InpRSIOverbought) > InpRSIResetThreshold)
           {
            g_entryState = STATE_IDLE;
           }
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//| Execute Entry                                                    |
//+------------------------------------------------------------------+
void ExecuteEntry(const ENUM_ORDER_TYPE orderType, const double atr)
  {
//--- Block if EA-owned position already exists (synced via CPositionInfo)
   if(SelectEAPosition())
      return;

   double ask         = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid         = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point       = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits      = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int    stopLevel   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int    freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

   double extraDist = InpExtraPoints * point;
   double stopDist  = atr * InpStopMultiplier + extraDist;
   double minDist   = MathMax(stopLevel, freezeLevel) * point + point;
   if(stopDist < minDist)
      stopDist = minDist;

   double entryPrice, sl, tp;

   if(orderType == ORDER_TYPE_BUY)
     {
      entryPrice = ask;
      sl         = NormalizeDouble(entryPrice - stopDist, digits);
      tp         = InpUseTakeProfit
                   ? NormalizeDouble(entryPrice + stopDist * InpTPMultiplier, digits)
                   : 0.0;
     }
   else
     {
      entryPrice = bid;
      sl         = NormalizeDouble(entryPrice + stopDist, digits);
      tp         = InpUseTakeProfit
                   ? NormalizeDouble(entryPrice - stopDist * InpTPMultiplier, digits)
                   : 0.0;
     }

   bool sent = (orderType == ORDER_TYPE_BUY)
               ? g_trade.Buy(InpLotSize, _Symbol, entryPrice, sl, tp, "MR_BUY")
               : g_trade.Sell(InpLotSize, _Symbol, entryPrice, sl, tp, "MR_SELL");

   if(!sent)
      Print("ERROR: Order send failed. RetCode=", g_trade.ResultRetcode(),
            " Comment=", g_trade.ResultComment());
   else
      Print("Order sent. Type=", EnumToString(orderType),
            " Price=", entryPrice, " SL=", sl, " TP=", tp);
  }

//+------------------------------------------------------------------+
//| Manage Trailing Stop                                             |
//| Caller guarantees SelectEAPosition() returned true prior.        |
//+------------------------------------------------------------------+
void ManageTrailingStop(const double atr)
  {
   if(!SelectEAPosition())
      return;

   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int    digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int    stopLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double extraDist  = InpExtraPoints * point;
   double trailDist  = atr * InpTrailingMultiplier + extraDist;
   double minDist    = stopLevel * point + point;
   if(trailDist < minDist) trailDist = minDist;

   double             currentSL = g_position.StopLoss();
   double             currentTP = g_position.TakeProfit();
   ENUM_POSITION_TYPE posType   = g_position.PositionType();

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(posType == POSITION_TYPE_BUY)
     {
      double newSL = NormalizeDouble(bid - trailDist, digits);
      if(newSL > currentSL + point)
         g_trade.PositionModify(_Symbol, newSL, currentTP);
     }
   else if(posType == POSITION_TYPE_SELL)
     {
      double newSL = NormalizeDouble(ask + trailDist, digits);
      if(currentSL == 0.0 || newSL < currentSL - point)
         g_trade.PositionModify(_Symbol, newSL, currentTP);
     }
  }

//+------------------------------------------------------------------+
//| Check Exit Conditions (KAMA regime flip)                         |
//+------------------------------------------------------------------+
void CheckExitConditions(const ENUM_KAMA_REGIME kamaNow,
                         const ENUM_KAMA_REGIME kamaPrev)
  {
   if(InpExitMode != EXIT_KAMA_REGIME)
      return;

   if(!SelectEAPosition())
      return;

   ENUM_POSITION_TYPE posType = g_position.PositionType();

//--- BUY exits when KAMA flips Bullish → Bearish
   if(posType == POSITION_TYPE_BUY)
     {
      if(kamaPrev == REGIME_BULLISH && kamaNow == REGIME_BEARISH)
        {
         if(!g_trade.PositionClose(_Symbol))
            Print("ERROR: Failed to close BUY. RetCode=", g_trade.ResultRetcode());
         else
            Print("KAMA regime exit: BUY closed (Bullish->Bearish).");
        }
     }
//--- SELL exits when KAMA flips Bearish → Bullish
   else if(posType == POSITION_TYPE_SELL)
     {
      if(kamaPrev == REGIME_BEARISH && kamaNow == REGIME_BULLISH)
        {
         if(!g_trade.PositionClose(_Symbol))
            Print("ERROR: Failed to close SELL. RetCode=", g_trade.ResultRetcode());
         else
            Print("KAMA regime exit: SELL closed (Bearish->Bullish).");
        }
     }
  }
//+------------------------------------------------------------------+
