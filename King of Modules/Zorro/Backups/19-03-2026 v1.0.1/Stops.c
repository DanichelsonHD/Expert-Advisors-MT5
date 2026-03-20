// ============================================================
//  Stops.c  –  Zorro translation of Stops.mqh
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
// ============================================================

#ifndef STOPS_C
#define STOPS_C

#include "Indicators.c"

#define MIN_STOP_PIPS  10

static var MinStopDist()
{
    return max(Spread, PIP * MIN_STOP_PIPS);
}


static var CalculateATRStop(var atr)
{
    var stopDist = atr * InpStopMultiplier + InpStopExtraPoints * PIP;
    return max(stopDist, MinStopDist());
}


// ============================================================
//  CalculateTechnicalStop  –  returns DISTANCE (price units)
//
//  NOTE:
//  Zorro does not expose exact fill price pre-entry.
//  price() / Spread is used as best approximation:
//    BUY  entry ≈ price() + Spread  (Ask estimate)
//    SELL entry ≈ price()           (Bid estimate)
//  This differs slightly from MQL5 OrderSend execution where
//  the exact Ask/Bid at order submission is available.
// ============================================================
static var CalculateTechnicalStop(int signal)
{
    var buffer  = InpStopExtraPoints * PIP;
    var minDist = MinStopDist();

    if(signal == SIGNAL_BUY)
    {
        var* lo    = seriesLow();
        var lowest = lo[1];
        for(int i = 2; i <= InpTechnicalStopLookback; i++)
            if(lo[i] < lowest) lowest = lo[i];

        var entryPrice = price() + Spread;   // Ask estimate
        var dist       = entryPrice - lowest + buffer;
        return max(dist, minDist);
    }
    else
    {
        var* hi     = seriesHigh();
        var highest = hi[1];
        for(int i = 2; i <= InpTechnicalStopLookback; i++)
            if(hi[i] > highest) highest = hi[i];

        var entryPrice = price();            // Bid estimate
        var dist       = highest - entryPrice + buffer;
        return max(dist, minDist);
    }
}


var GetStopLoss(int signal, var atr)
{
    int mode = (signal == SIGNAL_BUY) ? InpLongStopMode
                                                  : InpShortStopMode;
    if(mode == STOP_TECHNICAL)
        return CalculateTechnicalStop(signal);

    return CalculateATRStop(atr);
}


void ManageTrailingStop(var atr)
{
    if(InpLongStopMode  != TRAILING_STOP &&
       InpShortStopMode != TRAILING_STOP)
        return;

    var trailDist = atr * InpStopMultiplier + InpStopExtraPoints * PIP;
    var minDist   = MinStopDist();
    if(trailDist < minDist) trailDist = minDist;

    for(open_trades)
    {
        if(TradeIsLong && InpLongStopMode == TRAILING_STOP)
        {
            var bid   = price();
            var newSL = bid - trailDist;
            if(newSL > TradeStopLimit)
                TradeStopLimit = newSL;
        }
        else if(TradeIsShort && InpShortStopMode == TRAILING_STOP)
        {
            var ask   = price() + Spread;
            var newSL = ask + trailDist;
            if(TradeStopLimit == 0.0 || newSL < TradeStopLimit)
                TradeStopLimit = newSL;
        }
    }
}

#endif // STOPS_C
