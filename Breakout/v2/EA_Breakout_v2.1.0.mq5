#property copyright "EA_Breakout_v2.1.0"
#property link      ""
#property version   "2.10"
#property strict

#include <Trade\Trade.mqh>

//=============================================================
// INPUTS
//=============================================================

// --- Core
input ENUM_TIMEFRAMES InpTimeframe   = PERIOD_H1;  // Timeframe (M30 or H1)
input int             InpMagicNumber = 20250101;   // Magic Number

// --- Risk
input double InpRiskPercent       = 0.5;  // Risk % per Trade
input double InpRR                = 2.5;  // Risk:Reward Ratio
input double InpATRStopMultiplier = 1.5;  // ATR Stop Fallback Multiplier

// --- Structure Detection
input int    InpSwingMinBars      = 8;   // Min Bars Between Swings
input double InpSwingVertMinATR   = 0.6;  // Min Vertical Swing Distance (ATR)
input double InpSlopeMinATR       = 0.00; // Min Trendline Slope (ATR factor)

// --- Session Filter
input bool InpUseSessionFilter  = true; // Enable Session Filter
input int  InpSessionStartHour  = 6;    // Session Start Hour (UTC)
input int  InpSessionEndHour    = 22;   // Session End Hour (UTC)

// --- Hard Filter Thresholds
input double InpHardSpreadMaxATR = 0.15; // Max Spread as ATR fraction (Hard)

// --- Flex Filter Weights
input double InpMinFlexScore       = 2.0;  // Minimum Weighted Flex Score
input double W_ADX_Strength        = 1.0;  // Weight: ADX Strength
input double W_ADX_Rising          = 1.0;  // Weight: ADX Rising
input double W_ATR_Expansion       = 1.4;  // Weight: ATR Expansion
input double W_Impulse_Body        = 1.0;  // Weight: Impulse Candle Body
input double W_Compression         = 1.0;  // Weight: Compression Quality
input double W_HTF_Alignment       = 1.4;  // Weight: HTF EMA Alignment
input double W_Spread_Quality      = 0.6;  // Weight: Spread Quality
input double W_Stoch_Alignment     = 0.8;  // Weight: Stochastic Alignment
input double W_Slope_Strength      = 0.7;  // Weight: Trendline Slope

// --- Flex Filter Thresholds
input double InpADXMin              = 20.0; // ADX Strength Threshold
input bool   InpADXRisingEnabled    = true; // Enable ADX Rising Filter
input double InpATRExpansionRatio   = 1.05; // ATR Expansion Ratio
input double InpImpulseBodyATR      = 0.3;  // Min Impulse Body (ATR factor)
input double InpCompressionATR      = 2.5;  // Max Compression Range (ATR)
input bool   InpHTFFlexEnabled      = true; // Enable HTF EMA Flex Filter
input bool   InpSpreadFlexEnabled   = true; // Enable Spread Flex Filter
input bool   InpStochFlexEnabled    = true; // Enable Stochastic Flex Filter
input double InpStochBuyLevel       = 50.0; // Stochastic Buy Threshold
input double InpStochSellLevel      = 50.0; // Stochastic Sell Threshold

// --- Stochastic Params
input int InpStochK       = 5;  // Stochastic K Period
input int InpStochD       = 3;  // Stochastic D Period
input int InpStochSlowing = 3;  // Stochastic Slowing

// --- Pullback Entry
input bool   InpPullbackEnabled     = true; // Enable Pullback Entry
input int    InpPullbackMaxBars     = 10;   // Max Bars for Pullback Window
input double InpPullbackZoneATR     = 0.3;  // Pullback Zone Width (ATR)
input bool   InpPullbackNeedCandle  = true; // Require Rejection Candle

// --- Position Management
input bool   InpUseStructuralTrail  = true; // Enable Structural Trailing
input bool   InpUseATRTrail         = true; // Enable ATR Trailing (after 1R)
input double InpATRTrailMultiplier  = 1.5;  // ATR Trail Distance Multiplier
input bool   InpUseEMATrail         = false; // Enable EMA(20) Trail Protection
input int    InpEMAPeriod           = 20;   // EMA Period for Trail

// --- Early Exit
input bool   InpUseEarlyExit        = true; // Enable Early Exit Engine
input double InpExitThreshold       = 2.0;  // Exit Score Threshold
input double W_Exit_OppositeImpulse = 1.5;  // Exit Weight: Opposite Impulse
input double W_Exit_StructFlip      = 2.0;  // Exit Weight: Structure Flip
input double W_Exit_ADXCollapse     = 1.0;  // Exit Weight: ADX Collapse
input double W_Exit_ATRContraction  = 0.8;  // Exit Weight: ATR Contraction
input double W_Exit_EMABreak        = 0.7;  // Exit Weight: Close Against EMA

// --- Partial Close
input bool   InpPartialCloseEnabled = false; // Enable Partial Close at 1R
input double InpPartialCloseRR      = 1.0;   // Partial Close R Level

// --- State Control
input int  InpReEntryBars           = 10;  // Min Bars After Loss (Re-Entry)
input int  InpFalseBreakBars        = 8;   // False Breakout Monitor Window
input int  InpBreakoutExpireBars    = 30;  // Breakout State Expiry (Bars)
input int  InpMaxConsecLosses       = 3;   // Max Consecutive Losses (Pause)

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
#define DATA_BUFFER      150
#define HTF_TIMEFRAME    PERIOD_H4

//=============================================================
// ENUMS
//=============================================================
enum FilterType { FILTER_HARD, FILTER_FLEX, FILTER_DISABLED };

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
    double priceA;
    double priceB;
    int    idxA;
    int    idxB;
};

struct StrategyState
{
    bool     breakoutActive;
    bool     falseBreak;
    datetime breakoutTime;
    int      direction;
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

struct PartialCloseState
{
    bool done;
};

struct TickData
{
    MqlRates rates[DATA_BUFFER];
    double   atr[DATA_BUFFER];
    double   adx[5];
    double   atrAvg;
    double   htfEMA;
    double   stoch;
    double   ema20[3];
};

//=============================================================
// INDICATOR HANDLES
//=============================================================
int g_hATR      = INVALID_HANDLE;
int g_hADX      = INVALID_HANDLE;
int g_hFractals = INVALID_HANDLE;
int g_hHTF_EMA  = INVALID_HANDLE;
int g_hStoch    = INVALID_HANDLE;
int g_hEMA20    = INVALID_HANDLE;

CTrade g_Trade;

//=============================================================
// GLOBAL STATE
//=============================================================
SwingPoint      g_SwingHighs[MAX_SWINGS];
SwingPoint      g_SwingLows[MAX_SWINGS];
int             g_SwingHighCount = 0;
int             g_SwingLowCount  = 0;

StrategyState   g_Strategy;
PullbackState   g_Pullback;
ProtectionState g_Protection;
TrendlineState  g_Trendline;
TickData        g_Data;
PartialCloseState g_PartialClose;

// Peak ADX tracking for exit engine
double g_PeakADX = 0;

//=============================================================
// INIT
//=============================================================
int OnInit()
{
    if (InpTimeframe != PERIOD_M30 && InpTimeframe != PERIOD_H1)
    {
        Print("EA_Breakout: Invalid timeframe. Use M30 or H1.");
        return INIT_FAILED;
    }

    g_hATR      = iATR(_Symbol, InpTimeframe, ATR_PERIOD);
    g_hADX      = iADX(_Symbol, InpTimeframe, ADX_PERIOD);
    g_hFractals = iFractals(_Symbol, InpTimeframe);
    g_hHTF_EMA  = iMA(_Symbol, HTF_TIMEFRAME, HTF_EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
    g_hStoch    = iStochastic(_Symbol, InpTimeframe,
                              InpStochK, InpStochD, InpStochSlowing,
                              MODE_SMA, STO_LOWHIGH);
    g_hEMA20    = iMA(_Symbol, InpTimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

    if (g_hATR      == INVALID_HANDLE ||
        g_hADX      == INVALID_HANDLE ||
        g_hFractals == INVALID_HANDLE ||
        g_hHTF_EMA  == INVALID_HANDLE ||
        g_hStoch    == INVALID_HANDLE ||
        g_hEMA20    == INVALID_HANDLE)
    {
        Print("EA_Breakout: Indicator handle creation failed.");
        return INIT_FAILED;
    }

    ArraySetAsSeries(g_Data.rates, true);
    ArraySetAsSeries(g_Data.atr,   true);
    ArraySetAsSeries(g_Data.adx,   true);
    ArraySetAsSeries(g_Data.ema20, true);

    ResetStrategyState();
    ResetPullbackState();

    g_Protection.lastLossTime = 0;
    g_Protection.consecLosses = 0;
    g_Data.htfEMA = 0;
    g_Data.stoch  = 50;
    g_PeakADX     = 0;
    g_PartialClose.done = false;

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
    if (g_hEMA20    != INVALID_HANDLE) IndicatorRelease(g_hEMA20);
}

//=============================================================
// TRADE TRANSACTION — LOSS TRACKING
//=============================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
    if (trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

    ulong ticket = trans.deal;
    if (ticket == 0 || !HistoryDealSelect(ticket)) return;
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
    // Position management runs every tick
    if (HasOpenPosition())
    {
        ManagePosition();

        if (!IsNewCandle()) return;
        if (!LoadMarketData()) return;
        DetectSwings();

        EvaluateExit();
        return;
    }

    if (!IsNewCandle())    return;
    if (!LoadMarketData()) return;

    if (!PassesSessionFilter())                              return;
    if (g_Protection.consecLosses >= InpMaxConsecLosses)    return;
    if (!PassesReEntryFilter())                              return;

    DetectSwings();
    TickStrategyState();

    if (g_Strategy.falseBreak) return;

    if (g_Strategy.breakoutActive)
    {
        MonitorFalseBreakout();
        return;
    }

    if (InpPullbackEnabled && g_Pullback.active)
    {
        if (EvaluatePullbackEntry())
        {
            ExecuteTrade();
            return;
        }
    }

    EvaluateEntry();
}

//=============================================================
// DATA LOADER
//=============================================================
bool LoadMarketData()
{
    if (CopyRates(_Symbol, InpTimeframe, 0, DATA_BUFFER, g_Data.rates) < DATA_BUFFER) return false;
    if (CopyBuffer(g_hATR, 0, 0, DATA_BUFFER, g_Data.atr) < DATA_BUFFER)             return false;
    if (CopyBuffer(g_hADX, 0, 0, 5, g_Data.adx) < 5)                                 return false;

    double sum = 0;
    for (int i = 1; i <= ATR_AVG_BARS; i++) sum += g_Data.atr[i];
    g_Data.atrAvg = (ATR_AVG_BARS > 0) ? sum / ATR_AVG_BARS : 0;
    if (g_Data.atrAvg <= 0) return false;

    double emaBuf[];
    ArraySetAsSeries(emaBuf, true);
    if (CopyBuffer(g_hHTF_EMA, 0, 0, 1, emaBuf) >= 1)
        g_Data.htfEMA = emaBuf[0];

    double stochBuf[];
    ArraySetAsSeries(stochBuf, true);
    if (CopyBuffer(g_hStoch, 0, 0, 1, stochBuf) >= 1)
        g_Data.stoch = stochBuf[0];

    if (CopyBuffer(g_hEMA20, 0, 0, 3, g_Data.ema20) < 3)
    {
        g_Data.ema20[0] = 0;
        g_Data.ema20[1] = 0;
    }

    // Track peak ADX for exit engine
    if (g_Data.adx[1] > g_PeakADX) g_PeakADX = g_Data.adx[1];

    return true;
}

//=============================================================
// SWING DETECTION
//=============================================================
void DetectSwings()
{
    double fractalUp[];
    double fractalDn[];
    ArraySetAsSeries(fractalUp, true);
    ArraySetAsSeries(fractalDn, true);

    if (CopyBuffer(g_hFractals, 0, 0, DATA_BUFFER, fractalUp) < DATA_BUFFER) return;
    if (CopyBuffer(g_hFractals, 1, 0, DATA_BUFFER, fractalDn) < DATA_BUFFER) return;

    g_SwingHighCount = 0;
    g_SwingLowCount  = 0;

    for (int i = FRACTAL_WING + 1; i < DATA_BUFFER - FRACTAL_WING - 1; i++)
    {
        if (fractalUp[i] != EMPTY_VALUE && fractalUp[i] > 0)
            TryAddSwingHigh(fractalUp[i], i, g_Data.rates[i].time);

        if (fractalDn[i] != EMPTY_VALUE && fractalDn[i] > 0)
            TryAddSwingLow(fractalDn[i], i, g_Data.rates[i].time);
    }
}

void TryAddSwingHigh(const double price, const int idx, const datetime t)
{
    if (g_SwingHighCount >= MAX_SWINGS) return;
    if (g_SwingHighCount > 0)
    {
        SwingPoint last = g_SwingHighs[g_SwingHighCount - 1];
        if (MathAbs(idx - last.barIndex) < InpSwingMinBars)                 return;
        if (MathAbs(price - last.price)  < g_Data.atrAvg * InpSwingVertMinATR) return;
    }
    g_SwingHighs[g_SwingHighCount].price    = price;
    g_SwingHighs[g_SwingHighCount].barIndex = idx;
    g_SwingHighs[g_SwingHighCount].time     = t;
    g_SwingHighCount++;
}

void TryAddSwingLow(const double price, const int idx, const datetime t)
{
    if (g_SwingLowCount >= MAX_SWINGS) return;
    if (g_SwingLowCount > 0)
    {
        SwingPoint last = g_SwingLows[g_SwingLowCount - 1];
        if (MathAbs(idx - last.barIndex) < InpSwingMinBars)                  return;
        if (MathAbs(price - last.price)  < g_Data.atrAvg * InpSwingVertMinATR) return;
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
    if (MathAbs(ptA.barIndex - ptB.barIndex) < InpSwingMinBars)                    return false;
    if (MathAbs(ptA.price    - ptB.price)    < g_Data.atrAvg * InpSwingVertMinATR) return false;
    double slope = (ptB.price - ptA.price) / double(ptB.barIndex - ptA.barIndex);
    if (MathAbs(slope) < g_Data.atrAvg * InpSlopeMinATR)                           return false;
    return true;
}

//=============================================================
// ENGINE 1 — ENTRY ENGINE
//=============================================================

bool PassesHardFilters(const bool isBuy, const double trendValue)
{
    // Hard 1: Structural breakout close
    if (isBuy  && g_Data.rates[1].close <= trendValue) return false;
    if (!isBuy && g_Data.rates[1].close >= trendValue) return false;

    // Hard 2: Trade mode available
    if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
        return false;

    // Hard 3: Spread safety
    if (InpHardSpreadMaxATR > 0 && g_Data.atrAvg > 0)
    {
        double curSpread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
        if (curSpread > g_Data.atrAvg * InpHardSpreadMaxATR) return false;
    }

    return true;
}

double CalculateFlexScore(const bool isBuy, const TrendlineState &tl)
{
    double score      = 0.0;
    double atrCurrent = g_Data.atr[1];
    double atrAvg     = g_Data.atrAvg;
    double adxVal     = g_Data.adx[1];

    // ADX Strength
    if (adxVal > InpADXMin)
        score += W_ADX_Strength;

    // ADX Rising
    if (InpADXRisingEnabled && g_Data.adx[1] > g_Data.adx[2])
        score += W_ADX_Rising;

    // ATR Expansion
    if (atrCurrent > atrAvg * InpATRExpansionRatio)
        score += W_ATR_Expansion;

    // Impulse Candle Body
    double body = MathAbs(g_Data.rates[1].close - g_Data.rates[1].open);
    if (body > atrCurrent * InpImpulseBodyATR)
        score += W_Impulse_Body;

    // Compression Quality
    double highest = g_Data.rates[1].high;
    double lowest  = g_Data.rates[1].low;
    for (int i = 2; i <= 10; i++)
    {
        if (g_Data.rates[i].high > highest) highest = g_Data.rates[i].high;
        if (g_Data.rates[i].low  < lowest)  lowest  = g_Data.rates[i].low;
    }
    if ((highest - lowest) <= atrAvg * InpCompressionATR)
        score += W_Compression;

    // Trendline Slope Strength
    if (tl.idxA != tl.idxB)
    {
        double slope = MathAbs((tl.priceB - tl.priceA) / double(tl.idxB - tl.idxA));
        if (slope > atrAvg * InpSlopeMinATR)
            score += W_Slope_Strength;
    }

    // HTF EMA Alignment
    if (InpHTFFlexEnabled && g_Data.htfEMA > 0)
    {
        if (isBuy  && g_Data.rates[1].close > g_Data.htfEMA) score += W_HTF_Alignment;
        if (!isBuy && g_Data.rates[1].close < g_Data.htfEMA) score += W_HTF_Alignment;
    }

    // Spread Quality
    if (InpSpreadFlexEnabled)
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
                score += W_Spread_Quality;
        }
    }

    // Stochastic Alignment
    if (InpStochFlexEnabled)
    {
        if (isBuy  && g_Data.stoch > InpStochBuyLevel)  score += W_Stoch_Alignment;
        if (!isBuy && g_Data.stoch < InpStochSellLevel) score += W_Stoch_Alignment;
    }

    return score;
}

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

    if (CalculateFlexScore(isBuy, tl) < InpMinFlexScore)
        return false;

    return true;
}

void EvaluateEntry()
{
    // BUY: price breaks above descending trendline (two swing highs)
    if (g_SwingHighCount >= 2)
    {
        SwingPoint ptA = g_SwingHighs[g_SwingHighCount - 2];
        SwingPoint ptB = g_SwingHighs[g_SwingHighCount - 1];

        if (ptB.price < ptA.price && ValidateTrendline(ptA, ptB))
        {
            if (EvaluateBreakoutDirection(1, ptA, ptB))
            {
                CommitBreakout(1, ptA, ptB);
                ExecuteTrade();
                return;
            }
        }
    }

    // SELL: price breaks below ascending trendline (two swing lows)
    if (g_SwingLowCount >= 2)
    {
        SwingPoint ptA = g_SwingLows[g_SwingLowCount - 2];
        SwingPoint ptB = g_SwingLows[g_SwingLowCount - 1];

        if (ptB.price > ptA.price && ValidateTrendline(ptA, ptB))
        {
            if (EvaluateBreakoutDirection(-1, ptA, ptB))
            {
                CommitBreakout(-1, ptA, ptB);
                ExecuteTrade();
                return;
            }
        }
    }
}

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

    g_PeakADX = g_Data.adx[1];
    g_PartialClose.done = false;

    if (InpPullbackEnabled)
    {
        g_Pullback.active    = true;
        g_Pullback.startTime = g_Data.rates[1].time;
        g_Pullback.direction = direction;
    }
}

//=============================================================
// ENGINE 2 — POSITION MANAGEMENT ENGINE (every tick)
//=============================================================

void ManagePosition()
{
    if (!PositionSelect(_Symbol)) return;
    if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) return;

    bool   isBuy       = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
    double currentSL   = PositionGetDouble(POSITION_SL);
    double openPrice   = PositionGetDouble(POSITION_PRICE_OPEN);
    double currentBid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentAsk  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double currentPrice = isBuy ? currentBid : currentAsk;
    double slDist      = MathAbs(openPrice - currentSL);
    int    digits      = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

    if (slDist <= 0) return;

    double newSL = currentSL;

    // --- Partial Close at 1R
    if (InpPartialCloseEnabled && !g_PartialClose.done)
    {
        double targetPrice = isBuy ? openPrice + InpPartialCloseRR * slDist
                                   : openPrice - InpPartialCloseRR * slDist;

        bool targetReached = isBuy ? currentBid >= targetPrice
                                   : currentAsk <= targetPrice;
        if (targetReached)
        {
            double lot = PositionGetDouble(POSITION_VOLUME);
            double halfLot = NormalizeDouble(lot * 0.5, 2);
            double minVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            halfLot = MathMax(MathFloor(halfLot / step) * step, minVol);

            if (halfLot < lot)
            {
                g_Trade.PositionClosePartial(_Symbol, halfLot);
                g_PartialClose.done = true;
            }
        }
    }

    // --- Structural Trail: move SL to most recent confirmed swing
    if (InpUseStructuralTrail)
    {
        if (isBuy && g_SwingLowCount > 0)
        {
            for (int i = g_SwingLowCount - 1; i >= 0; i--)
            {
                double swingPrice = g_SwingLows[i].price;
                if (swingPrice < currentBid && swingPrice > newSL)
                {
                    newSL = swingPrice;
                    break;
                }
            }
        }
        else if (!isBuy && g_SwingHighCount > 0)
        {
            for (int i = g_SwingHighCount - 1; i >= 0; i--)
            {
                double swingPrice = g_SwingHighs[i].price;
                if (swingPrice > currentAsk && swingPrice < newSL)
                {
                    newSL = swingPrice;
                    break;
                }
            }
        }
    }

    // --- ATR Trail: activate after 1R
    if (InpUseATRTrail && g_Data.atr[1] > 0)
    {
        double oneRTarget = isBuy ? openPrice + slDist : openPrice - slDist;
        bool   oneRHit    = isBuy ? currentBid >= oneRTarget : currentAsk <= oneRTarget;

        if (oneRHit)
        {
            double atrTrailSL = isBuy ? currentBid - InpATRTrailMultiplier * g_Data.atr[1]
                                      : currentAsk + InpATRTrailMultiplier * g_Data.atr[1];

            if (isBuy  && atrTrailSL > newSL) newSL = atrTrailSL;
            if (!isBuy && atrTrailSL < newSL) newSL = atrTrailSL;
        }
    }

    // --- EMA Trail Protection
    if (InpUseEMATrail && g_Data.ema20[1] > 0)
    {
        double emaValue = g_Data.ema20[1];
        if (isBuy  && emaValue > newSL && emaValue < currentBid) newSL = emaValue;
        if (!isBuy && emaValue < newSL && emaValue > currentAsk) newSL = emaValue;
    }

    // Apply SL modification only if improved
    newSL = NormalizeDouble(newSL, digits);

    bool improved = isBuy  ? (newSL > currentSL + _Point)
                           : (newSL < currentSL - _Point);

    if (!improved) return;

    double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    double freeze  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
    double distToPrice = MathAbs(currentPrice - newSL);

    if (distToPrice < minStop || distToPrice < freeze) return;

    double currentTP = PositionGetDouble(POSITION_TP);
    g_Trade.PositionModify(_Symbol, newSL, currentTP);
}

//=============================================================
// ENGINE 3 — EXIT ENGINE
//=============================================================

void EvaluateExit()
{
    if (!InpUseEarlyExit) return;
    if (!PositionSelect(_Symbol)) return;
    if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) return;

    bool   isBuy      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
    double exitScore  = 0.0;
    double atrCurrent = g_Data.atr[1];
    double atrAvg     = g_Data.atrAvg;

    // Exit: Opposite impulse candle
    double body = MathAbs(g_Data.rates[1].close - g_Data.rates[1].open);
    bool   oppositeImpulse = isBuy
        ? (g_Data.rates[1].close < g_Data.rates[1].open && body > atrCurrent * InpImpulseBodyATR)
        : (g_Data.rates[1].close > g_Data.rates[1].open && body > atrCurrent * InpImpulseBodyATR);
    if (oppositeImpulse)
        exitScore += W_Exit_OppositeImpulse;

    // Exit: Structure flip (new swing forms against position)
    if (isBuy && g_SwingHighCount >= 2)
    {
        SwingPoint lastHigh = g_SwingHighs[g_SwingHighCount - 1];
        SwingPoint prevHigh = g_SwingHighs[g_SwingHighCount - 2];
        if (lastHigh.price < prevHigh.price)
            exitScore += W_Exit_StructFlip;
    }
    else if (!isBuy && g_SwingLowCount >= 2)
    {
        SwingPoint lastLow = g_SwingLows[g_SwingLowCount - 1];
        SwingPoint prevLow = g_SwingLows[g_SwingLowCount - 2];
        if (lastLow.price > prevLow.price)
            exitScore += W_Exit_StructFlip;
    }

    // Exit: ADX collapse (>20% drop from peak)
    if (g_PeakADX > 0 && g_Data.adx[1] < g_PeakADX * 0.8)
        exitScore += W_Exit_ADXCollapse;

    // Exit: ATR contraction after expansion
    if (atrCurrent < atrAvg * 0.9)
        exitScore += W_Exit_ATRContraction;

    // Exit: Close against EMA20
    if (g_Data.ema20[1] > 0)
    {
        if (isBuy  && g_Data.rates[1].close < g_Data.ema20[1]) exitScore += W_Exit_EMABreak;
        if (!isBuy && g_Data.rates[1].close > g_Data.ema20[1]) exitScore += W_Exit_EMABreak;
    }

    if (exitScore >= InpExitThreshold)
    {
        g_Trade.PositionClose(_Symbol);
        g_PeakADX = 0;
        ResetStrategyState();
        ResetPullbackState();
        g_PartialClose.done = false;
    }
}

//=============================================================
// FALSE BREAKOUT MONITOR
//=============================================================

void MonitorFalseBreakout()
{
    int barsElapsed = BarsSince(g_Strategy.breakoutTime);

    if (barsElapsed <= 0 || barsElapsed > InpFalseBreakBars)
    {
        g_Strategy.breakoutActive = false;
        return;
    }

    double trendVal = ProjectTrendline(g_Trendline, 1);
    double close    = g_Data.rates[1].close;

    bool falseBreak =
        (g_Strategy.direction == 1  && close < trendVal) ||
        (g_Strategy.direction == -1 && close > trendVal);

    if (falseBreak)
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
    if (!g_Pullback.active) return false;

    int barsElapsed = BarsSince(g_Pullback.startTime);
    if (barsElapsed > InpPullbackMaxBars)
    {
        g_Pullback.active = false;
        return false;
    }

    double trendVal  = ProjectTrendline(g_Trendline, 1);
    double zoneWidth = InpPullbackZoneATR * g_Data.atr[1];
    bool   isBuy     = (g_Pullback.direction == 1);

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

    if (InpPullbackNeedCandle)
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
// RISK ENGINE — STOP + LOTS
//=============================================================

double CalculateStructuralStop(const bool isBuy, const double entryPrice)
{
    double atrStop = InpATRStopMultiplier * g_Data.atr[1];

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

void ExecuteTrade()
{
    if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL) return;

    bool   isBuy  = (g_Strategy.direction == 1);
    double price  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double slPrice = CalculateStructuralStop(isBuy, price);
    double slDist  = MathAbs(price - slPrice);
    if (slDist <= 0) return;

    double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    double freeze  = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
    if (slDist < minStop) { Print("ExecuteTrade: SL below stops level.");  return; }
    if (slDist < freeze)  { Print("ExecuteTrade: SL inside freeze level."); return; }

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
        Print("ExecuteTrade: Order failed - ", g_Trade.ResultRetcode());
}

//=============================================================
// STATE MACHINE
//=============================================================

void TickStrategyState()
{
    if (g_Strategy.breakoutActive && BarsSince(g_Strategy.breakoutTime) > InpBreakoutExpireBars)
    {
        g_Strategy.breakoutActive = false;
        g_Pullback.active         = false;
    }

    if (g_Strategy.falseBreak && BarsSince(g_Strategy.breakoutTime) > InpBreakoutExpireBars)
    {
        g_Strategy.falseBreak     = false;
        g_Strategy.breakoutActive = false;
    }
}

bool PassesReEntryFilter()
{
    if (g_Protection.lastLossTime == 0) return true;

    int lastLossShift = iBarShift(_Symbol, InpTimeframe, g_Protection.lastLossTime, false);
    if (lastLossShift < 0) return true;

    int barsSinceLoss = lastLossShift - 1;
    return (barsSinceLoss < 0 || barsSinceLoss >= InpReEntryBars);
}

bool PassesSessionFilter()
{
    if (!InpUseSessionFilter) return true;

    MqlDateTime dt;
    TimeToStruct(TimeTradeServer(), dt);
    return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);
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