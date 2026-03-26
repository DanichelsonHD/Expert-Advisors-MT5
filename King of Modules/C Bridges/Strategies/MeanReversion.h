#ifndef MEANREVERSION_H
#define MEANREVERSION_H

#include "../Core/Engine.h"


struct MeanReversionParams
{
    double adx_threshold;    // default 20.0
    double rsi_oversold;     // default 35.0
    double rsi_overbought;   // default 65.0
    double sl_atr_mult;      // default 1.5
    double tp_atr_mult;      // default 2.5
};

// -----------------------------------------------------------------------
// Evaluate mean reversion conditions.
// Returns a TradeSignal (direction=0 if no signal).
//
// Re-entry rule:
//   Long  → price WAS outside lower BB/KC and has now re-entered
//            (close > bb_lower AND close > kc_lower)
//   Short → price WAS outside upper BB/KC and has now re-entered
//            (close < bb_upper AND close < kc_upper)
//   We detect the "was outside" condition via prev_ind being passed in.
// -----------------------------------------------------------------------
inline TradeSignal Evaluate(
    const IndicatorData&        ind,
    const IndicatorData&        prev_ind,
    const MeanReversionParams&  p)
{
    TradeSignal sig = {0, 0.0, 0.0, 0.0};

    // Regime filter
    //if (ind.adx14 >= p.adx_threshold)
    //    return sig;

    // Long: prev bar outside lower bands, current bar re-entered
    bool prev_below_bands = (prev_ind.close < prev_ind.bb_lower ||
                                prev_ind.close < prev_ind.kc_lower);
    bool reentry_long     = (ind.close > ind.bb_lower && ind.close > ind.kc_lower);
    bool rsi_long         = (ind.rsi14 < p.rsi_oversold);

    if (prev_below_bands && (reentry_long || rsi_long))
    {
        sig.direction = 1;
        sig.entry     = ind.close;
        sig.sl        = ind.close - p.sl_atr_mult * ind.atr14;
        sig.tp        = ind.close + p.tp_atr_mult * ind.atr14;
        return sig;
    }

    // Short: prev bar outside upper bands, current bar re-entered
    bool prev_above_bands = (prev_ind.close > prev_ind.bb_upper ||
                                prev_ind.close > prev_ind.kc_upper);
    bool reentry_short    = (ind.close < ind.bb_upper && ind.close < ind.kc_upper);
    bool rsi_short        = (ind.rsi14 > p.rsi_overbought);

    if (prev_above_bands && (reentry_short || rsi_short))
    {
        sig.direction = -1;
        sig.entry     = ind.close;
        sig.sl        = ind.close + p.sl_atr_mult * ind.atr14;
        sig.tp        = ind.close - p.tp_atr_mult * ind.atr14;
        return sig;
    }

    return sig;
}

#endif 