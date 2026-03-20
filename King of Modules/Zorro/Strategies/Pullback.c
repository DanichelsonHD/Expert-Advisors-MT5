#ifndef PULLBACK_C
#define PULLBACK_C

#include "Indicators.c"

int SignalPullback()
{
    // #3: one execution per bar
    static int lastBar;
    if(Bar == lastBar) return SIGNAL_NONE;
    lastBar = Bar;

    return SIGNAL_NONE;
}

#endif // PULLBACK_C
