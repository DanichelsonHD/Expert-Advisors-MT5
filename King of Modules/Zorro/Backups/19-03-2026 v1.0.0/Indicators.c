// ============================================================
//  Indicators.c  –  Zorro translation of Indicators.mqh
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
//
//  REVISION (Source-accurate):
//    Full KAMA with filter algorithm implemented from
//    KAMA_with_filter.mq5 source.  Three prior defects corrected:
//
//    1. KAMA filter (freeze logic) now implemented.
//       val[] ≠ ama[] in the original — filtered KAMA can freeze
//       when movement is small relative to recent volatility.
//
//    2. Flat colour now preserved correctly.
//       Original: valc[i] = ... : valc[i-1]  (hold previous when flat)
//       Prior code emitted 0 or 1 on every bar without the hold.
//
//    3. Raw / filtered KAMA separated into two series.
//       kamaRawSeries()  → sole call-site for ama[]  (ComputeKAMA_Raw)
//       kamaValSeries()  → sole call-site for val[]  (ComputeKAMA_Filtered)
//       kamaColorSeries()→ sole call-site for valc[] (color with flat-hold)
// ============================================================
//
//  INDICATOR SOURCE PARAMETERS (from EA call to iCustom):
//    inpPeriod           = InpKAMAPeriod      (14)
//    inpFastPeriod       = InpKAMAFastPeriod  (2)
//    inpSlowPeriod       = InpKAMASlowPeriod  (30)
//    inpPower            = 2   (hard-coded in original iCustom call)
//    inpFilter           = 50
//    inpFilterPeriod     = 4
//    inpFilterDifference = 50.0
//    inpPrice            = PRICE_CLOSE
//
//  COLOUR CONVENTION (internal, 0/1 — all strategy files use this):
//    0 → KAMA rising  (original valc = 2 / bullish)
//    1 → KAMA falling (original valc = 1 / bearish)
//    flat → hold previous colour (matches original valc[i-1])
//
//  series() CALL-SITE RULE:
//    Zorro identifies a series buffer by its call-site (source
//    location). Never call series(ComputeKAMA_Raw()) or
//    series(ComputeKAMA_Filtered()) outside their designated
//    helper functions. All consumers call the public helpers.
// ============================================================

#ifndef INDICATORS_C
#define INDICATORS_C

#include "Inputs.c"


// ============================================================
//  KAMA STATE  –  file-scope statics, one instance per script
// ============================================================
static var  s_kama         = 0.0;  // recursive raw KAMA (ama[])
static var  s_kamaFiltered = 0.0;  // last emitted filtered value (val[])
static var  s_kamaColor    = 0.0;  // last non-flat colour (0=rising, 1=falling)
static int  s_kamaWarmup   = 0;    // warmup bar counter


// ============================================================
//  IndicatorsInit
//  Sets LookBack to prime all indicators, including ATR(50).
// ============================================================
int IndicatorsInit()
{
    int lookback = InpATRPeriod
                 + InpKAMAPeriod + InpKAMASlowPeriod
                 + InpKeltnerEMAPeriod
                 + InpRSIPeriod
                 + InpKAMASlopeLookback
                 + 50    // ATR(50) used by strategy filters
                 + 10;   // safety margin

    if(lookback > LookBack)
        LookBack = lookback;

    s_kama         = 0.0;
    s_kamaFiltered = 0.0;
    s_kamaColor    = 0.0;
    s_kamaWarmup   = 0;

    return 1;
}


// ============================================================
//  IndicatorsRelease  –  no-op
// ============================================================
void IndicatorsRelease()
{
    // Zorro frees series memory automatically on EXITRUN.
}


// ============================================================
//  GetRSI
//  prev    → RSI bar[-1]
//  current → RSI bar[ 0]
// ============================================================
int GetRSI(var* prev, var* current)
{
    var* rsiSeries = series(RSI(seriesClose(), InpRSIPeriod));
    *current = rsiSeries[0];
    *prev    = rsiSeries[1];
    return 1;
}


// ============================================================
//  GetKeltner
//  Upper = EMA(close, EmaPeriod) + ATRFactor * ATR(AtrPeriod)
//  Lower = EMA(close, EmaPeriod) − ATRFactor * ATR(AtrPeriod)
//  Matches Keltner_Channel.mq5 (MetaQuotes standard).
// ============================================================
int GetKeltner(var* upper, var* lower)
{
    var ema    = EMA(seriesClose(), InpKeltnerEMAPeriod);
    var atrVal = ATR(InpATRPeriod);
    *upper = ema + InpKeltnerATRFactor * atrVal;
    *lower = ema - InpKeltnerATRFactor * atrVal;
    return 1;
}


// ============================================================
//  ComputeKAMA_Raw  –  internal
//  Kaufman AMA with power=2 (iKama from KAMA_with_filter.mq5).
//  Produces ama[] — the pre-filter KAMA value.
//  MUST be called ONLY from kamaRawSeries().
// ============================================================
static var ComputeKAMA_Raw()
{
    var fast_sc = 2.0 / (InpKAMAFastPeriod + 1.0);
    var slow_sc = 2.0 / (InpKAMASlowPeriod + 1.0);
    var* cls    = seriesClose();

    if(s_kamaWarmup < InpKAMAPeriod)
    {
        s_kamaWarmup++;
        s_kama = cls[0];
        return s_kama;
    }

    var signal    = fabs(cls[0] - cls[InpKAMAPeriod]);
    var noise     = 0.0;
    for(int i = 0; i < InpKAMAPeriod; i++)
        noise += fabs(cls[i] - cls[i + 1]);

    var er = (noise > 0.0) ? signal / noise : 0.0;
    var sc = pow(er * (fast_sc - slow_sc) + slow_sc, 2.0);   // inpPower = 2

    s_kama = s_kama + sc * (cls[0] - s_kama);
    return s_kama;
}


// ============================================================
//  kamaRawSeries  –  internal
//  SOLE call-site for raw KAMA (ama[]) series.
//  [0] = current bar raw KAMA, [k] = k bars ago.
// ============================================================
static var* kamaRawSeries()
{
    return series(ComputeKAMA_Raw());
}


// ============================================================
//  ComputeKAMA_Filtered  –  internal
//  Applies the freeze filter from KAMA_with_filter.mq5.
//
//  Filter parameters (from original iCustom call):
//    inpFilter           = 50
//    inpFilterPeriod     = 4
//    inpFilterDifference = 50.0
//    inpSlowPeriod       = InpKAMASlowPeriod (30)
//
//  Freeze conditions:
//    Rising  (cAmaDiff > 0):
//      cAmaDiff < filterValue
//      AND high[cur] ≤ max(high[1..4]) + 50*PIP
//    Falling (cAmaDiff < 0):
//      |cAmaDiff| < filterValue
//      AND low[cur] ≥ min(low[1..4]) − 50*PIP
//    When frozen: val[i] = val[i-1]  (held in s_kamaFiltered)
//
//  NormalizeDouble omitted (precision < 0.005 XAUUSD, negligible).
//  MUST be called ONLY from kamaValSeries().
// ============================================================
static var ComputeKAMA_Filtered()
{
    var* rawSeries = kamaRawSeries();
    var  rawNow    = rawSeries[0];
    var  rawPrev   = rawSeries[1];

    // During warmup: no filter, pass raw through
    if(s_kamaWarmup <= InpKAMAPeriod)
    {
        s_kamaFiltered = rawNow;
        return rawNow;
    }

    // Start as raw KAMA; may be overridden by freeze
    var filteredNow = rawNow;

    var cAmaDiff = rawNow - rawPrev;
    var aAmaDiff = fabs(cAmaDiff);

    // sAmaDiff: sum of |ama[k] - ama[k+1]| over InpKAMASlowPeriod (30) bars
    var sAmaDiff = 0.0;
    for(int k = 0; k < InpKAMASlowPeriod; k++)
        sAmaDiff += fabs(rawSeries[k] - rawSeries[k + 1]);

    // filterValue = inpFilter * sAmaDiff / (100 * inpSlowPeriod)
    var filterValue = 50.0 * sAmaDiff / (100.0 * InpKAMASlowPeriod);

    // High/low series for band comparison
    var* hi = seriesHigh();
    var* lo = seriesLow();

    // max(high[1..inpFilterPeriod=4])
    var maxHigh = hi[1];
    for(int k = 2; k <= 4; k++)
        if(hi[k] > maxHigh) maxHigh = hi[k];

    // min(low[1..inpFilterPeriod=4])
    var minLow = lo[1];
    for(int k = 2; k <= 4; k++)
        if(lo[k] < minLow) minLow = lo[k];

    var curHigh = hi[0];
    var curLow  = lo[0];

    // Rising freeze check
    if(cAmaDiff > 0.0)
    {
        if(cAmaDiff < filterValue && curHigh <= maxHigh + 50.0 * PIP)
            filteredNow = s_kamaFiltered;   // freeze: hold previous filtered value
    }
    // Falling freeze check
    else if(cAmaDiff < 0.0)
    {
        if(aAmaDiff < filterValue && curLow >= minLow - 50.0 * PIP)
            filteredNow = s_kamaFiltered;   // freeze
    }
    // cAmaDiff == 0.0: raw is flat → no freeze needed, filtered = raw

    s_kamaFiltered = filteredNow;
    return filteredNow;
}


// ============================================================
//  kamaValSeries  (public)
//  SOLE call-site for filtered KAMA (val[]) series.
//  All code needing KAMA price history MUST use this function.
//    [0] = current bar, [k] = k bars ago.
// ============================================================
var* kamaValSeries()
{
    return series(ComputeKAMA_Filtered());
}


// ============================================================
//  kamaColorSeries  (public)
//  SOLE call-site for KAMA colour series.
//
//  Original colour logic (KAMA_with_filter.mq5):
//    valc[i] = (val[i] > val[i-1]) ? 2
//             :(val[i] < val[i-1]) ? 1
//             : valc[i-1]   ← flat → hold previous
//
//  Zorro convention (0/1 used by all strategy files):
//    0.0 → rising  (was 2)
//    1.0 → falling (was 1)
//    flat → s_kamaColor (holds last non-flat colour)
//
//    [0] = current bar colour, [1] = previous bar colour.
// ============================================================
var* kamaColorSeries()
{
    var* ks = kamaValSeries();

    var colorNow;
    if     (ks[0] > ks[1]) colorNow = 0.0;           // rising
    else if(ks[0] < ks[1]) colorNow = 1.0;           // falling
    else                   colorNow = s_kamaColor;   // flat: hold previous

    s_kamaColor = colorNow;
    return series(colorNow);
}


// ============================================================
//  GetKAMAColor  (public)
//  Returns integer colour codes via pointers.
//    0 = rising/bullish,  1 = falling/bearish
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
//  Returns |val[1] − val[InpKAMASlopeLookback]| in price units.
//  Uses filtered KAMA (val[]) to match original slope filter.
// ============================================================
var GetKAMASlope()
{
    var* ks = kamaValSeries();
    return fabs(ks[1] - ks[InpKAMASlopeLookback]);
}


// ============================================================
//  GetATR  (public)
//  current → ATR bar[0] (Wilder's, matches ATR.mq5)
//  avg     → mean of last InpATRPeriod ATR values
// ============================================================
int GetATR(var* current, var* avg)
{
    var* atrSeries = series(ATR(InpATRPeriod));
    *current = atrSeries[0];

    var sum = 0.0;
    for(int i = 0; i < InpATRPeriod; i++)
        sum += atrSeries[i];
    *avg = sum / InpATRPeriod;

    return 1;
}

#endif // INDICATORS_C
