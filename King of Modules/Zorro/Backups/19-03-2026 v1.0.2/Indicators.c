#ifndef INDICATORS_C
#define INDICATORS_C

#include "Inputs.c"

// ── KAMA state (no inline init – Lite-C restriction) ──────────
var s_kama;
var s_kamaFiltered;
var s_kamaColor;
int s_kamaWarmup;

int s_kamaRawLastBar;
int s_kamaFilteredLastBar;
int s_kamaColorLastBar;

var s_kamaRawCache;
var s_kamaFilteredCache;
var s_kamaColorCache;


// ============================================================
//  IndicatorsInit
// ============================================================
int IndicatorsInit()
{
    int lookback;

    lookback = InpATRPeriod
             + InpKAMAPeriod + InpKAMASlowPeriod
             + InpKeltnerEMAPeriod
             + InpRSIPeriod
             + InpKAMASlopeLookback
             + 50
             + 10;

    if(lookback > LookBack) LookBack = lookback;

    s_kama               = 0;
    s_kamaFiltered       = 0;
    s_kamaColor          = 0;
    s_kamaWarmup         = 0;
    s_kamaRawLastBar     = -1;
    s_kamaFilteredLastBar = -1;
    s_kamaColorLastBar   = -1;
    s_kamaRawCache       = 0;
    s_kamaFilteredCache  = 0;
    s_kamaColorCache     = 0;
    return 1;
}

void IndicatorsRelease() {}


// ============================================================
//  GetRSI
// ============================================================
int GetRSI(var* prev, var* current)
{
    var* s;
    s        = series(RSI(series(price()), InpRSIPeriod));
    *current = s[0];
    *prev    = s[1];
    return 1;
}


// ============================================================
//  GetKeltner
// ============================================================
int GetKeltner(var* upper, var* lower)
{
    var ema;
    var atr;
    ema    = EMA(series(price()), InpKeltnerEMAPeriod);
    atr    = ATR(InpATRPeriod);
    *upper = ema + InpKeltnerATRFactor * atr;
    *lower = ema - InpKeltnerATRFactor * atr;
    return 1;
}


// ============================================================
//  ComputeKAMA_Raw
// ============================================================
var ComputeKAMA_Raw()
{
    var fast_sc;
    var slow_sc;
    var* cls;
    var signal;
    var noise;
    var er;
    var sc;
    int i;

    if(Bar == s_kamaRawLastBar)
        return s_kamaRawCache;

    fast_sc = 2.0 / (InpKAMAFastPeriod + 1.0);
    slow_sc = 2.0 / (InpKAMASlowPeriod + 1.0);
    cls     = series(price());

    if(s_kamaWarmup < InpKAMAPeriod)
    {
        s_kamaWarmup++;
        s_kama = cls[0];
    }
    else
    {
        signal = fabs(cls[0] - cls[InpKAMAPeriod]);
        noise  = 0;
        for(i = 0; i < InpKAMAPeriod; i++)
            noise += fabs(cls[i] - cls[i + 1]);

        if(noise > 0) er = signal / noise; else er = 0;
        sc     = pow(er * (fast_sc - slow_sc) + slow_sc, 2.0);
        s_kama = s_kama + sc * (cls[0] - s_kama);
    }

    s_kamaRawLastBar = Bar;
    s_kamaRawCache   = s_kama;
    return s_kama;
}

var* kamaRawSeries()
{
    return series(ComputeKAMA_Raw());
}


// ============================================================
//  ComputeKAMA_Filtered
// ============================================================
var ComputeKAMA_Filtered()
{
    var* rs;
    var  rawNow;
    var  rawPrev;
    var  cAmaDiff;
    var  aAmaDiff;
    var  sAmaDiff;
    var  filterValue;
    var* hi;
    var* lo;
    var  maxHigh;
    var  minLow;
    var  filteredNow;
    int  k;

    if(Bar == s_kamaFilteredLastBar)
        return s_kamaFilteredCache;

    rs      = kamaRawSeries();
    rawNow  = rs[0];
    rawPrev = rs[1];

    if(s_kamaWarmup <= InpKAMAPeriod)
    {
        s_kamaFiltered        = rawNow;
        s_kamaFilteredLastBar = Bar;
        s_kamaFilteredCache   = rawNow;
        return rawNow;
    }

    cAmaDiff = rawNow - rawPrev;
    aAmaDiff = fabs(cAmaDiff);

    sAmaDiff = 0;
    for(k = 0; k < InpKAMASlowPeriod; k++)
        sAmaDiff += fabs(rs[k] - rs[k + 1]);

    filterValue = 50.0 * sAmaDiff / (100.0 * InpKAMASlowPeriod);

    hi = series(priceHigh());
    lo = series(priceLow());

    maxHigh = hi[1];
    for(k = 2; k <= 4; k++) if(hi[k] > maxHigh) maxHigh = hi[k];

    minLow = lo[1];
    for(k = 2; k <= 4; k++) if(lo[k] < minLow) minLow = lo[k];

    filteredNow = rawNow;

    if(cAmaDiff > 0)
    {
        if(cAmaDiff < filterValue && hi[0] <= maxHigh + 50.0 * PIP)
            filteredNow = s_kamaFiltered;
    }
    else if(cAmaDiff < 0)
    {
        if(aAmaDiff < filterValue && lo[0] >= minLow - 50.0 * PIP)
            filteredNow = s_kamaFiltered;
    }

    s_kamaFiltered        = filteredNow;
    s_kamaFilteredLastBar = Bar;
    s_kamaFilteredCache   = filteredNow;
    return filteredNow;
}

var* kamaValSeries()
{
    return series(ComputeKAMA_Filtered());
}


// ============================================================
//  kamaColorSeries
// ============================================================
var* kamaColorSeries()
{
    var* ks;
    var  colorNow;

    if(Bar == s_kamaColorLastBar)
        return series(s_kamaColorCache);

    ks = kamaValSeries();

    if     (ks[0] > ks[1]) colorNow = 0;
    else if(ks[0] < ks[1]) colorNow = 1;
    else                   colorNow = s_kamaColor;

    s_kamaColor        = colorNow;
    s_kamaColorLastBar = Bar;
    s_kamaColorCache   = colorNow;
    return series(colorNow);
}


// ============================================================
//  GetKAMAColor
// ============================================================
int GetKAMAColor(int* prev, int* current)
{
    var* cs;
    cs       = kamaColorSeries();
    *current = (int)cs[0];
    *prev    = (int)cs[1];
    return 1;
}


// ============================================================
//  GetKAMASlope
// ============================================================
var GetKAMASlope()
{
    var* ks;
    ks = kamaValSeries();
    return fabs(ks[1] - ks[InpKAMASlopeLookback]);
}


// ============================================================
//  GetATR
// ============================================================
int GetATR(var* current, var* avg)
{
    var* s;
    var  sum;
    int  i;

    s        = series(ATR(InpATRPeriod));
    *current = s[0];

    sum = 0;
    for(i = 0; i < InpATRPeriod; i++) sum += s[i];
    *avg = sum / InpATRPeriod;
    return 1;
}

#endif // INDICATORS_C
