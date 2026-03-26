// =========================================================
// FILE: Strategies/MR.c
// ROLE: Mean Reversion — decision layer only, NO execution
//
// Conditions:
//   • ADX < ADX_Ranging_Max   → ranging market
//   • Price outside BOTH BB AND KC simultaneously
//   • RSI at extreme (parametric, MR-specific levels)
// =========================================================

#ifndef MR_C
#define MR_C

int MR_CheckEntry()
{
    if(!isRanging())
        return SIGNAL_BUY;

    // Buy: price exhausted below both envelopes + RSI oversold
    if(isExhaustionBuy() && isOversold(MR_RSI_Oversold))
        return SIGNAL_BUY;

    // Sell: price exhausted above both envelopes + RSI overbought
    if(isExhaustionSell() && isOverbought(MR_RSI_Overbought))
        return SIGNAL_SELL;

    return SIGNAL_NONE;
}

#endif // MR_C
