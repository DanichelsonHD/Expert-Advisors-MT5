#property copyright "Structural Swing Breakout EA v2.0"
#property link      ""
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//=============================================================
// INPUTS
//=============================================================

// --- Core
input ENUM_TIMEFRAMES InpTimeframe         = PERIOD_H1;   // Timeframe (M30 or H1 only)
input int             InpMagicNumber       = 20250101;    // Magic Number

// --- Risk
input double InpRiskPercent        = 0.5;   // Risk Percent per Trade
input double InpRR                 = 2.5;   // Risk:Reward Ratio
input double InpATRStopMultiplier  = 1.5;   // ATR Stop Fallback Multiplier

// --- Structure
input int    InpSwingMinDist       = 10;    // Min Bars Between Swings
input double InpSwingVertMinATR    = 0.8;   // Min Vertical Distance (ATR factor)
input double InpSlopeMinFactor     = 0.02;  // Min Slope Strength (ATR factor)

// --- Regime (Hard Filters)
input double InpCompressionATRFactor = 2.5; // Max Compression Range (ATR factor)
input bool   InpHTFAsHardFilter      = false; // HTF EMA as Hard Filter

// --- Entry Quality (Flex Filters)
input int    InpMinFlexScore        = 3;    // Minimum Flex Score Required
input double InpADXMin              = 20.0; // ADX Strength Threshold
input bool   InpRequireADXRising    = true; // Require Rising ADX
input double InpATRExpansionRatio   = 1.05; // ATR Expansion Ratio
input double InpImpulseATRFactor    = 0.3;  // Min Impulse Body (ATR factor)
input bool   InpUseHTFasFlex        = true; // HTF EMA as Flex Filter
input bool   InpUseSpreadFilter     = true; // Spread Quality as Flex Filter
input bool   InpUseStochasticFlex   = true; // Stochastic as Flex Filter
input double InpStochBuyLevel       = 50.0; // Stochastic Buy Level
input double InpStochSellLevel      = 50.0; // Stochastic Sell Level

// --- Stochastic Parameters
input int InpStochK        = 5;  // Stochastic K
input int InpStochD        = 3;  // Stochastic D
input int InpStochSlowing  = 3;  // Stochastic Slowing

// --- Pullback Entry
input bool   InpEnablePullback        = true; // Enable Pullback Entry
input int    InpPullbackMaxBars       = 10;   // Max Bars for Pullback Window
input double InpPullbackZoneATR       = 0.3;  // Pullback Zone Width (ATR factor)
input bool   InpRequireRejectionCandle = true; // Require Rejection Candle

// --- State Control
input int  InpReEntryCandles         = 10;   // Min Bars After Loss Before Re-Entry
input int  InpFalseBreakMaxBars      = 8;    // Bars to Monitor for False Breakout
input int  InpBreakoutExpiresBars    = 30;   // Bars Until Breakout State Expires

// --- Max Consecutive Losses
input int InpMaxConsecLosses = 3;           // Max Consecutive Losses Before Pause

//=============================================================
// CONSTANTS
//=============================================================
#define ATR_PERIOD       14
#define ADX_PERIOD       14
#define ATR_AVG_BARS     20
#define SPREAD_AVG_BARS  10
#define MAX_SWINGS       50
#define HTF_EMA_PERIOD   200
#define FRACTAL_WING     2
#define DATA_BUFFER      100
#define HTF_TIMEFRAME    PERIOD_H4

//=============================================================
// HANDLES
//=============================================================
int g_hATR      = INVALID_HANDLE;
int g_hADX      = INVALID_HANDLE;
int g_hFractals = INVALID_HANDLE;
int g_hHTF_EMA  = INVALID_HANDLE;
int g_hStoch    = INVALID_HANDLE;

CTrade g_Trade;

//=============================================================
// STRUCTS
//=============================================================

struct SwingPoint
{
    double   price;
    int      barIndex;
    datetime time;
};

struct TrendlineState
{
    double   priceA;
    double   priceB;
    int      idxA;
    int      idxB;
};

struct StrategyState
{
    bool     breakoutActive;
    bool     falseBreak;
    datetime breakoutTime;
    int      direction;       // 1 = buy, -1 = sell
};

struct PullbackState
{
    bool     active;
    datetime startTime;
    int      direction;
};

struct ProtectionState
{
    datetime lastLossTime;
    int      consecLosses;
};

//=============================================================
// CACHED MARKET DATA (loaded once per candle)
//=============================================================
struct TickData
{
    MqlRates rates[DATA_BUFFER];
    double   atr[DATA_BUFFER];
    double   adx[5];
    double   atrAvg;
};

//=============================================================
// GLOBAL STATE
//=============================================================
SwingPoint g_SwingHighs[MAX_SWINGS];
SwingPoint g_SwingLows[MAX_SWINGS];
int        g_SwingHighCount = 0;
int        g_SwingLowCount  = 0;

StrategyState  g_Strategy;
PullbackState  g_Pullback;
ProtectionState g_Protection;
TrendlineState g_Trendline;
TickData       g_Data;

//=============================================================
// INIT
//=============================================================
int OnInit()
{
    if (InpTimeframe != PERIOD_M30 && InpTimeframe != PERIOD_H1)
    {
        Print("Invalid timeframe. Use M30 or H1.");
        return INIT_FAILED;
    }

    g_hATR      = iATR(_Symbol, InpTimeframe, ATR_PERIOD);
    g_hADX      = iADX(_Symbol, InpTimeframe, ADX_PERIOD);
    g_hFractals = iFractals(_Symbol, InpTimeframe);
    g_hHTF_EMA  = iMA(_Symbol, HTF_TIMEFRAME, HTF_EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
    g_hStoch    = iStochastic(_Symbol, InpTimeframe,
                              InpStochK, InpStochD, InpStochSlowing,
                              MODE_SMA, STO_LOWHIGH);

    if (g_hATR      == INVALID_HANDLE ||
        g_hADX      == INVALID_HANDLE ||
        g_hFractals == INVALID_HANDLE ||
        g_hHTF_EMA  == INVALID_HANDLE ||
        g_hStoch    == INVALID_HANDLE)
    {
        Print("Indicator handle creation failed.");
        return INIT_FAILED;
    }

    ResetStrategyState();
    ResetPullbackState();

    g_Protection.lastLossTime  = 0;
    g_Protection.consecLosses  = 0;

    ArraySetAsSeries(g_Data.rates, true);
    ArraySetAsSeries(g_Data.atr,   true);
    ArraySetAsSeries(g_Data.adx,   true);

    g_Trade.SetExpertMagicNumber(InpMagicNumber);

    return INIT_SUCCEEDED;
}

//=============================================================
// DEINIT
//=============================================================
void OnDeinit(const int reason)
{
    if (g_hATR      != INVALID_HANDLE) IndicatorRelease(g_hATR);
    if (g_hADX      != INVALID_HANDLE) IndicatorRelease(g_hADX);
    if (g_hFractals != INVALID_HANDLE) IndicatorRelease(g_hFractals);
    if (g_hHTF_EMA  != INVALID_HANDLE) IndicatorRelease(g_hHTF_EMA);
    if (g_hStoch    != INVALID_HANDLE) IndicatorRelease(g_hStoch);
}

//=============================================================
// TRADE TRANSACTION — TRACK LOSSES
//=============================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
    if (trans.type != TRADE_TRANSACTION_DEAL_ADD)
        return;

    ulong ticket = trans.deal;
    if (ticket == 0 || !HistoryDealSelect(ticket))
        return;

    if (HistoryDealGetInteger(ticket, DEAL_MAGIC)  != InpMagicNumber) return;
    if (HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)        return;
    if (HistoryDealGetInteger(ticket, DEAL_ENTRY)  != DEAL_ENTRY_OUT) return;

    double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

    if (profit < 0.0)
    {
        g_Protection.lastLossTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
        g_Protection.consecLosses++;
    }
    else
    {
        g_Protection.consecLosses = 0;
    }
}

//=============================================================
// MAIN TICK
//=============================================================
void OnTick()
{
    if (!IsNewCandle())
        return;

    if (HasOpenPosition())
        return;

    if (!LoadMarketData())
        return;

    if (g_Protection.consecLosses >= InpMaxConsecLosses)
        return;

    if (!PassesReEntryFilter())
        return;

    DetectSwings();
    TickStrategyState();

    if (g_Strategy.falseBreak)
        return;

    if (g_Strategy.breakoutActive)
    {
        MonitorFalseBreakout();
        return;
    }

    if (InpEnablePullback && g_Pullback.active)
    {
        if (EvaluatePullbackEntry())
        {
            ExecuteTrade();
            return;
        }
    }

    if (EvaluateBreakout())
        ExecuteTrade();
}

//=============================================================
// MODULE A: DATA
//=============================================================
bool LoadMarketData()
{
    if (CopyRates(_Symbol, InpTimeframe, 0, DATA_BUFFER, g_Data.rates) < DATA_BUFFER)
        return false;
    if (CopyBuffer(g_hATR, 0, 0, DATA_BUFFER, g_Data.atr) < DATA_BUFFER)
        return false;
    if (CopyBuffer(g_hADX, 0, 0, 5, g_Data.adx) < 5)
        return false;

    double sum = 0;
    for (int i = 1; i <= ATR_AVG_BARS; i++)
        sum += g_Data.atr[i];

    g_Data.atrAvg = (ATR_AVG_BARS > 0) ? sum / ATR_AVG_BARS : 0;

    return (g_Data.atrAvg > 0);
}

//=============================================================
// MODULE B: STRUCTURE
//=============================================================
void DetectSwings()
{
    const int lookback = DATA_BUFFER;

    double fractalUp[];
    double fractalDn[];
    ArraySetAsSeries(fractalUp, true);
    ArraySetAsSeries(fractalDn, true);

    if (CopyBuffer(g_hFractals, 0, 0, lookback, fractalUp) < lookback) return;
    if (CopyBuffer(g_hFractals, 1, 0, lookback, fractalDn) < lookback) return;

    g_SwingHighCount = 0;
    g_SwingLowCount  = 0;

    double atrAvg = g_Data.atrAvg;

    for (int i = FRACTAL_WING + 1; i < lookback - FRACTAL_WING - 1; i++)
    {
        if (fractalUp[i] != EMPTY_VALUE && fractalUp[i] > 0)
            TryAddSwingHigh(fractalUp[i], i, g_Data.rates[i].time, atrAvg);

        if (fractalDn[i] != EMPTY_VALUE && fractalDn[i] > 0)
            TryAddSwingLow(fractalDn[i], i, g_Data.rates[i].time, atrAvg);
    }
}

void TryAddSwingHigh(const double price, const int idx, const datetime t, const double atrAvg)
{
    if (g_SwingHighCount >= MAX_SWINGS)
        return;

    if (g_SwingHighCount > 0)
    {
        SwingPoint last = g_SwingHighs[g_SwingHighCount - 1];
        if (MathAbs(idx - last.barIndex) < InpSwingMinDist)           return;
        if (MathAbs(price - last.price)  < atrAvg * InpSwingVertMinATR) return;
    }

    g_SwingHighs[g_SwingHighCount].price    = price;
    g_SwingHighs[g_SwingHighCount].barIndex = idx;
    g_SwingHighs[g_SwingHighCount].time     = t;
    g_SwingHighCount++;
}

void TryAddSwingLow(const double price, const int idx, const datetime t, const double atrAvg)
{
    if (g_SwingLowCount >= MAX_SWINGS)
        return;

    if (g_SwingLowCount > 0)
    {
        SwingPoint last = g_SwingLows[g_SwingLowCount - 1];
        if (MathAbs(idx - last.barIndex) < InpSwingMinDist)           return;
        if (MathAbs(price - last.price)  < atrAvg * InpSwingVertMinATR) return;
    }

    g_SwingLows[g_SwingLowCount].price    = price;
    g_SwingLows[g_SwingLowCount].barIndex = idx;
    g_SwingLows[g_SwingLowCount].time     = t;
    g_SwingLowCount++;
}

double ProjectTrendline(const TrendlineState &tl, const int targetIdx)
{
    if (tl.idxA == tl.idxB) return tl.priceA;
    double slope = (tl.priceB - tl.priceA) / double(tl.idxB - tl.idxA);
    return tl.priceA + slope * double(targetIdx - tl.idxA);
}

bool ValidateTrendline(const SwingPoint &ptA, const SwingPoint &ptB)
{
    double atrAvg = g_Data.atrAvg;

    if (MathAbs(ptA.barIndex - ptB.barIndex) < InpSwingMinDist)
        return false;
    if (MathAbs(ptA.price - ptB.price) < atrAvg * InpSwingVertMinATR)
        return false;

    double slope = (ptB.price - ptA.price) / double(ptB.barIndex - ptA.barIndex);
    if (MathAbs(slope) < atrAvg * InpSlopeMinFactor)
        return false;

    return true;
}

//=============================================================
// MODULE C: REGIME (HARD FILTERS)
//=============================================================
bool PassesHardFilters(const bool isBuy, const double trendValue)
{
    double atrAvg = g_Data.atrAvg;

    // Hard 1: Structural breakout close
    if (isBuy  && g_Data.rates[1].close <= trendValue) return false;
    if (!isBuy && g_Data.rates[1].close >= trendValue) return false;

    // Hard 2: Compression validation
    double highest = g_Data.rates[1].high;
    double lowest  = g_Data.rates[1].low;
    for (int i = 2; i <= 10; i++)
    {
        if (g_Data.rates[i].high > highest) highest = g_Data.rates[i].high;
        if (g_Data.rates[i].low  < lowest)  lowest  = g_Data.rates[i].low;
    }
    if ((highest - lowest) > atrAvg * InpCompressionATRFactor)
        return false;

    // Hard 3: Slope already enforced in ValidateTrendline

    // Hard 4: HTF alignment (optional)
    if (InpHTFAsHardFilter)
    {
        double emaBuf[];
        ArraySetAsSeries(emaBuf, true);
        if (CopyBuffer(g_hHTF_EMA, 0, 0, 1, emaBuf) >= 1)
        {
            if (isBuy  && g_Data.rates[1].close <= emaBuf[0]) return false;
            if (!isBuy && g_Data.rates[1].close >= emaBuf[0]) return false;
        }
    }

    return true;
}

//=============================================================
// MODULE D: ENTRY QUALITY (FLEX SCORE)
//=============================================================
int CalculateFlexScore(const bool isBuy)
{
    int    score      = 0;
    double atrCurrent = g_Data.atr[1];
    double atrAvg     = g_Data.atrAvg;
    double adxVal     = g_Data.adx[1];

    // +1 ADX Strength
    if (adxVal > InpADXMin)
        score++;

    // +1 ADX Rising
    if (InpRequireADXRising && g_Data.adx[1] > g_Data.adx[2])
        score++;

    // +1 ATR Expansion
    if (atrCurrent > atrAvg * InpATRExpansionRatio)
        score++;

    // +1 Impulse Body
    double body = MathAbs(g_Data.rates[1].close - g_Data.rates[1].open);
    if (body > atrCurrent * InpImpulseATRFactor)
        score++;

    // +1 Compression Quality
    double highest = g_Data.rates[1].high;
    double lowest  = g_Data.rates[1].low;
    for (int i = 2; i <= 10; i++)
    {
        if (g_Data.rates[i].high > highest) highest = g_Data.rates[i].high;
        if (g_Data.rates[i].low  < lowest)  lowest  = g_Data.rates[i].low;
    }
    if ((highest - lowest) <= atrAvg * InpCompressionATRFactor)
        score++;

    // +1 HTF EMA Alignment (flex only)
    if (InpUseHTFasFlex && !InpHTFAsHardFilter)
    {
        double emaBuf[];
        ArraySetAsSeries(emaBuf, true);
        if (CopyBuffer(g_hHTF_EMA, 0, 0, 1, emaBuf) >= 1)
        {
            if (isBuy  && g_Data.rates[1].close > emaBuf[0]) score++;
            if (!isBuy && g_Data.rates[1].close < emaBuf[0]) score++;
        }
    }

    // +1 Spread Quality
    if (InpUseSpreadFilter)
    {
        double spreadSum  = 0;
        int    validCount = 0;
        for (int i = 1; i <= SPREAD_AVG_BARS; i++)
        {
            if (g_Data.rates[i].spread > 0)
            {
                spreadSum += g_Data.rates[i].spread * _Point;
                validCount++;
            }
        }
        if (validCount > 0)
        {
            double avgSpread = spreadSum / validCount;
            double curSpread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
            if (curSpread > 0 && curSpread <= avgSpread)
                score++;
        }
    }

    // +1 Stochastic Alignment
    if (InpUseStochasticFlex)
    {
        double stochBuf[];
        ArraySetAsSeries(stochBuf, true);
        if (CopyBuffer(g_hStoch, 0, 0, 1, stochBuf) >= 1)
        {
            if (isBuy  && stochBuf[0] > InpStochBuyLevel)  score++;
            if (!isBuy && stochBuf[0] < InpStochSellLevel) score++;
        }
    }

    return score;
}

//=============================================================
// EVALUATE BREAKOUT (pure evaluation, no state change)
//=============================================================
bool EvaluateBreakoutDirection(const int direction,
                               const SwingPoint &ptA,
                               const SwingPoint &ptB)
{
    bool isBuy = (direction == 1);

    TrendlineState tl;
    tl.priceA = ptA.price;
    tl.priceB = ptB.price;
    tl.idxA   = ptA.barIndex;
    tl.idxB   = ptB.barIndex;

    double trendVal = ProjectTrendline(tl, 1);

    if (!PassesHardFilters(isBuy, trendVal))
        return false;

    if (CalculateFlexScore(isBuy) < InpMinFlexScore)
        return false;

    return true;
}

bool EvaluateBreakout()
{
    // BUY: price breaks above descending trendline from two swing highs
    if (g_SwingHighCount >= 2)
    {
        SwingPoint ptA = g_SwingHighs[g_SwingHighCount - 2];
        SwingPoint ptB = g_SwingHighs[g_SwingHighCount - 1];

        if (ptB.price < ptA.price && ValidateTrendline(ptA, ptB))
        {
            if (EvaluateBreakoutDirection(1, ptA, ptB))
            {
                CommitBreakout(1, ptA, ptB);
                return true;
            }
        }
    }

    // SELL: price breaks below ascending trendline from two swing lows
    if (g_SwingLowCount >= 2)
    {
        SwingPoint ptA = g_SwingLows[g_SwingLowCount - 2];
        SwingPoint ptB = g_SwingLows[g_SwingLowCount - 1];

        if (ptB.price > ptA.price && ValidateTrendline(ptA, ptB))
        {
            if (EvaluateBreakoutDirection(-1, ptA, ptB))
            {
                CommitBreakout(-1, ptA, ptB);
                return true;
            }
        }
    }

    return false;
}

//=============================================================
// COMMIT BREAKOUT (state mutation only)
//=============================================================
void CommitBreakout(const int direction, const SwingPoint &ptA, const SwingPoint &ptB)
{
    g_Strategy.breakoutActive = true;
    g_Strategy.falseBreak     = false;
    g_Strategy.direction      = direction;
    g_Strategy.breakoutTime   = g_Data.rates[1].time;

    g_Trendline.priceA = ptA.price;
    g_Trendline.priceB = ptB.price;
    g_Trendline.idxA   = ptA.barIndex;
    g_Trendline.idxB   = ptB.barIndex;

    if (InpEnablePullback)
    {
        g_Pullback.active    = true;
        g_Pullback.startTime = g_Data.rates[1].time;
        g_Pullback.direction = direction;
    }
}

//=============================================================
// MONITOR FALSE BREAKOUT
//=============================================================
void MonitorFalseBreakout()
{
    int barsElapsed = BarsSince(g_Strategy.breakoutTime);

    if (barsElapsed <= 0 || barsElapsed > InpFalseBreakMaxBars)
    {
        g_Strategy.breakoutActive = false;
        return;
    }

    double trendVal = ProjectTrendline(g_Trendline, 1);
    double close    = g_Data.rates[1].close;

    bool falseBreakDetected =
        (g_Strategy.direction == 1  && close < trendVal) ||
        (g_Strategy.direction == -1 && close > trendVal);

    if (falseBreakDetected)
    {
        g_Strategy.falseBreak     = true;
        g_Strategy.breakoutActive = false;
        g_Pullback.active         = false;
    }
}

//=============================================================
// PULLBACK ENTRY
//=============================================================
bool EvaluatePullbackEntry()
{
    if (!g_Pullback.active)
        return false;

    int barsElapsed = BarsSince(g_Pullback.startTime);

    if (barsElapsed > InpPullbackMaxBars)
    {
        g_Pullback.active = false;
        return false;
    }

    double trendVal     = ProjectTrendline(g_Trendline, 1);
    double atrCurrent   = g_Data.atr[1];
    double zoneWidth    = InpPullbackZoneATR * atrCurrent;
    bool   isBuy        = (g_Pullback.direction == 1);

    if (isBuy)
    {
        if (g_Data.rates[1].low > trendVal + zoneWidth) return false;
        if (g_Data.rates[1].low < trendVal - zoneWidth) return false;
    }
    else
    {
        if (g_Data.rates[1].high < trendVal - zoneWidth) return false;
        if (g_Data.rates[1].high > trendVal + zoneWidth) return false;
    }

    if (InpRequireRejectionCandle)
    {
        if (isBuy)
        {
            if (g_Data.rates[1].close <= g_Data.rates[1].open) return false;
            if (g_Data.rates[1].close <= trendVal)             return false;
        }
        else
        {
            if (g_Data.rates[1].close >= g_Data.rates[1].open) return false;
            if (g_Data.rates[1].close >= trendVal)             return false;
        }
    }

    g_Strategy.direction = g_Pullback.direction;
    g_Pullback.active    = false;
    return true;
}

//=============================================================
// MODULE E: RISK
//=============================================================
double CalculateStructuralStop(const bool isBuy, const double entryPrice)
{
    double atrCurrent = g_Data.atr[1];
    double atrStop    = InpATRStopMultiplier * atrCurrent;

    if (isBuy)
    {
        for (int i = g_SwingLowCount - 1; i >= 0; i--)
        {
            if (g_SwingLows[i].price < entryPrice)
                return MathMax(g_SwingLows[i].price, entryPrice - atrStop);
        }
        return entryPrice - atrStop;
    }
    else
    {
        for (int i = g_SwingHighCount - 1; i >= 0; i--)
        {
            if (g_SwingHighs[i].price > entryPrice)
                return MathMin(g_SwingHighs[i].price, entryPrice + atrStop);
        }
        return entryPrice + atrStop;
    }
}

double CalculateLotSize(const double riskMoney, const double slDist)
{
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if (tickValue <= 0 || tickSize <= 0 || slDist <= 0) return 0;

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
// EXECUTE TRADE
//=============================================================
void ExecuteTrade()
{
    if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
        return;

    bool   isBuy  = (g_Strategy.direction == 1);
    double price  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double slPrice = CalculateStructuralStop(isBuy, price);
    double slDist  = MathAbs(price - slPrice);
    if (slDist <= 0) return;

    double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    double freeze  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;

    if (slDist < minStop)
    {
        Print("ExecuteTrade: SL below stops level.");
        return;
    }
    if (slDist < freeze)
    {
        Print("ExecuteTrade: SL inside freeze level.");
        return;
    }

    double tpPrice  = isBuy ? price + InpRR * slDist : price - InpRR * slDist;
    int    digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    price   = NormalizeDouble(price,   digits);
    slPrice = NormalizeDouble(slPrice, digits);
    tpPrice = NormalizeDouble(tpPrice, digits);

    double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
    double lot       = CalculateLotSize(riskMoney, slDist);
    if (lot <= 0) return;

    ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    if (!g_Trade.PositionOpen(_Symbol, orderType, lot, price, slPrice, tpPrice))
        Print("ExecuteTrade: Order failed - ", g_Trade.ResultRetcode());
}

//=============================================================
// MODULE F: STATE
//=============================================================
void TickStrategyState()
{
    // Expire breakout state after N bars
    if (g_Strategy.breakoutActive)
    {
        int barsElapsed = BarsSince(g_Strategy.breakoutTime);
        if (barsElapsed > InpBreakoutExpiresBars)
        {
            g_Strategy.breakoutActive = false;
            g_Pullback.active         = false;
        }
    }

    // Expire false breakout flag after 24h window
    if (g_Strategy.falseBreak)
    {
        int barsElapsed = BarsSince(g_Strategy.breakoutTime);
        if (barsElapsed > InpBreakoutExpiresBars)
        {
            g_Strategy.falseBreak     = false;
            g_Strategy.breakoutActive = false;
        }
    }
}

bool PassesReEntryFilter()
{
    if (g_Protection.lastLossTime == 0)
        return true;

    int lastLossShift = iBarShift(_Symbol, InpTimeframe, g_Protection.lastLossTime, false);
    if (lastLossShift < 0)
        return true;

    int barsSinceLoss = lastLossShift - 1;
    if (barsSinceLoss >= 0 && barsSinceLoss < InpReEntryCandles)
        return false;

    return true;
}

void ResetStrategyState()
{
    g_Strategy.breakoutActive = false;
    g_Strategy.falseBreak     = false;
    g_Strategy.breakoutTime   = 0;
    g_Strategy.direction      = 0;
}

void ResetPullbackState()
{
    g_Pullback.active    = false;
    g_Pullback.startTime = 0;
    g_Pullback.direction = 0;
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
    return (PositionSelect(_Symbol) &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
}

int BarsSince(const datetime t)
{
    if (t == 0) return -1;
    int shift = iBarShift(_Symbol, InpTimeframe, t, false);
    return (shift >= 1) ? shift - 1 : 0;
}