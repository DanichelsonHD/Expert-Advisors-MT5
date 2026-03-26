// =========================================================
// FILE: Entries.c
// ROLE: Execution layer — lot sizing, signal aggregation,
//       trade entry. NO strategy logic here.
// =========================================================

#ifndef ENTRIES_C
#define ENTRIES_C

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
            //       win/loss streaks. This returns FixedLot as base.
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
// Stop / TakeProfit are set as distance from Close[0]
// (used as entry price approximation in bar simulation).
// In live trading, entry price = next bar open; adjust if
// precision is critical for technical stop modes.
// ---------------------------------------------------------
void ExecuteTrade(int signal)
{
    Lots = CalculateLots();

    if(signal == SIGNAL_BUY)
    {
        var stopPrice = CalculateStopLong();
        var takePrice = CalculateTakeLong();

        // Zorro Stop / TakeProfit = distance from entry
        Stop       = Close[0] - stopPrice;
        TakeProfit = takePrice - Close[0];

        enterLong();
    }
    else if(signal == SIGNAL_SELL)
    {
        var stopPrice = CalculateStopShort();
        var takePrice = CalculateTakeShort();

        Stop       = stopPrice - Close[0];
        TakeProfit = Close[0] - takePrice;

        enterShort();
    }
}

// ---------------------------------------------------------
// STRATEGY AGGREGATION
// Priority order: MR → PB → BO → SCI
// First non-NONE signal wins; lower priority skipped
// ---------------------------------------------------------
void ExecuteStrategies()
{
    int signal = SIGNAL_NONE;

    if(UseMR && signal == SIGNAL_NONE)
        signal = MR_CheckEntry();

    if(UsePB && signal == SIGNAL_NONE)
        signal = PB_CheckEntry();

    if(UseBO && signal == SIGNAL_NONE)
        signal = BO_CheckEntry();

    if(UseSCI && signal == SIGNAL_NONE)
        signal = SCI_CheckEntry();

    if(signal != SIGNAL_NONE)
        ExecuteTrade(signal);
}

#endif // ENTRIES_C
