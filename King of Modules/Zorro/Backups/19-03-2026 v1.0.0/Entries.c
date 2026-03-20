// ============================================================
//  Entries.c  –  Zorro translation of Entries.mqh
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
// ============================================================
//
//  ARCHITECTURE NOTES (MQL5 → Zorro)
//  ------------------------------------------------------------------
//  IsWithinTradingHours()  → defined in EA_KingofModules.c; NOT
//                            redefined here to avoid duplicate symbol.
//
//  CountOpenPositions()    → NumOpenTrades (Zorro global).
//                            Zorro isolates trades per script; magic-
//                            number filtering is unnecessary.
//
//  g_trade.Buy / g_trade.Sell → enterLong() / enterShort()
//                            Lots and Stop set as globals before call.
//
//  Stop (Zorro)            → price-unit DISTANCE from entry (positive).
//                            GetStopLoss() (Stops.c) must return a
//                            distance, not an absolute price.
//                            See Stops.c translation notes.
//
//  SymbolInfoDouble(SYMBOL_VOLUME_MIN/MAX) → MinLots / MaxLots
//                            Zorro broker-plugin globals.
//
//  NormalizeDouble(lot, 2) → roundto(lot, LotStep)
//                            LotStep is a Zorro broker-plugin global.
//
//  Bar-change guard (s_lastBarTime / iTime) → REMOVED.
//                            run() is called exactly once per closed
//                            bar in Zorro; the guard is redundant.
//
//  ENUM_SWING_MODE check   → original uses truthiness (mode != 0).
//                            Preserved faithfully.
//    [NOTE] SWING_LONG (1) enables the strategy for BUY signals and
//           SWING_SHORT (2) for SELL signals, but the original code
//           does NOT enforce directional filtering at this level —
//           it relies on each Signal*() function to return the correct
//           direction. Preserved as-is; add directional gating here
//           only if explicitly requested.
// ============================================================

#ifndef ENTRIES_C
#define ENTRIES_C

#include "Indicators.c"
#include "Stops.c"
#include "Takes.c"

#include "Strategies/MeanReversion.c"
#include "Strategies/Pullback.c"
#include "Strategies/Breakout.c"
#include "Strategies/KamaTrend.c"

// Forward declarations (implemented in Stops.c)
var GetStopLoss(ENUM_SIGNAL signal, var atr);
var GetTakeProfit(ENUM_SIGNAL signal, var atr);


// ============================================================
//  CountOpenPositions
//  Original: iterated PositionsTotal() with magic-number filter.
//  Zorro: NumOpenTrades already reflects only this script's trades.
// ============================================================
int CountOpenPositions()
{
    return NumOpenTrades;
}


// ============================================================
//  CalculateLotSize
//  Computes lot for the next entry.
//  Step-lot scaling: lot grows by InpStepLot for every
//  InpStepCapital of balance above the base.
// ============================================================
var CalculateLotSize()
{
    if(!InpUseStepLotScaling)
        return g_currentScaledLot;

    var steps = floor(Balance / InpStepCapital);
    var lot   = InpLotSize + steps * InpStepLot;

    // Clamp to broker limits
    lot = max(lot, MinLots);
    lot = min(lot, MaxLots);

    // Normalise to broker lot step
    return roundto(lot, LotStep);
}


// ============================================================
//  ExecuteEntry
//  Converts a strategy signal into a Zorro trade.
//
//  Stop is set as a price-unit distance (Zorro convention).
//  GetStopLoss() in Stops.c must return distance, not abs price.
//
//  Take profit is applied via ManageTakes() each bar; TP at
//  entry time can optionally be set here through TakeProfit.
// ============================================================
void ExecuteEntry(ENUM_SIGNAL signal, var atr)
{
    if(signal == SIGNAL_NONE)
        return;

    if(CountOpenPositions() >= InpMaxSimultaneousTrades)
        return;

    var lot  = CalculateLotSize();
    var slDist = GetStopLoss(signal, atr);   // distance in price units

    Lots = lot;
    Stop = slDist;   // Zorro: distance from entry (positive value)

    // Optional: set TP at entry if UseTakeProfit is enabled
    // (ManageTakes() handles dynamic TP each bar regardless)
    if(InpUseTakeProfit)
        TakeProfit = GetTakeProfit(signal, atr);
    else
        TakeProfit = 0;

    if(signal == SIGNAL_BUY)
        enterLong();
    else
        enterShort();
}


// ============================================================
//  EntriesEngine
//  Evaluates each enabled strategy and attempts entry.
//  Bar-change guard removed – Zorro guarantees one call per bar.
//  Each Signal*() function reads closed-bar indicator values.
// ============================================================
void EntriesEngine()
{
    var atrVal = 0, atrAvg = 0;
    if(!GetATR(&atrVal, &atrAvg))
        return;

    ENUM_SIGNAL s;

    // ── Mean Reversion ───────────────────────────────────────
    s = SignalMeanReversion();
    if(s != SIGNAL_NONE && UseMRStrategy)
        ExecuteEntry(s, atrVal);

    // ── Trend Pullback  (Not Implemented – stub returns NONE) ─
    s = SignalPullback();
    if(s != SIGNAL_NONE && UseTPStrategy)
        ExecuteEntry(s, atrVal);

    // ── Trendline Breakout  (Not Implemented – stub returns NONE) ─
    s = SignalBreakout();
    if(s != SIGNAL_NONE && UseTBStrategy)
        ExecuteEntry(s, atrVal);

    // ── KAMA Trend ───────────────────────────────────────────
    s = SignalKamaTrend();
    if(s != SIGNAL_NONE && UseKTStrategy)
        ExecuteEntry(s, atrVal);

    // ── RSI Exhaustion  (not wired in original EntriesEngine)
    //    UseREStrategy is declared in Inputs but SignalRSIExhaustion
    //    was not called here in the original MQL5 code.
    //    Preserved as a placeholder for future wiring.
    // s = SignalRSIExhaustion();
    // if(s != SIGNAL_NONE && UseREStrategy)
    //     ExecuteEntry(s, atrVal);
}

#endif // ENTRIES_C
