//+------------------------------------------------------------------+
//| EA_MeanReversion_v1.0.3.mq5                                      |
//| Mean Reversion - RSI + Keltner Channel + KAMA                    |
//| PATCHED: KAMA Color Inversion Exit (Swing TP)                    |
//+------------------------------------------------------------------+
#property copyright "Daniel Pereira"
#property link      ""
#property version   "1.03"
#property strict

#include <Trade\Trade.mqh>

//=============================================================
// INPUTS
//=============================================================

// --- Core
input ENUM_TIMEFRAMES InpTimeframe   = PERIOD_H1;  // Timeframe (M15, M30, H1)
input int              InpMagicNumber = 123456;      // Magic Number

// --- Risk
input double InpRiskPercent = 1.0; // Risk % per Trade

// --- RSI
input int    InpRSI_Period    = 7;    // RSI Period
input double InpRSI_BuyLevel  = 20.0; // RSI Buy Level
input double InpRSI_SellLevel = 72.0; // RSI Sell Level

// --- Keltner Channel
input int    InpKC_EMA_Period = 21;  // KC EMA Period
input int    InpKC_ATR_Period = 7;    // KC ATR Period
input double InpKC_Multiplier = 3.0; // KC ATR Multiplier

// --- KAMA
input int InpKAMA_Period       = 14; // KAMA Period
input int InpKAMA_FastEnd      = 3;  // KAMA Fast End Period
input int InpKAMA_SlowEnd      = 30; // KAMA Slow End Period
input int InpKAMA_FilterPeriod = 7;  // KAMA Filter Period

// --- Stop Loss
input int    InpStopLookback     = 6;  // Stop Lookback Candles
input double InpStopBufferPoints = 30; // Stop Buffer (Points)

// --- Take Profit / Exit (KAMA Color Inversion Active)
input bool   InpUseKAMAExit        = true; // Use KAMA Color Inversion Exit

// --- Time Filter
input bool InpUseTimeFilter           = true;  // Enable Time Filter
input int  InpStartHour               = 9;     // Session Start Hour (Server Time)
input int  InpEndHour                 = 18;    // Session End Hour (Server Time)
input bool InpClosePositionsAtEndHour = true;  // Close Positions at End Hour

// --- ATR Filter (Optional)
input bool   InpUseATRFilter      = false; // Enable ATR Candle Range Filter
input double InpATR_MaxMultiplier = 2.0;   // Max Candle Range (ATR * Multiplier)

// --- Fractal Trailing Stop
input int InpFractalStopBufferPoints = 20; // Fractal Stop Buffer (Points)

// --- Entry Delay
input int InpEntryDelayCandles = 0; // Entry evaluated X candles after signal

// --- Cooldown After Stop
input int InpCooldownAfterStopCandles = 4; // Candles to wait after Stop Loss

//=============================================================
// HANDLES & STATE
//=============================================================
int g_hRSI      = INVALID_HANDLE;
int g_hKC       = INVALID_HANDLE;
int g_hKAMA      = INVALID_HANDLE;
int g_hATR      = INVALID_HANDLE;
int g_hFractals = INVALID_HANDLE;

CTrade g_Trade;
bool g_rsiBuyBroken  = false;
bool g_rsiSellBroken = false;
int g_cooldownCounter = 0;
ulong g_lastTicket  = 0;

//=============================================================
// INIT
//=============================================================
int OnInit()
{
    g_hRSI = iRSI(_Symbol, InpTimeframe, InpRSI_Period, PRICE_CLOSE);
    
    g_hKC = iCustom(_Symbol, InpTimeframe, "Keltner Channel", InpKC_EMA_Period, InpKC_ATR_Period, InpKC_Multiplier, false);

    // KAMA buffer 0 = value, buffer 1 = color/direction
    g_hKAMA = iCustom(_Symbol, InpTimeframe, "KAMA with filter", InpKAMA_Period, InpKAMA_FastEnd, InpKAMA_SlowEnd, 2, 50, InpKAMA_FilterPeriod, 50, PRICE_CLOSE);

    g_hFractals = iFractals(_Symbol, InpTimeframe);

    if (InpUseATRFilter) g_hATR = iATR(_Symbol, InpTimeframe, 14);

    if (g_hRSI == INVALID_HANDLE || g_hKC == INVALID_HANDLE || g_hKAMA == INVALID_HANDLE || g_hFractals == INVALID_HANDLE)
        return INIT_FAILED;

    g_Trade.SetExpertMagicNumber(InpMagicNumber);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    IndicatorRelease(g_hRSI);
    IndicatorRelease(g_hKC);
    IndicatorRelease(g_hKAMA);
    IndicatorRelease(g_hATR);
    IndicatorRelease(g_hFractals);
}

//=============================================================
// MAIN TICK
//=============================================================
void OnTick()
{
    CheckEndHourClose();
    bool newCandle = IsNewCandle();
    if (newCandle) DetectStopClosure();

    if (HasOpenPosition())
    {
        if (newCandle) RunExitManager();
        return;
    }

    if (!newCandle) return;
    if (g_cooldownCounter > 0) { g_cooldownCounter--; return; }
    if (!PassesTimeFilter()) return;

    int signalShift = 1 + InpEntryDelayCandles;

    double rsiBuf[];
    ArraySetAsSeries(rsiBuf, true);
    if (CopyBuffer(g_hRSI, 0, signalShift, 2, rsiBuf) < 2) return;
    
    if (rsiBuf[1] > InpRSI_SellLevel) g_rsiSellBroken = true;
    if (rsiBuf[1] < InpRSI_BuyLevel)  g_rsiBuyBroken = true;

    bool rsiSellConfirmed = g_rsiSellBroken && (rsiBuf[0] < InpRSI_SellLevel);
    bool rsiBuyConfirmed  = g_rsiBuyBroken  && (rsiBuf[0] > InpRSI_BuyLevel);

    if (!rsiSellConfirmed && !rsiBuyConfirmed) return;

    double kama0, kama1;
    if (!GetKAMAValuesShifted(kama0, kama1, signalShift)) return;

    double kcUpper, kcLower;
    if (!GetKCBandsShifted(kcUpper, kcLower, signalShift)) return;

    double closePrice;
    if (!GetClosePriceShifted(closePrice, signalShift)) return;

    if (InpUseATRFilter && !PassesATRFilter()) return;

    bool sellSignal = rsiSellConfirmed && (kama0 > kama1) && (closePrice > kcUpper);
    bool buySignal  = rsiBuyConfirmed  && (kama0 < kama1) && (closePrice < kcLower);

    if (!sellSignal && !buySignal) return;

    bool isBuy = buySignal;
    double slPrice = CalculateStopPreReturn(isBuy);
    if (slPrice <= 0.0) return;

    double entryPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double slDist = MathAbs(entryPrice - slPrice);
    
    double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
    double lot = CalculateLotSize(riskMoney, slDist);
    if (lot <= 0.0) return;

    if (g_Trade.PositionOpen(_Symbol, isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, lot, entryPrice, slPrice, 0.0))
    {
        g_rsiBuyBroken = false; g_rsiSellBroken = false;
        g_lastTicket = g_Trade.ResultDeal();
    }
}

//=============================================================
// EXIT MANAGER (PATCHED)
//=============================================================
void RunExitManager()
{
    if (!PositionSelect(_Symbol)) return;
    if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) return;

    bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
    
    // --- KAMA COLOR INVERSION EXIT (SWING TAKE) ---
    int kamaColor0, kamaColor1;
    if (GetKAMAColor(kamaColor0, kamaColor1))
    {
        // BUY: exit when KAMA turns bearish (2 -> 1)
        if (isBuy && kamaColor1 == 2 && kamaColor0 == 1)
        {
            g_Trade.PositionClose(_Symbol);
            return;
        }
        // SELL: exit when KAMA turns bullish (1 -> 2)
        if (!isBuy && kamaColor1 == 1 && kamaColor0 == 2)
        {
            g_Trade.PositionClose(_Symbol);
            return;
        }
    }

    // --- Fractal Trailing Stop remains as secondary protection ---
    double currentSL = PositionGetDouble(POSITION_SL);
    double newSL = GetFractalTrailStop(isBuy);
    if (newSL > 0.0)
    {
        newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
        if (isBuy ? (newSL > currentSL + _Point) : (newSL < currentSL - _Point))
            g_Trade.PositionModify(_Symbol, newSL, 0.0);
    }
}

//=============================================================
// INDICATOR DATA READERS
//=============================================================
bool GetKAMAColor(int &color0, int &color1)
{
    double buf[];
    ArraySetAsSeries(buf, true);
    // Buffer 1 is the color/direction buffer
    if (CopyBuffer(g_hKAMA, 1, 1, 2, buf) < 2) return false;
    color0 = (int)buf[0]; // Last closed candle
    color1 = (int)buf[1]; // Previous candle
    return true;
}

bool GetKAMAValuesShifted(double &kama0, double &kama1, const int shift)
{
    double buf[];
    ArraySetAsSeries(buf, true);
    if (CopyBuffer(g_hKAMA, 0, shift, 2, buf) < 2) return false;
    kama0 = buf[0]; kama1 = buf[1];
    return true;
}

bool GetKCBandsShifted(double &upper, double &lower, const int shift)
{
    double bufU[], bufL[];
    ArraySetAsSeries(bufU, true); ArraySetAsSeries(bufL, true);
    if (CopyBuffer(g_hKC, 0, shift, 1, bufU) < 1 || CopyBuffer(g_hKC, 2, shift, 1, bufL) < 1) return false;
    upper = bufU[0]; lower = bufL[0];
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

//=============================================================
// CORE FUNCTIONS (UNTOUCHED)
//=============================================================
double GetFractalTrailStop(const bool isBuy)
{
    const int SEARCH_BARS = 200;
    double fracBuf[];
    ArraySetAsSeries(fracBuf, true);
    if (CopyBuffer(g_hFractals, isBuy ? 1 : 0, 0, SEARCH_BARS, fracBuf) < SEARCH_BARS) return 0.0;
    double f1 = 0, f2 = 0; int count = 0;
    for (int i = 2; i < SEARCH_BARS; i++) {
        if (fracBuf[i] != 0.0 && fracBuf[i] != EMPTY_VALUE) {
            if (++count == 1) f1 = fracBuf[i];
            if (count == 2) { f2 = fracBuf[i]; break; }
        }
    }
    if (count < 2) return 0.0;
    return isBuy ? MathMin(f1, f2) - InpFractalStopBufferPoints * _Point : MathMax(f1, f2) + InpFractalStopBufferPoints * _Point;
}

double CalculateStopPreReturn(const bool isBuy)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(_Symbol, InpTimeframe, 2, InpStopLookback, rates) < InpStopLookback) return 0.0;
    double val = isBuy ? rates[0].low : rates[0].high;
    for (int i = 1; i < InpStopLookback; i++)
        if (isBuy) { if (rates[i].low < val) val = rates[i].low; } else { if (rates[i].high > val) val = rates[i].high; }
    return isBuy ? val - InpStopBufferPoints * _Point : val + InpStopBufferPoints * _Point;
}

void DetectStopClosure()
{
    if (g_lastTicket == 0 || HasOpenPosition()) return;
    if (HistorySelectByPosition(g_lastTicket)) {
        int deals = HistoryDealsTotal();
        for (int i = deals - 1; i >= 0; i--) {
            ulong t = HistoryDealGetTicket(i);
            if (HistoryDealGetInteger(t, DEAL_POSITION_ID) == (long)g_lastTicket) {
                if (HistoryDealGetInteger(t, DEAL_REASON) == DEAL_REASON_SL) g_cooldownCounter = InpCooldownAfterStopCandles;
                break;
            }
        }
    }
    g_lastTicket = 0;
}

double CalculateLotSize(const double riskMoney, const double slDist)
{
    double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if (tv <= 0 || ts <= 0 || slDist <= 0) return 0;
    double lot = riskMoney / ((slDist / ts) * tv);
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    return MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), MathFloor(lot / step) * step));
}

bool PassesATRFilter()
{
    double buf[]; ArraySetAsSeries(buf, true);
    if (CopyBuffer(g_hATR, 0, 1, 20, buf) < 20) return true;
    double avg = 0; for (int i = 0; i < 20; i++) avg += buf[i];
    MqlRates r[]; ArraySetAsSeries(r, true); CopyRates(_Symbol, InpTimeframe, 1, 1, r);
    return ((r[0].high - r[0].low) <= (avg / 20.0) * InpATR_MaxMultiplier);
}

bool PassesTimeFilter() {
    if (!InpUseTimeFilter) return true;
    MqlDateTime dt; TimeToStruct(TimeTradeServer(), dt);
    return (dt.hour >= InpStartHour && dt.hour < InpEndHour);
}

void CheckEndHourClose() {
    if (InpUseTimeFilter && InpClosePositionsAtEndHour && HasOpenPosition()) {
        MqlDateTime dt; TimeToStruct(TimeTradeServer(), dt);
        if (dt.hour >= InpEndHour) g_Trade.PositionClose(_Symbol);
    }
}

bool IsNewCandle() {
    static datetime lt = 0; datetime ct = iTime(_Symbol, InpTimeframe, 0);
    if (lt != ct) { lt = ct; return true; } return false;
}

bool HasOpenPosition() {
    return (PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
}