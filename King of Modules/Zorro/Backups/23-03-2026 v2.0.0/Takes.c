// =========================================================
// FILE: Takes.c
// ROLE: Take profit calculation + dynamic exit management
// =========================================================

#ifndef TAKES_C
#define TAKES_C

// ---------------------------------------------------------
// CALCULATE TAKE PROFIT — LONG
// Returns absolute price level for take profit
// ---------------------------------------------------------
var CalculateTakeLong()
{
    var close = Close[0];
    var atr   = g_ATR14[0];

    switch(TakeMode)
    {
        case TAKE_SUPERTREND:
            // Wide initial TP; SuperTrend flip in ManageTakes()
            // handles the actual exit — this prevents premature TP hit
            return close + TakeATRMult * atr * 3.0;

        case TAKE_TRAILING:
            return close + TakeATRMult * atr;

        case TAKE_FIXED:
        default:
            return close + FixedTakePoints * PIP;
    }
}

// ---------------------------------------------------------
// CALCULATE TAKE PROFIT — SHORT
// Returns absolute price level for take profit
// ---------------------------------------------------------
var CalculateTakeShort()
{
    var close = Close[0];
    var atr   = g_ATR14[0];

    switch(TakeMode)
    {
        case TAKE_SUPERTREND:
            return close - TakeATRMult * atr * 3.0;

        case TAKE_TRAILING:
            return close - TakeATRMult * atr;

        case TAKE_FIXED:
        default:
            return close - FixedTakePoints * PIP;
    }
}

// ---------------------------------------------------------
// MANAGE TAKES — dynamic exit on open trades
//
// TAKE_SUPERTREND : exit on SuperTrend direction flip
// TAKE_TRAILING   : trail TP toward price using ATR
//
// NOTE: exitTrade(ThisTrade, 0, 0) — second param = price
//       (0 = market), third = lots (0 = all).
//       Verify signature against your Zorro version.
// NOTE: TradeProfitLimit maps to ThisTrade->fProfitLimit
// ---------------------------------------------------------
void ManageTakes()
{
    var close = Close[0];
    var atr   = g_ATR14[0];

    for(open_trades)
    {
        if(!TradeIsOpen) continue;

        // --- SuperTrend flip exit ---
        if(TakeMode == TAKE_SUPERTREND)
        {
            if(TradeIsLong  && isSTFlipBear())
                exitTrade(ThisTrade, 0, 0);
            else if(TradeIsShort && isSTFlipBull())
                exitTrade(ThisTrade, 0, 0);
        }

        // --- Trailing ATR take profit ---
        else if(TakeMode == TAKE_TRAILING)
        {
            if(TradeIsLong)
            {
                var newTP = close + TakeATRMult * atr;
                // Only tighten TP toward price (move it down toward current price)
                if(TradeProfitLimit == 0.0 || newTP < TradeProfitLimit)
                    TradeProfitLimit = newTP;
            }
            else if(TradeIsShort)
            {
                var newTP = close - TakeATRMult * atr;
                // Only tighten TP toward price (move it up toward current price)
                if(newTP > TradeProfitLimit)
                    TradeProfitLimit = newTP;
            }
        }
    }
}

#endif // TAKES_C
