#include <zorro.h>

// -----------------------------------------------------------------------------
// Optimizable Parameters
// -----------------------------------------------------------------------------
int    SMA_Trend_Period;
int    SMA_Pullback_Period;
int    ADX_Period;
double ADX_Threshold;
int    ATR_Period;
double Pullback_Min_ATR;
int    Stop_Lookback;
double Stop_Buffer_ATR;
double Trail_Multiplier;
double Min_ATR_Filter;
double Extreme_ATR_Multiplier; 

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
    BarPeriod    = 15;
    LookBack     = 220;
    Hedge        = 2;
    MaxLong      = 1;
    MaxShort     = 1;
    NumCores     = 4;
    Slippage     = 2;
    set(PARAMETERS | PLOTNOW);
}

// =============================================================================
// optimizeCalls
// =============================================================================
void optimizeCalls()
{
    SMA_Trend_Period       = 200;
    SMA_Pullback_Period    = optimize(20,  10,  30,   5, 0);
    ADX_Period             = optimize(21,   7,  28,   7, 0);
    ADX_Threshold          = optimize(20,  16,  30,   2, 0);
    ATR_Period             = optimize(14,   7,  21,   7, 0);
    Pullback_Min_ATR       = optimize( 5,   3,  10,   1, 0) / 10.0;
    Stop_Lookback          = optimize( 7,   5,  10,   1, 0);
    Stop_Buffer_ATR        = optimize( 2,   1,  10,   1, 0) / 10.0;
    Trail_Multiplier       = optimize(150, 100, 300,  25, 0) / 100.0;
    Min_ATR_Filter         = optimize( 5,   5,  50,   5, 0) * PIP;
    Extreme_ATR_Multiplier = optimize(30,  20,  50,   5, 0) / 10.0; 
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
    if (adxSeries[0] < ADX_Threshold)  return false;
    if (atrSeries[0] < Min_ATR_Filter) return false;
    return closePrices[0] > smaTrend[0];
}

bool isBearTrend()
{
    if (adxSeries[0] < ADX_Threshold)  return false;
    if (atrSeries[0] < Min_ATR_Filter) return false;
    return closePrices[0] < smaTrend[0];
}

// =============================================================================
// Pullback Module
// =============================================================================
bool isValidPullbackLong()
{
    if (!isBullTrend()) return false;
    if (lowPrices[0] > smaPullback[0]) return false;

    var recentHigh   = HH(5, 1);
    var pullbackSize = recentHigh - closePrices[0];
    if (pullbackSize < Pullback_Min_ATR * atrSeries[0]) return false;

    return true;
}

bool isValidPullbackShort()
{
    if (!isBearTrend()) return false;
    if (highPrices[0] < smaPullback[0]) return false;

    var recentLow    = LL(5, 1);
    var pullbackSize = closePrices[0] - recentLow;
    if (pullbackSize < Pullback_Min_ATR * atrSeries[0]) return false;

    return true;
}

// =============================================================================
// Mean Reversion Helper
// =============================================================================
bool isExtremeDistance()
{
    var dist = fabs(closePrices[0] - smaTrend[0]);
    return dist > Extreme_ATR_Multiplier * atrSeries[0];
}

// =============================================================================
// Trend Entry Module
// =============================================================================
bool entryLongSignal()
{
    if (!isValidPullbackLong())              return false;
    if (closePrices[0] <= smaPullback[0])    return false;
    if (closePrices[0] <= highPrices[1])     return false;
    if (isExtremeDistance())                 return false; 
    return true;
}

bool entryShortSignal()
{
    if (!isValidPullbackShort())             return false;
    if (closePrices[0] >= smaPullback[0])    return false;
    if (closePrices[0] >= lowPrices[1])      return false;
    if (isExtremeDistance())                 return false; 
    return true;
}

// =============================================================================
// Mean Reversion Entry Module (Updated with Rejection Logic)
// =============================================================================
bool entryLongReversion()
{
    if (atrSeries[0] < Min_ATR_Filter) return false;

    if (closePrices[0] < smaTrend[0] && isExtremeDistance())
    {
        // 1. Sweep previous low | 2. Bullish candle | 3. Strong close
        if (lowPrices[0] < lowPrices[1] && 
            closePrices[0] > openPrices[0] && 
            closePrices[0] > closePrices[1])
        {
            return true;
        }
    }
    return false;
}

bool entryShortReversion()
{
    if (atrSeries[0] < Min_ATR_Filter) return false;

    if (closePrices[0] > smaTrend[0] && isExtremeDistance())
    {
        // 1. Sweep previous high | 2. Bearish candle | 3. Strong close
        if (highPrices[0] > highPrices[1] && 
            closePrices[0] < openPrices[0] && 
            closePrices[0] < closePrices[1])
        {
            return true;
        }
    }
    return false;
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

    bool trendLong  = entryLongSignal();
    bool trendShort = entryShortSignal();

    // ==========================
    // TREND MODE
    // ==========================
    if (trendLong)
    {
        Entry = highPrices[1];
        enterLong();
        plot("Buy", lowPrices[0], MAIN | DOT, GREEN);
        Stop  = initialStopLong();
        Trail = Trail_Multiplier * atrSeries[0];
    }
    else if (trendShort)
    {
        Entry = lowPrices[1];
        enterShort();
        plot("Sell", highPrices[0], MAIN | DOT, RED);
        Stop  = initialStopShort();
        Trail = Trail_Multiplier * atrSeries[0];
    }
    // ==========================
    // MEAN REVERSION MODE (ONLY IF NO TREND SIGNAL)
    // ==========================
    else 
    {
        if (entryLongReversion())
        {
            enterLong();
            plot("Buy", lowPrices[0], MAIN | DOT, GREEN);
            Stop  = initialStopLong();
            Trail = Trail_Multiplier * atrSeries[0];
        }

        if (entryShortReversion())
        {
            enterShort();
            plot("Sell", highPrices[0], MAIN | DOT, RED);
            Stop  = initialStopShort();
            Trail = Trail_Multiplier * atrSeries[0];
        }
    }
}