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
void ManageTakes();
void EntriesEngine(var atrVal);

// #1: global scope — persists across bars
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

    if(is(INITRUN))
    {
        // #1: initialize only here
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

    // ATR computed ONCE per bar
    atr    = 0;
    atrAvg = 0;
    atrOK  = GetATR(&atr, &atrAvg);

    // #2: restore original selective gating
    // ManageTrailingStop requires ATR; ManageTakes does not
    if(atrOK)
        ManageTrailingStop(atr);

    ManageTakes();

    // Entry engine (time-filtered)
    if(InpUseTimeFilter && !IsWithinTradingHours())
        return;

    if(atrOK)
        EntriesEngine(atr);
}
