// ============================================================
//  EA_KingofModules.c  –  Zorro translation of EA_KingofModules.mq5
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
// ============================================================
//
//  ARCHITECTURE NOTES (MQL5 → Zorro)
//  ------------------------------------------------------------------
//  OnInit()   → is(INITRUN)  block inside run()
//  OnDeinit() → is(EXITRUN)  block inside run()
//  OnTick()   → body of run() (called once per completed bar)
//
//  CTrade / CPositionInfo removed entirely.
//  Zorro manages order execution natively via enterLong/enterShort.
//
//  Magic-number filtering (SelectEAPosition) is unnecessary in Zorro:
//  each script owns its own trade pool.  The helper is preserved as a
//  thin wrapper around NumOpenTrades for structural parity.
//
//  InpLongMagicNumber / InpShortMagicNumber are retained in Inputs.c
//  as documentation but are not used at runtime.
// ============================================================

#include "Inputs.c"
#include "Indicators.c"
#include "Strategies/MeanReversion.c"
#include "Entries.c"
#include "Takes.c"
#include "Stops.c"

// ============================================================
//  Forward declarations  (implemented in included files above)
// ============================================================
int  IndicatorsInit();
void IndicatorsRelease();
int  GetATR(var* atr, var* avg);          // returns 1 on success
void ManageTrailingStop(var atr);
void ManageTakes();
void EntriesEngine();


// ============================================================
//  SelectEAPosition
//  Original: syncs CPositionInfo and validates EA magic number.
//  Zorro:    all open trades belong to this script; no filtering
//            needed.  Returns 1 when at least one trade is open.
// ============================================================
int SelectEAPosition()
{
    return (NumOpenTrades > 0);
}


// ============================================================
//  IsWithinTradingHours
//  Original: checks MQL5 server time against InpStartHour/InpEndHour.
//  Zorro:    hour() returns the bar's hour in broker/server time.
// ============================================================
int IsWithinTradingHours()
{
    int h = hour();
    return (h >= InpStartHour && h < InpEndHour);
}


// ============================================================
//  run() – main Zorro entry point
//  Called once per completed bar (M15 / H1 depending on BarPeriod).
// ============================================================
void run()
{
    // ── Static init guard ────────────────────────────────────────────
    // Prevents EXITRUN from running management logic
    static int g_initOK = 0;

    // ── INITRUN ──────────────────────────────────────────────────────
    if(is(INITRUN))
    {
        if(!IndicatorsInit())
        {
            printf("Indicator initialization failed");
            g_initOK = 0;
            return;
        }

        g_initialBalance   = Balance;       // Zorro global: current account balance
        g_currentScaledLot = InpLotSize;
        Lots               = InpLotSize;    // Zorro global: default lot size for entries

        g_initOK = 1;
        printf("Init OK");
    }

    // ── EXITRUN ──────────────────────────────────────────────────────
    if(is(EXITRUN))
    {
        IndicatorsRelease();
        printf("Deinit OK");
        return;
    }

    // Guard: skip if init failed
    if(!g_initOK) return;

    // Skip management and entries during the lookback warm-up period
    if(is(LOOKBACK)) return;

    // ── Position management  (no time filter – runs every bar) ───────
    {
        var atr = 0, avg = 0;
        if(GetATR(&atr, &avg))
            ManageTrailingStop(atr);
        ManageTakes();
    }

    // ── Entry engine  (time-filtered) ────────────────────────────────
    if(InpUseTimeFilter && !IsWithinTradingHours())
        return;

    EntriesEngine();
}
