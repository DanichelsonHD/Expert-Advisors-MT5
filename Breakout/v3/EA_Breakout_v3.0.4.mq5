#property copyright "EA_Breakout_v3.0.4"
#property link      ""
#property version   "3.04"
#property strict

#include <Trade\Trade.mqh>

//=============================================================
// INPUTS
//=============================================================

// --- Core
input ENUM_TIMEFRAMES InpTimeframe   = PERIOD_H1; // Timeframe (M30 or H1)
input bool InpDebugDrawStructure     = true;      // Show Trendines on Graphic
input int  InpMagicNumber            = 20250101;  // Magic Number

// --- Risk
input double InpRiskPercent       = 0.5; // Risk % per Trade
input double InpRR                = 1.8; // Risk:Reward Ratio
input double InpATRStopMultiplier = 1.5; // ATR Stop Fallback Multiplier

// --- Structure
input int    InpSwingMinBars    = 5;   // Min Bars Between Swings
input double InpSwingVertMinATR = 0.5; // Min Vertical Swing Distance (ATR)

// --- ZigZag Structure
input bool   InpUseZigZag       = true;   // Use ZigZag instead of fractals
input int    InpZigZagDepth     = 12;     // ZigZag depth
input int    InpZigZagDeviation = 5;      // ZigZag deviation
input int    InpZigZagBackstep  = 3;      // ZigZag backstep

// --- Breakout
input double InpBreakoutBufferATR = 0.1; // Breakout Buffer (ATR fraction)

// --- Structural Validation
input double InpMinSlopeATR        = 0.05;  // Min normalized slope (ATR factor)
input double InpMinBodyPercent     = 0.6;   // Min body % of candle range
input bool   InpUseCompression     = true;  // Enable compression filter
input int    InpCompressionBars    = 10;    // Lookback bars for compression
input double InpCompressionFactor  = 0.8;   // Range must be < ATRAvg * factor
input bool   InpUseSpreadFilter    = true;  // Enable spread filter
input double InpMaxSpreadATR       = 0.2;   // Max spread as ATR fraction

// --- Dynamic Stop Model
input bool InpUseRecentCandleStop = true;   // Enable recent candle stop model
input int  InpStopLookback        = 5;      // Lookback candles for stop calculation

//================ SCORE SYSTEM =================
input double InpScoreThreshold = 8.5;   // Minimum total score required

//================ WEIGHTS - STRUCTURE =================
input double InpWeightDirection   = 2.0;   // LH/HL validation
input double InpWeightSlope       = 2.0;   // Slope strength
input double InpWeightBreakout    = 2.0;   // Close beyond trendline

//================ WEIGHTS - VOLATILITY =================
input double InpWeightATRExpansion = 1.5;  // ATR expansion
input double InpWeightCompression  = 1.0;  // Compression

//================ WEIGHTS - CANDLE =================
input double InpWeightBody = 1.5;   // Body strength

//================ WEIGHTS - CONTEXT =================
input double InpWeightHTF    = 1.0;   // HTF EMA alignment
input double InpWeightSpread = 1.0;   // Spread filter

// --- Regime Filters
input bool   InpUseHTFAlignment   = true;  // Enable HTF EMA Alignment
input int    InpHTFEMAPeriod      = 200;   // HTF EMA Period
input ENUM_TIMEFRAMES InpHTFTimeframe = PERIOD_H4; // HTF timeframe

input bool   InpUseATRExpansion   = true;  // Enable ATR Expansion Filter
input double InpATRExpansionRatio = 1.15;  // Current ATR must be > ATRAvg * ratio

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
int g_hZigZag   = INVALID_HANDLE;
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
    g_hZigZag = iCustom(_Symbol, InpTimeframe,
                        "ZigZag",
                        InpZigZagDepth,
                        InpZigZagDeviation,
                        InpZigZagBackstep);
    g_hHTFEMA   = iMA(_Symbol, InpHTFTimeframe, InpHTFEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

    if (g_hATR == INVALID_HANDLE || g_hZigZag == INVALID_HANDLE)
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
    if (g_hZigZag != INVALID_HANDLE)   IndicatorRelease(g_hZigZag);
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
    g_SwingHighCount = 0;
    g_SwingLowCount  = 0;

    if (!InpUseZigZag)
        return;

    double zzBuffer[DATA_BUFFER];
    ArraySetAsSeries(zzBuffer, true);

    if (CopyBuffer(g_hZigZag, 0, 0, DATA_BUFFER, zzBuffer) < DATA_BUFFER)
        return;

    for (int i = 2; i < DATA_BUFFER - 5; i++)
    {
        if (zzBuffer[i] != 0.0)
        {
            double price = zzBuffer[i];

            // Determine if high or low
            if (price >= g_Rates[i].high - _Point)
                TryAddSwing(g_SwingHighs, g_SwingHighCount, price, i, g_Rates[i].time);
            else if (price <= g_Rates[i].low + _Point)
                TryAddSwing(g_SwingLows, g_SwingLowCount, price, i, g_Rates[i].time);
        }
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
    double baseScore = 0.0;

    if (InpUseSpreadFilter)
    {
        double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
        if (spread <= g_ATR[1] * InpMaxSpreadATR)
            baseScore += InpWeightSpread;
    }

    if (InpUseCompression)
    {
        double highest = g_Rates[1].high;
        double lowest  = g_Rates[1].low;

        for(int i = 2; i <= InpCompressionBars; i++)
        {
            if(g_Rates[i].high > highest) highest = g_Rates[i].high;
            if(g_Rates[i].low  < lowest)  lowest  = g_Rates[i].low;
        }

        if((highest - lowest) <= g_ATRAvg * InpCompressionFactor)
            baseScore += InpWeightCompression;
    }

    double body  = MathAbs(g_Rates[1].close - g_Rates[1].open);
    double range = g_Rates[1].high - g_Rates[1].low;

    if (range > 0 && body / range >= InpMinBodyPercent)
        baseScore += InpWeightBody;

    // BUY
    if (g_SwingHighCount >= InpMinSwingsForBreakout)
    {
        double score = baseScore;
        bool breakoutValid = false;
        
        SwingPoint ptA = g_SwingHighs[g_SwingHighCount - 2];
        SwingPoint ptB = g_SwingHighs[g_SwingHighCount - 1];

        bool structureValid = true;

        for(int i = 1; i < InpMinSwingsForBreakout; i++)
        {
            if(g_SwingHighs[g_SwingHighCount - i].price >
            g_SwingHighs[g_SwingHighCount - i - 1].price)
            {
                structureValid = false;
                break;
            }
        }

        if(InpDebugDrawStructure)
            DrawTrendline(ptA, ptB);

        if(structureValid)
            score += InpWeightDirection;

        double slope = (ptB.price - ptA.price) / double(ptB.barIndex - ptA.barIndex);
        if (MathAbs(slope) >= g_ATRAvg * InpMinSlopeATR)
            score += InpWeightSlope;

        double trendVal = ProjectTrendline(ptA, ptB, 1);

        if (g_Rates[1].high > trendVal + InpBreakoutBufferATR * g_ATR[1])
        {
            score += InpWeightBreakout;
            breakoutValid = true;
        }

        if (InpUseHTFAlignment && g_Rates[1].close > g_htfEMA)
            score += InpWeightHTF;

        if (InpUseATRExpansion && g_ATR[1] >= g_ATRAvg * InpATRExpansionRatio)
            score += InpWeightATRExpansion;

        if (breakoutValid && score >= InpScoreThreshold)
            return 1;
    }

    // SELL
    if (g_SwingLowCount >= InpMinSwingsForBreakout)
    {
        double score = baseScore;
        bool breakoutValid = false;
        
        SwingPoint ptA = g_SwingLows[g_SwingLowCount - 2];
        SwingPoint ptB = g_SwingLows[g_SwingLowCount - 1];

        bool structureValid = true;

        for(int i = 1; i < InpMinSwingsForBreakout; i++)
        {
            if(g_SwingLows[g_SwingLowCount - i].price >
            g_SwingLows[g_SwingLowCount - i - 1].price)
            {
                structureValid = false;
                break;
            }
        }

        if(InpDebugDrawStructure)
            DrawTrendline(ptA, ptB);

        if(structureValid)
            score += InpWeightDirection;

        double slope = (ptB.price - ptA.price) / double(ptB.barIndex - ptA.barIndex);
        if (MathAbs(slope) >= g_ATRAvg * InpMinSlopeATR)
            score += InpWeightSlope;

        double trendVal = ProjectTrendline(ptA, ptB, 1);

        if (g_Rates[1].low < trendVal - InpBreakoutBufferATR * g_ATR[1])
        {
            score += InpWeightBreakout;
            breakoutValid = true;
        }

        if (InpUseHTFAlignment && g_Rates[1].close < g_htfEMA)
            score += InpWeightHTF;

        if (InpUseATRExpansion && g_ATR[1] >= g_ATRAvg * InpATRExpansionRatio)
            score += InpWeightATRExpansion;

        if (breakoutValid && score >= InpScoreThreshold)
            return -1;
    }

    return 0;
}

//=============================================================
// STOP CALCULATION
//=============================================================
double CalculateStop(const bool isBuy, const double entryPrice)
{
    double atrFallback = InpATRStopMultiplier * g_ATR[1];

    // --- Recent Candle Stop Model
    if (InpUseRecentCandleStop)
    {
        if (isBuy)
        {
            double recentLow = g_Rates[1].low;

            for (int i = 2; i <= InpStopLookback; i++)
            {
                if (g_Rates[i].low < recentLow)
                    recentLow = g_Rates[i].low;
            }

            return recentLow;
        }
        else
        {
            double recentHigh = g_Rates[1].high;

            for (int i = 2; i <= InpStopLookback; i++)
            {
                if (g_Rates[i].high > recentHigh)
                    recentHigh = g_Rates[i].high;
            }

            return recentHigh;
        }
    }

    // --- Fallback to ATR-based stop (original logic)
    if (isBuy)
        return entryPrice - atrFallback;
    else
        return entryPrice + atrFallback;
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
    
    double minATRStop = g_ATR[1] * 0.5;  // 0.5 ATR minimum safety
    if (slDist < minATRStop) return;
    
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

//=============================================================
// DEBUG
//=============================================================
void DrawTrendline(const SwingPoint &ptA, const SwingPoint &ptB)
{
    string name = "Trendline_Debug";

    ObjectDelete(0, name);

    ObjectCreate(0, name, OBJ_TREND, 0,
                 ptA.time, ptA.price,
                 ptB.time, ptB.price);

    ObjectSetInteger(0, name, OBJPROP_COLOR, clrGreen);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);

    // This makes the line extend infinitely to the right
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);

    // Optional: disable left ray
    ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
}