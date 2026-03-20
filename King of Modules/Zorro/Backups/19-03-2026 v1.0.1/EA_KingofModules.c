// ============================================================
//  EA_KingofModules.c  –  Zorro translation of EA_KingofModules.mq5
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
// ============================================================
//
//  PATCH NOTES (Final Hardening):
//  #3  – ManageTrailingStop, ManageTakes, and EntriesEngine are
//        all gated under atrOK. No module runs without a valid
//        ATR value.
//  #4  – SelectEAPosition() removed. Unused in Zorro context;
//        trade isolation is enforced by the runtime.
// ============================================================

#include "Inputs.c"
#include "Indicators.c"
#include "Entries.c"
#include "Takes.c"
#include "Stops.c"

int  IndicatorsInit();
void IndicatorsRelease();
int  GetATR(var* atr, var* avg);
void ManageTrailingStop(var atr);
void ManageTakes(var atr);
void EntriesEngine(var atrVal);


int IsWithinTradingHours()
{
    int h = hour();
    return (h >= InpStartHour && h < InpEndHour);
}


void run()
{
    static int g_initOK = 0;

    if(is(INITRUN))
    {
        if(!IndicatorsInit())
        {
            printf("Indicator initialization failed");
            g_initOK = 0;
            return;
        }

        g_initialBalance = Balance;
        Lots             = InpLotSize;

        g_initOK = 1;
        printf("Init OK");
    }

    if(is(EXITRUN))
    {
        IndicatorsRelease();
        printf("Deinit OK");
        return;
    }

    if(!g_initOK)    return;
    if(is(LOOKBACK)) return;

    // ── ATR computed ONCE per bar ─────────────────────────────
    var atr = 0, atrAvg = 0;
    int atrOK = GetATR(&atr, &atrAvg);

    // ── #3: all management and entry gated under atrOK ────────
    if(!atrOK) return;

    // ── Position management (no time filter) ──────────────────
    // Execution order: ManageTrailingStop first, ManageTakes second.
    // No shared mutable state between the two loops.
    ManageTrailingStop(atr);
    ManageTakes(atr);

    // ── Entry engine (time-filtered) ──────────────────────────
    if(InpUseTimeFilter && !IsWithinTradingHours())
        return;

    EntriesEngine(atr);
}
