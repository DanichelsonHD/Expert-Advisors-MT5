#include <zorro.h>

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

int g_initOK = 0;


int IsWithinTradingHours()
{
    int h = hour();
    return (h >= InpStartHour && h < InpEndHour);
}


void run()
{
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
