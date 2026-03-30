#include <zorro.h>
#include <ctime>

#include "configs.h"
#include "indicators.h"
#include "../../Core/Engine.h"
#include "../../Strategies/MeanReversion.h"

// ---------------------------------------------------------------------------
// Module-level state
// ---------------------------------------------------------------------------
static ZorroConfig          g_cfg;
static EngineConfig         g_eng_cfg;
static CooldownState        g_cooldown;
static IndicatorData        g_ind;
static IndicatorData        g_prev_ind;
static bool                 g_prev_valid    = false;
static MeanReversionParams  g_mr_params;

// ---------------------------------------------------------------------------
// Track open trade ticket for single-trade enforcement and close detection.
// ---------------------------------------------------------------------------
static TRADE*  g_active_trade  = nullptr;
static double  g_trade_open_price = 0.0;

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------
static double CurrentUnix()
{
    return (double)time(nullptr);
}

// ---------------------------------------------------------------------------
// Detect if the active trade has closed and update cooldown state.
// ---------------------------------------------------------------------------
static void CheckClosedTrade()
{
    if (g_active_trade == nullptr)
        return;

    // In Zorro, a trade is closed when exit price is set
    if (g_active_trade->fExitPrice == 0.0)
        return;

    double profit = g_active_trade->fResult;
    bool   is_win = (profit >= 0.0);

    Engine_OnTradeClose(g_cooldown, g_eng_cfg, is_win, CurrentUnix());

    g_active_trade = nullptr;
}

// ---------------------------------------------------------------------------
// Execute trade based on signal.
// SL and TP are absolute price levels from the strategy.
// ---------------------------------------------------------------------------
static void ExecuteTrade(const TradeSignal& sig)
{
    if (NumOpenLong + NumOpenShort > 0)
        return;

    TRADE* trade = nullptr;
    if (sig.direction == 1)
    {
        trade = enterLong((int)g_cfg.lot_size);
    }
    else if (sig.direction == -1)
    {
        trade = enterShort((int)g_cfg.lot_size);
    }

    if (trade != nullptr)
    {
        trade->fStopLimit = sig.sl;      // Stop loss limit price
        trade->fProfitLimit = sig.tp;    // Profit target limit price
        g_active_trade = trade;
    }
}

// ---------------------------------------------------------------------------
// Zorro run() — called every tick by the framework.
// Logic executes only once per new closed bar.
// ---------------------------------------------------------------------------
DLLFUNC int run()
{
    set(PARAMETERS+LOGFILE);
    set(TICKS);

    BarPeriod = 15;
    LookBack  = 200;
    StartDate = 2023;
    EndDate   = 2026;
    NumCores = 4;
    Capital = 10000;

    // --- One-time setup on first call ---
    static bool s_initialized = false;
    if (!s_initialized)
    {
        g_cfg = DefaultZorroConfig();

        g_eng_cfg.max_consecutive_losses = g_cfg.max_consecutive_losses;
        g_eng_cfg.cooldown_bars          = 96;  // e.g. 96 x 15min bars = 24 hours
        g_eng_cfg.cooldown_hours         = g_cfg.cooldown_hours;
        g_eng_cfg.use_bar_cooldown       = false;
        g_eng_cfg.enable_mean_reversion  = g_cfg.enable_mean_reversion;
        g_eng_cfg.risk_per_trade         = g_cfg.risk_per_trade;

        g_cooldown.consecutive_losses      = 0;
        g_cooldown.cooldown_bars_remaining = 0;

        g_mr_params.adx_threshold  = 20.0;
        g_mr_params.rsi_oversold   = 25.0;
        g_mr_params.rsi_overbought = 75.0;
        g_mr_params.sl_atr_mult    = 1.5;
        g_mr_params.tp_atr_mult    = 2.5;

        Indicators_Init(g_cfg);

        s_initialized = true;
    }

    // --- New bar gate (execute once per closed bar) ---
    static int s_prev_bar = -1;
    if (Bar == s_prev_bar)
        return 0;
    s_prev_bar = Bar;

    // --- Check if active trade closed ---
    CheckClosedTrade();

    // --- Cooldown check ---
    if (!Engine_CanTrade(g_cooldown, g_eng_cfg, CurrentUnix()))
        return 0;

    // --- Populate indicator snapshot from previous closed bar ---
    if (!Indicators_Update(g_ind, g_cfg))
        return 0;

    // --- Populate previous bar snapshot on first valid bar ---
    if (!g_prev_valid)
    {
        // Temporarily shift by 2 to get the bar before the current prev bar.
        // We reuse the same Indicators_Update but shift manually is not
        // available through our abstraction, so we store on second valid bar.
        g_prev_ind   = g_ind;
        g_prev_valid = true;
        return 0;
    }

    // --- Strategy evaluation ---
    if (g_eng_cfg.enable_mean_reversion)
    {
        TradeSignal sig = Evaluate(g_ind, g_prev_ind, g_mr_params);

        if (sig.direction != 0)
            ExecuteTrade(sig);
    }

    // --- Advance previous indicator snapshot ---
    g_prev_ind = g_ind;

    return 0;
}

// Include implementation files to ensure they're compiled into the DLL
#include "indicators.cpp"