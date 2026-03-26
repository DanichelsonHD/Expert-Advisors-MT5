#ifndef ENGINE_H
#define ENGINE_H

#include "../Indicators/kama_filter.h"

//--- Shared indicator snapshot
struct IndicatorData
{
    double ema20;
    double ema50;
    double rsi14;
    double atr14;
    double adx14;
    double bb_upper;
    double bb_lower;
    double kc_upper;
    double kc_lower;
    double kama;
    int    kama_color;
    double close;
    double high;
    double low;
};

//--- Cooldown / risk state
struct CooldownState
{
    int    consecutive_losses;
    double cooldown_until_unix;
};

//--- Trade signal
struct TradeSignal
{
    int    direction;
    double sl;
    double tp;
    double entry;
};

//--- Engine configuration
struct EngineConfig
{
    int    max_consecutive_losses;
    double cooldown_hours;
    bool   enable_mean_reversion;
    double risk_per_trade;
};

bool Engine_IsCoolingDown(const CooldownState &state, double current_unix)
{
    if (state.consecutive_losses >= 0 && state.cooldown_until_unix > 0.0)
        return current_unix < state.cooldown_until_unix;
    return false;
}

void Engine_OnTradeClose(CooldownState &state, const EngineConfig &cfg,
                          bool is_win, double current_unix)
{
    if (is_win)
    {
        state.consecutive_losses = 0;
    }
    else
    {
        state.consecutive_losses++;
        if (state.consecutive_losses >= cfg.max_consecutive_losses)
            state.cooldown_until_unix = current_unix + cfg.cooldown_hours * 3600.0;
    }
}

bool Engine_CanTrade(const CooldownState &state, const EngineConfig &cfg,
                      double current_unix)
{
    if (state.consecutive_losses >= cfg.max_consecutive_losses)
        return current_unix >= state.cooldown_until_unix;
    return true;
}

#endif // ENGINE_H