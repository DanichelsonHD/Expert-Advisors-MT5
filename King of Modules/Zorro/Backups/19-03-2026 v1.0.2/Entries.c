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
    int count = 0;

    for(open_trades)
        count++;

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

void EntriesEngine(var atrVal)
{
    int s;

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
    // NOT wired in original MQL5 EntriesEngine().
    // Disabled to preserve original behavior.
    // To activate: uncomment and set UseREStrategy accordingly.
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
