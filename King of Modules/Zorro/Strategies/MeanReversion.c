#ifndef MEAN_REVERSION_C
#define MEAN_REVERSION_C

#include "Indicators.c"


// ============================================================
//  ENTRY STATE MACHINE
// ============================================================

#define STATE_IDLE                 0
#define STATE_OVERSOLD_CONFIRMED   1
#define STATE_OVERBOUGHT_CONFIRMED 2

int g_mr_state = STATE_IDLE;


// ============================================================
//  PassMRKAMASlopeFilter
//  Blocks entry when KAMA slope exceeds ATR-scaled threshold
//  (strong trend present → avoid mean-reversion entry).
//  Returns 1 (pass) when slope is below threshold or filter disabled.
// ============================================================
int PassMRKAMASlopeFilter(var slope)
{
    if(!InpUseKAMAStrongTrendFilter)
        return 1;

    var atrVal = 0, atrAvg = 0;
    if(!GetATR(&atrVal, &atrAvg))
        return 0;

    var threshold = atrVal * InpKAMASlopeATRMultiplier;
    return (slope <= threshold);
}


// ============================================================
//  PassMRATRCompressionFilter
//  Allows entry only when ATR(14) < ATR(50) * multiplier
//  (low-volatility / mean-reverting regime).
//  ATR(50) series is created at this call-site (single buffer).
// ============================================================
int PassMRATRCompressionFilter()
{
    if(!InpUseATRMRTrendFilter)
        return 1;
    
    var* atrSeries;
    var atrFast;
    var atrSlow;

    atrSeries = series(ATR(InpATRPeriod));
    atrFast = atrSeries[0];                 // same series as GetATR()
    atrSeries = series(ATR(50));
    atrSlow = atrSeries[0];                 // dedicated ATR(50) buffer

    return (atrFast < atrSlow * InpATRMRTrendMultiplier);
}


// ============================================================
//  PassMRMeanDistanceFilter
//  Allows entry only when price is far enough from KAMA.
//  MQL5: CopyBuffer(g_handleKAMA,0,1,1,kama) → bar[-1] KAMA
//        CopyBuffer(g_handleATR,0,1,1,atr)   → bar[-1] ATR
//  Zorro: kamaValSeries()[1] and ATR series[0] (current bar ATR).
//  NOTE: original read bar-1 ATR; here we use bar-0 ATR for
//  simplicity (difference is negligible on M15/H1).
// ============================================================
int PassMRMeanDistanceFilter(var close1)
{
    if(!InpUseMeanDistanceFilter)
        return 1;

    var* kamaSeries;
    var* atrSeries;
    var kamaVal;
    var atrFast;

    kamaSeries = kamaValSeries();
    kamaVal    = kamaSeries[1];       // KAMA one bar ago
    atrSeries  = series(ATR(InpATRPeriod));
    atrFast    = atrSeries[0];
    var distance  = fabs(close1 - kamaVal);
    var threshold = atrFast * InpMeanDistanceATRMult;

    return (distance >= threshold);
}


// ============================================================
//  DetectMRExtreme
//  Transitions state machine from IDLE to OVERSOLD/OVERBOUGHT
//  when all three conditions align.
//
//  KAMA color map (Indicators.c):
//    kamaColor == 1 → bearish (falling)  → oversold context  (BUY)
//    kamaColor == 0 → bullish (rising)   → overbought context (SELL)
// ============================================================
void DetectMRExtreme(var curRSI, var close1,
                             var upperK, var lowerK, int kamaColor)
{
    if(g_mr_state != STATE_IDLE)
        return;

    // Oversold: RSI low + price below lower Keltner + KAMA falling
    if(curRSI < InpRSIOversold &&
       close1  < lowerK        &&
       kamaColor == 1)
    {
        g_mr_state = STATE_OVERSOLD_CONFIRMED;
        return;
    }

    // Overbought: RSI high + price above upper Keltner + KAMA rising
    if(curRSI > InpRSIOverbought &&
       close1  > upperK          &&
       kamaColor == 0)             // was ==2 in MQL5; 0=bullish here
    {
        g_mr_state = STATE_OVERBOUGHT_CONFIRMED;
        return;
    }
}


// ============================================================
//  ConfirmMRReturn
//  Fires signal when RSI crosses back out of the extreme zone.
//  Resets state to IDLE on confirmation.
// ============================================================
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


// ============================================================
//  ResetMRState
//  Clears a stale pending state when RSI has moved too far
//  from the extreme threshold without triggering confirmation.
// ============================================================
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


// ============================================================
//  SignalMeanReversion  (public)
//  Orchestrates all sub-functions and returns the net signal.
// ============================================================
int SignalMeanReversion()
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
    close1 = closeSeries[1];   // bar[-1] close (iClose shift=1)
    var slope  = GetKAMASlope();

    // ── Filters ──────────────────────────────────────────────
    // Original: !(PassATRCompression() || PassKAMASlope()) → skip
    // OR logic: EITHER filter passing is sufficient to allow entry
    if(!(PassMRATRCompressionFilter() || PassMRKAMASlopeFilter(slope)))
        return SIGNAL_NONE;

    if(!PassMRMeanDistanceFilter(close1))
        return SIGNAL_NONE;

    // ── State machine ────────────────────────────────────────
    DetectMRExtreme(curRSI, close1, upperK, lowerK, kamaColorCur);

    int signal = ConfirmMRReturn(curRSI, prevRSI);

    ResetMRState(curRSI);

    return signal;
}

#endif // MEAN_REVERSION_C
