#ifndef BREAKOUT_C
#define BREAKOUT_C

#include "Indicators.c"

int SignalBreakout()
{
    // #3: one execution per bar
    static int lastBar;
    if(Bar == lastBar) return SIGNAL_NONE;
    lastBar = Bar;

    return SIGNAL_NONE;
}

#endif // BREAKOUT_C
