#ifndef KAMA_TREND_C
#define KAMA_TREND_C

#include "Indicators.c"

#define KAMA_FLIP_LOOKBACK 3


// ============================================================
//  GetKamaFlip
//  #7: bullish transition = 1→2, bearish transition = 2→1
// ============================================================
int GetKamaFlip(int* bullishFlip, int* bearishFlip)
{
    var* cs;
    int  i;
    int  current;
    int  previous;

    cs = kamaColorSeries();

    *bullishFlip = 0;
    *bearishFlip = 0;

    for(i = 1; i <= KAMA_FLIP_LOOKBACK; i++)
    {
        current  = (int)cs[i];
        previous = (int)cs[i + 1];

        // #7: bearish→bullish: 1→2
        if(previous == 1 && current == 2) *bullishFlip = 1;
        // #7: bullish→bearish: 2→1
        if(previous == 2 && current == 1) *bearishFlip = 1;
    }

    return 1;
}


// ============================================================
//  PassATRExpansionFilter
//  #5/#6: use s[1] (closed bar), s[2] (prev closed bar)
// ============================================================
int PassATRExpansionFilter()
{
    var* atrFastSeries;
    var  atrFastNow;
    var  atrFastPrev;
    var* atrSlowSeries;
    var  atrSlow;

    if(!InpUseATRKTTrendFilter)
        return 1;

    // #6: pointer stored once
    atrFastSeries = series(ATR(InpATRPeriod));
    atrFastNow    = atrFastSeries[1];   // #5: closed bar
    atrFastPrev   = atrFastSeries[2];   // #5: prev closed bar

    if(atrFastNow <= atrFastPrev)
        return 0;

    atrSlowSeries = series(ATR(50));
    atrSlow       = atrSlowSeries[1];   // #5: closed bar

    return (atrFastNow > atrSlow * InpATRKTTrendMultiplier);
}


// ============================================================
//  PassADXTrendFilter
//  #5/#6: use s[1] (closed bar), s[2] (prev closed bar)
// ============================================================
int PassADXTrendFilter()
{
    var* adxSeries;
    var  adxNow;
    var  adxPrev;

    if(!InpUseADXFilter)
        return 1;

    // #6: pointer stored once
    adxSeries = series(ADX(InpADXPeriod));
    adxNow    = adxSeries[1];   // #5: closed bar
    adxPrev   = adxSeries[2];   // #5: prev closed bar

    if(adxNow <= adxPrev)
        return 0;

    return (adxNow < InpADXComparision);
}


int SignalKamaTrend()
{
    int bullishFlip;
    int bearishFlip;

    // #3: one execution per bar
    static int lastBar;
    if(Bar == lastBar) return SIGNAL_NONE;
    lastBar = Bar;

    bullishFlip = 0;
    bearishFlip = 0;

    if(!GetKamaFlip(&bullishFlip, &bearishFlip))
        return SIGNAL_NONE;

    if(!bullishFlip && !bearishFlip)
        return SIGNAL_NONE;

    if(!PassATRExpansionFilter())
        return SIGNAL_NONE;

    if(!PassADXTrendFilter())
        return SIGNAL_NONE;

    if(bearishFlip) return SIGNAL_SELL;
    if(bullishFlip) return SIGNAL_BUY;

    return SIGNAL_NONE;
}

#endif // KAMA_TREND_C
