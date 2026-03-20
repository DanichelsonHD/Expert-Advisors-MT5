// ============================================================
//  Stops.c  –  Zorro translation of Stops.mqh
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
// ============================================================
//
//  ARCHITECTURE NOTES (MQL5 → Zorro)
//  ------------------------------------------------------------------
//  All stop functions in MQL5 returned ABSOLUTE PRICE levels.
//  Zorro's Stop global expects a DISTANCE (positive price units).
//  All functions here return DISTANCES. Callers (Entries.c) assign
//  directly to Stop = GetStopLoss(...).
//
//  SYMBOL_POINT → defined locally as a constant for XAUUSD.
//    XAUUSD 5-digit broker: 1 point = 0.01 price unit.
//    Adjust POINT_VALUE if targeting a different instrument/broker.
//
//  SYMBOL_TRADE_STOPS_LEVEL / SYMBOL_TRADE_FREEZE_LEVEL →
//    No direct Zorro equivalent. A conservative minimum distance
//    guard of (Spread * 1.5) is substituted to prevent broker
//    rejection. Adjust MIN_STOP_DIST_FACTOR if needed.
//
//  iLow / iHigh (technical stop) → seriesLow() / seriesHigh()
//
//  g_position.StopLoss() → TradeStopLimit  (price level in Zorro)
//  g_trade.PositionModify() → modify TradeStopLimit directly;
//    Zorro propagates the change to the broker on the next sync.
//
//  ManageTrailingStop: original selected ONE position per symbol.
//    Zorro: iterated over all open trades with for(open_trades)
//    so every trade is managed independently.
//
//  CPositionInfo stop_pos → removed (no handle objects in Zorro).
// ============================================================

#ifndef STOPS_C
#define STOPS_C

#include "Indicators.c"


// ============================================================
//  INSTRUMENT CONSTANTS
//  ── Adjust for target instrument / broker precision ──
// ============================================================

// Minimum price increment (1 point).
// XAUUSD on a 5-digit broker: 0.01 per point.
#define POINT_VALUE   0.01

// Minimum stop distance guard factor relative to current Spread.
// Substitutes for SYMBOL_TRADE_STOPS_LEVEL + SYMBOL_TRADE_FREEZE_LEVEL.
#define MIN_STOP_DIST_FACTOR  1.5


// ============================================================
//  Internal helper: minimum allowable stop distance
// ============================================================
static var MinStopDist()
{
    return Spread * MIN_STOP_DIST_FACTOR;
}


// ============================================================
//  CalculateATRStop
//  Returns a stop DISTANCE (price units, always positive).
//  Mode: ATR-based with extra-points buffer.
// ============================================================
static var CalculateATRStop(var atr)
{
    var extraDist = InpStopExtraPoints * POINT_VALUE;
    var stopDist  = atr * InpStopMultiplier + extraDist;
    var minDist   = MinStopDist();

    return max(stopDist, minDist);
}


// ============================================================
//  CalculateTechnicalStop
//  Returns a stop DISTANCE derived from swing High/Low.
//
//  BUY  → distance = entry_price − lowest_low(lookback) + buffer
//  SELL → distance = highest_high(lookback) − entry_price + buffer
//
//  seriesLow()[i]  maps to iLow (_Symbol, _Period, i)
//  seriesHigh()[i] maps to iHigh(_Symbol, _Period, i)
//
//  NOTE: In Zorro, seriesLow/seriesHigh[0] is the current bar
//        (shift 0). The original used shift 1..N; we replicate by
//        reading [1]..[InpTechnicalStopLookback].
// ============================================================
static var CalculateTechnicalStop(ENUM_SIGNAL signal)
{
    var buffer  = InpStopExtraPoints * POINT_VALUE;
    var minDist = MinStopDist();

    if(signal == SIGNAL_BUY)
    {
        var* lo   = seriesLow();
        var lowest = lo[1];
        for(int i = 2; i <= InpTechnicalStopLookback; i++)
            if(lo[i] < lowest) lowest = lo[i];

        var entryPrice = priceClose();   // approximation; real fill uses Ask
        var dist       = entryPrice - lowest + buffer;
        return max(dist, minDist);
    }
    else // SIGNAL_SELL
    {
        var* hi      = seriesHigh();
        var highest  = hi[1];
        for(int i = 2; i <= InpTechnicalStopLookback; i++)
            if(hi[i] > highest) highest = hi[i];

        var entryPrice = priceClose();   // approximation; real fill uses Bid
        var dist       = highest - entryPrice + buffer;
        return max(dist, minDist);
    }
}


// ============================================================
//  GetStopLoss  (public – called from Entries.c)
//  Signature adapted: ENUM_SIGNAL replaces ENUM_ORDER_TYPE.
//  Returns a stop DISTANCE (positive, price units).
//
//  TRAILING_STOP mode at entry → falls through to ATR stop;
//  the trailing logic takes over bar-by-bar in ManageTrailingStop.
// ============================================================
var GetStopLoss(ENUM_SIGNAL signal, var atr)
{
    // Use the correct mode depending on direction
    ENUM_STOP_MODE mode = (signal == SIGNAL_BUY) ? InpLongStopMode
                                                  : InpShortStopMode;

    if(mode == STOP_TECHNICAL)
        return CalculateTechnicalStop(signal);

    // STOP_FIXED and TRAILING_STOP both use ATR distance at entry
    return CalculateATRStop(atr);
}


// ============================================================
//  ManageTrailingStop  (public – called from EA_KingofModules.c)
//  Runs every bar for all open trades (no time filter).
//
//  Trail logic (matches original):
//    LONG : newSL = price() − trailDist
//           advance only if newSL > TradeStopLimit
//    SHORT: newSL = price() + trailDist
//           advance only if TradeStopLimit==0 OR newSL < TradeStopLimit
//
//  TradeStopLimit in Zorro is the stop as an ABSOLUTE PRICE level.
//  price() returns the current bar's close (proxy for Bid).
// ============================================================
void ManageTrailingStop(var atr)
{
    // Only runs when trailing mode is active for at least one direction
    if(InpLongStopMode  != TRAILING_STOP &&
       InpShortStopMode != TRAILING_STOP)
        return;

    var extraDist  = InpStopExtraPoints * POINT_VALUE;
    var trailDist  = atr * InpStopMultiplier + extraDist;
    var minDist    = MinStopDist();
    if(trailDist < minDist) trailDist = minDist;

    var curPrice = price();   // current bar close; proxy for Bid/Ask

    for(open_trades)
    {
        if(TradeIsLong && InpLongStopMode == TRAILING_STOP)
        {
            var newSL = curPrice - trailDist;
            if(newSL > TradeStopLimit)
                TradeStopLimit = newSL;
        }
        else if(TradeIsShort && InpShortStopMode == TRAILING_STOP)
        {
            var newSL = curPrice + trailDist;
            if(TradeStopLimit == 0.0 || newSL < TradeStopLimit)
                TradeStopLimit = newSL;
        }
    }
}

#endif // STOPS_C
