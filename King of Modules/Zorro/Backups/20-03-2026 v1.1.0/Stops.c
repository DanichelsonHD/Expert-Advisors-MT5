#ifndef STOPS_C
#define STOPS_C

#include "Indicators.c"

#define MIN_STOP_PIPS 10

var MinStopDist()
{
    var s;
    var p;
    s = Spread;
    p = PIP * MIN_STOP_PIPS;
    if(s > p) return s; else return p;
}

var CalculateATRStop(var atr)
{
    var stopDist;
    var minDist;
    stopDist = atr * InpStopMultiplier + InpStopExtraPoints * PIP;
    minDist  = MinStopDist();
    if(stopDist > minDist) return stopDist; else return minDist;
}

// ============================================================
//  CalculateTechnicalStop
//  Uses g_low / g_high — no series() calls.
//  NOTE: Zorro does not expose exact fill price pre-entry.
//  price() / Spread used as best approximation.
// ============================================================
var CalculateTechnicalStop(int signal)
{
    var buffer;
    var minDist;
    var lowest;
    var highest;
    var entryPrice;
    var dist;
    int i;

    buffer  = InpStopExtraPoints * PIP;
    minDist = MinStopDist();

    if(signal == SIGNAL_BUY)
    {
        if(!g_low) return minDist;

        lowest = g_low[1];
        for(i = 2; i <= InpTechnicalStopLookback; i++)
            if(g_low[i] < lowest) lowest = g_low[i];

        entryPrice = price() + Spread;
        dist       = entryPrice - lowest + buffer;
        if(dist > minDist) return dist; else return minDist;
    }
    else
    {
        if(!g_high) return minDist;

        highest = g_high[1];
        for(i = 2; i <= InpTechnicalStopLookback; i++)
            if(g_high[i] > highest) highest = g_high[i];

        entryPrice = price();
        dist       = highest - entryPrice + buffer;
        if(dist > minDist) return dist; else return minDist;
    }
}

var GetStopLoss(int signal, var atr)
{
    int mode;
    if(signal == SIGNAL_BUY) mode = InpLongStopMode; else mode = InpShortStopMode;
    if(mode == STOP_TECHNICAL)
        return CalculateTechnicalStop(signal);
    return CalculateATRStop(atr);
}

void ManageTrailingStop(var atr)
{
    var trailDist;
    var minDist;
    var bid;
    var ask;
    var newSL;

    if(InpLongStopMode  != TRAILING_STOP &&
       InpShortStopMode != TRAILING_STOP)
        return;

    trailDist = atr * InpStopMultiplier + InpStopExtraPoints * PIP;
    minDist   = MinStopDist();
    if(trailDist < minDist) trailDist = minDist;

    for(open_trades)
    {
        if(TradeIsLong && InpLongStopMode == TRAILING_STOP)
        {
            bid   = price();
            newSL = bid - trailDist;
            if(newSL > TradeStopLimit)
                TradeStopLimit = newSL;
        }
        else if(TradeIsShort && InpShortStopMode == TRAILING_STOP)
        {
            ask   = price() + Spread;
            newSL = ask + trailDist;
            if(TradeStopLimit == 0 || newSL < TradeStopLimit)
                TradeStopLimit = newSL;
        }
    }
}

#endif // STOPS_C
