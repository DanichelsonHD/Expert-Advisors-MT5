#ifndef MEAN_REVERSION_C
#define MEAN_REVERSION_C

#include "Indicators.c"

#define STATE_IDLE                 0
#define STATE_OVERSOLD_CONFIRMED   1
#define STATE_OVERBOUGHT_CONFIRMED 2

int g_mr_state = STATE_IDLE;


int PassMRKAMASlopeFilter(var slope)
{
    var atrVal;
    var atrAvg;
    var threshold;

    if(!InpUseKAMAStrongTrendFilter)
        return 1;

    atrVal = 0;
    atrAvg = 0;
    if(!GetATR(&atrVal, &atrAvg))
        return 0;

    threshold = atrVal * InpKAMASlopeATRMultiplier;
    return (slope <= threshold);
}


int PassMRATRCompressionFilter()
{
    var* atrSeries;
    var  atrFast;
    var  atrSlow;

    if(!InpUseATRMRTrendFilter)
        return 1;

    atrSeries = series(ATR(InpATRPeriod));
    atrFast   = atrSeries[1];   // #5: closed bar

    atrSeries = series(ATR(50));
    atrSlow   = atrSeries[1];   // #5: closed bar

    return (atrFast < atrSlow * InpATRMRTrendMultiplier);
}


int PassMRMeanDistanceFilter(var close1)
{
    var* kamaSeries;
    var* atrSeries;
    var  kamaVal;
    var  atrFast;
    var  distance;
    var  threshold;

    if(!InpUseMeanDistanceFilter)
        return 1;

    kamaSeries = kamaValSeries();
    kamaVal    = kamaSeries[1];   // KAMA one bar ago

    atrSeries  = series(ATR(InpATRPeriod));
    atrFast    = atrSeries[1];    // #5: closed bar

    distance  = fabs(close1 - kamaVal);
    threshold = atrFast * InpMeanDistanceATRMult;

    return (distance >= threshold);
}


// ============================================================
//  DetectMRExtreme
//  #7: kamaColor == 1 → bearish (falling)  → oversold  (BUY)
//      kamaColor == 2 → bullish (rising)   → overbought (SELL)
// ============================================================
void DetectMRExtreme(var curRSI, var close1,
                     var upperK, var lowerK, int kamaColor)
{
    if(g_mr_state != STATE_IDLE)
        return;

    if(curRSI < InpRSIOversold &&
       close1  < lowerK        &&
       kamaColor == 1)          // #7: bearish = 1
    {
        g_mr_state = STATE_OVERSOLD_CONFIRMED;
        return;
    }

    if(curRSI > InpRSIOverbought &&
       close1  > upperK          &&
       kamaColor == 2)            // #7: bullish = 2
    {
        g_mr_state = STATE_OVERBOUGHT_CONFIRMED;
        return;
    }
}


int ConfirmMRReturn(var curRSI, var prevRSI)
{
    if(g_mr_state == STATE_OVERSOLD_CONFIRMED)
    {
        if(prevRSI <= InpRSIOversold && curRSI > InpRSIOversold)
        {
            g_mr_state = STATE_IDLE;
            return SIGNAL_BUY;
        }
    }

    if(g_mr_state == STATE_OVERBOUGHT_CONFIRMED)
    {
        if(prevRSI >= InpRSIOverbought && curRSI < InpRSIOverbought)
        {
            g_mr_state = STATE_IDLE;
            return SIGNAL_SELL;
        }
    }

    return SIGNAL_NONE;
}


void ResetMRState(var curRSI)
{
    if(g_mr_state == STATE_OVERSOLD_CONFIRMED)
    {
        if(curRSI > InpRSIOversold &&
           fabs(curRSI - InpRSIOversold) > InpRSIResetThreshold)
            g_mr_state = STATE_IDLE;
    }

    if(g_mr_state == STATE_OVERBOUGHT_CONFIRMED)
    {
        if(curRSI < InpRSIOverbought &&
           fabs(curRSI - InpRSIOverbought) > InpRSIResetThreshold)
            g_mr_state = STATE_IDLE;
    }
}


int SignalMeanReversion()
{
    var  curRSI;
    var  prevRSI;
    var  upperK;
    var  lowerK;
    int  kamaColorPrev;
    int  kamaColorCur;
    var* closeSeries;
    var  close1;
    var  slope;
    int  signal;

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

    // #6: pointer stored, #5: use [1] for closed bar close
    closeSeries = series(price());
    close1      = closeSeries[1];

    slope = GetKAMASlope();

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
