// =========================================================
// FILE: Main.c
// ROLE: Orchestrator — system init, execution flow control
//       NO indicator logic, NO strategy logic, NO execution
//
// Include order respects dependency chain:
//   Configs → Indicators → Stops → Takes → Strategies → Entries
// =========================================================

#include <zorro.h>

#include "Configs.c"
#include "Indicators.c"
#include "Stops.c"
#include "Takes.c"
#include "Strategies/MR.c"
#include "Strategies/PB.c"
#include "Strategies/BO.c"
#include "Strategies/SCI.c"
#include "Entries.c"

// ---------------------------------------------------------
// TIME FILTER
// ---------------------------------------------------------
int IsWithinTradingHours()
{
    int h = hour();
    return (h >= TradingHourStart && h < TradingHourEnd);
}

// ---------------------------------------------------------
// SYSTEM INIT
// ---------------------------------------------------------
void InitializeSystem()
{
    // Asset and timeframe
    // Adjust BarPeriod: 15 = M15, 60 = H1
    asset("EURUSD");
    BarPeriod = 60;

    // LookBack must cover the longest indicator period
    // ATR_Period_2 = 50 + EMA_Slow = 50 + buffer → 100 safe
    LookBack = 100;

    // Snapshot equity at session start
    g_EquityStart = Equity;
}

// ---------------------------------------------------------
// SYSTEM SHUTDOWN
// ---------------------------------------------------------
void ShutdownSystem()
{
    // Reserved — add cleanup or reporting here if needed
}

// ---------------------------------------------------------
// MAIN ENTRY POINT
// Zorro calls run() on every bar
// ---------------------------------------------------------
void run()
{
    if(INITRUN)
        InitializeSystem();

    if(EXITRUN) {
        ShutdownSystem();
        return;
    }

    if(LOOKBACK)
        return;

    UpdateAllSeries();      // raw price series  — ALWAYS FIRST
    UpdateIndicators();     // all derived indicators

    ManageStops();          // trailing stop progression
    ManageTakes();          // dynamic take profit / flip exit

    if(TimeFilterActive && !IsWithinTradingHours())
        return;

    ExecuteStrategies();    // signal aggregation + trade execution
}
