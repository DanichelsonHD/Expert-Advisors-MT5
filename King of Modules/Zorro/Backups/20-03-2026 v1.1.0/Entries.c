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

#define MIN_LOT 0.01
#define MAX_LOT 100

var GetStopLoss(int signal, var atr);
var GetTakeProfit(int signal, var atr);


int CountOpenPositions()
{
    int count;
    count = 0;
    for(open_trades) count++;
    return count;
}


var CalculateLotSize()
{
    var steps;
    var lot;

    if(!InpUseStepLotScaling)
        return InpLotSize;

    steps = floor(Balance / InpStepCapital);
    lot   = InpLotSize + steps * InpStepLot;

    if(lot < MIN_LOT) lot = MIN_LOT;
    if(lot > MAX_LOT) lot = MAX_LOT;
    return roundto(lot, InpStepLot);
}


int ExecuteEntry(int signal, var atr)
{
    var lot;
    var slDist;

    if(signal == SIGNAL_NONE)
        return 0;

    if(CountOpenPositions() >= InpMaxSimultaneousTrades)
        return 0;

    lot    = CalculateLotSize();
    slDist = GetStopLoss(signal, atr);

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


// ============================================================
//  EntriesEngine
//  ALL Signal* functions called EVERY BAR unconditionally.
//  TP/TB/KT commented out for isolation — uncomment to re-enable.
// ============================================================
void EntriesEngine(var atrVal)
{
    int sMR;

    // Always call all Signal* every bar (series determinism)
    sMR = SignalMeanReversion();
    SignalPullback();
    SignalBreakout();
    SignalKamaTrend();

    // ── Mean Reversion (active) ─────────────────────────────
    if(UseMRStrategy == SWING_LONG  && sMR == SIGNAL_BUY)
        if(ExecuteEntry(sMR, atrVal)) return;
    if(UseMRStrategy == SWING_SHORT && sMR == SIGNAL_SELL)
        if(ExecuteEntry(sMR, atrVal)) return;

    // ── Trend Pullback (isolated — re-enable when stable) ───
    // if(UseTPStrategy == SWING_LONG  && sTP == SIGNAL_BUY)
    //     if(ExecuteEntry(sTP, atrVal)) return;
    // if(UseTPStrategy == SWING_SHORT && sTP == SIGNAL_SELL)
    //     if(ExecuteEntry(sTP, atrVal)) return;

    // ── Trendline Breakout (isolated) ───────────────────────
    // if(UseTBStrategy == SWING_LONG  && sTB == SIGNAL_BUY)
    //     if(ExecuteEntry(sTB, atrVal)) return;
    // if(UseTBStrategy == SWING_SHORT && sTB == SIGNAL_SELL)
    //     if(ExecuteEntry(sTB, atrVal)) return;

    // ── KAMA Trend (isolated) ────────────────────────────────
    // if(UseKTStrategy == SWING_LONG  && sKT == SIGNAL_BUY)
    //     if(ExecuteEntry(sKT, atrVal)) return;
    // if(UseKTStrategy == SWING_SHORT && sKT == SIGNAL_SELL)
    //     if(ExecuteEntry(sKT, atrVal)) return;

    // ── RSI Exhaustion (not wired in original MQL5) ──────────
    // int sRE = SignalRSIExhaustion();
    // if(UseREStrategy == SWING_LONG  && sRE == SIGNAL_BUY)
    //     if(ExecuteEntry(sRE, atrVal)) return;
    // if(UseREStrategy == SWING_SHORT && sRE == SIGNAL_SELL)
    //     if(ExecuteEntry(sRE, atrVal)) return;
}

#endif // ENTRIES_C
