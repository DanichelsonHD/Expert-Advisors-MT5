// =========================================================
// FILE: Strategies/BO.c
// ROLE: Breakout — decision layer only, NO execution
//
// Conditions:
//   • BB inside KC (squeeze)          → volatility compressed
//   • ADX rising bar over bar         → momentum building
//   • Close breaks recent HH or LL    → structural breakout
// =========================================================

#ifndef BO_C
#define BO_C

int BO_CheckEntry()
{
    if(!isSqueeze())
        return SIGNAL_NONE;

    if(!isADXRising())
        return SIGNAL_NONE;

    // Buy: close breaks above highest high of last BO_StructureLookback bars
    if(isStructureBreakUp())
        return SIGNAL_BUY;

    // Sell: close breaks below lowest low of last BO_StructureLookback bars
    if(isStructureBreakDown())
        return SIGNAL_SELL;

    return SIGNAL_NONE;
}

#endif // BO_C
