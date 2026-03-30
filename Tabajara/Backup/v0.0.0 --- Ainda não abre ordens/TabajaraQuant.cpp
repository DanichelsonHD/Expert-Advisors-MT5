#include <zorro.h>

// =============================================================================
// TabajaraQuant.cpp
// Trend-following pullback continuation EA
// Style: billion.cpp — single file, native Zorro vars, no trade structs
// =============================================================================

// -----------------------------------------------------------------------------
// Optimizable Parameters
// -----------------------------------------------------------------------------
int    SMA_Trend_Period;       // SMA(200) — primary trend
int    SMA_Pullback_Period;    // SMA(20)  — pullback zone
int    ADX_Period;
double ADX_Threshold;
int    ATR_Period;
double Pullback_Min_ATR;       // minimum pullback size as ATR multiple
int    Stop_Lookback;          // swing stop lookback in bars
double Stop_Buffer_ATR;        // stop buffer as ATR multiple
double Trail_Multiplier;       // ATR trailing multiplier
double SMA200_Prox_ATR;        // proximity filter: skip if price within N*ATR of SMA200
double Min_ATR_Filter;         // minimum ATR to allow trading (price units)

// -----------------------------------------------------------------------------
// Series
// -----------------------------------------------------------------------------
vars closePrices, highPrices, lowPrices, openPrices;
vars smaTrend, smaPullback;
vars adxSeries, atrSeries;

// =============================================================================
// setupParameters
// =============================================================================
void setupParameters()
{
    StartDate    = 2023;
    BarPeriod    = 15;    // H4 — adjust per instrument
    LookBack     = 220;
    Hedge        = 2;
    MaxLong      = 1;
    MaxShort     = 1;
    NumCores     = 4;
    set(PARAMETERS | PLOTNOW);
}

// =============================================================================
// optimizeCalls
// =============================================================================
void optimizeCalls()
{
    SMA_Trend_Period    = 200;  // fixed
    SMA_Pullback_Period = optimize(20, 10, 30,  5, 0);
    ADX_Period          = optimize(21, 14, 28,  7, 0);
    ADX_Threshold       = optimize(20, 15, 30,  5, 0);
    ATR_Period          = optimize(14,  7, 21,  7, 0);
    Pullback_Min_ATR    = optimize( 5,  3, 10,  1, 0) / 10.0;  // 0.3 – 1.0
    Stop_Lookback       = optimize( 7,  5, 10,  1, 0);
    Stop_Buffer_ATR     = optimize( 2,  1,  4,  1, 0) / 10.0;  // 0.1 – 0.4
    Trail_Multiplier    = optimize(15, 10, 30,  5, 0) / 10.0;  // 1.0 – 3.0
    SMA200_Prox_ATR     = 0.5;
    Min_ATR_Filter      = 5.0 * PIP;
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

    smaTrend    = series(SMA(closePrices, SMA_Trend_Period));
    smaPullback = series(SMA(closePrices, SMA_Pullback_Period));
    adxSeries   = series(ADX(ADX_Period));
    atrSeries   = series(ATR(ATR_Period));
}

// =============================================================================
// Trend Module
// =============================================================================
bool isBullTrend()
{
    if (adxSeries[0] < ADX_Threshold)               return false;
    //if (atrSeries[0] < Min_ATR_Filter)               return false;
    if (fabs(closePrices[0] - smaTrend[0]) <
        SMA200_Prox_ATR * atrSeries[0])              return false;
    return closePrices[0] > smaTrend[0];
}

bool isBearTrend()
{
    if (adxSeries[0] < ADX_Threshold)               return false;
    //if (atrSeries[0] < Min_ATR_Filter)               return false;
    if (fabs(closePrices[0] - smaTrend[0]) <
        SMA200_Prox_ATR * atrSeries[0])              return false;
    return closePrices[0] < smaTrend[0];
}

// =============================================================================
// Pullback Module
// direction: +1 = bullish candles, -1 = bearish candles
// =============================================================================
int countConsecutiveCandles(int direction)
{
    int count = 0;
    int i;
    for (i = 0; i < 10; i++)
    {
        bool bull = (closePrices[i] > openPrices[i]);
        if (direction > 0 &&  bull) { count++; continue; }
        if (direction < 0 && !bull) { count++; continue; }
        break;
    }
    return count;
}

bool isValidPullbackLong()
{
    if (!isBullTrend())                              return false;
    if (closePrices[0] > smaPullback[0])             return false;
    if (countConsecutiveCandles(-1) < 2)             return false;

    var pullHigh = closePrices[0];
    int i;
    for (i = 0; i < 8; i++)
        if (closePrices[i] > pullHigh) pullHigh = closePrices[i];
    if ((pullHigh - closePrices[0]) <
        Pullback_Min_ATR * atrSeries[0])             return false;

    return true;
}

bool isValidPullbackShort()
{
    if (!isBearTrend())                              return false;
    if (closePrices[0] < smaPullback[0])             return false;
    if (countConsecutiveCandles(+1) < 2)             return false;

    var pullLow = closePrices[0];
    int i;
    for (i = 0; i < 8; i++)
        if (closePrices[i] < pullLow) pullLow = closePrices[i];
    if ((closePrices[0] - pullLow) <
        Pullback_Min_ATR * atrSeries[0])             return false;

    return true;
}

// =============================================================================
// Entry Module
// =============================================================================
bool entryLongSignal()
{
    if (!isValidPullbackLong())                      return false;
    return closePrices[0] > openPrices[0];
}

bool entryShortSignal()
{
    if (!isValidPullbackShort())                     return false;
    return closePrices[0] < openPrices[0];
}

// =============================================================================
// Stops Module
// =============================================================================
var initialStopLong()
{
    return LL(Stop_Lookback, 0) - Stop_Buffer_ATR * atrSeries[0];
}

var initialStopShort()
{
    return HH(Stop_Lookback, 0) + Stop_Buffer_ATR * atrSeries[0];
}

// =============================================================================
// run()
// =============================================================================
DLLFUNC void run()
{
    setupParameters();
    optimizeCalls();
    defineSeries();

    plot("SMA200", smaTrend,    MAIN | LINE, RED);
    plot("SMA20",  smaPullback, MAIN | LINE, GREEN);
    plot("ADX",    adxSeries,   NEW  | LINE, BLUE);
    plot("ATR",    atrSeries,   NEW  | LINE, ORANGE);

    if (Bar < LookBack) return;

    printf("\nADX: %.2f | ATR: %.5f | Dist200: %.5f",
        adxSeries[0],
        atrSeries[0],
        fabs(closePrices[0] - smaTrend[0])
    );

    // ------------------------------------------------------------------
    // LONG Entry — buy stop at previous bar high
    // ------------------------------------------------------------------
    if (entryLongSignal())
    {
        Entry      = highPrices[1];
        Stop       = initialStopLong();
        TakeProfit = 0;
        Trail      = Trail_Multiplier * atrSeries[0];
        enterLong();
    }

    // ------------------------------------------------------------------
    // SHORT Entry — sell stop at previous bar low
    // ------------------------------------------------------------------
    if (entryShortSignal())
    {
        Entry      = lowPrices[1];
        Stop       = initialStopShort();
        TakeProfit = 0;
        Trail      = Trail_Multiplier * atrSeries[0];
        enterShort();
    }
}
