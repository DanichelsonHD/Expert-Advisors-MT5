#property copyright "EA_Breakout_v3.0.1"
#property link      ""
#property version   "3.01"
#property strict

#include <Trade\Trade.mqh>

//=============================================================
// INPUTS
//=============================================================

// --- Core
input ENUM_TIMEFRAMES InpTimeframe   = PERIOD_H1; // Timeframe (M30 or H1)
input int             InpMagicNumber = 20250101;  // Magic Number

// --- Risk
input double InpRiskPercent       = 0.5; // Risk % per Trade
input double InpRR                = 2.0; // Risk:Reward Ratio
input double InpATRStopMultiplier = 1.5; // ATR Stop Fallback Multiplier

// --- Structure
input int    InpSwingMinBars    = 5;   // Min Bars Between Swings
input double InpSwingVertMinATR = 0.5; // Min Vertical Swing Distance (ATR)

// --- Breakout
input double InpBreakoutBufferATR = 0.1; // Breakout Buffer (ATR fraction)

// --- Regime Filters
input bool   InpUseHTFAlignment   = true;  // Enable HTF EMA Alignment
input int    InpHTFEMAPeriod      = 200;   // HTF EMA Period
input ENUM_TIMEFRAMES InpHTFTimeframe = PERIOD_H4; // HTF timeframe

input bool   InpUseATRExpansion   = true;  // Enable ATR Expansion Filter
input double InpATRExpansionRatio = 1.05;  // Current ATR must be > ATRAvg * ratio

// --- Session
input bool InpUseSessionFilter = true; // Enable Session Filter
input int  InpSessionStartHour = 6;    // Session Start Hour (UTC)
input int  InpSessionEndHour   = 22;   // Session End Hour (UTC)

// --- Management
input bool InpUseStructuralTrail = true; // Enable Structural Trailing SL

//=============================================================
// CONSTANTS
//=============================================================
#define ATR_PERIOD     14
#define ATR_AVG_BARS   20
#define MAX_SWINGS     50
#define FRACTAL_WING   2
#define DATA_BUFFER    150

//=============================================================
// STRUCTS
//=============================================================
struct SwingPoint
{
    double   price;
    int      barIndex;
    datetime time;
};

//=============================================================
// HANDLES
//=============================================================
int g_hATR      = INVALID_HANDLE;
int g_hFractals = INVALID_HANDLE;
int g_hHTFEMA   = INVALID_HANDLE;

CTrade g_Trade;

//=============================================================
// GLOBAL STATE (minimal)
//=============================================================
SwingPoint g_SwingHighs[MAX_SWINGS];
SwingPoint g_SwingLows[MAX_SWINGS];
int        g_SwingHighCount = 0;
int        g_SwingLowCount  = 0;

// Cached per-candle market data
MqlRates g_Rates[DATA_BUFFER];
double   g_ATR[DATA_BUFFER];
double   g_ATRAvg = 0;
double   g_htfEMA = 0;

//=============================================================
// INIT
//=============================================================
int OnInit()
{
    if (InpTimeframe != PERIOD_M30 && InpTimeframe != PERIOD_H1)
    {
        Print("EA_Breakout: Use M30 or H1 only.");
        return INIT_FAILED;
    }

    g_hATR      = iATR(_Symbol, InpTimeframe, ATR_PERIOD);
    g_hFractals = iFractals(_Symbol, InpTimeframe);
    g_hHTFEMA   = iMA(_Symbol, InpHTFTimeframe, InpHTFEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

    if (g_hATR == INVALID_HANDLE || g_hFractals == INVALID_HANDLE)
    {
        Print("EA_Breakout: Indicator handle creation failed.");
        return INIT_FAILED;
    }

    if(g_hHTFEMA == INVALID_HANDLE)
    {
        Print("HTF EMA handle failed.");
        return INIT_FAILED;
    }

    ArraySetAsSeries(g_Rates, true);
    ArraySetAsSeries(g_ATR,   true);

    g_Trade.SetExpertMagicNumber(InpMagicNumber);
    return INIT_SUCCEEDED;
}

//=============================================================
// DEINIT
//=============================================================
void OnDeinit(const int reason)
{
    if (g_hATR      != INVALID_HANDLE) IndicatorRelease(g_hATR);
    if (g_hFractals != INVALID_HANDLE) IndicatorRelease(g_hFractals);
    if (g_hHTFEMA   != INVALID_HANDLE) IndicatorRelease(g_hHTFEMA);
}

//=============================================================
// MAIN TICK
//=============================================================
void OnTick()
{
    if (HasOpenPosition())
    {
        if (InpUseStructuralTrail && IsNewCandle())
        {
            if (LoadMarketData())
            {
                DetectSwings();
                ManageTrail();
            }
        }
        return;
    }

    if (!IsNewCandle())    return;
    if (!LoadMarketData()) return;
    if (!PassesSession())  return;

    DetectSwings();

    int direction = CheckBreakout();
    if (direction != 0)
        ExecuteBreakout(direction);
}

//=============================================================
// DATA LOADER
//=============================================================
bool LoadMarketData()
{
    if (CopyRates(_Symbol, InpTimeframe, 0, DATA_BUFFER, g_Rates) < DATA_BUFFER)
        return false;
    if (CopyBuffer(g_hATR, 0, 0, DATA_BUFFER, g_ATR) < DATA_BUFFER)
        return false;

    double htfBuf[1];
    ArraySetAsSeries(htfBuf, true);
    
    if (InpUseHTFAlignment)
    {
        if (CopyBuffer(g_hHTFEMA, 0, 0, 1, htfBuf) >= 1)
            g_htfEMA = htfBuf[0];
    }

    double sum = 0;
    for (int i = 1; i <= ATR_AVG_BARS; i++)
        sum += g_ATR[i];

    g_ATRAvg = sum / ATR_AVG_BARS;
    return (g_ATRAvg > 0);
}

//=============================================================
// SWING DETECTION
//=============================================================
void DetectSwings()
{
    double fractalUp[DATA_BUFFER];
    double fractalDn[DATA_BUFFER];
    ArraySetAsSeries(fractalUp, true);
    ArraySetAsSeries(fractalDn, true);

    if (CopyBuffer(g_hFractals, 0, 0, DATA_BUFFER, fractalUp) < DATA_BUFFER) return;
    if (CopyBuffer(g_hFractals, 1, 0, DATA_BUFFER, fractalDn) < DATA_BUFFER) return;

    g_SwingHighCount = 0;
    g_SwingLowCount  = 0;

    for (int i = FRACTAL_WING + 1; i < DATA_BUFFER - FRACTAL_WING - 1; i++)
    {
        if (fractalUp[i] != EMPTY_VALUE && fractalUp[i] > 0)
            TryAddSwing(g_SwingHighs, g_SwingHighCount, fractalUp[i], i, g_Rates[i].time);

        if (fractalDn[i] != EMPTY_VALUE && fractalDn[i] > 0)
            TryAddSwing(g_SwingLows,  g_SwingLowCount,  fractalDn[i], i, g_Rates[i].time);
    }
}

void TryAddSwing(SwingPoint &swings[], int &count, const double price,
                 const int idx, const datetime t)
{
    if (count >= MAX_SWINGS) return;

    if (count > 0)
    {
        if (MathAbs(idx - swings[count - 1].barIndex) < InpSwingMinBars)              return;
        if (MathAbs(price - swings[count - 1].price)  < g_ATRAvg * InpSwingVertMinATR) return;
    }

    swings[count].price    = price;
    swings[count].barIndex = idx;
    swings[count].time     = t;
    count++;
}

//=============================================================
// TRENDLINE HELPERS
//=============================================================
double ProjectTrendline(const SwingPoint &ptA, const SwingPoint &ptB, const int targetIdx)
{
    if (ptA.barIndex == ptB.barIndex) return ptA.price;
    double slope = (ptB.price - ptA.price) / double(ptB.barIndex - ptA.barIndex);
    return ptA.price + slope * double(targetIdx - ptA.barIndex);
}

//=============================================================
// ENTRY MODULE
//=============================================================
int CheckBreakout()
{
    double buffer = InpBreakoutBufferATR * g_ATR[1];
    double close  = g_Rates[1].close;

    // BUY: close breaks above projected swing-high trendline
    if (g_SwingHighCount >= 2)
    {
        SwingPoint ptA = g_SwingHighs[g_SwingHighCount - 2];
        SwingPoint ptB = g_SwingHighs[g_SwingHighCount - 1];
        double trendVal = ProjectTrendline(ptA, ptB, 1);

        if (close > trendVal + buffer)
        {
            if (InpUseHTFAlignment && close <= g_htfEMA)
                return 0;

            if (InpUseATRExpansion && g_ATR[1] <= g_ATRAvg * InpATRExpansionRatio)
                return 0;

            return 1;
        }
    }

    // SELL: close breaks below projected swing-low trendline
    if (g_SwingLowCount >= 2)
    {
        SwingPoint ptA = g_SwingLows[g_SwingLowCount - 2];
        SwingPoint ptB = g_SwingLows[g_SwingLowCount - 1];
        double trendVal = ProjectTrendline(ptA, ptB, 1);

        if (close < trendVal - buffer)
        {
            if (InpUseHTFAlignment && close >= g_htfEMA)
                return 0;

            if (InpUseATRExpansion && g_ATR[1] <= g_ATRAvg * InpATRExpansionRatio)
                return 0;

            return -1;
        }
    }

    return 0;
}

//=============================================================
// STOP CALCULATION
//=============================================================
double CalculateStop(const bool isBuy, const double entryPrice)
{
    double atrStop = InpATRStopMultiplier * g_ATR[1];

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

//=============================================================
// LOT SIZE
//=============================================================
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
// EXECUTION MODULE
//=============================================================
void ExecuteBreakout(const int direction)
{
    if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
        return;

    bool   isBuy  = (direction == 1);
    double price  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double slPrice = CalculateStop(isBuy, price);
    double slDist  = MathAbs(price - slPrice);
    if (slDist <= 0) return;

    double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * _Point;
    double freeze  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
    if (slDist < minStop) { Print("ExecuteBreakout: SL below stops level.");  return; }
    if (slDist < freeze)  { Print("ExecuteBreakout: SL inside freeze level."); return; }

    double tpPrice = isBuy ? price + InpRR * slDist : price - InpRR * slDist;
    int    digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

    price   = NormalizeDouble(price,   digits);
    slPrice = NormalizeDouble(slPrice, digits);
    tpPrice = NormalizeDouble(tpPrice, digits);

    double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
    double lot       = CalculateLotSize(riskMoney, slDist);
    if (lot <= 0) return;

    ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    if (!g_Trade.PositionOpen(_Symbol, orderType, lot, price, slPrice, tpPrice))
        Print("ExecuteBreakout: Order failed - ", g_Trade.ResultRetcode());
}

//=============================================================
// MANAGEMENT MODULE — STRUCTURAL TRAIL
//=============================================================
void ManageTrail()
{
    if (!PositionSelect(_Symbol)) return;
    if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) return;

    bool   isBuy      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
    double currentSL  = PositionGetDouble(POSITION_SL);
    double currentTP  = PositionGetDouble(POSITION_TP);
    double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double curPrice   = isBuy ? bid : ask;
    int    digits     = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double newSL      = currentSL;

    if (isBuy)
    {
        for (int i = g_SwingLowCount - 1; i >= 0; i--)
        {
            double swingPrice = g_SwingLows[i].price;
            if (swingPrice < curPrice && swingPrice > newSL)
            {
                newSL = swingPrice;
                break;
            }
        }
    }
    else
    {
        for (int i = g_SwingHighCount - 1; i >= 0; i--)
        {
            double swingPrice = g_SwingHighs[i].price;
            if (swingPrice > curPrice && swingPrice < newSL)
            {
                newSL = swingPrice;
                break;
            }
        }
    }

    newSL = NormalizeDouble(newSL, digits);

    bool improved = isBuy ? (newSL > currentSL + _Point)
                          : (newSL < currentSL - _Point);
    if (!improved) return;

    double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)  * _Point;
    double freeze  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
    if (MathAbs(curPrice - newSL) < minStop) return;
    if (MathAbs(curPrice - newSL) < freeze)  return;

    g_Trade.PositionModify(_Symbol, newSL, currentTP);
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

bool PassesSession()
{
    if (!InpUseSessionFilter) return true;
    MqlDateTime dt;
    TimeToStruct(TimeTradeServer(), dt);
    return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);
}