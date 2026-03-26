#ifndef INDICATORS_C
#define INDICATORS_C

#include "Inputs.c"

// ── KAMA persistent state ─────────────────────────────────────
var s_kama;
var s_kamaFiltered;
var s_kamaColor;
int s_kamaWarmup;

// ── Centralized series pointers ───────────────────────────────
var* g_price;
var* g_high;
var* g_low;
var* g_rsi;
var* g_atr;
var* g_atr50;
var* g_adx;
var* g_kama;
var* g_kamaColor;


int IndicatorsInit()
{
    int lookback;

    lookback = 200;

    if(lookback > LookBack) LookBack = lookback;

    s_kama         = 0;
    s_kamaFiltered = 0;
    s_kamaColor    = 0;
    s_kamaWarmup   = 0;

    g_price     = 0;
    g_high      = 0;
    g_low       = 0;
    g_rsi       = 0;
    g_atr       = 0;
    g_atr50     = 0;
    g_adx       = 0;
    g_kama      = 0;
    g_kamaColor = 0;

    return 1;
}

void IndicatorsRelease() {}


int GetRSI(var* prev, var* current)
{
    if(!g_rsi) return 0;
    *current = g_rsi[0];
    *prev    = g_rsi[1];
    return 1;
}


int GetKeltner(var* upper, var* lower)
{
    var ema;
    var atr;

    if(!g_price || !g_atr) return 0;

    ema    = EMA(g_price, InpKeltnerEMAPeriod);
    atr    = g_atr[0];
    *upper = ema + InpKeltnerATRFactor * atr;
    *lower = ema - InpKeltnerATRFactor * atr;
    return 1;
}


// ============================================================
//  ComputeKAMA_Raw — uses g_price, no series() call
// ============================================================
var ComputeKAMA_Raw()
{
    var fast_sc;
    var slow_sc;
    var sig;
    var noise;
    var er;
    var sc;
    int i;

    fast_sc = 2.0 / (InpKAMAFastPeriod + 1.0);
    slow_sc = 2.0 / (InpKAMASlowPeriod + 1.0);

    if(s_kamaWarmup < InpKAMAPeriod)
    {
        s_kamaWarmup++;
        s_kama = g_price[0];
    }
    else
    {
        sig   = fabs(g_price[0] - g_price[InpKAMAPeriod]);
        noise = 0;
        for(i = 0; i < InpKAMAPeriod; i++)
            noise += fabs(g_price[i] - g_price[i + 1]);

        if(noise > 0) er = sig / noise; else er = 0;
        sc     = pow(er * (fast_sc - slow_sc) + slow_sc, 2.0);
        s_kama = s_kama + sc * (g_price[0] - s_kama);
    }

    return s_kama;
}

// Static pointer — series() called ONCE at first bar, reused after
var* kamaRawSeries()
{
    static var* kama_raw_ptr;
    if(!kama_raw_ptr)
        kama_raw_ptr = series(ComputeKAMA_Raw());
    else
        series(ComputeKAMA_Raw());  // advance buffer, reuse pointer
    return kama_raw_ptr;
}


// ============================================================
//  ComputeKAMA_Filtered — uses kamaRawSeries(), g_high, g_low
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

    maxHigh = g_high[1];
    for(k = 2; k <= 4; k++) if(g_high[k] > maxHigh) maxHigh = g_high[k];

    minLow = g_low[1];
    for(k = 2; k <= 4; k++) if(g_low[k] < minLow) minLow = g_low[k];

    filteredNow = rawNow;

    if(cAmaDiff > 0)
    {
        if(cAmaDiff < filterValue && g_high[0] <= maxHigh + 50.0 * PIP)
            filteredNow = s_kamaFiltered;
    }
    else if(cAmaDiff < 0)
    {
        if(aAmaDiff < filterValue && g_low[0] >= minLow - 50.0 * PIP)
            filteredNow = s_kamaFiltered;
    }

    s_kamaFiltered = filteredNow;
    return filteredNow;
}

// Static pointer — series() called ONCE, reused after
var* kamaValSeries()
{
    static var* kama_val_ptr;
    if(!kama_val_ptr)
        kama_val_ptr = series(ComputeKAMA_Filtered());
    else
        series(ComputeKAMA_Filtered());  // advance buffer
    return kama_val_ptr;
}


// ============================================================
//  kamaColorSeries — series() unconditional, static pointer
//  0 = rising/bullish, 1 = falling/bearish, flat = hold previous
// ============================================================
var ComputeKAMAColor()
{
    var* ks;
    var  colorNow;

    ks = kamaValSeries();

    if     (ks[0] > ks[1]) colorNow = 0;
    else if(ks[0] < ks[1]) colorNow = 1;
    else                   colorNow = s_kamaColor;

    s_kamaColor = colorNow;
    return colorNow;
}

var* kamaColorSeries()
{
    static var* kama_color_ptr;
    if(!kama_color_ptr)
        kama_color_ptr = series(ComputeKAMAColor());
    else
        series(ComputeKAMAColor());  // advance buffer
    return kama_color_ptr;
}


int GetKAMAColor(int* prev, int* current)
{
    if(!g_kamaColor) return 0;
    *current = (int)g_kamaColor[0];
    *prev    = (int)g_kamaColor[1];
    return 1;
}


var GetKAMASlope()
{
    if(!g_kama) return 0;
    return fabs(g_kama[1] - g_kama[InpKAMASlopeLookback]);
}


int GetATR(var* current, var* avg)
{
    var  sum;
    int  i;

    if(!g_atr) return 0;

    *current = g_atr[0];

    sum = 0;
    for(i = 0; i < InpATRPeriod; i++) sum += g_atr[i];
    *avg = sum / InpATRPeriod;
    return 1;
}


// ============================================================
//  UpdateAllSeries
//  Called EVERY BAR, UNCONDITIONALLY.
//  ALL series() / indicator calls are centralized here.
//  No other file may call series(), RSI(), ATR(), EMA(), ADX().
// ============================================================
void UpdateAllSeries()
{
    g_price     = series(price());
    g_high      = series(priceHigh());
    g_low       = series(priceLow());
    g_rsi       = series(RSI(g_price, InpRSIPeriod));
    g_atr       = series(ATR(InpATRPeriod));
    g_atr50     = series(ATR(50));
    g_adx       = series(ADX(InpADXPeriod));
    g_kama      = kamaValSeries();
    g_kamaColor = kamaColorSeries();
}

#endif // INDICATORS_C
