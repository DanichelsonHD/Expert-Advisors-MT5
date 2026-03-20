// ============================================================
//  Takes.c  –  Zorro translation of Takes.mqh
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
// ============================================================
//
//  ARCHITECTURE NOTES (MQL5 → Zorro)
//  ------------------------------------------------------------------
//  All TP functions in MQL5 returned ABSOLUTE PRICE levels.
//  Zorro's TakeProfit global expects a DISTANCE (price units).
//  GetTakeProfit() returns a DISTANCE. Callers (Entries.c) assign
//  directly to TakeProfit = GetTakeProfit(...).
//
//  ENUM_KAMA_REGIME → direct C enum translation (no changes).
//
//  ResolveKAMARegime → maps color-buffer int to regime.
//    MQL5 color code 1 → BEARISH  (KAMA falling, red)
//    MQL5 color code 2 → BULLISH  (KAMA rising, blue)
//    NOTE: color codes depend on the original "KAMA with filter"
//    indicator. In our Indicators.c re-implementation:
//      GetKAMAColor returns 0 = rising (was color 2 / BULLISH)
//                           1 = falling (was color 1 / BEARISH)
//    The mapping below is therefore ADJUSTED to the Indicators.c
//    convention:
//      0 → KAMA_REGIME_BULLISH
//      1 → KAMA_REGIME_BEARISH
//
//  take_pos.Select / g_position.PositionType → TradeIsLong /
//    TradeIsShort inside for(open_trades) loop.
//
//  g_trade.PositionClose(_Symbol) → exitTrade(ThisTrade)
//    closes the specific trade currently iterated.
//
//  ManageTakes: original checked magic number then called TakeKAMA.
//    In Zorro the script owns all trades; no magic filter needed.
//    Runs for every open trade; direction tested inside TakeKAMA.
//
//  CPositionInfo take_pos → removed.
// ============================================================

#ifndef TAKES_C
#define TAKES_C

#include "Indicators.c"


// ============================================================
//  ENUM_KAMA_REGIME
// ============================================================
typedef enum {
    KAMA_REGIME_NONE    = 0,
    KAMA_REGIME_BEARISH = 1,
    KAMA_REGIME_BULLISH = 2
} ENUM_KAMA_REGIME;


// ============================================================
//  ResolveKAMARegime
//  Maps the integer color code from GetKAMAColor() to a regime.
//
//  Indicators.c convention (re-implemented KAMA):
//    0 → KAMA rising  → BULLISH
//    1 → KAMA falling → BEARISH
//
//  Original MQL5 "KAMA with filter" used:
//    1 → BEARISH (red),  2 → BULLISH (blue)
//  Mapping is adjusted accordingly.
// ============================================================
ENUM_KAMA_REGIME ResolveKAMARegime(int colorCode)
{
    if(colorCode == 0) return KAMA_REGIME_BULLISH;
    if(colorCode == 1) return KAMA_REGIME_BEARISH;
    return KAMA_REGIME_NONE;
}


// ============================================================
//  CalculateTakeProfit  (internal)
//  Returns a TP DISTANCE (positive, price units).
//
//  MQL5 original returned absolute price; Zorro needs distance.
//  Distance = ATR * InpTPMultiplier + extra points buffer.
// ============================================================
static var CalculateTakeProfit_ATR()
{
    var atrVal = 0, atrAvg = 0;
    if(!GetATR(&atrVal, &atrAvg))
        return 0.0;

    var extraDist = InpTakeExtraPoints * POINT_VALUE;
    var tpDist    = atrVal * InpTPMultiplier + extraDist;

    return tpDist;
}


// ============================================================
//  GetTakeProfit  (public – called from Entries.c)
//  Returns a TP DISTANCE (positive, price units).
//
//  TAKE_FIXED  → ATR-based distance (same as TAKE_KAMA at entry;
//                KAMA exit is managed bar-by-bar in ManageTakes)
//  TAKE_POINTS → fixed distance in points (InpTakePoints)
//  TAKE_KAMA   → ATR-based initial distance; KAMA flip closes it
// ============================================================
var GetTakeProfit(ENUM_SIGNAL signal, var atr)
{
    if(!InpUseTakeProfit)
        return 0.0;

    ENUM_TAKE_MODE mode = (signal == SIGNAL_BUY) ? InpLongTakeMode
                                                  : InpShortTakeMode;

    if(mode == TAKE_POINTS)
        return InpTakePoints * POINT_VALUE;

    // TAKE_FIXED and TAKE_KAMA: ATR-based distance at entry
    var extraDist = InpTakeExtraPoints * POINT_VALUE;
    return atr * InpTPMultiplier + extraDist;
}


// ============================================================
//  TakeKAMA  (internal per-trade)
//  Called inside for(open_trades) – ThisTrade is current trade.
//
//  Closes the trade when KAMA regime flips against the position:
//    LONG  exit: previous bar BULLISH → current bar BEARISH
//    SHORT exit: previous bar BEARISH → current bar BULLISH
// ============================================================
static void TakeKAMA()
{
    int prev = 0, cur = 0;
    if(!GetKAMAColor(&prev, &cur))
        return;

    ENUM_KAMA_REGIME prevRegime = ResolveKAMARegime(prev);
    ENUM_KAMA_REGIME curRegime  = ResolveKAMARegime(cur);

    if(TradeIsLong)
    {
        if(prevRegime == KAMA_REGIME_BULLISH && curRegime == KAMA_REGIME_BEARISH)
        {
            exitTrade(ThisTrade);
            printf("TakeKAMA: LONG closed – KAMA flipped Bullish→Bearish");
        }
    }
    else if(TradeIsShort)
    {
        if(prevRegime == KAMA_REGIME_BEARISH && curRegime == KAMA_REGIME_BULLISH)
        {
            exitTrade(ThisTrade);
            printf("TakeKAMA: SHORT closed – KAMA flipped Bearish→Bullish");
        }
    }
}


// ============================================================
//  ManageTakes  (public – called from EA_KingofModules.c)
//  Runs every bar for all open trades (no time filter).
//  Each trade is evaluated and closed individually if the
//  KAMA exit condition is met.
//
//  Only TAKE_KAMA mode triggers active management here.
//  TAKE_FIXED and TAKE_POINTS rely on the TakeProfit price level
//  set at entry time (handled by Zorro's broker sync).
// ============================================================
void ManageTakes()
{
    if(!InpUseTakeProfit)
        return;

    // Only KAMA mode requires bar-by-bar management
    if(InpLongTakeMode  != TAKE_KAMA &&
       InpShortTakeMode != TAKE_KAMA)
        return;

    for(open_trades)
    {
        // Apply KAMA take only to trades whose direction matches
        // the configured mode
        if(TradeIsLong  && InpLongTakeMode  == TAKE_KAMA) TakeKAMA();
        if(TradeIsShort && InpShortTakeMode == TAKE_KAMA) TakeKAMA();
    }
}

#endif // TAKES_C
