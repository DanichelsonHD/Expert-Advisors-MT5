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
    set(PARAMETERS+LOGFILE);
    set(TRADEMODE+PLOTNOW);

    g_EquityStart = Equity;    
    
    // LookBack must cover the longest indicator period
    // ATR_Period_2 = 50 + EMA_Slow = 50 + buffer → 100 safe
    LookBack = 100;
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
    // Snapshot equity at session start
    if(INITRUN)
        InitializeSystem();

    // ------- Core indicator parameters -------
    int ATR_Period_1 = optimize(14, 6, 30, 1);
    int ATR_Period_2 = optimize(50, 30, 70, 5);
    int EMA_Fast     = optimize(20, 10, 30, 1);
    int EMA_Slow     = optimize(50, 30, 70, 5);
    int RSI_Period   = optimize(14, 6, 30, 1);
    int ADX_Period   = optimize(14, 6, 30, 1);

    // ------- Bollinger Bands -------
    int BB_Period = optimize(20, 10, 30, 1);
    var BB_StdDev = optimize(2.0, 1, 3, 0.1);

    // ------- Keltner Channel -------
    int KC_Period = optimize(20, 10, 30, 1);
    var KC_Mult   = optimize(1.5, 0.5, 3, 0.5);

    // ------- SuperTrend -------
    int ST_Period = optimize(10, 6, 30, 1);
    var ST_Mult   = optimize(3.0, 1.5, 6, 0.5);

    // ------- RSI thresholds -------
    var RSI_Overbought_Default = optimize(70.0, 55, 85, 1);
    var RSI_Oversold_Default   = optimize(30.0, 15, 45, 1);

    // ------- ADX thresholds -------
    var ADX_Ranging_Max  = optimize(20.0, 10, 30, 1);
    var ADX_Trending_Min = optimize(25.0, 20, 40, 1);

    // ------- Strategy-specific: MR -------
    var MR_RSI_Overbought = optimize(65.0, 55, 85, 1);
    var MR_RSI_Oversold   = optimize(35.0, 15, 45, 1);

    // ------- Strategy-specific: PB -------
    var PB_RSI_Low         = optimize(40.0, 15, 45, 1);
    var PB_RSI_High        = optimize(60.0, 55, 85, 1);
    var PB_EMAProximityPct = optimize(0.3, 0.1, 1.5, 0.1);   // max % distance from EMA20

    if(EXITRUN) {
        ShutdownSystem();
        return;
    }

    UpdateAllSeries();      // raw price series  — ALWAYS FIRST
    UpdateIndicators();     // all derived indicators

    ManageStops();          // trailing stop progression
    ManageTakes();          // dynamic take profit / flip exit

    if(TimeFilterActive && !IsWithinTradingHours())
        return;

    ExecuteStrategies();    // signal aggregation + trade execution
}
