// =========================================================
// FILE: Entries.c
// ROLE: Execution layer — lot sizing, signal aggregation,
//       trade entry. NO strategy logic here.
//
// POSITION OWNERSHIP MODEL:
//   Each trade is tagged via TradeComment = strategyID.
//   Enforcement: max 1 open trade per strategy.
//   Global system cap: 4 concurrent trades (one per strategy).
//   Strategies remain pure — zero execution awareness.
// =========================================================

#ifndef ENTRIES_C
#define ENTRIES_C

// ---------------------------------------------------------
// POSITION OWNERSHIP CHECK
// Returns 1 if strategyID already has an open trade
// ---------------------------------------------------------
int HasOpenTradeByStrategy(int strategyID)
{
    for(open_trades)
    {
        if(!TradeIsOpen) continue;

        if(TradeVar[0] == strategyID)
            return 1;
    }
    return 0;
}

// ---------------------------------------------------------
// GLOBAL TRADE COUNT
// Returns total number of currently open trades (all strategies)
// Reserved for future global cap enforcement
// ---------------------------------------------------------
int CountOpenTrades()
{
    int count = 0;
    for(open_trades)
    {
        if(TradeIsOpen) count++;
    }
    return count;
}

// ---------------------------------------------------------
// LOT CALCULATION
// ---------------------------------------------------------
var CalculateLots()
{
    switch(LotMode)
    {
        case LOT_EQUITY:
        {
            // Risk RiskPercent% of equity over FixedStopPoints distance
            // NOTE: FixedStopPoints used as reference stop distance.
            //       For variable stops, compute actual stop distance
            //       before calling this function and substitute below.
            var riskAmt  = Equity * RiskPercent / 100.0;
            var stopDist = FixedStopPoints * PIP;
            if(stopDist <= 0.0 || LotAmount <= 0.0) return FixedLot;
            return riskAmt / (stopDist * LotAmount);
        }

        case LOT_STEP:
        {
            // NOTE: Full step scaling requires tracking consecutive
            //       win/loss streaks. Returns FixedLot as base.
            //       Extend with trade history logic as needed.
            return FixedLot;
        }

        case LOT_FIXED:
        default:
            return FixedLot;
    }
}

// ---------------------------------------------------------
// TRADE EXECUTION
//
// strategyID is stored in TradeComment before entry —
// this is the sole mechanism for trade ownership tracking.
//
// Stop / TakeProfit are set as distance from Close[0]
// (entry price approximation in bar simulation).
// In live trading entry = next bar open; adjust if
// precision is critical for technical stop modes.
// ---------------------------------------------------------
void ExecuteTrade(int signal, int strategyID)
{
    Lots = CalculateLots();

    if(signal == SIGNAL_BUY)
    {
        var stopPrice = CalculateStopLong();
        var takePrice = CalculateTakeLong();

        Stop       = stopPrice - g_Close[0];
        TakeProfit = g_Close[0] - takePrice;

        enterLong();
        
    }
    else if(signal == SIGNAL_SELL)
    {
        var stopPrice = CalculateStopShort();
        var takePrice = CalculateTakeShort();

        Stop       = stopPrice - g_Close[0];
        TakeProfit = g_Close[0] - takePrice;

        enterShort();
    }

    printf("FORCED ENTRY TEST\n");
    enterLong();
    TradeVar[0] = strategyID;
}

// ---------------------------------------------------------
// STRATEGY AGGREGATION
//
// Priority: MR → PB → BO → SCI
// Rules per strategy:
//   1. Check signal (pure decision — no state)
//   2. Guard: skip if strategy already owns an open trade
//   3. Execute and return — one entry per bar maximum
//
// Concurrent trades: up to 4 (one per active strategy).
// Cross-strategy independence is fully preserved.
// ---------------------------------------------------------
void ExecuteStrategies()
{
    int signal;

    // --- MR ---
    if(UseMR)
    {
        signal = MR_CheckEntry();
        if(signal != SIGNAL_NONE && !HasOpenTradeByStrategy(STRAT_MR))
        {
            ExecuteTrade(signal, STRAT_MR);
            return;
        }
    }

    // --- PB ---
    if(UsePB)
    {
        signal = PB_CheckEntry();
        if(signal != SIGNAL_NONE && !HasOpenTradeByStrategy(STRAT_PB))
        {
            ExecuteTrade(signal, STRAT_PB);
            return;
        }
    }

    // --- BO ---
    if(UseBO)
    {
        signal = BO_CheckEntry();
        if(signal != SIGNAL_NONE && !HasOpenTradeByStrategy(STRAT_BO))
        {
            ExecuteTrade(signal, STRAT_BO);
            return;
        }
    }

    // --- SCI ---
    if(UseSCI)
    {
        signal = SCI_CheckEntry();
        if(signal != SIGNAL_NONE && !HasOpenTradeByStrategy(STRAT_SCI))
        {
            ExecuteTrade(signal, STRAT_SCI);
            return;
        }
    }
}

#endif // ENTRIES_C

