#ifndef INDICATORS_C
#define INDICATORS_C

#include "Inputs.c"

// ── KAMA persistent state ─────────────────────────────────────
var s_kama;
var s_kamaFiltered;
var s_kamaColor;
int s_kamaWarmup;


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

    s_kama         = 0;
    s_kamaFiltered = 0;
    s_kamaColor    = 0;
    s_kamaWarmup   = 0;
    return 1;
}

void IndicatorsRelease() {}


// ============================================================
//  GetRSI
//  s[1] = last closed bar (MQL5 CopyBuffer shift=1)
//  s[2] = bar before that
// ============================================================
int GetRSI(var* prev, var* current)
{
    var* priceSeries;
    var* s;

    priceSeries = series(price());
    s           = series(RSI(priceSeries, InpRSIPeriod));

    *current = s[1];
    *prev    = s[2];
    return 1;
}


// ============================================================
//  GetKeltner
// ============================================================
int GetKeltner(var* upper, var* lower)
{
    var* priceSeries;
    var  ema;
    var  atr;

    priceSeries = series(price());
    ema         = EMA(priceSeries, InpKeltnerEMAPeriod);
    atr         = ATR(InpATRPeriod);

    *upper = ema + InpKeltnerATRFactor * atr;
    *lower = ema - InpKeltnerATRFactor * atr;
    return 1;
}


// ============================================================
//  ComputeKAMA_Raw
//  MUST always execute fully — no early returns.
// ============================================================
var ComputeKAMA_Raw()
{
    var* priceSeries;
    var  fast_sc;
    var  slow_sc;
    var  sig;
    var  noise;
    var  er;
    var  sc;
    int  i;

    fast_sc     = 2.0 / (InpKAMAFastPeriod + 1.0);
    slow_sc     = 2.0 / (InpKAMASlowPeriod + 1.0);
    priceSeries = series(price());

    if(s_kamaWarmup < InpKAMAPeriod)
    {
        s_kamaWarmup++;
        s_kama = priceSeries[0];
    }
    else
    {
        sig   = fabs(priceSeries[0] - priceSeries[InpKAMAPeriod]);
        noise = 0;
        for(i = 0; i < InpKAMAPeriod; i++)
            noise += fabs(priceSeries[i] - priceSeries[i + 1]);

        if(noise > 0) er = sig / noise; else er = 0;
        sc     = pow(er * (fast_sc - slow_sc) + slow_sc, 2.0);
        s_kama = s_kama + sc * (priceSeries[0] - s_kama);
    }

    return s_kama;
}

var* kamaRawSeries()
{
    return series(ComputeKAMA_Raw());
}


// ============================================================
//  ComputeKAMA_Filtered
//  MUST always execute fully — no early returns.
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

    rs      = kamaRawSeries();
    rawNow  = rs[0];
    rawPrev = rs[1];

    if(s_kamaWarmup <= InpKAMAPeriod)
    {
        s_kamaFiltered = rawNow;
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

    s_kamaFiltered = filteredNow;
    return filteredNow;
}

var* kamaValSeries()
{
    return series(ComputeKAMA_Filtered());
}


// ============================================================
//  kamaColorSeries
//  series() called unconditionally.
//  2 = rising/bullish  (original valc=2)
//  1 = falling/bearish (original valc=1)
//  flat = hold s_kamaColor (original valc[i-1])
// ============================================================
var* kamaColorSeries()
{
    var* ks;
    var  colorNow;

    ks = kamaValSeries();

    if     (ks[0] > ks[1]) colorNow = 2;
    else if(ks[0] < ks[1]) colorNow = 1;
    else                   colorNow = s_kamaColor;

    s_kamaColor = colorNow;

    return series(colorNow);
}


int GetKAMAColor(int* prev, int* current)
{
    var* cs;
    cs       = kamaColorSeries();
    *current = (int)cs[0];
    *prev    = (int)cs[1];
    return 1;
}


var GetKAMASlope()
{
    var* ks;
    ks = kamaValSeries();
    return fabs(ks[1] - ks[InpKAMASlopeLookback]);
}


// ============================================================
//  GetATR
//  s[1] = last closed bar ATR (MQL5 CopyBuffer shift=1)
// ============================================================
int GetATR(var* current, var* avg)
{
    var* s;
    var  sum;
    int  i;

    s        = series(ATR(InpATRPeriod));
    *current = s[1];

    sum = 0;
    for(i = 1; i <= InpATRPeriod; i++) sum += s[i];
    *avg = sum / InpATRPeriod;
    return 1;
}

#endif // INDICATORS_C
