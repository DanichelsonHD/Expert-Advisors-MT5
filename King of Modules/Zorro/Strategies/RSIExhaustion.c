#ifndef RSI_EXHAUSTION_C
#define RSI_EXHAUSTION_C

#include "Indicators.c"


// ============================================================
//  PassREATRCompressionFilter
//  #5/#6: use s[1] (closed bar)
// ============================================================
int PassREATRCompressionFilter()
{
    var* atrSeries;
    var  atrFast;
    var  atrSlow;

    // #6: pointer stored once per series call
    atrSeries = series(ATR(InpATRPeriod));
    atrFast   = atrSeries[1];   // #5: closed bar

    atrSeries = series(ATR(50));
    atrSlow   = atrSeries[1];   // #5: closed bar

    return (atrFast * InpATRRETrendMultiplier < atrSlow);
}


// ============================================================
//  DetectRSIExhaustion
//  #7: kamaColor == 1 → bearish (SELL)
//      kamaColor == 2 → bullish (BUY)
// ============================================================
int DetectRSIExhaustion(var curRSI, var upperK, var lowerK,
                        int kamaColor, var close1)
{
    if((curRSI < InpRSIOversold || close1 < lowerK) && kamaColor == 1)
        return SIGNAL_SELL;

    if((curRSI > InpRSIOverbought || close1 > upperK) && kamaColor == 2)   // #7
        return SIGNAL_BUY;

    return SIGNAL_NONE;
}


int SignalRSIExhaustion()
{
    var  curRSI;
    var  prevRSI;
    var  upperK;
    var  lowerK;
    int  kamaColorPrev;
    int  kamaColorCur;
    var* closeSeries;
    var  close1;

    // #3: one execution per bar
    static int lastBar;
    if(Bar == lastBar) return SIGNAL_NONE;
    lastBar = Bar;

    curRSI  = 0;
    prevRSI = 0;
    if(!GetRSI(&prevRSI, &curRSI))
        return SIGNAL_NONE;

    upperK = 0;
    lowerK = 0;
    if(!GetKeltner(&upperK, &lowerK))
        return SIGNAL_NONE;

    kamaColorPrev = 0;
    kamaColorCur  = 0;
    if(!GetKAMAColor(&kamaColorPrev, &kamaColorCur))
        return SIGNAL_NONE;

    // #6: pointer stored, #5: closed bar
    closeSeries = series(price());
    close1      = closeSeries[1];

    if(!PassREATRCompressionFilter())
        return SIGNAL_NONE;

    return DetectRSIExhaustion(curRSI, upperK, lowerK, kamaColorCur, close1);
}

#endif // RSI_EXHAUSTION_C
