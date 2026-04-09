#include <zorro.h>

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
int    RSI_Period;
double RSI_Overbought;
double RSI_Oversold;

int    BB_Period;
double BB_Deviation;

int    SMA_Long_Period;
int    SMA_BB_Period;
int    SMA_Medium_Period;

int    Stop_Lookback;
double Stop_Buffer;
double BE_Offset;
double Profit_Lock;
double Final_Target;

// -----------------------------------------------------------------------------
// STEP 1 — Execution Toggles (not optimized)
// -----------------------------------------------------------------------------
int EnableLongs        = 1;
int EnableShorts       = 1;
int EnableWithTrend    = 1;
int EnableAgainstTrend = 1;

// -----------------------------------------------------------------------------
// Series
// -----------------------------------------------------------------------------
vars closePrices, highPrices, lowPrices, openPrices;
vars rsiSeries;
vars bbUpper, bbLower;
vars smaLongSeries, smaBBSeries, smaMediumSeries;

// -----------------------------------------------------------------------------
// State window
// -----------------------------------------------------------------------------
int MAX_STATE_BARS = 3;

// =============================================================================
// setupParameters
// =============================================================================
void setupParameters()
{
    StartDate    = 2023;
    BarPeriod    = 15;
    LookBack     = 250;
    Hedge        = 2;
    MaxLong      = 1;
    MaxShort     = 1;
    NumCores     = 4;
    Slippage     = 2;
    set(PARAMETERS | PLOTNOW | LOGFILE);
}

// =============================================================================
// optimizeCalls
// =============================================================================
void optimizeCalls()
{
    RSI_Period      = optimize(4,   2,  8,   2, 0);
    RSI_Overbought  = optimize(75, 70, 80,   5, 0);
    RSI_Oversold    = optimize(25, 20, 30,   5, 0);

    BB_Period       = optimize(21, 14, 28,   7, 0);
    BB_Deviation    = optimize(20, 15, 25,   5, 0) / 10.0;

    SMA_BB_Period     = BB_Period;
    SMA_Medium_Period = 50;
    SMA_Long_Period   = 200;

    BE_Offset    = 3  / 20.0 * PIP;
    Profit_Lock  = 25 / 15.0 * PIP;
    Final_Target = 300/ 15.0 * PIP;

    Stop_Lookback = 4;
    Stop_Buffer   = 130 / 20.0 * PIP;
}

// =============================================================================
// defineSeries
// =============================================================================
void defineSeries()
{
    closePrices = series(priceClose(0));
    highPrices  = series(priceHigh(0));
    lowPrices   = series(priceLow(0));
    openPrices  = series(priceOpen(0));

    rsiSeries       = series(RSI(closePrices, RSI_Period));
    bbUpper         = series(BBands(closePrices, BB_Period,  BB_Deviation,  BB_Deviation, 0));
    bbLower         = series(BBands(closePrices, BB_Period, -BB_Deviation, -BB_Deviation, 0));
    smaLongSeries   = series(SMA(closePrices, SMA_Long_Period));
    smaBBSeries     = series(SMA(closePrices, SMA_BB_Period));
    smaMediumSeries = series(SMA(closePrices, SMA_Medium_Period));
}

// =============================================================================
// Entry signals — untouched per spec
// =============================================================================
bool entryLong()
{
    static bool longExhausted = false;
    static int  bars          = 0;

    var bbLow = bbLower[0];

    if (!longExhausted && rsiSeries[0] < RSI_Oversold && closePrices[0] <= bbLow)
    {
        longExhausted = true;
        bars = 0;
    }

    if (longExhausted)
        bars++;

    if (bars > MAX_STATE_BARS)
        longExhausted = false;

    if (longExhausted && rsiSeries[0] > RSI_Oversold && closePrices[0] >= bbLow)
    {
        longExhausted = false;
        return true;
    }

    return false;
}

bool entryShort()
{
    static bool shortExhausted = false;
    static int  bars           = 0;

    var bbHigh = bbUpper[0];

    if (!shortExhausted && rsiSeries[0] > RSI_Overbought && closePrices[0] >= bbHigh)
    {
        shortExhausted = true;
        bars = 0;
    }

    if (shortExhausted)
        bars++;

    if (bars > MAX_STATE_BARS)
        shortExhausted = false;

    if (shortExhausted && rsiSeries[0] < RSI_Overbought && closePrices[0] <= bbHigh)
    {
        shortExhausted = false;
        return true;
    }

    return false;
}

// =============================================================================
// Stops
// =============================================================================
var initialStopLong()
{
    return MinVal(lowPrices, Stop_Lookback) - Stop_Buffer;
}

var initialStopShort()
{
    return MaxVal(highPrices, Stop_Lookback) + Stop_Buffer;
}

// =============================================================================
// STEP 4 + 5 — Trade Management Engine
// Regime-aware: with-trend runs longer (BE + cross exit)
//               against-trend exits fast (price at smaBB)
// =============================================================================
void manageTrades()
{
    TRADE* tr;

    while (tr = forTrade(0))
    {
        if (!(tr->flags & TR_OPEN)) continue;

        bool isLong  = !(tr->flags & TR_SHORT);
        bool isShort =  (tr->flags & TR_SHORT);

        bool isBull = priceClose(0) > smaLongSeries[0];
        bool isBear = priceClose(0) < smaLongSeries[0];

        // =====================================================================
        // LONG
        // =====================================================================
        if (isLong)
        {
            // ---- WITH TREND ----
            if (isBull)
            {
                // BE when price touches smaBB
                if (priceClose(0) >= smaBBSeries[0])
                {
                    var be = tr->fEntryPrice + BE_Offset;
                    if (tr->fStopLimit < be)
                        tr->fStopLimit = be;
                }

                // Exit on structural cross
                if (crossOver(smaMediumSeries, smaBBSeries))
                    exitTrade(tr);
            }

            // ---- AGAINST TREND ----
            if (isBear)
            {
                // Immediate TP at smaBB
                if (priceClose(0) >= smaBBSeries[0])
                    exitTrade(tr);
            }
        }

        // =====================================================================
        // SHORT
        // =====================================================================
        if (isShort)
        {
            // ---- WITH TREND ----
            if (isBear)
            {
                if (priceClose(0) <= smaBBSeries[0])
                {
                    var be = tr->fEntryPrice - BE_Offset;
                    if (tr->fStopLimit > be || tr->fStopLimit == 0)
                        tr->fStopLimit = be;
                }

                if (crossUnder(smaMediumSeries, smaBBSeries))
                    exitTrade(tr);
            }

            // ---- AGAINST TREND ----
            if (isBull)
            {
                if (priceClose(0) <= smaBBSeries[0])
                    exitTrade(tr);
            }
        }
    }
}

// =============================================================================
// run()
// =============================================================================
DLLFUNC void run()
{
    setupParameters();
    optimizeCalls();
    defineSeries();

    // STEP 6 — management runs first, every bar
    manageTrades();

    plot("BB_Upper",    bbUpper,         MAIN | LINE, BLUE);
    plot("BB_Lower",    bbLower,         MAIN | LINE, BLUE);
    plot("SMA 200",     smaLongSeries,   MAIN | LINE, ORANGE);
    plot("SMA_BB",      smaBBSeries,     MAIN | LINE, GREEN);
    plot("SMA_Medium",  smaMediumSeries, MAIN | LINE, RED);
    plot("RSI",         rsiSeries,       NEW  | LINE, RED);

    if (Bar < LookBack) return;

    // STEP 2 — trend detection
    bool isBull = priceClose(0) > smaLongSeries[0];
    bool isBear = priceClose(0) < smaLongSeries[0];

    // STEP 3 — LONG entry with regime filter
    if (entryLong() && NumOpenLong == 0)
    {
        bool isWithTrendLong    = isBull;
        bool isAgainstTrendLong = isBear;

        if (!EnableLongs) return;
        if (isWithTrendLong    && !EnableWithTrend)    return;
        if (isAgainstTrendLong && !EnableAgainstTrend) return;

        Stop = initialStopLong();
        // TakeProfit removed — exits handled by manageTrades()
        enterLong();
    }

    // STEP 3 — SHORT entry with regime filter
    if (entryShort() && NumOpenShort == 0)
    {
        bool isWithTrendShort    = isBear;
        bool isAgainstTrendShort = isBull;

        if (!EnableShorts) return;
        if (isWithTrendShort    && !EnableWithTrend)    return;
        if (isAgainstTrendShort && !EnableAgainstTrend) return;

        Stop = initialStopShort();
        // TakeProfit removed — exits handled by manageTrades()
        enterShort();
    }
}
