#property copyright "Structural Trendline Breakout EA v1.0.-"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//--- INPUTS
input ENUM_TIMEFRAMES InpTimeframe         = PERIOD_M15;
input double          InpRiskPercent       = 0.5;
input double          InpRR                = 2.0;
input double          InpDailyLossLimit    = 1.0;
input int             InpMaxDailyTrades    = 2;
input int             InpMaxConsecLosses   = 2;
input int             InpReEntryCandles    = 20;
input bool            InpUseHTFConfirm     = true;
input int             InpSessionStartHour  = 9;
input int             InpSessionStartMin   = 0;
input int             InpSessionEndHour    = 13;
input int             InpSessionEndMin     = 30;

//--- CONSTANTS
#define ATR_PERIOD       14
#define ADX_PERIOD       14
#define ATR_AVG_BARS     20
#define SPREAD_AVG_BARS  10
#define SWING_MIN_DIST   10
#define MAX_SWINGS       50
#define HTF_EMA_PERIOD   200
#define FRACTAL_WING     2

//--- HANDLES
int hATR        = INVALID_HANDLE;
int hADX        = INVALID_HANDLE;
int hFractals   = INVALID_HANDLE;
int hHTF_EMA    = INVALID_HANDLE;

CTrade Trade;
static const int Magic = 20250101;

//--- SWING STRUCTURE
struct SwingPoint
{
    double   price;
    int      index;
    datetime time;
};

//--- STATE
SwingPoint ValidSwingHighs[MAX_SWINGS];
SwingPoint ValidSwingLows[MAX_SWINGS];
int        SwingHighCount = 0;
int        SwingLowCount  = 0;

bool       g_breakoutFired    = false;
datetime   g_breakoutTime     = 0;
int        g_breakoutDir      = 0; // 1=BUY, -1=SELL
double     g_trendlineA_price = 0;
double     g_trendlineB_price = 0;
int        g_trendlineA_idx   = 0;
int        g_trendlineB_idx   = 0;
bool       g_falseBreakout    = false;

int        g_consecLosses     = 0;
datetime   g_lastLossTime     = 0;
int        g_lastLossBar      = 0;

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

    Trade.SetExpertMagicNumber(Magic);
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
// MAIN TICK
//=============================================================
void OnTick()
{
    if (!IsNewCandle())
        return;

    if (PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == Magic)
        return;

    if (!CheckSession())
        return;

    if (!ManageDailyLimits())
        return;

    double atrAvg = GetATRAverage(ATR_AVG_BARS);
    if (atrAvg <= 0)
        return;

    DetectSwings(atrAvg);

    if (g_breakoutFired && !g_falseBreakout)
    {
        MonitorFalseBreakout();
        return;
    }

    if (g_falseBreakout)
        return;

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

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(_Symbol, InpTimeframe, 0, lookback, rates) < lookback) return;

    SwingHighCount = 0;
    SwingLowCount  = 0;

    for (int i = FRACTAL_WING + 1; i < lookback - FRACTAL_WING - 1; i++)
    {
        // Swing High
        if (fractalUp[i] != EMPTY_VALUE && fractalUp[i] > 0)
        {
            bool validDist  = true;
            bool validVert  = true;

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
                ValidSwingHighs[SwingHighCount].time  = rates[i].time;
                SwingHighCount++;
            }
        }

        // Swing Low
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
                ValidSwingLows[SwingLowCount].time  = rates[i].time;
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
    if (MathAbs(ptA.price - ptB.price) < 0.5 * atrAvg)
        return false;
    return true;
}

//=============================================================
// BREAKOUT CHECK
//=============================================================
bool CheckBreakout(const double atrAvg)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(_Symbol, InpTimeframe, 0, 22, rates) < 22) return false;

    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);
    if (CopyBuffer(hATR, 0, 0, ATR_AVG_BARS + 2, atrBuf) < ATR_AVG_BARS + 2) return false;

    double atrCurrent = atrBuf[1];

    double adxBuf[];
    ArraySetAsSeries(adxBuf, true);
    if (CopyBuffer(hADX, 0, 0, 2, adxBuf) < 2) return false;
    double adxVal = adxBuf[1];

    // Check re-entry cooldown after loss
    if (g_lastLossBar > 0)
    {
        int currentBar = Bars(_Symbol, InpTimeframe);
        if ((currentBar - g_lastLossBar) < InpReEntryCandles)
            return false;
    }

    // BUY breakout: descending trendline from two swing highs
    bool buyBreak  = false;
    bool sellBreak = false;

    if (SwingHighCount >= 2)
    {
        SwingPoint ptA = ValidSwingHighs[SwingHighCount - 2];
        SwingPoint ptB = ValidSwingHighs[SwingHighCount - 1];

        if (ptB.price < ptA.price && ValidateTrendline(ptA, ptB, atrAvg))
        {
            double trendVal = ProjectTrendline(ptA.price, ptA.index, ptB.price, ptB.index, 1);

            if (rates[1].close > trendVal)
            {
                if (CheckExpansion(atrCurrent, atrBuf) &&
                    CheckMomentum(adxVal) &&
                    CheckRangeExpansion(rates, true) &&
                    CheckCandleStrength(rates[1], true))
                {
                    if (!InpUseHTFConfirm || CheckHTFFilter(true))
                    {
                        if (CheckSpreadFilter())
                        {
                            buyBreak = true;
                            g_breakoutDir      = 1;
                            g_trendlineA_price = ptA.price;
                            g_trendlineA_idx   = ptA.index;
                            g_trendlineB_price = ptB.price;
                            g_trendlineB_idx   = ptB.index;
                        }
                    }
                }
            }
        }
    }

    if (!buyBreak && SwingLowCount >= 2)
    {
        SwingPoint ptA = ValidSwingLows[SwingLowCount - 2];
        SwingPoint ptB = ValidSwingLows[SwingLowCount - 1];

        if (ptB.price > ptA.price && ValidateTrendline(ptA, ptB, atrAvg))
        {
            double trendVal = ProjectTrendline(ptA.price, ptA.index, ptB.price, ptB.index, 1);

            if (rates[1].close < trendVal)
            {
                if (CheckExpansion(atrCurrent, atrBuf) &&
                    CheckMomentum(adxVal) &&
                    CheckRangeExpansion(rates, false) &&
                    CheckCandleStrength(rates[1], false))
                {
                    if (!InpUseHTFConfirm || CheckHTFFilter(false))
                    {
                        if (CheckSpreadFilter())
                        {
                            sellBreak = true;
                            g_breakoutDir      = -1;
                            g_trendlineA_price = ptA.price;
                            g_trendlineA_idx   = ptA.index;
                            g_trendlineB_price = ptB.price;
                            g_trendlineB_idx   = ptB.index;
                        }
                    }
                }
            }
        }
    }

    if (buyBreak || sellBreak)
    {
        g_breakoutFired = true;
        g_breakoutTime  = rates[1].time;
        g_falseBreakout = false;
        return true;
    }

    return false;
}

//=============================================================
// EXPANSION FILTER
//=============================================================
bool CheckExpansion(const double atrCurrent, const double &atrBuf[])
{
    double sum = 0;
    for (int i = 2; i <= ATR_AVG_BARS + 1; i++)
        sum += atrBuf[i];
    double avg = sum / ATR_AVG_BARS;
    return atrCurrent > avg;
}

//=============================================================
// MOMENTUM FILTER
//=============================================================
bool CheckMomentum(const double adxVal)
{
    return (adxVal > 25.0 && adxVal < 45.0);
}

//=============================================================
// RANGE EXPANSION
//=============================================================
bool CheckRangeExpansion(const MqlRates &rates[], const bool isBuy)
{
    if (isBuy)
    {
        double highest = rates[1].high;
        for (int i = 2; i <= 20; i++)
            if (rates[i].high > highest) highest = rates[i].high;
        return rates[1].high >= highest;
    }
    else
    {
        double lowest = rates[1].low;
        for (int i = 2; i <= 20; i++)
            if (rates[i].low < lowest) lowest = rates[i].low;
        return rates[1].low <= lowest;
    }
}

//=============================================================
// CANDLE STRENGTH FILTER
//=============================================================
bool CheckCandleStrength(const MqlRates &candle, const bool isBuy)
{
    double range = candle.high - candle.low;
    if (range <= 0) return false;

    double body  = MathAbs(candle.close - candle.open);
    if (body / range < 0.6) return false;

    if (isBuy)
        return candle.close >= (candle.low + 0.75 * range);
    else
        return candle.close <= (candle.low + 0.25 * range);
}

//=============================================================
// HTF FILTER
//=============================================================
bool CheckHTFFilter(const bool isBuy)
{
    double emaBuf[];
    ArraySetAsSeries(emaBuf, true);
    if (CopyBuffer(hHTF_EMA, 0, 0, 2, emaBuf) < 2) return false;

    double currentPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (isBuy)  return currentPrice > emaBuf[0];
    else        return currentPrice < emaBuf[0];
}

//=============================================================
// SPREAD FILTER
//=============================================================
bool CheckSpreadFilter()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(_Symbol, InpTimeframe, 0, SPREAD_AVG_BARS + 1, rates) < SPREAD_AVG_BARS + 1)
        return false;

    double spreadSum = 0;
    for (int i = 1; i <= SPREAD_AVG_BARS; i++)
        spreadSum += (rates[i].spread * _Point);
    double avgSpread = spreadSum / SPREAD_AVG_BARS;

    double curSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
    return curSpread <= avgSpread;
}

//=============================================================
// CALCULATE STOP
//=============================================================
double CalculateStop(const bool isBuy, const double entryPrice, const double atrCurrent)
{
    double structStop;
    double atrStop = 1.0 * atrCurrent;

    if (isBuy)
    {
        double lastLow = DBL_MAX;
        for (int i = 0; i < SwingLowCount; i++)
        {
            if (ValidSwingLows[i].price < entryPrice)
                lastLow = MathMin(lastLow, ValidSwingLows[i].price);
        }
        if (lastLow == DBL_MAX) lastLow = entryPrice - atrStop;
        structStop = lastLow;
        return MathMin(structStop, entryPrice - atrStop);
    }
    else
    {
        double lastHigh = -DBL_MAX;
        for (int i = 0; i < SwingHighCount; i++)
        {
            if (ValidSwingHighs[i].price > entryPrice)
                lastHigh = MathMax(lastHigh, ValidSwingHighs[i].price);
        }
        if (lastHigh == -DBL_MAX) lastHigh = entryPrice + atrStop;
        structStop = lastHigh;
        return MathMax(structStop, entryPrice + atrStop);
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

    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);
    if (CopyBuffer(hATR, 0, 0, 2, atrBuf) < 2) return;
    double atrCurrent = atrBuf[1];

    bool isBuy  = (g_breakoutDir == 1);
    double price = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                         : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double slPrice = CalculateStop(isBuy, price, atrCurrent);
    double slDist  = MathAbs(price - slPrice);
    if (slDist <= 0) return;

    double tpDist  = InpRR * slDist;
    double tpPrice = isBuy ? price + tpDist : price - tpDist;

    double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = balance * (InpRiskPercent / 100.0);
    double lot       = CalculateLotSize(riskMoney, slDist);
    if (lot <= 0) return;

    ENUM_ORDER_TYPE orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    Trade.PositionOpen(_Symbol, orderType, lot, price, slPrice, tpPrice);
}

//=============================================================
// FALSE BREAKOUT MONITOR
//=============================================================
void MonitorFalseBreakout()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if (CopyRates(_Symbol, InpTimeframe, 0, 8, rates) < 8) return;

    datetime breakoutBarTime = g_breakoutTime;
    int barsElapsed = 0;
    for (int i = 1; i < 8; i++)
    {
        if (rates[i].time <= breakoutBarTime)
        {
            barsElapsed = i - 1;
            break;
        }
    }

    if (barsElapsed > 5 || barsElapsed <= 0)
    {
        g_breakoutFired = false;
        return;
    }

    double trendVal = ProjectTrendline(g_trendlineA_price, g_trendlineA_idx,
                                       g_trendlineB_price, g_trendlineB_idx, 1);

    double c1 = rates[1].close;

    if (g_breakoutDir == 1 && c1 < trendVal)
    {
        g_falseBreakout = true;
        g_breakoutFired = false;
    }
    else if (g_breakoutDir == -1 && c1 > trendVal)
    {
        g_falseBreakout = true;
        g_breakoutFired = false;
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

    HistorySelect(dayStart, serverTime);

    double dailyProfit   = 0;
    int    tradesToday   = 0;
    int    consecLosses  = 0;
    bool   lastWasLoss   = false;

    uint total = HistoryDealsTotal();
    for (uint i = 0; i < total; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if (HistoryDealGetInteger(ticket, DEAL_MAGIC)  != Magic)        continue;
        if (HistoryDealGetString(ticket,  DEAL_SYMBOL) != _Symbol)      continue;
        if (HistoryDealGetInteger(ticket, DEAL_ENTRY)  != DEAL_ENTRY_OUT) continue;

        tradesToday++;
        double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
        dailyProfit  += profit;

        if (profit < 0)
        {
            consecLosses++;
            lastWasLoss       = true;
            g_lastLossTime    = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
        }
        else
        {
            consecLosses = 0;
            lastWasLoss  = false;
        }
    }

    g_consecLosses = consecLosses;

    if (tradesToday >= InpMaxDailyTrades)
        return false;

    if (consecLosses >= InpMaxConsecLosses)
        return false;

    double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
    double startBalance = balance - dailyProfit;
    double lossLimit    = startBalance * (InpDailyLossLimit / 100.0);

    if (dailyProfit <= -lossLimit)
        return false;

    return true;
}

//=============================================================
// ATR AVERAGE
//=============================================================
double GetATRAverage(const int period)
{
    double buf[];
    ArraySetAsSeries(buf, true);
    if (CopyBuffer(hATR, 0, 1, period, buf) < period) return 0;
    double sum = 0;
    for (int i = 0; i < period; i++) sum += buf[i];
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