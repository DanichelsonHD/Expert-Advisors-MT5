//+------------------------------------------------------------------+
//| EA_MeanReversion_v1.0.0.mq5                                      |
//| Mean Reversion - RSI + Keltner Channel + KAMA                    |
//+------------------------------------------------------------------+
#property copyright "Daniel Pereira"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//=============================================================
// INPUTS
//=============================================================

// --- Core
input ENUM_TIMEFRAMES InpTimeframe   = PERIOD_H1;  // Timeframe (M15, M30, H1)
input int             InpMagicNumber = 123456;      // Magic Number

// --- Risk
input double InpRiskPercent = 1.0; // Risk % per Trade

// --- RSI
input int    InpRSI_Period    = 7;    // RSI Period
input double InpRSI_BuyLevel  = 25.0; // RSI Buy Level
input double InpRSI_SellLevel = 75.0; // RSI Sell Level

// --- Keltner Channel
input int    InpKC_EMA_Period = 21;  // KC EMA Period
input int    InpKC_ATR_Period = 7;   // KC ATR Period
input double InpKC_Multiplier = 2.5; // KC ATR Multiplier

// --- KAMA
input int InpKAMA_Period       = 14; // KAMA Period
input int InpKAMA_FastEnd      = 3;  // KAMA Fast End Period
input int InpKAMA_SlowEnd      = 30; // KAMA Slow End Period
input int InpKAMA_FilterPeriod = 7;  // KAMA Filter Period

// --- Stop Loss
input int    InpStopLookback     = 5;  // Stop Lookback Candles
input double InpStopBufferPoints = 30; // Stop Buffer (Points)

// --- Take Profit / Exit
input double InpRR_Min             = 1.5;  // Minimum Risk:Reward
input bool   InpUseKAMAExit        = true; // Use KAMA Slope Inversion Exit
input bool   InpUseTrailingAfter1R = true; // Enable Trailing After 1R

// --- Time Filter
input bool InpUseTimeFilter           = true;  // Enable Time Filter
input int  InpStartHour               = 9;     // Session Start Hour (Server Time)
input int  InpEndHour                 = 18;    // Session End Hour (Server Time)
input bool InpClosePositionsAtEndHour = true;  // Close Positions at End Hour

// --- ATR Filter (Optional)
input bool   InpUseATRFilter      = false; // Enable ATR Candle Range Filter
input double InpATR_MaxMultiplier = 2.0;   // Max Candle Range (ATR * Multiplier)

//=============================================================
// HANDLES
//=============================================================
int g_hRSI  = INVALID_HANDLE;
int g_hKC   = INVALID_HANDLE;
int g_hKAMA = INVALID_HANDLE;
int g_hATR  = INVALID_HANDLE;

//=============================================================
// GLOBAL STATE
//=============================================================
CTrade g_Trade;

//=============================================================
// INIT
//=============================================================
int OnInit()
{
    g_hRSI = iRSI(_Symbol, InpTimeframe, InpRSI_Period, PRICE_CLOSE);
    if (g_hRSI == INVALID_HANDLE)
    {
        Print("EA_MeanReversion: RSI handle creation failed.");
        return INIT_FAILED;
    }

    // KC buffer 0 = Upper, buffer 1 = Middle EMA, buffer 2 = Lower
    g_hKC = iCustom(_Symbol, InpTimeframe,
                    "Keltner Channel",
                    InpKC_EMA_Period,
                    InpKC_ATR_Period,
                    InpKC_Multiplier,
                    false);
    if (g_hKC == INVALID_HANDLE)
    {
        Print("EA_MeanReversion: Keltner Channel handle creation failed.");
        return INIT_FAILED;
    }

    // KAMA buffer 0 = val (filtered KAMA line)
    g_hKAMA = iCustom(_Symbol, InpTimeframe,
                      "KAMA with filter",
                      InpKAMA_Period,
                      InpKAMA_FastEnd,
                      InpKAMA_SlowEnd,
                      2,
                      50,
                      InpKAMA_FilterPeriod,
                      50,
                      PRICE_CLOSE);
    if (g_hKAMA == INVALID_HANDLE)
    {
        Print("EA_MeanReversion: KAMA handle creation failed.");
        return INIT_FAILED;
    }

    if (InpUseATRFilter)
    {
        g_hATR = iATR(_Symbol, InpTimeframe, 14);
        if (g_hATR == INVALID_HANDLE)
        {
            Print("EA_MeanReversion: ATR handle creation failed.");
            return INIT_FAILED;
        }
    }

    g_Trade.SetExpertMagicNumber(InpMagicNumber);
    return INIT_SUCCEEDED;
}

//=============================================================
// DEINIT
//=============================================================
void OnDeinit(const int reason)
{
    if (g_hRSI  != INVALID_HANDLE) IndicatorRelease(g_hRSI);
    if (g_hKC   != INVALID_HANDLE) IndicatorRelease(g_hKC);
    if (g_hKAMA != INVALID_HANDLE) IndicatorRelease(g_hKAMA);
    if (g_hATR  != INVALID_HANDLE) IndicatorRelease(g_hATR);
}

//=============================================================
// MAIN TICK
//=============================================================
void OnTick()
{
    // --- End-hour close check runs every tick
    CheckEndHourClose();

    // --- Exit manager runs on each new candle when position is open
    if (HasOpenPosition())
    {
        if (IsNewCandle())
            RunExitManager();
        return;
    }

    // --- Entry logic: new candle only
    if (!IsNewCandle()) return;

    // 1. Time Filter
    if (!PassesTimeFilter()) return;

    // Load indicator data evaluated at last closed candle (index 1)
    double kama0, kama1;
    if (!GetKAMAValues(kama0, kama1)) return;

    double kcUpper, kcLower;
    if (!GetKCBands(kcUpper, kcLower)) return;

    double rsi;
    if (!GetRSIValue(rsi)) return;

    double closePrice;
    if (!GetClosePrice(closePrice)) return;

    // 2. ATR Filter (optional)
    if (InpUseATRFilter)
    {
        if (!PassesATRFilter()) return;
    }

    // 3. Trend Check (KAMA slope)
    bool kamaUp   = (kama0 > kama1);
    bool kamaDown = (kama0 < kama1);

    // 4. Extreme Check (RSI + Keltner)
    bool sellSignal = kamaUp   && (closePrice > kcUpper) && (rsi > InpRSI_SellLevel);
    bool buySignal  = kamaDown && (closePrice < kcLower)  && (rsi < InpRSI_BuyLevel);

    if (!sellSignal && !buySignal) return;

    bool isBuy = buySignal;

    // 5. Stop Calculation
    double slPrice = CalculateStop(isBuy);
    if (slPrice <= 0.0) return;

    double entryPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                               : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double slDist = MathAbs(entryPrice - slPrice);
    if (slDist <= 0.0) return;

    double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    double freeze  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
    if (slDist < minStop) { Print("EA_MeanReversion: SL below stops level.");  return; }
    if (slDist < freeze)  { Print("EA_MeanReversion: SL inside freeze level."); return; }

    // 6. Risk Lot Calculation
    double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
    double lot = CalculateLotSize(riskMoney, slDist);
    if (lot <= 0.0) return;

    double tpPrice = isBuy ? entryPrice + InpRR_Min * slDist
                           : entryPrice - InpRR_Min * slDist;

    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    entryPrice = NormalizeDouble(entryPrice, digits);
    slPrice    = NormalizeDouble(slPrice,    digits);
    tpPrice    = NormalizeDouble(tpPrice,    digits);

    // 7. Order Execution
    if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL) return;

    ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    if (!g_Trade.PositionOpen(_Symbol, orderType, lot, entryPrice, slPrice, tpPrice))
        Print("EA_MeanReversion: Order failed - ", g_Trade.ResultRetcode());
}

//=============================================================
// EXIT MANAGER
//=============================================================
void RunExitManager()
{
    if (!PositionSelect(_Symbol)) return;
    if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) return;

    bool   isBuy     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    int    digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

    double riskDist  = MathAbs(openPrice - currentSL);
    double curPrice  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    bool reached1R = isBuy ? (curPrice >= openPrice + riskDist)
                           : (curPrice <= openPrice - riskDist);

    // --- KAMA Exit: only allowed after 1R is reached
    if (InpUseKAMAExit && reached1R)
    {
        double kama0, kama1;
        if (GetKAMAValues(kama0, kama1))
        {
            bool kamaInverted = isBuy ? (kama0 < kama1) : (kama0 > kama1);
            if (kamaInverted)
            {
                g_Trade.PositionClose(_Symbol);
                return;
            }
        }
    }

    // --- Trailing After 1R
    if (InpUseTrailingAfter1R && reached1R)
    {
        double newSL = CalculateStop(isBuy);
        if (newSL <= 0.0) return;

        newSL = NormalizeDouble(newSL, digits);

        bool improved = isBuy ? (newSL > currentSL + _Point)
                              : (newSL < currentSL - _Point);
        if (!improved) return;

        double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
        double freeze  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
        if (MathAbs(curPrice - newSL) < minStop) return;
        if (MathAbs(curPrice - newSL) < freeze)  return;

        g_Trade.PositionModify(_Symbol, newSL, currentTP);
    }
}

//=============================================================
// STOP CALCULATION
// BUY:  Lowest Low of last InpStopLookback candles - buffer
// SELL: Highest High of last InpStopLookback candles + buffer
//=============================================================
double CalculateStop(const bool isBuy)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(_Symbol, InpTimeframe, 1, InpStopLookback, rates) < InpStopLookback)
        return 0.0;

    double bufferPoints = InpStopBufferPoints * _Point;

    if (isBuy)
    {
        double lowestLow = rates[0].low;
        for (int i = 1; i < InpStopLookback; i++)
        {
            if (rates[i].low < lowestLow)
                lowestLow = rates[i].low;
        }
        return lowestLow - bufferPoints;
    }
    else
    {
        double highestHigh = rates[0].high;
        for (int i = 1; i < InpStopLookback; i++)
        {
            if (rates[i].high > highestHigh)
                highestHigh = rates[i].high;
        }
        return highestHigh + bufferPoints;
    }
}

//=============================================================
// LOT SIZE
//=============================================================
double CalculateLotSize(const double riskMoney, const double slDist)
{
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if (tickValue <= 0.0 || tickSize <= 0.0 || slDist <= 0.0) return 0.0;

    double lot  = riskMoney / ((slDist / tickSize) * tickValue);
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

    lot = MathFloor(lot / step) * step;
    lot = MathMax(lot, minV);
    lot = MathMin(lot, maxV);
    return lot;
}

//=============================================================
// INDICATOR DATA READERS
//=============================================================

// Returns KAMA[0] and KAMA[1] evaluated at last two closed candles
bool GetKAMAValues(double &kama0, double &kama1)
{
    double buf[];
    ArraySetAsSeries(buf, true);
    // index 1 = last closed candle (KAMA[0] in strategy terms)
    // index 2 = candle before that  (KAMA[1] in strategy terms)
    if (CopyBuffer(g_hKAMA, 0, 1, 2, buf) < 2) return false;
    kama0 = buf[0];
    kama1 = buf[1];
    return true;
}

// Returns Keltner upper and lower bands at last closed candle
bool GetKCBands(double &upper, double &lower)
{
    double bufUpper[];
    double bufLower[];
    ArraySetAsSeries(bufUpper, true);
    ArraySetAsSeries(bufLower, true);
    if (CopyBuffer(g_hKC, 0, 1, 1, bufUpper) < 1) return false;
    if (CopyBuffer(g_hKC, 2, 1, 1, bufLower) < 1) return false;
    upper = bufUpper[0];
    lower = bufLower[0];
    return true;
}

// Returns RSI at last closed candle
bool GetRSIValue(double &rsi)
{
    double buf[];
    ArraySetAsSeries(buf, true);
    if (CopyBuffer(g_hRSI, 0, 1, 1, buf) < 1) return false;
    rsi = buf[0];
    return true;
}

// Returns close price of last closed candle
bool GetClosePrice(double &closePrice)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(_Symbol, InpTimeframe, 1, 1, rates) < 1) return false;
    closePrice = rates[0].close;
    return true;
}

//=============================================================
// ATR FILTER
//=============================================================
bool PassesATRFilter()
{
    if (g_hATR == INVALID_HANDLE) return true;

    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);
    if (CopyBuffer(g_hATR, 0, 1, 20, atrBuf) < 20) return true;

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(_Symbol, InpTimeframe, 1, 1, rates) < 1) return true;

    double atrAvg = 0.0;
    for (int i = 0; i < 20; i++) atrAvg += atrBuf[i];
    atrAvg /= 20.0;

    if (atrAvg <= 0.0) return true;

    double candleRange = rates[0].high - rates[0].low;
    return (candleRange <= atrAvg * InpATR_MaxMultiplier);
}

//=============================================================
// TIME FILTER
//=============================================================
bool PassesTimeFilter()
{
    if (!InpUseTimeFilter) return true;
    MqlDateTime dt;
    TimeToStruct(TimeTradeServer(), dt);
    return (dt.hour >= InpStartHour && dt.hour < InpEndHour);
}

void CheckEndHourClose()
{
    if (!InpUseTimeFilter)            return;
    if (!InpClosePositionsAtEndHour)  return;
    if (!HasOpenPosition())           return;

    MqlDateTime dt;
    TimeToStruct(TimeTradeServer(), dt);
    if (dt.hour >= InpEndHour)
        g_Trade.PositionClose(_Symbol);
}

//=============================================================
// HELPERS
//=============================================================
bool IsNewCandle()
{
    static datetime lastTime = 0;
    datetime currTime = iTime(_Symbol, InpTimeframe, 0);
    if (lastTime != currTime)
    {
        lastTime = currTime;
        return true;
    }
    return false;
}

bool HasOpenPosition()
{
    if (!PositionSelect(_Symbol)) return false;
    return (PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
}
//+------------------------------------------------------------------+
