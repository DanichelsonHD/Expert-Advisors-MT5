// ============================================================
//  Strategies/RSIExhaustion.c
//  Zorro translation of Strategies/RSIExhaustion.mqh
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
// ============================================================
//
//  ARCHITECTURE NOTES (MQL5 → Zorro)
//  ------------------------------------------------------------------
//  Bar-change guard (lastBar / iTime) → REMOVED (Zorro per-bar).
//
//  UpdateMRIndicators() shared with MeanReversion.mqh in MQL5.
//  Here the same indicator values are obtained directly through
//  the canonical Indicators.c helpers.
//
//  PassREATRCompressionFilter:
//    Allows entry when ATR(14) * multiplier < ATR(50)
//    (price in a compressed, range-bound regime).
//    Note: UseATRMRTrendFilter guard is ABSENT in the original —
//    this filter always runs when the function is called.
//    Preserved as-is.
//
//  DetectRSIExhaustion:
//    MOMENTUM CONTINUATION strategy (opposite of MeanReversion):
//      Oversold/below lower Keltner + KAMA bearish → SELL (continue)
//      Overbought/above upper Keltner + KAMA bullish → BUY (continue)
//    KAMA color (Indicators.c convention):
//      1 = falling/bearish  → SELL condition  (was ==1 in MQL5 ✓)
//      0 = rising/bullish   → BUY  condition  (was ==2 in MQL5)
//
//  [WIRING NOTE] SignalRSIExhaustion is NOT called in the original
//    EntriesEngine(). It is implemented here fully and wired to
//    UseREStrategy in Entries.c via the placeholder comment.
//    Uncomment that block in Entries.c to activate.
// ============================================================

#ifndef RSI_EXHAUSTION_C
#define RSI_EXHAUSTION_C

#include "../Indicators.c"


// ============================================================
//  PassREATRCompressionFilter
//  Returns 1 when ATR(14)*multiplier < ATR(50) (compressed regime).
//  ATR(50) series is at a dedicated call-site here.
// ============================================================
static int PassREATRCompressionFilter()
{
    var atrFast = series(ATR(InpATRPeriod))[0];
    var atrSlow = series(ATR(50))[0];

    return (atrFast * InpATRRETrendMultiplier < atrSlow);
}


// ============================================================
//  DetectRSIExhaustion
//  Pure momentum-continuation logic:
//    SELL: extreme RSI/price on the low side + KAMA still falling
//    BUY:  extreme RSI/price on the high side + KAMA still rising
//
//  OR logic between RSI and Keltner conditions is preserved
//  faithfully from the original.
// ============================================================
static ENUM_SIGNAL DetectRSIExhaustion(var curRSI,
                                        var upperK, var lowerK,
                                        int kamaColor, var close1)
{
    // SELL: oversold OR below lower band, KAMA bearish (falling)
    if((curRSI < InpRSIOversold || close1 < lowerK) && kamaColor == 1)
        return SIGNAL_SELL;

    // BUY:  overbought OR above upper band, KAMA bullish (rising)
    if((curRSI > InpRSIOverbought || close1 > upperK) && kamaColor == 0)
        return SIGNAL_BUY;

    return SIGNAL_NONE;
}


// ============================================================
//  SignalRSIExhaustion  (public)
// ============================================================
ENUM_SIGNAL SignalRSIExhaustion()
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

    var close1 = seriesClose()[1];   // bar[-1] close

    // ── Filter ───────────────────────────────────────────────
    if(!PassREATRCompressionFilter())
        return SIGNAL_NONE;

    // ── Signal ───────────────────────────────────────────────
    return DetectRSIExhaustion(curRSI, upperK, lowerK,
                                kamaColorCur, close1);
}

#endif // RSI_EXHAUSTION_C
