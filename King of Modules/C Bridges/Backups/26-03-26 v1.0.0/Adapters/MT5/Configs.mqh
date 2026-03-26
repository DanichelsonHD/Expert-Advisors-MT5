#property strict

// ---------------------------------------------------------------------------
// User inputs
// ---------------------------------------------------------------------------
input group "=== Risk ==="
input double InpRiskPerTrade           = 1.0;   // Risk % per trade
input int    InpMaxConsecutiveLosses   = 3;      // Max consecutive losses
input double InpCooldownHours          = 24.0;  // Cooldown hours after streak

input group "=== Strategies ==="
input bool   InpEnableMeanReversion    = true;

input group "=== Mean Reversion ==="
input double InpMR_ADX_Threshold      = 20.0;
input double InpMR_RSI_Oversold       = 35.0;
input double InpMR_RSI_Overbought     = 65.0;
input double InpMR_SL_ATR_Mult        = 1.5;
input double InpMR_TP_ATR_Mult        = 2.5;

input group "=== KAMA ==="
input int    InpKAMA_Period            = 14;
input int    InpKAMA_FastPeriod        = 2;
input int    InpKAMA_SlowPeriod        = 30;
input int    InpKAMA_WindowPeriod      = 4;
input bool   InpKAMA_UseFilter         = true;
input double InpKAMA_FilterStrength    = 50.0;
input double InpKAMA_FilterDiffPts     = 50.0;

input group "=== Indicators ==="
input int    InpEMA20_Period           = 20;
input int    InpEMA50_Period           = 50;
input int    InpRSI_Period             = 14;
input int    InpATR_Period             = 14;
input int    InpADX_Period             = 14;
input int    InpBB_Period              = 20;
input double InpBB_Deviation           = 2.0;
input int    InpKC_EMA_Period          = 20;
input int    InpKC_ATR_Period          = 14;
input double InpKC_Multiplier          = 1.5;

input group "=== Execution ==="
input double InpLotSize                = 0.1;
input int    InpMagicNumber            = 20240001;
input int    InpSlippage               = 10;