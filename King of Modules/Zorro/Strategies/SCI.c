// =========================================================
// FILE: Strategies/SCI.c
// ROLE: SuperTrend + CI — decision layer only, NO execution
//
// Conditions:
//   • ADX > ADX_Trending_Min   → confirmed trending context
//   • SuperTrend direction flip → momentum shift signal
// =========================================================

#ifndef SCI_C
#define SCI_C

int SCI_CheckEntry()
{
    if(!isTrending())
        return SIGNAL_NONE;

    // Buy: SuperTrend flipped from bearish to bullish
    if(isSTFlipBull())
        return SIGNAL_BUY;

    // Sell: SuperTrend flipped from bullish to bearish
    if(isSTFlipBear())
        return SIGNAL_SELL;

    return SIGNAL_NONE;
}

#endif // SCI_C
