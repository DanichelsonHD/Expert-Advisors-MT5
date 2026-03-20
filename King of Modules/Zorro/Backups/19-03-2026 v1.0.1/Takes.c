// ============================================================
//  Takes.c  –  Zorro translation of Takes.mqh
//  Original: EA_KingofModules v1.30
//  Authors:  Daniel Pereira & Lucas Mattos
// ============================================================
//
//  PATCH NOTES (Final Hardening):
//  #5  – All printf() calls inside TakeKAMA() removed.
//        Log output inside for(open_trades) executes per trade
//        per bar and pollutes the log file. Removed entirely.
// ============================================================

#ifndef TAKES_C
#define TAKES_C

#include "Indicators.c"

#define KAMA_REGIME_NONE    0
#define KAMA_REGIME_BEARISH 1
#define KAMA_REGIME_BULLISH 2

int ResolveKAMARegime(int colorCode)
{
    if(colorCode == 0) return KAMA_REGIME_BULLISH;
    if(colorCode == 1) return KAMA_REGIME_BEARISH;
    return KAMA_REGIME_NONE;
}


// ============================================================
//  GetTakeProfit  (public)
// ============================================================
var GetTakeProfit(int signal, var atr)
{
    if(!InpUseTakeProfit)
        return 0.0;

    int mode = (signal == SIGNAL_BUY) ? InpLongTakeMode
                                                  : InpShortTakeMode;

    if(mode == TAKE_POINTS)
        return InpTakePoints * PIP;

    return atr * InpTPMultiplier + InpTakeExtraPoints * PIP;
}


// ============================================================
//  TakeKAMA  –  internal per-trade
//  #5: printf removed — no log output inside trade loop.
// ============================================================
static void TakeKAMA(int kamaColorPrev, int kamaColorCur)
{
    int prevRegime = ResolveKAMARegime(kamaColorPrev);
    int curRegime  = ResolveKAMARegime(kamaColorCur);

    if(TradeIsLong)
    {
        if(prevRegime == KAMA_REGIME_BULLISH && curRegime == KAMA_REGIME_BEARISH)
            exitTrade(ThisTrade);
    }
    else if(TradeIsShort)
    {
        if(prevRegime == KAMA_REGIME_BEARISH && curRegime == KAMA_REGIME_BULLISH)
            exitTrade(ThisTrade);
    }
}


// ============================================================
//  ManageTakes  (public)
// ============================================================
void ManageTakes(var atr)
{
    if(!InpUseTakeProfit)
        return;

    if(InpLongTakeMode  != TAKE_KAMA &&
       InpShortTakeMode != TAKE_KAMA)
        return;

    int kamaColorPrev = 0, kamaColorCur = 0;
    if(!GetKAMAColor(&kamaColorPrev, &kamaColorCur))
        return;

    for(open_trades)
    {
        if(TradeIsLong  && InpLongTakeMode  == TAKE_KAMA)
            TakeKAMA(kamaColorPrev, kamaColorCur);
        if(TradeIsShort && InpShortTakeMode == TAKE_KAMA)
            TakeKAMA(kamaColorPrev, kamaColorCur);
    }
}

#endif // TAKES_C
