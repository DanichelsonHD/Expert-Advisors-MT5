#ifndef KAMA_TREND_C
#define KAMA_TREND_C

#include "Indicators.c"

#define KAMA_FLIP_LOOKBACK 3


int GetKamaFlip(int* bullishFlip, int* bearishFlip)
{
    int i;
    int current;
    int previous;

    if(!g_kamaColor) return 0;

    *bullishFlip = 0;
    *bearishFlip = 0;

    for(i = 1; i <= KAMA_FLIP_LOOKBACK; i++)
    {
        current  = (int)g_kamaColor[i];
        previous = (int)g_kamaColor[i + 1];

        if(previous == 1 && current == 0) *bullishFlip = 1;
        if(previous == 0 && current == 1) *bearishFlip = 1;
    }

    return 1;
}


// ============================================================
//  PassATRExpansionFilter — uses g_atr and g_atr50
// ============================================================
int PassATRExpansionFilter()
{
    if(!InpUseATRKTTrendFilter) return 1;
    if(!g_atr || !g_atr50) return 0;

    if(g_atr[0] <= g_atr[1]) return 0;

    return (g_atr[0] > g_atr50[0] * InpATRKTTrendMultiplier);
}


// ============================================================
//  PassADXTrendFilter — uses g_adx
// ============================================================
int PassADXTrendFilter()
{
    if(!InpUseADXFilter) return 1;
    if(!g_adx) return 0;

    if(g_adx[0] <= g_adx[1]) return 0;

    return (g_adx[0] < InpADXComparision);
}


int SignalKamaTrend()
{
    int bullishFlip;
    int bearishFlip;

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
