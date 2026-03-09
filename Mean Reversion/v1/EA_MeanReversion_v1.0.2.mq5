//+------------------------------------------------------------------+
//| EA_MeanReversion_v1.0.2.mq5                                      |
//| Mean Reversion - RSI + Keltner Channel + KAMA                    |
//+------------------------------------------------------------------+
#property copyright "Daniel Pereira"
#property link      ""
#property version   "1.02"
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

// --- Take Profit / Exit (kept for input compatibility)
input double InpRR_Min             = 1.5;  // Minimum Risk:Reward (unused - see fractal exit)
input bool   InpUseKAMAExit        = true; // Use KAMA Slope Inversion Exit
input bool   InpUseTrailingAfter1R = true; // Enable Trailing After 1R (unused - see fractal trail)

// --- Time Filter
input bool InpUseTimeFilter           = true;  // Enable Time Filter
input int  InpStartHour               = 9;     // Session Start Hour (Server Time)
input int  InpEndHour                 = 18;    // Session End Hour (Server Time)
input bool InpClosePositionsAtEndHour = true;  // Close Positions at End Hour

// --- ATR Filter (Optional)
input bool   InpUseATRFilter      = false; // Enable ATR Candle Range Filter
input double InpATR_MaxMultiplier = 2.0;   // Max Candle Range (ATR * Multiplier)

// --- Cooldown (preserved for compatibility)
input int InpCooldownCandlesAfterStop = 3; // Cooldown Candles After Stop Loss (legacy)

// --- Fractal Trailing Stop
input int InpFractalStopBufferPoints = 20; // Fractal Stop Buffer (Points)

// --- Entry Delay
input int InpEntryDelayCandles = 2; // Entry evaluated X candles after signal

// --- Cooldown After Stop (separate)
input int InpCooldownAfterStopCandles = 3; // Candles to wait after Stop Loss

//=============================================================
// HANDLES
//=============================================================
int g_hRSI      = INVALID_HANDLE;
int g_hKC       = INVALID_HANDLE;
int g_hKAMA     = INVALID_HANDLE;
int g_hATR      = INVALID_HANDLE;
int g_hFractals = INVALID_HANDLE;

//=============================================================
// GLOBAL STATE
//=============================================================
CTrade g_Trade;

// RSI break+return flags
bool g_rsiBuyBroken  = false;
bool g_rsiSellBroken = false;

// Cooldown counter (counts closed candles remaining)
int g_cooldownCounter = 0;

// Last known position ticket to detect closure
ulong g_lastTicket  = 0;
bool  g_lastWasStop = false;

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

    g_hFractals = iFractals(_Symbol, InpTimeframe);
    if (g_hFractals == INVALID_HANDLE)
    {
        Print("EA_MeanReversion: Fractals handle creation failed.");
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
    if (g_hRSI      != INVALID_HANDLE) IndicatorRelease(g_hRSI);
    if (g_hKC       != INVALID_HANDLE) IndicatorRelease(g_hKC);
    if (g_hKAMA     != INVALID_HANDLE) IndicatorRelease(g_hKAMA);
    if (g_hATR      != INVALID_HANDLE) IndicatorRelease(g_hATR);
    if (g_hFractals != INVALID_HANDLE) IndicatorRelease(g_hFractals);
}

//=============================================================
// MAIN TICK
//=============================================================
void OnTick()
{
    // --- End-hour close check runs every tick
    CheckEndHourClose();

    bool newCandle = IsNewCandle();

    // --- Detect position closure and check if it was a stop
    if (newCandle)
        DetectStopClosure();

    // --- Exit manager runs on each new candle when position is open
    if (HasOpenPosition())
    {
        if (newCandle)
            RunExitManager();
        return;
    }

    if (!newCandle) return;

    // 1. Cooldown After Stop
    if (g_cooldownCounter > 0)
    {
        g_cooldownCounter--;
        return;
    }

    // 2. Time Filter
    if (!PassesTimeFilter()) return;

    // Signal shift: evaluate indicator values at candle (1 + InpEntryDelayCandles)
    int signalShift = 1 + InpEntryDelayCandles;

    // 3. RSI Logic (shifted by delay)
    double rsiBuf[];
    ArraySetAsSeries(rsiBuf, true);
    if (CopyBuffer(g_hRSI, 0, signalShift, 2, rsiBuf) < 2) return;
    double rsiCurrent  = rsiBuf[0]; // RSI at signalShift
    double rsiPrevious = rsiBuf[1]; // RSI at signalShift + 1

    // RSI Break Detection
    if (rsiPrevious > InpRSI_SellLevel)
        g_rsiSellBroken = true;

    if (rsiPrevious < InpRSI_BuyLevel)
        g_rsiBuyBroken = true;

    // RSI Return Confirmation
    bool rsiSellConfirmed = g_rsiSellBroken && (rsiCurrent < InpRSI_SellLevel);
    bool rsiBuyConfirmed  = g_rsiBuyBroken  && (rsiCurrent > InpRSI_BuyLevel);

    if (!rsiSellConfirmed && !rsiBuyConfirmed) return;

    // 4. KAMA Alignment (shifted)
    double kama0, kama1;
    if (!GetKAMAValuesShifted(kama0, kama1, signalShift)) return;

    bool kamaUp   = (kama0 > kama1);
    bool kamaDown = (kama0 < kama1);

    // 5. Keltner Condition (shifted)
    double kcUpper, kcLower;
    if (!GetKCBandsShifted(kcUpper, kcLower, signalShift)) return;

    double closePrice;
    if (!GetClosePriceShifted(closePrice, signalShift)) return;

    // ATR Filter (optional, uses current candle)
    if (InpUseATRFilter)
    {
        if (!PassesATRFilter()) return;
    }

    bool sellSignal = rsiSellConfirmed && kamaUp   && (closePrice > kcUpper);
    bool buySignal  = rsiBuyConfirmed  && kamaDown && (closePrice < kcLower);

    if (!sellSignal && !buySignal) return;

    bool isBuy = buySignal;

    // 6. Stop Calculation (current structure unchanged)
    double slPrice = CalculateStopPreReturn(isBuy);
    if (slPrice <= 0.0) return;

    double entryPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                               : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double slDist = MathAbs(entryPrice - slPrice);
    if (slDist <= 0.0) return;

    double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    double freeze  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
    if (slDist < minStop) { Print("EA_MeanReversion: SL below stops level.");  return; }
    if (slDist < freeze)  { Print("EA_MeanReversion: SL inside freeze level."); return; }

    // 7. Risk Calculation
    double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
    double lot = CalculateLotSize(riskMoney, slDist);
    if (lot <= 0.0) return;

    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    entryPrice = NormalizeDouble(entryPrice, digits);
    slPrice    = NormalizeDouble(slPrice,    digits);

    // 8. Order Execution
    if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL) return;

    ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    if (g_Trade.PositionOpen(_Symbol, orderType, lot, entryPrice, slPrice, 0.0))
    {
        g_rsiBuyBroken  = false;
        g_rsiSellBroken = false;
        g_lastTicket    = g_Trade.ResultDeal();
    }
    else
        Print("EA_MeanReversion: Order failed - ", g_Trade.ResultRetcode());
}

//=============================================================
// EXIT MANAGER
// Fractal Trailing + KAMA Inversion Exit
// Exit manager uses shift=1 (unchanged)
//=============================================================
void RunExitManager()
{
    if (!PositionSelect(_Symbol)) return;
    if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) return;

    bool   isBuy     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
    double currentSL = PositionGetDouble(POSITION_SL);
    int    digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double curPrice  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // --- KAMA Inversion Exit
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

    // --- Fractal Trailing Stop
    double newSL = GetFractalTrailStop(isBuy);
    if (newSL <= 0.0) return;

    newSL = NormalizeDouble(newSL, digits);

    bool improved = isBuy ? (newSL > currentSL + _Point)
                          : (newSL < currentSL - _Point);
    if (!improved) return;

    double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    double freeze  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
    if (MathAbs(curPrice - newSL) < minStop) return;
    if (MathAbs(curPrice - newSL) < freeze)  return;

    g_Trade.PositionModify(_Symbol, newSL, 0.0);
}

//=============================================================
// FRACTAL TRAIL STOP
// BUY:  MathMin(first, second) down fractal - buffer
// SELL: MathMax(first, second) up fractal   + buffer
//=============================================================
double GetFractalTrailStop(const bool isBuy)
{
    const int SEARCH_BARS = 200;
    double fracBuf[];
    ArraySetAsSeries(fracBuf, true);

    double bufferPoints = InpFractalStopBufferPoints * _Point;

    if (isBuy)
    {
        // DOWN fractals: buffer index 1
        if (CopyBuffer(g_hFractals, 1, 0, SEARCH_BARS, fracBuf) < SEARCH_BARS)
            return 0.0;

        double first  = 0.0;
        double second = 0.0;
        int    count  = 0;

        for (int i = 2; i < SEARCH_BARS; i++)
        {
            if (fracBuf[i] != 0.0 && fracBuf[i] != EMPTY_VALUE)
            {
                count++;
                if (count == 1) first  = fracBuf[i];
                if (count == 2) { second = fracBuf[i]; break; }
            }
        }

        if (count < 2) return 0.0;

        double selected = MathMin(first, second);
        return selected - bufferPoints;
    }
    else
    {
        // UP fractals: buffer index 0
        if (CopyBuffer(g_hFractals, 0, 0, SEARCH_BARS, fracBuf) < SEARCH_BARS)
            return 0.0;

        double first  = 0.0;
        double second = 0.0;
        int    count  = 0;

        for (int i = 2; i < SEARCH_BARS; i++)
        {
            if (fracBuf[i] != 0.0 && fracBuf[i] != EMPTY_VALUE)
            {
                count++;
                if (count == 1) first  = fracBuf[i];
                if (count == 2) { second = fracBuf[i]; break; }
            }
        }

        if (count < 2) return 0.0;

        double selected = MathMax(first, second);
        return selected + bufferPoints;
    }
}

//=============================================================
// STOP CALCULATION (pre-return candle, unchanged)
//=============================================================
double CalculateStopPreReturn(const bool isBuy)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(_Symbol, InpTimeframe, 2, InpStopLookback, rates) < InpStopLookback)
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
// STOP CLOSURE DETECTION
//=============================================================
void DetectStopClosure()
{
    if (g_lastTicket == 0) return;
    if (HasOpenPosition())
    {
        g_lastTicket = PositionGetInteger(POSITION_TICKET);
        return;
    }

    if (HistorySelectByPosition(g_lastTicket))
    {
        int deals = HistoryDealsTotal();
        for (int i = deals - 1; i >= 0; i--)
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if (HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == (long)g_lastTicket)
            {
                ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);
                if (reason == DEAL_REASON_SL)
                {
                    g_cooldownCounter = InpCooldownAfterStopCandles;
                }
                break;
            }
        }
    }

    g_lastTicket = 0;
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

// Exit manager: shift=1 (unchanged)
bool GetKAMAValues(double &kama0, double &kama1)
{
    double buf[];
    ArraySetAsSeries(buf, true);
    if (CopyBuffer(g_hKAMA, 0, 1, 2, buf) < 2) return false;
    kama0 = buf[0];
    kama1 = buf[1];
    return true;
}

// Entry logic: shifted by signalShift
bool GetKAMAValuesShifted(double &kama0, double &kama1, const int shift)
{
    double buf[];
    ArraySetAsSeries(buf, true);
    if (CopyBuffer(g_hKAMA, 0, shift, 2, buf) < 2) return false;
    kama0 = buf[0];
    kama1 = buf[1];
    return true;
}

bool GetKCBandsShifted(double &upper, double &lower, const int shift)
{
    double bufUpper[];
    double bufLower[];
    ArraySetAsSeries(bufUpper, true);
    ArraySetAsSeries(bufLower, true);
    if (CopyBuffer(g_hKC, 0, shift, 1, bufUpper) < 1) return false;
    if (CopyBuffer(g_hKC, 2, shift, 1, bufLower) < 1) return false;
    upper = bufUpper[0];
    lower = bufLower[0];
    return true;
}

bool GetClosePriceShifted(double &closePrice, const int shift)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(_Symbol, InpTimeframe, shift, 1, rates) < 1) return false;
    closePrice = rates[0].close;
    return true;
}

bool GetRSIValue(double &rsi)
{
    double buf[];
    ArraySetAsSeries(buf, true);
    if (CopyBuffer(g_hRSI, 0, 1, 1, buf) < 1) return false;
    rsi = buf[0];
    return true;
}

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
    if (!InpUseTimeFilter)           return;
    if (!InpClosePositionsAtEndHour) return;
    if (!HasOpenPosition())          return;

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
