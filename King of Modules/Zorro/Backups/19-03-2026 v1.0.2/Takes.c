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

var GetTakeProfit(int signal, var atr)
{
    int mode;

    if(!InpUseTakeProfit)
        return 0;

    if(signal == SIGNAL_BUY) mode = InpLongTakeMode; else mode = InpShortTakeMode;

    if(mode == TAKE_POINTS)
        return InpTakePoints * PIP;

    return atr * InpTPMultiplier + InpTakeExtraPoints * PIP;
}

void TakeKAMA(int kamaColorPrev, int kamaColorCur)
{
    int prevRegime;
    int curRegime;

    prevRegime = ResolveKAMARegime(kamaColorPrev);
    curRegime  = ResolveKAMARegime(kamaColorCur);

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

void ManageTakes(var atr)
{
    int kamaColorPrev;
    int kamaColorCur;

    if(!InpUseTakeProfit)
        return;

    if(InpLongTakeMode  != TAKE_KAMA &&
       InpShortTakeMode != TAKE_KAMA)
        return;

    kamaColorPrev = 0;
    kamaColorCur  = 0;
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
