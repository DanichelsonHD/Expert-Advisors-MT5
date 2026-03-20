// ============================================================
//  Entries.c  –  Zorro translation of Entries.mqh
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
// ============================================================
//
//  PATCH NOTES (Final Hardening):
//  #2  – RSIExhaustion execution block commented out.
//        Original MQL5 EntriesEngine() did NOT wire this strategy.
//        Include retained for compilation; execution disabled to
//        preserve original behavior.
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
#include "Strategies/RSIExhaustion.c"

var GetStopLoss(ENUM_SIGNAL signal, var atr);
var GetTakeProfit(ENUM_SIGNAL signal, var atr);


int CountOpenPositions()
{
    return NumOpenTrades;
}


var CalculateLotSize()
{
    if(!InpUseStepLotScaling)
        return InpLotSize;

    var steps = floor(Balance / InpStepCapital);
    var lot   = InpLotSize + steps * InpStepLot;

    lot = max(lot, MinLots);
    lot = min(lot, MaxLots);
    return roundto(lot, LotStep);
}


int ExecuteEntry(ENUM_SIGNAL signal, var atr)
{
    if(signal == SIGNAL_NONE)
        return 0;

    if(CountOpenPositions() >= InpMaxSimultaneousTrades)
        return 0;

    var lot    = CalculateLotSize();
    var slDist = GetStopLoss(signal, atr);

    Lots = lot;
    Stop = slDist;

    if(InpUseTakeProfit)
        TakeProfit = GetTakeProfit(signal, atr);
    else
        TakeProfit = 0;

    if(signal == SIGNAL_BUY)
        enterLong();
    else
        enterShort();

    return 1;
}


void EntriesEngine(var atrVal)
{
    ENUM_SIGNAL s;

    // ── Mean Reversion ──────────────────────────────────────
    if(UseMRStrategy != SWING_OFF)
    {
        s = SignalMeanReversion();
        if(s == SIGNAL_BUY  && UseMRStrategy == SWING_LONG)
            if(ExecuteEntry(s, atrVal)) return;
        if(s == SIGNAL_SELL && UseMRStrategy == SWING_SHORT)
            if(ExecuteEntry(s, atrVal)) return;
    }

    // ── Trend Pullback ──────────────────────────────────────
    if(UseTPStrategy != SWING_OFF)
    {
        s = SignalPullback();
        if(s == SIGNAL_BUY  && UseTPStrategy == SWING_LONG)
            if(ExecuteEntry(s, atrVal)) return;
        if(s == SIGNAL_SELL && UseTPStrategy == SWING_SHORT)
            if(ExecuteEntry(s, atrVal)) return;
    }

    // ── Trendline Breakout ──────────────────────────────────
    if(UseTBStrategy != SWING_OFF)
    {
        s = SignalBreakout();
        if(s == SIGNAL_BUY  && UseTBStrategy == SWING_LONG)
            if(ExecuteEntry(s, atrVal)) return;
        if(s == SIGNAL_SELL && UseTBStrategy == SWING_SHORT)
            if(ExecuteEntry(s, atrVal)) return;
    }

    // ── KAMA Trend ──────────────────────────────────────────
    if(UseKTStrategy != SWING_OFF)
    {
        s = SignalKamaTrend();
        if(s == SIGNAL_BUY  && UseKTStrategy == SWING_LONG)
            if(ExecuteEntry(s, atrVal)) return;
        if(s == SIGNAL_SELL && UseKTStrategy == SWING_SHORT)
            if(ExecuteEntry(s, atrVal)) return;
    }

    // ── RSI Exhaustion ──────────────────────────────────────
    // #2: NOT wired in original MQL5 EntriesEngine().
    //     Disabled to preserve original behavior.
    //     To activate: uncomment and set UseREStrategy accordingly.
    //
    // if(UseREStrategy != SWING_OFF)
    // {
    //     s = SignalRSIExhaustion();
    //     if(s == SIGNAL_BUY  && UseREStrategy == SWING_LONG)
    //         if(ExecuteEntry(s, atrVal)) return;
    //     if(s == SIGNAL_SELL && UseREStrategy == SWING_SHORT)
    //         if(ExecuteEntry(s, atrVal)) return;
    // }
}

#endif // ENTRIES_C
