#include <zorro.h>

// =============================================================================
// MeanReversionEA.cpp
// Mean Reversion EA — RSI(4) + Bollinger Bands + ADX regime + ATR volatility
// Style: billion.cpp / TabajaraQuant.cpp — single file, native Zorro vars
// =============================================================================

// -----------------------------------------------------------------------------
// Parameters
// -----------------------------------------------------------------------------
int    RSI_Period;
double RSI_Overbought;
double RSI_Oversold;

int    BB_Period;
double BB_Deviation;
int    BB_Shift;

int    SMA_Period;

int    ADX_Period;
double ADX_Min;
double ADX_Max;

int    ATR_Period;
int    ATR_Lookback;
double ATR_Percentile;

int    Stop_Lookback;
double Stop_Buffer;       // in price units (e.g. 50 * PIP)

double BE_Offset;         // break-even offset in price units
double Profit_Lock;       // profit level to lock at SMA21
double Final_Target;      // fixed TP in price units

// -----------------------------------------------------------------------------
// Series
// -----------------------------------------------------------------------------
vars closePrices, highPrices, lowPrices, openPrices;
vars rsiSeries;
vars bbUpper, bbLower, smaSeries;
vars adxSeries, atrSeries;

// -----------------------------------------------------------------------------
// State flags (two-phase entry requires memory across bars)
// -----------------------------------------------------------------------------
int MAX_STATE_BARS = 8;

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
    //NumWFOCycles = 6;
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
    BB_Deviation    = optimize(20, 15, 25,   5, 0) / 10.0;  // 1.5 – 2.5
    BB_Shift        = 0 ;

    SMA_Period      = BB_Period;  // fixed — middle band reference

    ADX_Period      = optimize(21, 14,  28,  7, 0);
    ADX_Min         = optimize(17, 11,  20,  3, 0);
    ADX_Max         = optimize(36, 27,  42,  3, 0);

    ATR_Period      = optimize(14,  7,  21,  7, 0);
    ATR_Lookback    = optimize(75, 50, 100, 25, 0);
    ATR_Percentile  = optimize(35, 25,  65, 10, 0) / 100.0; // 0.25 – 0.50

    BE_Offset       = 3 / 20 * PIP; //optimize(10,  1,  10,  1, 0) / 20 * PIP;
    Profit_Lock     = optimize(75, 25, 155, 10, 0) / 15 * PIP;
    Final_Target    = 300 / 15 * PIP; //optimize(100, 25, 350, 25, 0) / 15 * PIP;

    Stop_Lookback   = 4; //optimize( 7,  1,  10,  1, 0);      // fixed per blueprint
    Stop_Buffer     = 130  / 20 * PIP; //optimize(60, 10, 150, 10, 0) / 20 * PIP;
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

    rsiSeries   = series(RSI(closePrices, RSI_Period));

    // Zorro BBands: BBands(Data, Period, Upper_sigma, Lower_sigma, MA_type)
    // Upper band: positive deviation; lower band: negative deviation
    // BB_Shift = 2 means we read [BB_Shift] index (2 bars back) — applied at read time
    bbUpper     = series(BBands(closePrices, BB_Period,  BB_Deviation, BB_Deviation, 0));
    bbLower     = series(BBands(closePrices, BB_Period, -BB_Deviation, -BB_Deviation, 0));
    smaSeries   = series(SMA(closePrices, SMA_Period));

    adxSeries   = series(ADX(ADX_Period));
    atrSeries   = series(ATR(ATR_Period));
}

// =============================================================================
// Regime Filter — ADX range gate
// =============================================================================
bool isRangeMarket()
{
    var adx = adxSeries[0];
    return adx > ADX_Min && adx < ADX_Max;
}

// =============================================================================
// Volatility Filter — dynamic ATR threshold
// ATR_threshold = (ATR_max - ATR_min) * ATR_Percentile + ATR_min
// =============================================================================
bool sufficientVolatility()
{
    var atrMin = MinVal(atrSeries, ATR_Lookback);
    var atrMax = MaxVal(atrSeries, ATR_Lookback);
    var threshold = (atrMax - atrMin) * ATR_Percentile + atrMin;
    return atrSeries[0] > threshold;
}

// =============================================================================
// Combined market filter — must pass both gates
// =============================================================================
bool filtersPass()
{
    return isRangeMarket() && sufficientVolatility();
}

// =============================================================================
// Entry Logic — Two-Phase state machine
// =============================================================================

// ---- LONG ----
bool entryLong()
{
    static bool exhausted = false;
    static int bars = 0;

    var bbLow = bbLower[0];

    // exhaustion trigger
    if (!exhausted && rsiSeries[0] < RSI_Oversold && closePrices[0] < bbLow)
    {
        exhausted = true;
        bars = 0;
    }

    if (exhausted)
        bars++;

    if (bars > MAX_STATE_BARS)
        exhausted = false;

    // recovery → entry
    if (exhausted && rsiSeries[0] > RSI_Oversold && closePrices[0] > bbLow)
    {
        exhausted = false;
        return filtersPass();
    }

    return false;
}

// ---- SHORT ----
bool entryShort()
{
    static bool exhausted = false;
    static int bars = 0;

    var bbHigh = bbUpper[0];

    if (!exhausted && rsiSeries[0] > RSI_Overbought && closePrices[0] > bbHigh)
    {
        exhausted = true;
        bars = 0;
    }

    if (exhausted)
        bars++;

    if (bars > MAX_STATE_BARS)
        exhausted = false;

    if (exhausted && rsiSeries[0] < RSI_Overbought && closePrices[0] < bbHigh)
    {
        exhausted = false;
        return filtersPass();
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

int MAX_BARS_IN_TRADE = 70;

// =============================================================================
// Trade Management
// Multi-stage stop update per open trade — no trade struct access
// Uses TradeStopLimit (Zorro's per-trade stop price, accessible in for loop)
// =============================================================================
void manageTrades()
{
    TRADE* tr;

    while(tr = forTrade(0))
    {
        if(!(tr->flags & TR_OPEN)) continue;

        // max duration exit
        if (Bar - tr->nBarOpen > MAX_BARS_IN_TRADE)
        {
            exitTrade(tr);
            continue;
        }

        var entry  = tr->fEntryPrice;
        var profit = tr->fResult;
        var sma    = smaSeries[0];

        // LONG
        if(!(tr->flags & TR_SHORT))
        {
            if (priceClose(0) <= sma - 2.0 * atrSeries[0])
            {
                exitTrade(tr);
                continue;
            }

            if (priceClose(0) >= sma)
            {
                var be = entry + BE_Offset;
                if (tr->fStopLimit < be)
                    tr->fStopLimit = be;
            }

            if (profit >= Profit_Lock)
            {
                if (tr->fStopLimit < sma)
                    tr->fStopLimit = sma;
            }
        }
        // SHORT
        else
        {
            if (priceClose(0) >= sma + 2.0 * atrSeries[0])
            {
                exitTrade(tr);
                continue;
            }

            if (priceClose(0) <= sma)
            {
                var be = entry - BE_Offset;
                if (tr->fStopLimit > be || tr->fStopLimit == 0)
                    tr->fStopLimit = be;
            }

            if (profit >= Profit_Lock)
            {
                if (tr->fStopLimit > sma || tr->fStopLimit == 0)
                    tr->fStopLimit = sma;
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

    if (Bar < LookBack) return;

    manageTrades();

    if (entryLong() && NumOpenLong == 0)
    {
        Stop       = initialStopLong();
        TakeProfit = priceClose(0) + Final_Target;
        enterLong();
    }

    if (entryShort() && NumOpenShort == 0)
    {
        Stop       = initialStopShort();
        TakeProfit = priceClose(0) - Final_Target;
        enterShort();
    }
}
