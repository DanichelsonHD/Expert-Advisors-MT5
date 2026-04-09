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
double Stop_Buffer;       // in price units (e.g. 50 * PIP)

double BE_Offset;         // break-even offset in price units
double Profit_Lock;       // profit level to lock at SMA21
double Final_Target;      // fixed TP in price units

vars closePrices, highPrices, lowPrices, openPrices;
vars rsiSeries;
vars bbUpper, bbLower;
vars smaLongSeries, smaBBSeries, smaMediumSeries;

// -----------------------------------------------------------------------------
// State flags (two-phase entry requires memory across bars)
// -----------------------------------------------------------------------------
int MAX_STATE_BARS = 3;


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


void optimizeCalls()
{
    RSI_Period      = optimize(4,   2,  8,   2, 0);
    RSI_Overbought  = optimize(75, 70, 80,   5, 0);
    RSI_Oversold    = optimize(25, 20, 30,   5, 0);

    BB_Period       = optimize(21, 14, 28,   7, 0);
    BB_Deviation    = optimize(20, 15, 25,   5, 0) / 10.0;  // 1.5 – 2.5

    SMA_BB_Period   = BB_Period;  // middle band reference
    SMA_Medium_Period   = 50;  // middle band reference
    SMA_Long_Period = 200;        // fixed

    BE_Offset       = 3 / 20 * PIP; //optimize(10,  1,  10,  1, 0) / 20 * PIP;
    Profit_Lock     = 25 / 15 * PIP; //optimize(75, 25, 155, 10, 0) / 15 * PIP;
    Final_Target    = 300 / 15 * PIP; //optimize(100, 25, 350, 25, 0) / 15 * PIP;

    Stop_Lookback   = 4; //optimize( 7,  1,  10,  1, 0);      // fixed per blueprint
    Stop_Buffer     = 130  / 20 * PIP; //optimize(60, 10, 150, 10, 0) / 20 * PIP;
}


void defineSeries()
{
    closePrices = series(priceClose(0));
    highPrices  = series(priceHigh(0));
    lowPrices   = series(priceLow(0));
    openPrices  = series(priceOpen(0));

    rsiSeries   = series(RSI(closePrices, RSI_Period));

    // Zorro BBands: BBands(Data, Period, Upper_sigma, Lower_sigma, MA_type)
    // Upper band: positive deviation; lower band: negative deviation
    bbUpper         = series(BBands(closePrices, BB_Period,  BB_Deviation, BB_Deviation, 0));
    bbLower         = series(BBands(closePrices, BB_Period, -BB_Deviation, -BB_Deviation, 0));
    smaLongSeries   = series(SMA(closePrices, SMA_Long_Period));
    smaBBSeries     = series(SMA(closePrices, SMA_BB_Period));
    smaMediumSeries = series(SMA(closePrices, SMA_Medium_Period));
}

// ---- LONG ----
bool entryLong()
{
    static bool longExhausted = false;
    static int bars = 0;

    var bbLow = bbLower[0];

    // exhaustion trigger
    if (!longExhausted && rsiSeries[0] < RSI_Oversold && closePrices[0] <= bbLow)
    {
        longExhausted = true;
        bars = 0;
    }

    if (longExhausted)
        bars++;

    if (bars > MAX_STATE_BARS)
        longExhausted = false;

    // recovery → entry
    if (longExhausted && rsiSeries[0] > RSI_Oversold && closePrices[0] >= bbLow)
    {
        longExhausted = false;
        return true;
    }

    return false;
}

// ---- SHORT ----
bool entryShort()
{
    static bool shortExhausted = false;
    static int bars = 0;

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

var initialStopLong()
{
    return MinVal(lowPrices, Stop_Lookback) - Stop_Buffer;
}

var initialStopShort()
{
    return MaxVal(highPrices, Stop_Lookback) + Stop_Buffer;
}

DLLFUNC void run()
{

    setupParameters();

    optimizeCalls();
    defineSeries();

    plot("BB_Upper", bbUpper, MAIN | LINE, BLUE);
    plot("BB_Lower", bbLower, MAIN | LINE, BLUE);
    plot("SMA 200",    smaLongSeries, MAIN | LINE, ORANGE);
    plot("SMA_BB",    smaBBSeries, MAIN | LINE, GREEN);
    plot("SMA_Medium",    smaMediumSeries, MAIN | LINE, RED);
    plot("RSI",      rsiSeries, NEW  | LINE, RED);

    if (Bar < LookBack) return;

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