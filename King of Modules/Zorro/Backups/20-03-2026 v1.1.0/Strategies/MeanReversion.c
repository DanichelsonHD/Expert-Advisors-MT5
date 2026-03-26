#ifndef MEAN_REVERSION_C
#define MEAN_REVERSION_C

#include "Indicators.c"

#define STATE_IDLE                 0
#define STATE_OVERSOLD_CONFIRMED   1
#define STATE_OVERBOUGHT_CONFIRMED 2

int g_mr_state = STATE_IDLE;


int PassMRKAMASlopeFilter(var slope)
{
    var threshold;

    if(!InpUseKAMAStrongTrendFilter) return 1;
    if(!g_atr) return 0;

    threshold = g_atr[0] * InpKAMASlopeATRMultiplier;
    return (slope <= threshold);
}


int PassMRATRCompressionFilter()
{
    if(!InpUseATRMRTrendFilter) return 1;
    if(!g_atr || !g_atr50) return 0;

    return (g_atr[0] < g_atr50[0] * InpATRMRTrendMultiplier);
}


int PassMRMeanDistanceFilter(var close1)
{
    var distance;
    var threshold;

    if(!InpUseMeanDistanceFilter) return 1;
    if(!g_kama || !g_atr) return 0;

    distance  = fabs(close1 - g_kama[1]);
    threshold = g_atr[0] * InpMeanDistanceATRMult;
    return (distance >= threshold);
}


void DetectMRExtreme(var curRSI, var close1,
                     var upperK, var lowerK, int kamaColor)
{
    if(g_mr_state != STATE_IDLE) return;

    if(curRSI < InpRSIOversold  && close1 < lowerK && kamaColor == 1)
    { g_mr_state = STATE_OVERSOLD_CONFIRMED;   return; }

    if(curRSI > InpRSIOverbought && close1 > upperK && kamaColor == 0)
    { g_mr_state = STATE_OVERBOUGHT_CONFIRMED; return; }
}


int ConfirmMRReturn(var curRSI, var prevRSI)
{
    if(g_mr_state == STATE_OVERSOLD_CONFIRMED)
    {
        if(prevRSI <= InpRSIOversold && curRSI > InpRSIOversold)
        { g_mr_state = STATE_IDLE; return SIGNAL_BUY; }
    }

    if(g_mr_state == STATE_OVERBOUGHT_CONFIRMED)
    {
        if(prevRSI >= InpRSIOverbought && curRSI < InpRSIOverbought)
        { g_mr_state = STATE_IDLE; return SIGNAL_SELL; }
    }

    return SIGNAL_NONE;
}


void ResetMRState(var curRSI)
{
    if(g_mr_state == STATE_OVERSOLD_CONFIRMED)
        if(curRSI > InpRSIOversold &&
           fabs(curRSI - InpRSIOversold) > InpRSIResetThreshold)
            g_mr_state = STATE_IDLE;

    if(g_mr_state == STATE_OVERBOUGHT_CONFIRMED)
        if(curRSI < InpRSIOverbought &&
           fabs(curRSI - InpRSIOverbought) > InpRSIResetThreshold)
            g_mr_state = STATE_IDLE;
}


// ============================================================
//  SignalMeanReversion
//  All data from global pointers. No series()/ATR()/RSI() here.
// ============================================================
int SignalMeanReversion()
{
    var curRSI;
    var prevRSI;
    var upperK;
    var lowerK;
    int kamaColorCur;
    var close1;
    var slope;
    int signal;
    var ema;
    var atr;

    if(!g_rsi || !g_price || !g_atr || !g_kama || !g_kamaColor)
        return SIGNAL_NONE;

    curRSI  = g_rsi[0];
    prevRSI = g_rsi[1];

    // Keltner inline — EMA uses g_price, no new series()
    ema    = EMA(g_price, InpKeltnerEMAPeriod);
    atr    = g_atr[0];
    upperK = ema + InpKeltnerATRFactor * atr;
    lowerK = ema - InpKeltnerATRFactor * atr;

    kamaColorCur = (int)g_kamaColor[0];
    close1       = g_price[1];
    slope        = GetKAMASlope();

    if(!(PassMRATRCompressionFilter() || PassMRKAMASlopeFilter(slope)))
        return SIGNAL_NONE;

    if(!PassMRMeanDistanceFilter(close1))
        return SIGNAL_NONE;

    DetectMRExtreme(curRSI, close1, upperK, lowerK, kamaColorCur);

    signal = ConfirmMRReturn(curRSI, prevRSI);

    ResetMRState(curRSI);

    return signal;
}

#endif // MEAN_REVERSION_C
