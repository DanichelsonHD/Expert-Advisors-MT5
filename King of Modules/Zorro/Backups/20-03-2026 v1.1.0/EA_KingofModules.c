#include <zorro.h>

#include "Inputs.c"
#include "Indicators.c"
#include "Entries.c"
#include "Takes.c"
#include "Stops.c"

int  IndicatorsInit();
void IndicatorsRelease();
int  GetATR(var* atr, var* avg);
void UpdateAllSeries();
void ManageTrailingStop(var atr);
void ManageTakes(var atr);
void EntriesEngine(var atrVal);

int g_initOK;

int IsWithinTradingHours()
{
    int h;
    h = hour();
    return (h >= InpStartHour && h < InpEndHour);
}

void run()
{
    var atr;
    var atrAvg;
    int atrOK;

    set(PARAMETERS+LOGFILE);
    set(GENETIC);

        // RSI
        InpRSIPeriod     = optimize(14, 5, 30, 1);
        InpRSIOversold   = optimize(28.0, 15.0, 35.0, 1.0);
        InpRSIOverbought = optimize(72.0, 65.0, 85.0, 1.0);

        // KAMA
        InpKAMAPeriod     = optimize(14, 5, 30, 1);
        InpKAMAFastPeriod = optimize(2, 1, 10, 1);
        InpKAMASlowPeriod = optimize(30, 10, 50, 5);

        // ATR base
        InpATRPeriod = optimize(14, 5, 30, 1);

        // Keltner (importante pro MR)
        InpKeltnerEMAPeriod = optimize(14, 5, 30, 1);
        InpKeltnerATRFactor = optimize(2.5, 0.5, 5.0, 0.25);

    if(is(INITRUN))
    {
        g_initOK = 0;

        if(!IndicatorsInit())
        {
            printf("Indicator initialization failed");
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

    // ── Update ALL series UNCONDITIONALLY — must be first ─────
    UpdateAllSeries();

    // ── ATR value from precomputed g_atr ─────────────────────
    atr    = 0;
    atrAvg = 0;
    atrOK  = GetATR(&atr, &atrAvg);

    // ── Position management (no time filter) ──────────────────
    if(atrOK)
        ManageTrailingStop(atr);

    ManageTakes(atr);

    // ── Entry engine (time-filtered) ──────────────────────────
    if(InpUseTimeFilter && !IsWithinTradingHours())
        return;

    if(atrOK)
        EntriesEngine(atr);
}