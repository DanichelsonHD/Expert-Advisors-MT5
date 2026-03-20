#ifndef RSI_EXHAUSTION_C
#define RSI_EXHAUSTION_C

#include "Indicators.c"


// ============================================================
//  PassREATRCompressionFilter
//  Returns 1 when ATR(14)*multiplier < ATR(50) (compressed regime).
//  ATR(50) series is at a dedicated call-site here.
// ============================================================
int PassREATRCompressionFilter()
{
    var* atrSeries;
    var atrFast;
    var atrSlow;

    atrSeries = series(ATR(InpATRPeriod));
    atrFast = atrSeries[0];
    atrSeries = series(ATR(50));
    atrSlow = atrSeries[0];

    return (atrFast * InpATRRETrendMultiplier < atrSlow);
}


// ============================================================
//  DetectRSIExhaustion
//  Pure momentum-continuation logic:
//    SELL: extreme RSI/price on the low side + KAMA still falling
//    BUY:  extreme RSI/price on the high side + KAMA still rising
//
//  OR logic between RSI and Keltner conditions is preserved
//  faithfully from the original.
// ============================================================
int DetectRSIExhaustion(var curRSI,
                                        var upperK, var lowerK,
                                        int kamaColor, var close1)
{
    // SELL: oversold OR below lower band, KAMA bearish (falling)
    if((curRSI < InpRSIOversold || close1 < lowerK) && kamaColor == 1)
        return SIGNAL_SELL;

    // BUY:  overbought OR above upper band, KAMA bullish (rising)
    if((curRSI > InpRSIOverbought || close1 > upperK) && kamaColor == 0)
        return SIGNAL_BUY;

    return SIGNAL_NONE;
}


// ============================================================
//  SignalRSIExhaustion  (public)
// ============================================================
int SignalRSIExhaustion()
{
    // ── Gather indicators ────────────────────────────────────
    var curRSI = 0, prevRSI = 0;
    if(!GetRSI(&prevRSI, &curRSI))
        return SIGNAL_NONE;

    var upperK = 0, lowerK = 0;
    if(!GetKeltner(&upperK, &lowerK))
        return SIGNAL_NONE;

    int kamaColorPrev = 0, kamaColorCur = 0;
    if(!GetKAMAColor(&kamaColorPrev, &kamaColorCur))
        return SIGNAL_NONE;

    var* closeSeries;
    var close1;

    closeSeries = series(price());
    close1 = closeSeries[1];   // bar[-1] close

    // ── Filter ───────────────────────────────────────────────
    if(!PassREATRCompressionFilter())
        return SIGNAL_NONE;

    // ── Signal ───────────────────────────────────────────────
    return DetectRSIExhaustion(curRSI, upperK, lowerK,
                                kamaColorCur, close1);
}

#endif // RSI_EXHAUSTION_C
