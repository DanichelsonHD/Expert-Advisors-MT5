// =========================================================
// FILE: Strategies/PB.c
// ROLE: Pullback — decision layer only, NO execution
//
// Conditions:
//   • ADX > ADX_Trending_Min   → trending market
//   • Price near EMA20         → pullback zone
//   • RSI between 40–60        → momentum neutral
//   • Direction confirmed by EMA50 + SuperTrend
// =========================================================

#ifndef PB_C
#define PB_C

int PB_CheckEntry()
{
    if(!isTrending())
        return SIGNAL_NONE;

    if(!isPriceNearEMA20())
        return SIGNAL_NONE;

    if(!isRSINeutral())
        return SIGNAL_NONE;

    // Buy: trend up, pullback to EMA20 in bullish structure
    if(isAboveEMA50() && isSTBull())
        return SIGNAL_BUY;

    // Sell: trend down, pullback to EMA20 in bearish structure
    if(isBelowEMA50() && isSTBear())
        return SIGNAL_SELL;

    return SIGNAL_NONE;
}

#endif // PB_C
