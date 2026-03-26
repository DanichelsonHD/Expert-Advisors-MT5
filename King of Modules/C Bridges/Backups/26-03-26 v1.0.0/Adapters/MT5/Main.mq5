#property strict
#property copyright "KingQuant"
#property version   "1.00"

#include "Configs.mqh"
#include "Indicators.mqh"
#include "../../Core/Engine.h"
#include "../../Strategies/MeanReversion.h"

// ---------------------------------------------------------------------------
// Module-level state
// ---------------------------------------------------------------------------
static EngineConfig   g_cfg;
static CooldownState  g_cooldown;
static IndicatorData  g_ind;
static IndicatorData  g_prev_ind;
static bool           g_prev_valid = false;

static MeanReversionParams g_mr_params;

static datetime g_last_bar = 0;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
bool IsNewBar()
{
    datetime current = iTime(_Symbol, PERIOD_CURRENT, 0);
    if (current != g_last_bar)
    {
        g_last_bar = current;
        return true;
    }
    return false;
}

double CurrentUnix()
{
    return (double)TimeCurrent();
}

void OpenTrade(const TradeSignal& sig)
{
    MqlTradeRequest req = {};
    MqlTradeResult  res = {};

    req.action    = TRADE_ACTION_DEAL;
    req.symbol    = _Symbol;
    req.volume    = InpLotSize;
    req.type      = (sig.direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    req.price     = (sig.direction == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                         : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    req.sl        = sig.sl;
    req.tp        = sig.tp;
    req.deviation = InpSlippage;
    req.magic     = InpMagicNumber;
    req.comment   = "KQ_MR";

    if (!OrderSend(req, res))
    {
        Print("OrderSend failed. Error: ", GetLastError());
    }
}

void CheckClosedTrades()
{
    // Scan history for closed trades with our magic number since last check.
    // Update cooldown state accordingly.
    HistorySelect(0, TimeCurrent());
    int total = HistoryDealsTotal();
    static int s_last_checked = 0;

    for (int i = s_last_checked; i < total; ++i)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if (HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
        ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
        if (entry != DEAL_ENTRY_OUT) continue;

        double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
        bool   is_win = (profit >= 0.0);

        Engine_OnTradeClose(g_cooldown, g_cfg, is_win, CurrentUnix());
    }
    s_last_checked = total;
}

// ---------------------------------------------------------------------------
// MQL5 event handlers
// ---------------------------------------------------------------------------
int OnInit()
{
    g_cfg.max_consecutive_losses = InpMaxConsecutiveLosses;
    g_cfg.cooldown_hours         = InpCooldownHours;
    g_cfg.enable_mean_reversion  = InpEnableMeanReversion;
    g_cfg.risk_per_trade         = InpRiskPerTrade;

    g_cooldown.consecutive_losses  = 0;
    g_cooldown.cooldown_until_unix = 0.0;

    g_mr_params.adx_threshold  = InpMR_ADX_Threshold;
    g_mr_params.rsi_oversold   = InpMR_RSI_Oversold;
    g_mr_params.rsi_overbought = InpMR_RSI_Overbought;
    g_mr_params.sl_atr_mult    = InpMR_SL_ATR_Mult;
    g_mr_params.tp_atr_mult    = InpMR_TP_ATR_Mult;

    if (!Indicators_Init(_Symbol, PERIOD_CURRENT))
    {
        Print("Indicators_Init failed.");
        return INIT_FAILED;
    }

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    Indicators_Deinit();
}

void OnTick()
{
    if (!IsNewBar()) return;

    CheckClosedTrades();

    if (!Engine_CanTrade(g_cooldown, g_cfg, CurrentUnix())) return;

    if (!Indicators_Update(g_ind, 1)) return;

    if (!g_prev_valid)
    {
        if (!Indicators_Update(g_prev_ind, 2)) return;
        g_prev_valid = true;
    }

    // Mean Reversion
    if (g_cfg.enable_mean_reversion)
    {
        TradeSignal sig = Evaluate(g_ind, g_prev_ind, g_mr_params);
        if (sig.direction != 0)
            OpenTrade(sig);
    }

    g_prev_ind = g_ind;
}

void OnTrade() {}