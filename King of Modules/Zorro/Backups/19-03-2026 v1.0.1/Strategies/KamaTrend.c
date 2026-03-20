#ifndef KAMA_TREND_C
#define KAMA_TREND_C

#include "../Indicators.c"

#define KAMA_FLIP_LOOKBACK 3


// ============================================================
//  GetKamaFlip
//  Scans the last KAMA_FLIP_LOOKBACK bar-pairs for a regime flip.
//  bullishFlip → any bar in the window transitioned bearish→bullish
//  bearishFlip → any bar in the window transitioned bullish→bearish
//
//  kamaColorSeries() index:
//    [1] = most recent closed bar (bar 1)
//    [2] = bar 2, etc.
//  Pairs examined: ([1],[2]), ([2],[3]), ([3],[4])
//    i.e. current=cs[i], previous=cs[i+1] for i=1..KAMA_FLIP_LOOKBACK
// ============================================================
static int GetKamaFlip(int* bullishFlip, int* bearishFlip)
{
    var* cs = kamaColorSeries();

    *bullishFlip = 0;
    *bearishFlip = 0;

    for(int i = 1; i <= KAMA_FLIP_LOOKBACK; i++)
    {
        int current  = (int)cs[i];
        int previous = (int)cs[i + 1];

        // bearish→bullish: 1→0
        if(previous == 1 && current == 0) *bullishFlip = 1;
        // bullish→bearish: 0→1
        if(previous == 0 && current == 1) *bearishFlip = 1;
    }

    return 1;
}


// ============================================================
//  PassATRExpansionFilter
//  Allows entry only when:
//    (a) ATR(14) is rising vs. previous bar  AND
//    (b) ATR(14) > ATR(50) * InpATRKTTrendMultiplier
//  (expanding volatility / trending regime).
// ============================================================
static int PassATRExpansionFilter()
{
    if(!InpUseATRKTTrendFilter)
        return 1;

    var* atrFastSeries = series(ATR(InpATRPeriod));
    var  atrFastNow    = atrFastSeries[0];
    var  atrFastPrev   = atrFastSeries[1];

    // ATR must be rising
    if(atrFastNow <= atrFastPrev)
        return 0;

    var atrSlow = series(ATR(50))[0];

    return (atrFastNow > atrSlow * InpATRKTTrendMultiplier);
}


// ============================================================
//  PassADXTrendFilter
//  Allows entry only when:
//    (a) ADX is rising vs. previous bar  AND
//    (b) ADX < InpADXComparision (not yet in overextended trend)
// ============================================================
static int PassADXTrendFilter()
{
    if(!InpUseADXFilter)
        return 1;

    var* adxSeries = series(ADX(InpADXPeriod));
    var  adxNow    = adxSeries[0];
    var  adxPrev   = adxSeries[1];

    if(adxNow <= adxPrev)
        return 0;

    return (adxNow < InpADXComparision);
}


// ============================================================
//  SignalKamaTrend  (public)
//  Fires SIGNAL_BUY on bullish KAMA flip, SIGNAL_SELL on bearish,
//  subject to ATR expansion and ADX trend strength filters.
// ============================================================
int SignalKamaTrend()
{
    int bullishFlip = 0, bearishFlip = 0;
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
