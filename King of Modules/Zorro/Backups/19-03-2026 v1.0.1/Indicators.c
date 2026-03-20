// ============================================================
//  Indicators.c  –  Zorro translation of Indicators.mqh
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
// ============================================================
//
//  PATCH NOTES (Final Hardening):
//  #1  – KAMA determinism: per-bar guard added using Bar index.
//        ComputeKAMA_Raw() and ComputeKAMA_Filtered() update
//        their static state only once per bar. Subsequent calls
//        on the same bar return cached values without mutation.
//        Original recursive behavior preserved.
// ============================================================

#ifndef INDICATORS_C
#define INDICATORS_C

#include "Inputs.c"

// ── KAMA state ────────────────────────────────────────────────
static var s_kama          = 0.0;
static var s_kamaFiltered  = 0.0;
static var s_kamaColor     = 0.0;
static int s_kamaWarmup    = 0;

// Per-bar guard variables (#1)
static int s_kamaRawLastBar      = -1;
static int s_kamaFilteredLastBar = -1;
static int s_kamaColorLastBar    = -1;

// Cached outputs for same-bar repeat calls (#1)
static var s_kamaRawCache      = 0.0;
static var s_kamaFilteredCache = 0.0;
static var s_kamaColorCache    = 0.0;


// ============================================================
//  IndicatorsInit
// ============================================================
int IndicatorsInit()
{
    int lookback = InpATRPeriod
                 + InpKAMAPeriod + InpKAMASlowPeriod
                 + InpKeltnerEMAPeriod
                 + InpRSIPeriod
                 + InpKAMASlopeLookback
                 + 50
                 + 10;

    if(lookback > LookBack) LookBack = lookback;

    s_kama              = 0.0;
    s_kamaFiltered      = 0.0;
    s_kamaColor         = 0.0;
    s_kamaWarmup        = 0;
    s_kamaRawLastBar    = -1;
    s_kamaFilteredLastBar = -1;
    s_kamaColorLastBar  = -1;
    s_kamaRawCache      = 0.0;
    s_kamaFilteredCache = 0.0;
    s_kamaColorCache    = 0.0;
    return 1;
}

void IndicatorsRelease() {}


// ============================================================
//  GetRSI
// ============================================================
int GetRSI(var* prev, var* current)
{
    var* s   = series(RSI(seriesClose(), InpRSIPeriod));
    *current = s[0];
    *prev    = s[1];
    return 1;
}


// ============================================================
//  GetKeltner
// ============================================================
int GetKeltner(var* upper, var* lower)
{
    var ema = EMA(seriesClose(), InpKeltnerEMAPeriod);
    var atr = ATR(InpATRPeriod);
    *upper  = ema + InpKeltnerATRFactor * atr;
    *lower  = ema - InpKeltnerATRFactor * atr;
    return 1;
}


// ============================================================
//  ComputeKAMA_Raw  –  internal, called only from kamaRawSeries()
//  #1: per-bar guard — state updated once per bar only.
// ============================================================
static var ComputeKAMA_Raw()
{
    // #1: return cached value if already computed this bar
    if(Bar == s_kamaRawLastBar)
        return s_kamaRawCache;

    var fast_sc = 2.0 / (InpKAMAFastPeriod + 1.0);
    var slow_sc = 2.0 / (InpKAMASlowPeriod + 1.0);
    var* cls    = seriesClose();

    if(s_kamaWarmup < InpKAMAPeriod)
    {
        s_kamaWarmup++;
        s_kama = cls[0];
    }
    else
    {
        var signal = fabs(cls[0] - cls[InpKAMAPeriod]);
        var noise  = 0.0;
        for(int i = 0; i < InpKAMAPeriod; i++)
            noise += fabs(cls[i] - cls[i + 1]);

        var er = (noise > 0.0) ? signal / noise : 0.0;
        var sc = pow(er * (fast_sc - slow_sc) + slow_sc, 2.0);
        s_kama = s_kama + sc * (cls[0] - s_kama);
    }

    s_kamaRawLastBar = Bar;
    s_kamaRawCache   = s_kama;
    return s_kama;
}

// SOLE call-site for raw KAMA series
static var* kamaRawSeries()
{
    return series(ComputeKAMA_Raw());
}


// ============================================================
//  ComputeKAMA_Filtered  –  internal, called only from kamaValSeries()
//  #1: per-bar guard — state updated once per bar only.
// ============================================================
static var ComputeKAMA_Filtered()
{
    // #1: return cached value if already computed this bar
    if(Bar == s_kamaFilteredLastBar)
        return s_kamaFilteredCache;

    var* rs      = kamaRawSeries();
    var  rawNow  = rs[0];
    var  rawPrev = rs[1];

    if(s_kamaWarmup <= InpKAMAPeriod)
    {
        s_kamaFiltered = rawNow;
        s_kamaFilteredLastBar = Bar;
        s_kamaFilteredCache   = rawNow;
        return rawNow;
    }

    var cAmaDiff = rawNow - rawPrev;
    var aAmaDiff = fabs(cAmaDiff);

    var sAmaDiff = 0.0;
    for(int k = 0; k < InpKAMASlowPeriod; k++)
        sAmaDiff += fabs(rs[k] - rs[k + 1]);

    var filterValue = 50.0 * sAmaDiff / (100.0 * InpKAMASlowPeriod);

    var* hi = seriesHigh();
    var* lo = seriesLow();

    var maxHigh = hi[1];
    for(int k = 2; k <= 4; k++) if(hi[k] > maxHigh) maxHigh = hi[k];

    var minLow = lo[1];
    for(int k = 2; k <= 4; k++) if(lo[k] < minLow) minLow = lo[k];

    var filteredNow = rawNow;

    if(cAmaDiff > 0.0)
    {
        if(cAmaDiff < filterValue && hi[0] <= maxHigh + 50.0 * PIP)
            filteredNow = s_kamaFiltered;
    }
    else if(cAmaDiff < 0.0)
    {
        if(aAmaDiff < filterValue && lo[0] >= minLow - 50.0 * PIP)
            filteredNow = s_kamaFiltered;
    }

    s_kamaFiltered        = filteredNow;
    s_kamaFilteredLastBar = Bar;
    s_kamaFilteredCache   = filteredNow;
    return filteredNow;
}

// SOLE call-site for filtered KAMA series
var* kamaValSeries()
{
    return series(ComputeKAMA_Filtered());
}


// ============================================================
//  kamaColorSeries  –  SOLE call-site for colour series
//  #1: per-bar guard — colour state updated once per bar only.
//  0.0 = rising/bullish  (original valc=2)
//  1.0 = falling/bearish (original valc=1)
//  flat = hold s_kamaColor (original valc[i-1])
// ============================================================
var* kamaColorSeries()
{
    // #1: return cached series if already computed this bar
    if(Bar == s_kamaColorLastBar)
        return series(s_kamaColorCache);

    var* ks = kamaValSeries();

    var colorNow;
    if     (ks[0] > ks[1]) colorNow = 0.0;
    else if(ks[0] < ks[1]) colorNow = 1.0;
    else                   colorNow = s_kamaColor;

    s_kamaColor         = colorNow;
    s_kamaColorLastBar  = Bar;
    s_kamaColorCache    = colorNow;
    return series(colorNow);
}


// ============================================================
//  GetKAMAColor  (public)
// ============================================================
int GetKAMAColor(int* prev, int* current)
{
    var* cs  = kamaColorSeries();
    *current = (int)cs[0];
    *prev    = (int)cs[1];
    return 1;
}


// ============================================================
//  GetKAMASlope  (public)
// ============================================================
var GetKAMASlope()
{
    var* ks = kamaValSeries();
    return fabs(ks[1] - ks[InpKAMASlopeLookback]);
}


// ============================================================
//  GetATR  (public)
// ============================================================
int GetATR(var* current, var* avg)
{
    var* s   = series(ATR(InpATRPeriod));
    *current = s[0];

    var sum = 0.0;
    for(int i = 0; i < InpATRPeriod; i++) sum += s[i];
    *avg = sum / InpATRPeriod;
    return 1;
}

#endif // INDICATORS_C
