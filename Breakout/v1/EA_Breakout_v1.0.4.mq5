#property copyright "Structural Trendline Breakout EA v1.04"
#property link      ""
#property version   "1.04"
#property strict

#include <Trade\Trade.mqh>

//--- INPUTS
input ENUM_TIMEFRAMES InpTimeframe              = PERIOD_M15; //Time Frame
input double          InpRiskPercent            = 0.5;        //Risk Percent
input double          InpRR                     = 2.0;        //Risk Reward
input double          InpDailyLossLimit         = 1.0;        //Daily Loss Limit
input int             InpMaxDailyTrades         = 2;          //Max Daily Trades
input int             InpMaxConsecLosses        = 2;          //Max Consecutive Losses
input int             InpReEntryCandles         = 20;         //Min Re-Entry Candles
input bool            InpUseHTFConfirm          = true;       //Use HTF Confirm
input bool            InpHTFAsHardFilter        = false;      //HTF as Hard Filter
input int             InpSessionStartHour       = 9;          //Session Start Hour
input int             InpSessionStartMin        = 0;          //Session Start Minute
input int             InpSessionEndHour         = 13;         //Session End Hour
input int             InpSessionEndMin          = 30;         //Session End Minute
input int             InpMinFlexScore           = 2;          //Min Flex Score
input bool            InpUseSpreadFilter        = true;       //Use Spread Filter
input bool            InpUseHTFasFlex           = true;       //Use HTF as Flex
input bool            InpEnablePullbackEntry    = true;       //Enable Pullback Entry
input int             InpPullbackMaxBars        = 8;          //Max Bars After Breakout to Allow Retest
input double          InpPullbackATRZone        = 0.3;        //Distance From Trendline in ATR
input bool            InpRequireRejectionCandle = true;       //Require Rejection Candle
input double          InpADXMin                 = 25.0;       //ADX Minimum Threshold
input double          InpCandleBodyRatio        = 0.6;        //Candle Body Ratio
input double          InpATRExpansionRatio      = 1.0;        //ATR Expansion Ratio
input int             InpMagicNumber            = 20250101;   //Magic Number

//--- CONSTANTS
#define ATR_PERIOD       14
#define ADX_PERIOD       14
#define ATR_AVG_BARS     20
#define SPREAD_AVG_BARS  10
#define SWING_MIN_DIST   10
#define MAX_SWINGS       50
#define HTF_EMA_PERIOD   200
#define FRACTAL_WING     2
#define TICK_BUFFER_SIZE 50

//--- HANDLES
int hATR      = INVALID_HANDLE;
int hADX      = INVALID_HANDLE;
int hFractals = INVALID_HANDLE;
int hHTF_EMA  = INVALID_HANDLE;

CTrade Trade;

//--- SWING STRUCTURE
struct SwingPoint
{
    double   price;
    int      index;
    datetime time;
};

//--- DEAL INFO STRUCTURE
struct DealInfo
{
    datetime time;
    double   profit;
};

//--- BREAKOUT STATE STRUCTURE
struct BreakoutState
{
    bool     active;
    bool     falseBreak;
    datetime time;
    int      direction;
};

//--- CENTRALIZED TICK DATA
static MqlRates s_rates[TICK_BUFFER_SIZE];
static double   s_atrBuf[TICK_BUFFER_SIZE];
static double   s_adxBuf[5];

//--- STATE
SwingPoint ValidSwingHighs[MAX_SWINGS];
SwingPoint ValidSwingLows[MAX_SWINGS];
int        SwingHighCount = 0;
int        SwingLowCount  = 0;

BreakoutState g_state;

double     g_trendlineA_price = 0;
double     g_trendlineB_price = 0;
int        g_trendlineA_idx   = 0;
int        g_trendlineB_idx   = 0;

int        g_consecLosses     = 0;
datetime   g_lastLossTime     = 0;
int        g_lastLossBar      = -1;

bool       g_pullbackActive    = false;
datetime   g_pullbackStartTime = 0;
int        g_pullbackDirection = 0;

//--- DAILY LIMITS CACHE
static datetime s_cachedDay     = 0;
static double   s_cachedProfit  = 0;
static int      s_cachedTrades  = 0;
static int      s_cachedConsec  = 0;
static int      s_cachedLossBar = -1;

//=============================================================
// INIT / DEINIT
//=============================================================
int OnInit()
{
    if (_Symbol != "EURUSD" && _Symbol != "GBPUSD")
        return INIT_FAILED;
    if (InpTimeframe != PERIOD_M15 && InpTimeframe != PERIOD_M30)
        return INIT_FAILED;

    hATR      = iATR(_Symbol, InpTimeframe, ATR_PERIOD);
    hADX      = iADX(_Symbol, InpTimeframe, ADX_PERIOD);
    hFractals = iFractals(_Symbol, InpTimeframe);
    hHTF_EMA  = iMA(_Symbol, PERIOD_H1, HTF_EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);

    if (hATR == INVALID_HANDLE || hADX == INVALID_HANDLE ||
        hFractals == INVALID_HANDLE || hHTF_EMA == INVALID_HANDLE)
        return INIT_FAILED;

    g_state.active     = false;
    g_state.falseBreak = false;
    g_state.time       = 0;
    g_state.direction  = 0;

    ArraySetAsSeries(s_rates,  true);
    ArraySetAsSeries(s_atrBuf, true);
    ArraySetAsSeries(s_adxBuf, true);

    Trade.SetExpertMagicNumber(InpMagicNumber);
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    if (hATR      != INVALID_HANDLE) IndicatorRelease(hATR);
    if (hADX      != INVALID_HANDLE) IndicatorRelease(hADX);
    if (hFractals != INVALID_HANDLE) IndicatorRelease(hFractals);
    if (hHTF_EMA  != INVALID_HANDLE) IndicatorRelease(hHTF_EMA);
}

//=============================================================
// TRADE TRANSACTION — CACHE INVALIDATION
//=============================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
    if (trans.type != TRADE_TRANSACTION_DEAL_ADD)
        return;

    ulong dealTicket = trans.deal;
    if (dealTicket == 0)
        return;

    if (!HistoryDealSelect(dealTicket))
        return;

    long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
    string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
    long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

    if (dealMagic == InpMagicNumber &&
        dealSymbol == _Symbol &&
        entryType == DEAL_ENTRY_OUT)
    {
        s_cachedDay = 0;
    }
}

//=============================================================
// MAIN TICK
//=============================================================
void OnTick()
{
    if (!IsNewCandle())
        return;

    if (PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        return;

    if (!CheckSession())
        return;

    if (!ManageDailyLimits())
        return;

    if (CopyRates(_Symbol, InpTimeframe, 0, TICK_BUFFER_SIZE, s_rates)  < TICK_BUFFER_SIZE) return;
    if (CopyBuffer(hATR, 0, 0, TICK_BUFFER_SIZE, s_atrBuf) < TICK_BUFFER_SIZE) return;
    if (CopyBuffer(hADX, 0, 0, 5, s_adxBuf) < 5) return;

    double atrAvg = GetATRAverage(ATR_AVG_BARS);
    if (atrAvg <= 0)
        return;

    DetectSwings(atrAvg);

    if (g_state.active)
    {
        int shift = iBarShift(_Symbol, InpTimeframe, g_state.time, false);
        if (shift > 20)
            g_state.active = false;
    }

    if (g_state.falseBreak)
    {
        if (TimeCurrent() - g_state.time > 86400)
        {
            g_state.falseBreak = false;
            g_state.active     = false;
        }
        else
            return;
    }

    if (g_state.active && !g_state.falseBreak)
    {
        MonitorFalseBreakout();
        return;
    }

    if (InpEnablePullbackEntry && g_pullbackActive)
    {
        if (CheckPullbackEntry())
        {
            ExecuteTrade();
            return;
        }
    }

    if (!CheckBreakout(atrAvg))
        return;

    ExecuteTrade();
}

//=============================================================
// SESSION FILTER (UTC)
//=============================================================
bool CheckSession()
{
    datetime serverTime = TimeTradeServer();
    MqlDateTime dt;
    TimeToStruct(serverTime, dt);

    int minutesNow   = dt.hour * 60 + dt.min;
    int minutesStart = InpSessionStartHour * 60 + InpSessionStartMin;
    int minutesEnd   = InpSessionEndHour   * 60 + InpSessionEndMin;

    return (minutesNow >= minutesStart && minutesNow < minutesEnd);
}

//=============================================================
// SWING DETECTION
//=============================================================
void DetectSwings(const double atrAvg)
{
    const int lookback = 200;

    double fractalUp[];
    double fractalDn[];
    ArraySetAsSeries(fractalUp, true);
    ArraySetAsSeries(fractalDn, true);

    if (CopyBuffer(hFractals, 0, 0, lookback, fractalUp) < lookback) return;
    if (CopyBuffer(hFractals, 1, 0, lookback, fractalDn) < lookback) return;

    MqlRates swingRates[];
    ArraySetAsSeries(swingRates, true);
    if (CopyRates(_Symbol, InpTimeframe, 0, lookback, swingRates) < lookback) return;

    SwingHighCount = 0;
    SwingLowCount  = 0;

    for (int i = FRACTAL_WING + 1; i < lookback - FRACTAL_WING - 1; i++)
    {
        if (fractalUp[i] != EMPTY_VALUE && fractalUp[i] > 0)
        {
            bool validDist = true;
            bool validVert = true;

            if (SwingHighCount > 0)
            {
                int prevIdx = ValidSwingHighs[SwingHighCount - 1].index;
                if (MathAbs(i - prevIdx) < SWING_MIN_DIST)
                    validDist = false;
                if (MathAbs(fractalUp[i] - ValidSwingHighs[SwingHighCount - 1].price) < 0.5 * atrAvg)
                    validVert = false;
            }

            if (validDist && validVert && SwingHighCount < MAX_SWINGS)
            {
                ValidSwingHighs[SwingHighCount].price = fractalUp[i];
                ValidSwingHighs[SwingHighCount].index = i;
                ValidSwingHighs[SwingHighCount].time  = swingRates[i].time;
                SwingHighCount++;
            }
        }

        if (fractalDn[i] != EMPTY_VALUE && fractalDn[i] > 0)
        {
            bool validDist = true;
            bool validVert = true;

            if (SwingLowCount > 0)
            {
                int prevIdx = ValidSwingLows[SwingLowCount - 1].index;
                if (MathAbs(i - prevIdx) < SWING_MIN_DIST)
                    validDist = false;
                if (MathAbs(fractalDn[i] - ValidSwingLows[SwingLowCount - 1].price) < 0.5 * atrAvg)
                    validVert = false;
            }

            if (validDist && validVert && SwingLowCount < MAX_SWINGS)
            {
                ValidSwingLows[SwingLowCount].price = fractalDn[i];
                ValidSwingLows[SwingLowCount].index = i;
                ValidSwingLows[SwingLowCount].time  = swingRates[i].time;
                SwingLowCount++;
            }
        }
    }
}

//=============================================================
// TRENDLINE PROJECTION
//=============================================================
double ProjectTrendline(const double priceA, const int idxA,
                        const double priceB, const int idxB,
                        const int targetIdx)
{
    if (idxA == idxB) return priceA;
    double slope = (priceB - priceA) / double(idxB - idxA);
    return priceA + slope * double(targetIdx - idxA);
}

bool ValidateTrendline(const SwingPoint &ptA, const SwingPoint &ptB, const double atrAvg)
{
    if (MathAbs(ptA.index - ptB.index) < SWING_MIN_DIST)
        return false;
    if (MathAbs(ptA.price - ptB.price) < atrAvg * 0.8)
        return false;
    return true;
}

//=============================================================
// HARD FILTERS
//=============================================================
bool CheckHardFilters(const bool isBuy,
                      const double trendValue,
                      const double atrCurrent,
                      const double atrAvg,
                      const double adxVal)
{
    if (isBuy)
    {
        if (s_rates[1].close <= trendValue)                return false;
        if (atrCurrent <= atrAvg * InpATRExpansionRatio)   return false;
        if (adxVal <= InpADXMin)                           return false;
    }
    else
    {
        if (s_rates[1].close >= trendValue)                return false;
        if (atrCurrent <= atrAvg * InpATRExpansionRatio)   return false;
        if (adxVal <= InpADXMin)                           return false;
    }

    if (InpUseHTFConfirm && InpHTFAsHardFilter)
    {
        double emaBuf[];
        ArraySetAsSeries(emaBuf, true);
        if (CopyBuffer(hHTF_EMA, 0, 0, 1, emaBuf) >= 1)
        {
            double closePrice = s_rates[1].close;
            if (isBuy  && closePrice <= emaBuf[0]) return false;
            if (!isBuy && closePrice >= emaBuf[0]) return false;
        }
    }

    return true;
}

//=============================================================
// FLEX SCORE
//=============================================================
int CalculateFlexScore(const bool isBuy,
                       const double atrCurrent,
                       const double atrAvg)
{
    int score = 0;

    // +1 Range Expansion
    if (isBuy)
    {
        double highest = s_rates[1].high;
        for (int i = 2; i <= 20; i++)
            if (s_rates[i].high > highest) highest = s_rates[i].high;
        if (s_rates[1].high >= highest) score++;
    }
    else
    {
        double lowest = s_rates[1].low;
        for (int i = 2; i <= 20; i++)
            if (s_rates[i].low < lowest) lowest = s_rates[i].low;
        if (s_rates[1].low <= lowest) score++;
    }

    // +1 Candle Strength
    double range = s_rates[1].high - s_rates[1].low;
    if (range > 0)
    {
        double body = MathAbs(s_rates[1].close - s_rates[1].open);
        if (body / range >= InpCandleBodyRatio)
        {
            if (isBuy  && s_rates[1].close >= (s_rates[1].low + 0.75 * range)) score++;
            if (!isBuy && s_rates[1].close <= (s_rates[1].low + 0.25 * range)) score++;
        }
    }

    // +1 Spread Filter (conditional)
    if (InpUseSpreadFilter)
    {
        double spreadSum = 0;
        for (int i = 1; i <= SPREAD_AVG_BARS; i++)
            spreadSum += (s_rates[i].spread * _Point);
        double avgSpread = spreadSum / SPREAD_AVG_BARS;
        double curSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
        if (curSpread <= avgSpread) score++;
    }

    // +1 HTF EMA as Flex (conditional)
    if (InpUseHTFConfirm && !InpHTFAsHardFilter)
    {
        double emaBuf[];
        ArraySetAsSeries(emaBuf, true);
        if (CopyBuffer(hHTF_EMA, 0, 0, 2, emaBuf) >= 2)
        {
            double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if (isBuy  && currentPrice > emaBuf[0]) score++;
            if (!isBuy && currentPrice < emaBuf[0]) score++;
        }
    }

    score = MathMin(score, 4);
    return score;
}

//=============================================================
// EVALUATE DIRECTION (no state mutation)
//=============================================================
bool EvaluateDirection(const int direction,
                       const SwingPoint &ptA,
                       const SwingPoint &ptB,
                       const double atrAvg,
                       const double atrCurrent,
                       const double adxVal,
                       double &outTrendVal)
{
    bool isBuy = (direction == 1);

    outTrendVal = ProjectTrendline(ptA.price, ptA.index, ptB.price, ptB.index, 1);

    if (!CheckHardFilters(isBuy, outTrendVal, atrCurrent, atrAvg, adxVal))
        return false;

    int flexScore = CalculateFlexScore(isBuy, atrCurrent, atrAvg);
    if (flexScore < InpMinFlexScore)
        return false;

    return true;
}

//=============================================================
// COMMIT BREAKOUT (state mutation only here)
//=============================================================
void CommitBreakout(const int direction,
                    const SwingPoint &ptA,
                    const SwingPoint &ptB)
{
    g_state.direction  = direction;
    g_trendlineA_price = ptA.price;
    g_trendlineA_idx   = ptA.index;
    g_trendlineB_price = ptB.price;
    g_trendlineB_idx   = ptB.index;
    g_state.active     = true;
    g_state.time       = s_rates[1].time;
    g_state.falseBreak = false;

    if (InpEnablePullbackEntry)
    {
        g_pullbackActive    = true;
        g_pullbackStartTime = s_rates[1].time;
        g_pullbackDirection = direction;
    }
}

//=============================================================
// BREAKOUT CHECK
//=============================================================
bool CheckBreakout(const double atrAvg)
{
    double atrCurrent = s_atrBuf[1];
    double adxVal     = s_adxBuf[1];

    if (g_lastLossBar >= 0)
    {
        int lastLossShift = g_lastLossBar;
        int currentShift  = 1;
        int barsSinceLoss = lastLossShift - currentShift;
        if (barsSinceLoss >= 0 && barsSinceLoss < InpReEntryCandles)
            return false;
    }

    // BUY: descending trendline from two swing highs
    if (SwingHighCount >= 2)
    {
        SwingPoint ptA = ValidSwingHighs[SwingHighCount - 2];
        SwingPoint ptB = ValidSwingHighs[SwingHighCount - 1];

        if (ptB.price < ptA.price && ValidateTrendline(ptA, ptB, atrAvg))
        {
            double trendVal = 0;
            if (EvaluateDirection(1, ptA, ptB, atrAvg, atrCurrent, adxVal, trendVal))
            {
                CommitBreakout(1, ptA, ptB);
                return true;
            }
        }
    }

    // SELL: ascending trendline from two swing lows
    if (SwingLowCount >= 2)
    {
        SwingPoint ptA = ValidSwingLows[SwingLowCount - 2];
        SwingPoint ptB = ValidSwingLows[SwingLowCount - 1];

        if (ptB.price > ptA.price && ValidateTrendline(ptA, ptB, atrAvg))
        {
            double trendVal = 0;
            if (EvaluateDirection(-1, ptA, ptB, atrAvg, atrCurrent, adxVal, trendVal))
            {
                CommitBreakout(-1, ptA, ptB);
                return true;
            }
        }
    }

    return false;
}

//=============================================================
// PULLBACK ENTRY
//=============================================================
bool CheckPullbackEntry()
{
    if (!g_pullbackActive)
        return false;

    if (PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        return false;

    int barsElapsed = 0;
    for (int i = 1; i < 10; i++)
    {
        if (s_rates[i].time <= g_pullbackStartTime)
        {
            barsElapsed = i - 1;
            break;
        }
    }

    if (barsElapsed > InpPullbackMaxBars)
    {
        g_pullbackActive = false;
        return false;
    }

    double trendVal = ProjectTrendline(g_trendlineA_price, g_trendlineA_idx,
                                       g_trendlineB_price, g_trendlineB_idx, 1);

    double atrCurrent   = s_atrBuf[1];
    double zoneDistance = InpPullbackATRZone * atrCurrent;
    bool   isBuy        = (g_pullbackDirection == 1);

    if (isBuy)
    {
        if (s_rates[1].low > trendVal + zoneDistance) return false;
        if (s_rates[1].low < trendVal - zoneDistance) return false;
    }
    else
    {
        if (s_rates[1].high < trendVal - zoneDistance) return false;
        if (s_rates[1].high > trendVal + zoneDistance) return false;
    }

    if (InpRequireRejectionCandle)
    {
        if (isBuy)
        {
            if (s_rates[1].close <= s_rates[1].open) return false;
            if (s_rates[1].close <= trendVal)        return false;
        }
        else
        {
            if (s_rates[1].close >= s_rates[1].open) return false;
            if (s_rates[1].close >= trendVal)        return false;
        }
    }

    g_state.direction = g_pullbackDirection;
    g_pullbackActive  = false;
    return true;
}

//=============================================================
// CALCULATE STOP
//=============================================================
double CalculateStop(const bool isBuy, const double entryPrice, const double atrCurrent)
{
    double atrStop = 1.0 * atrCurrent;

    if (isBuy)
    {
        for (int i = SwingLowCount - 1; i >= 0; i--)
        {
            if (ValidSwingLows[i].price < entryPrice)
                return MathMin(ValidSwingLows[i].price, entryPrice - atrStop);
        }
        return entryPrice - atrStop;
    }
    else
    {
        for (int i = SwingHighCount - 1; i >= 0; i--)
        {
            if (ValidSwingHighs[i].price > entryPrice)
                return MathMax(ValidSwingHighs[i].price, entryPrice + atrStop);
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

    double lot    = riskMoney / ((slDist / tickSize) * tickValue);
    double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    lot = MathFloor(lot / step) * step;
    lot = MathMax(lot, minVol);
    lot = MathMin(lot, maxVol);
    return lot;
}

//=============================================================
// EXECUTE TRADE
//=============================================================
void ExecuteTrade()
{
    if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
        return;

    double atrCurrent = s_atrBuf[1];
    bool   isBuy      = (g_state.direction == 1);
    double price      = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double slPrice = CalculateStop(isBuy, price, atrCurrent);
    double slDist  = MathAbs(price - slPrice);
    if (slDist <= 0) return;

    int    stopsLevel      = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double minStopDistance = stopsLevel * _Point;
    if (slDist < minStopDistance)
    {
        Print("SL too close to market.");
        return;
    }

    double tpDist  = InpRR * slDist;
    double tpPrice = isBuy ? price + tpDist : price - tpDist;

    int digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    price   = NormalizeDouble(price,   digits);
    slPrice = NormalizeDouble(slPrice, digits);
    tpPrice = NormalizeDouble(tpPrice, digits);

    double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = balance * (InpRiskPercent / 100.0);
    double lot       = CalculateLotSize(riskMoney, slDist);
    if (lot <= 0) return;

    ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    if (!Trade.PositionOpen(_Symbol, orderType, lot, price, slPrice, tpPrice))
    {
        Print("Order failed: ", Trade.ResultRetcode());
        return;
    }
}

//=============================================================
// FALSE BREAKOUT MONITOR
//=============================================================
void MonitorFalseBreakout()
{
    int barsElapsed = 0;
    for (int i = 1; i < 8; i++)
    {
        if (s_rates[i].time <= g_state.time)
        {
            barsElapsed = i - 1;
            break;
        }
    }

    if (barsElapsed > 5 || barsElapsed <= 0)
    {
        g_state.active = false;
        return;
    }

    double trendVal = ProjectTrendline(g_trendlineA_price, g_trendlineA_idx,
                                       g_trendlineB_price, g_trendlineB_idx, 1);

    double c1 = s_rates[1].close;

    if (g_state.direction == 1 && c1 < trendVal)
    {
        g_state.falseBreak = true;
        g_state.active     = false;
        g_pullbackActive   = false;
    }
    else if (g_state.direction == -1 && c1 > trendVal)
    {
        g_state.falseBreak = true;
        g_state.active     = false;
        g_pullbackActive   = false;
    }
}

//=============================================================
// DAILY LIMITS + CONSECUTIVE LOSSES
//=============================================================
bool ManageDailyLimits()
{
    datetime serverTime = TimeTradeServer();
    MqlDateTime dt;
    TimeToStruct(serverTime, dt);
    dt.hour = 0; dt.min = 0; dt.sec = 0;
    datetime dayStart = StructToTime(dt);

    if (s_cachedDay == dayStart)
    {
        if (s_cachedTrades >= InpMaxDailyTrades)   return false;
        if (s_cachedConsec >= InpMaxConsecLosses)  return false;

        double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
        double startBalance = balance - s_cachedProfit;
        double lossLimit    = startBalance * (InpDailyLossLimit / 100.0);
        if (s_cachedProfit <= -lossLimit) return false;

        g_lastLossBar  = s_cachedLossBar;
        g_consecLosses = s_cachedConsec;
        return true;
    }

    HistorySelect(dayStart, serverTime);

    uint     total      = HistoryDealsTotal();
    DealInfo deals[];
    ArrayResize(deals, total);
    int dealIndex = 0;

    for (uint i = 0; i < total; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if (HistoryDealGetInteger(ticket, DEAL_MAGIC)  != InpMagicNumber) continue;
        if (HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)        continue;
        if (HistoryDealGetInteger(ticket, DEAL_ENTRY)  != DEAL_ENTRY_OUT) continue;

        deals[dealIndex].time   = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
        deals[dealIndex].profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
        dealIndex++;
    }
    ArrayResize(deals, dealIndex);

    double   dailyProfit  = 0;
    int      tradesToday  = 0;
    int      consecLosses = 0;
    int      lossBar      = -1;
    datetime lastLossTime = 0;

    for (int i = 0; i < dealIndex; i++)
    {
        tradesToday++;
        dailyProfit += deals[i].profit;

        if (deals[i].profit < 0)
        {
            consecLosses++;
            lastLossTime = deals[i].time;
            int shift = iBarShift(_Symbol, InpTimeframe, lastLossTime, false);
            if (shift >= 0)
                lossBar = shift;
        }
        else
        {
            consecLosses = 0;
        }
    }

    s_cachedDay     = dayStart;
    s_cachedProfit  = dailyProfit;
    s_cachedTrades  = tradesToday;
    s_cachedConsec  = consecLosses;
    s_cachedLossBar = lossBar;

    g_lastLossBar  = lossBar;
    g_consecLosses = consecLosses;
    if (lastLossTime > 0)
        g_lastLossTime = lastLossTime;

    if (tradesToday  >= InpMaxDailyTrades)  return false;
    if (consecLosses >= InpMaxConsecLosses) return false;

    double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
    double startBalance = balance - dailyProfit;
    double lossLimit    = startBalance * (InpDailyLossLimit / 100.0);
    if (dailyProfit <= -lossLimit) return false;

    return true;
}

//=============================================================
// ATR AVERAGE
//=============================================================
double GetATRAverage(const int period)
{
    double sum = 0;
    for (int i = 1; i <= period; i++)
        sum += s_atrBuf[i];
    return sum / period;
}

//=============================================================
// NEW CANDLE DETECTION
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