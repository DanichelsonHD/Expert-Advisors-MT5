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
//  NOTE:
//  Zorro does not expose exact fill price pre-entry.
//  price() / Spread is used as best approximation:
//    BUY  entry ≈ price() + Spread  (Ask estimate)
//    SELL entry ≈ price()           (Bid estimate)
//  This differs slightly from MQL5 OrderSend execution where
//  the exact Ask/Bid at order submission is available.
// ============================================================
var CalculateTechnicalStop(int signal)
{
    var  buffer;
    var  minDist;
    var* lo;
    var* hi;
    var  lowest;
    var  highest;
    var  entryPrice;
    var  dist;
    int  i;

    buffer  = InpStopExtraPoints * PIP;
    minDist = MinStopDist();

    if(signal == SIGNAL_BUY)
    {
        lo     = series(priceLow());
        lowest = lo[1];
        for(i = 2; i <= InpTechnicalStopLookback; i++)
            if(lo[i] < lowest) lowest = lo[i];

        entryPrice = price() + Spread;
        dist       = entryPrice - lowest + buffer;
        if(dist > minDist) return dist; else return minDist;
    }
    else
    {
        hi      = series(priceHigh());
        highest = hi[1];
        for(i = 2; i <= InpTechnicalStopLookback; i++)
            if(hi[i] > highest) highest = hi[i];

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
