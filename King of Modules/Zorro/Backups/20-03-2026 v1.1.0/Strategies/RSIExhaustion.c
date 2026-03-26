#ifndef RSI_EXHAUSTION_C
#define RSI_EXHAUSTION_C

#include "Indicators.c"


// ============================================================
//  PassREATRCompressionFilter — uses g_atr and g_atr50
// ============================================================
int PassREATRCompressionFilter()
{
    if(!g_atr || !g_atr50) return 0;

    return (g_atr[0] * InpATRRETrendMultiplier < g_atr50[0]);
}


int DetectRSIExhaustion(var curRSI, var upperK, var lowerK,
                        int kamaColor, var close1)
{
    if((curRSI < InpRSIOversold  || close1 < lowerK) && kamaColor == 1)
        return SIGNAL_SELL;

    if((curRSI > InpRSIOverbought || close1 > upperK) && kamaColor == 0)
        return SIGNAL_BUY;

    return SIGNAL_NONE;
}


int SignalRSIExhaustion()
{
    var curRSI;
    var prevRSI;
    var upperK;
    var lowerK;
    int kamaColorCur;
    var close1;
    var ema;
    var atr;

    if(!g_rsi || !g_price || !g_atr || !g_kamaColor)
        return SIGNAL_NONE;

    curRSI  = g_rsi[0];
    prevRSI = g_rsi[1];

    // Keltner inline — no new series()
    ema    = EMA(g_price, InpKeltnerEMAPeriod);
    atr    = g_atr[0];
    upperK = ema + InpKeltnerATRFactor * atr;
    lowerK = ema - InpKeltnerATRFactor * atr;

    kamaColorCur = (int)g_kamaColor[0];
    close1       = g_price[1];

    if(!PassREATRCompressionFilter())
        return SIGNAL_NONE;

    return DetectRSIExhaustion(curRSI, upperK, lowerK, kamaColorCur, close1);
}

#endif // RSI_EXHAUSTION_C
