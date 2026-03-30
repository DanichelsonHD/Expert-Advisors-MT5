#ifndef ENGINE_H
#define ENGINE_H

#include "../Indicators/kama_filter.h"

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

struct CooldownState
{
    int consecutive_losses;
    int cooldown_bars_remaining;
};

struct TradeSignal
{
    int    direction;
    double sl;
    double tp;
    double entry;
};

struct EngineConfig
{
    int    max_consecutive_losses;
    int    cooldown_bars;
    double cooldown_hours;
    bool   use_bar_cooldown;
    bool   enable_mean_reversion;
    double risk_per_trade;
};

bool Engine_IsCoolingDown(const CooldownState& state, double current_unix)
{
    return state.cooldown_bars_remaining > 0;
}

void Engine_OnTradeClose(CooldownState& state, const EngineConfig& cfg,
                          bool is_win, double current_unix)
{
    if (is_win)
    {
        state.consecutive_losses      = 0;
        state.cooldown_bars_remaining = 0;
    }
    else
    {
        state.consecutive_losses++;
        if (state.consecutive_losses >= cfg.max_consecutive_losses)
            state.cooldown_bars_remaining = cfg.cooldown_bars;
    }
}

bool Engine_CanTrade(CooldownState& state, const EngineConfig& cfg,
                      double current_unix)
{
    if (state.cooldown_bars_remaining > 0)
    {
        state.cooldown_bars_remaining--;
        return false;
    }
    return true;
}

#endif // ENGINE_H