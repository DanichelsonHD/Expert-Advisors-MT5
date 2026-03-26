// =========================================================
// FILE: Stops.c
// ROLE: Stop loss calculation + trailing stop management
// =========================================================

#ifndef STOPS_C
#define STOPS_C

// ---------------------------------------------------------
// CALCULATE STOP — LONG
// Returns absolute price level for stop loss
// ---------------------------------------------------------
var CalculateStopLong()
{
    var close = Close[0];

    switch(StopMode)
    {
        case STOP_TECHNICAL:
            // Lowest low of previous StopLookback bars minus buffer
            return LowestLow(StopLookback) - StopBufferPoints * PIP;

        case STOP_TRAILING:
            // Initial ATR-based placement; ManageStops() handles progression
            return close - StopATRMult * g_ATR14[0];

        case STOP_FIXED:
        default:
            return close - FixedStopPoints * PIP;
    }
}

// ---------------------------------------------------------
// CALCULATE STOP — SHORT
// Returns absolute price level for stop loss
// ---------------------------------------------------------
var CalculateStopShort()
{
    var close = Close[0];

    switch(StopMode)
    {
        case STOP_TECHNICAL:
            // Highest high of previous StopLookback bars plus buffer
            return HighestHigh(StopLookback) + StopBufferPoints * PIP;

        case STOP_TRAILING:
            return close + StopATRMult * g_ATR14[0];

        case STOP_FIXED:
        default:
            return close + FixedStopPoints * PIP;
    }
}

// ---------------------------------------------------------
// MANAGE STOPS — trailing adjustment on open trades
// Only active when StopMode == STOP_TRAILING
// NOTE: TradeStopLimit maps to ThisTrade->fStopLimit in
//       Zorro's TRADE struct — verify against your zorro.h
// ---------------------------------------------------------
void ManageStops()
{
    if(StopMode != STOP_TRAILING)
        return;

    var close = Close[0];
    var atr   = g_ATR14[0];

    for(open_trades)
    {
        if(!TradeIsOpen) continue;

        if(TradeIsLong)
        {
            var newStop = close - StopATRMult * atr;
            // Only move stop up, never down
            if(newStop > TradeStopLimit)
                TradeStopLimit = newStop;
        }
        else if(TradeIsShort)
        {
            var newStop = close + StopATRMult * atr;
            // Only move stop down, never up
            if(TradeStopLimit == 0.0 || newStop < TradeStopLimit)
                TradeStopLimit = newStop;
        }
    }
}

#endif // STOPS_C
