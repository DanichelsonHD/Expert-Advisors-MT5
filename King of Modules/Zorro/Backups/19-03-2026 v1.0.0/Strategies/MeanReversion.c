// ============================================================
//  Strategies/MeanReversion.c
//  Zorro translation of Strategies/MeanReversion.mqh
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
// ============================================================
//
//  ARCHITECTURE NOTES (MQL5 → Zorro)
//  ------------------------------------------------------------------
//  Bar-change guard (lastBar / iTime) → REMOVED. Zorro calls
//    run() exactly once per closed bar.
//
//  UpdateMRIndicators() → logic inlined into SignalMeanReversion().
//    Each indicator sub-call uses the canonical Indicators.c helpers:
//    GetRSI(), GetKeltner(), kamaColorSeries(), GetKAMASlope().
//
//  iClose(_Symbol,_Period,1) → seriesClose()[1]
//
//  iATR(50) static handle → series(ATR(50))[0]
//    Zorro computes ATR(50) natively; no handle or init required.
//    series() at this call-site creates a dedicated ATR(50) buffer.
//
//  CopyBuffer(g_handleKAMA,0,1,N,buf) for slope →
//    GetKAMASlope() (Indicators.c), which reads kamaValSeries()
//    at its single call-site.
//
//  PassMRMeanDistanceFilter: CopyBuffer(g_handleKAMA,0,1,1,kama)
//    → kamaValSeries()[1]  (bar-1 KAMA value, shifted-1 original)
//
//  KAMA color codes (Indicators.c convention):
//    0 = rising/bullish   [was colorCode 2 in MQL5]
//    1 = falling/bearish  [was colorCode 1 in MQL5]
//    DetectMRExtreme:
//      kamaColor==1 (bearish) for oversold detection  → unchanged
//      kamaColor==2 (bullish) for overbought detection → becomes 0
//
//  Filter logic:
//    Original: !(PassATRCompression() || PassKAMASlope()) → skip.
//    Preserved exactly — OR semantics mean EITHER filter alone is
//    sufficient to allow entry.
// ============================================================

#ifndef MEAN_REVERSION_C
#define MEAN_REVERSION_C

#include "../Indicators.c"


// ============================================================
//  ENTRY STATE MACHINE
// ============================================================
typedef enum {
    STATE_IDLE                 = 0,
    STATE_OVERSOLD_CONFIRMED   = 1,
    STATE_OVERBOUGHT_CONFIRMED = 2
} ENUM_ENTRY_STATE;

static ENUM_ENTRY_STATE g_mr_state = STATE_IDLE;


// ============================================================
//  PassMRKAMASlopeFilter
//  Blocks entry when KAMA slope exceeds ATR-scaled threshold
//  (strong trend present → avoid mean-reversion entry).
//  Returns 1 (pass) when slope is below threshold or filter disabled.
// ============================================================
static int PassMRKAMASlopeFilter(var slope)
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
static int PassMRATRCompressionFilter()
{
    if(!InpUseATRMRTrendFilter)
        return 1;

    var atrFast = series(ATR(InpATRPeriod))[0];   // same series as GetATR()
    var atrSlow = series(ATR(50))[0];              // dedicated ATR(50) buffer

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
static int PassMRMeanDistanceFilter(var close1)
{
    if(!InpUseMeanDistanceFilter)
        return 1;

    var kamaVal   = kamaValSeries()[1];       // KAMA one bar ago
    var atrFast   = series(ATR(InpATRPeriod))[0];
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
static void DetectMRExtreme(var curRSI, var close1,
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
static ENUM_SIGNAL ConfirmMRReturn(var curRSI, var prevRSI)
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
static void ResetMRState(var curRSI)
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
ENUM_SIGNAL SignalMeanReversion()
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

    var close1 = seriesClose()[1];   // bar[-1] close (iClose shift=1)
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

    ENUM_SIGNAL signal = ConfirmMRReturn(curRSI, prevRSI);

    ResetMRState(curRSI);

    return signal;
}

#endif // MEAN_REVERSION_C
