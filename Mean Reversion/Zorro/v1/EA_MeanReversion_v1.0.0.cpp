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
static bool exhaustedLong  = false;  // RSI < 25 AND price < BB lower seen
static bool exhaustedShort = false;  // RSI > 75 AND price > BB upper seen

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
    set(PARAMETERS | PLOTNOW);
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
    BB_Shift        = 0; //optimize( 2,  0,  3,   1, 0) * -1;

    SMA_Period      = 21;  // fixed — middle band reference

    ADX_Period      = optimize(21, 14, 28,   7, 0);
    ADX_Min         = optimize(17, 14, 20,   3, 0);
    ADX_Max         = optimize(36, 30, 42,   6, 0);

    ATR_Period      = optimize(14,  7, 21,   7, 0);
    ATR_Lookback    = optimize(75, 50, 100, 25, 0);
    ATR_Percentile  = optimize(37, 25, 50,  12, 0) / 100.0; // 0.25 – 0.50

    Stop_Lookback   = optimize( 3,  1, 10,   1, 0);      // fixed per blueprint
    Stop_Buffer     = optimize(50, 20, 100, 10, 0) * PIP;

    BE_Offset       = 10.0 * PIP;
    Profit_Lock     = 200 * PIP; //optimize(200, 100, 300, 50, 0) * PIP;
    Final_Target    = 350 * PIP; //optimize(300, 150, 450, 50, 0) * PIP;
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
// Entry Logic — Two-Phase
// Phase 1: exhaustion detection (sets flag)
// Phase 2: confirmation (triggers entry)
// BB_Shift = 2: we read band values at index [BB_Shift]
// =============================================================================

// ---- LONG ----
bool entryLong()
{
    var bbLow  = bbLower[BB_Shift];  // shifted band value
    var bbLow0 = bbLower[0];         // current band value for close-back check

    // Phase 1: exhaustion — RSI below oversold AND price below lower band
    if (rsiSeries[0] < RSI_Oversold && closePrices[0] < bbLow)
        exhaustedLong = true;

    // Phase 2: confirmation — RSI crossed back above oversold AND price closed back inside
    if (exhaustedLong)
    {
        if (rsiSeries[0] > RSI_Oversold && closePrices[0] > bbLow0)
        {
            exhaustedLong = false;  // reset
            return filtersPass();
        }
    }
    return false;
}

// ---- SHORT ----
bool entryShort()
{
    var bbHigh  = bbUpper[BB_Shift];
    var bbHigh0 = bbUpper[0];

    // Phase 1: exhaustion
    if (rsiSeries[0] > RSI_Overbought && closePrices[0] > bbHigh)
        exhaustedShort = true;

    // Phase 2: confirmation
    if (exhaustedShort)
    {
        if (rsiSeries[0] < RSI_Overbought && closePrices[0] < bbHigh0)
        {
            exhaustedShort = false;
            return filtersPass();
        }
    }
    return false;
}

// =============================================================================
// Stops
// =============================================================================
var initialStopLong()
{
    return LL(Stop_Lookback, 0) - Stop_Buffer;
}

var initialStopShort()
{
    return HH(Stop_Lookback, 0) + Stop_Buffer;
}

// =============================================================================
// Trade Management
// Multi-stage stop update per open trade — no trade struct access
// Uses TradeStopLimit (Zorro's per-trade stop price, accessible in for loop)
// =============================================================================
void manageTrades()
{
    TRADE* tr;

    while(tr = forTrade(0)) // 0 = todos os trades abertos
    {
        if(!(tr->flags & TR_OPEN)) continue;

        var entry  = tr->fEntryPrice;
        var profit = tr->fResult;
        var stop   = tr->fStopLimit;

        var sma = smaSeries[0];

        // LONG
        if(!(tr->flags & TR_SHORT))
        {
            // BE
            if (priceClose(0) >= sma)
            {
                var be = entry + BE_Offset;
                if (stop < be)
                    tr->fStopLimit = be;
            }

            // TRAIL
            if (profit >= Profit_Lock)
            {
                if (tr->fStopLimit < sma)
                    tr->fStopLimit = sma;
            }
        }
        // SHORT
        else
        {
            if (priceClose(0) <= sma)
            {
                var be = entry - BE_Offset;
                if (stop > be || stop == 0)
                    tr->fStopLimit = be;
            }

            if (profit >= Profit_Lock)
            {
                if (tr->fStopLimit > sma || stop == 0)
                    tr->fStopLimit = sma;
            }
        }

        plot("Stop", TradeStopLimit, MAIN | LINE | MINV, RED);
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

    plot("BB_Upper", bbUpper, MAIN | LINE, BLUE);
    plot("BB_Lower", bbLower, MAIN | LINE, BLUE);
    plot("SMA21",    smaSeries, MAIN | LINE, ORANGE);
    plot("RSI",      rsiSeries, NEW  | LINE, RED);
    plot("ADX",      adxSeries, NEW  | LINE, MAGENTA);

    if (Bar < LookBack) return;

    // Trade management — runs every bar on open positions
    manageTrades();

    // LONG entry
    if (entryLong())
    {
        Stop       = initialStopLong();
        TakeProfit = priceClose(0) + Final_Target;
        enterLong();
        plot("Buy", lowPrices[0], MAIN | DOT, GREEN);
    }

    // SHORT entry
    if (entryShort())
    {
        Stop       = initialStopShort();
        TakeProfit = priceClose(0) - Final_Target;
        enterShort();
        plot("Sell", highPrices[0], MAIN | DOT, RED);
    }
}
