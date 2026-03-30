#ifndef ZORRO_CONFIGS_H
#define ZORRO_CONFIGS_H

struct ZorroConfig
{
    int    max_consecutive_losses;
    double cooldown_hours;
    double risk_per_trade;
    bool   enable_mean_reversion;

    // KAMA
    int    kama_period;
    int    kama_fast_period;
    int    kama_slow_period;
    int    kama_window_period;
    bool   kama_use_filter;
    double kama_filter_strength;
    double kama_filter_diff_pts;

    // Indicator periods
    int    ema20_period;
    int    ema50_period;
    int    rsi_period;
    int    atr_period;
    int    adx_period;
    int    bb_period;
    double bb_deviation;
    int    kc_ema_period;
    int    kc_atr_period;
    double kc_multiplier;

    // Execution
    double lot_size;
};

inline ZorroConfig DefaultZorroConfig()
{
    ZorroConfig cfg;
    cfg.max_consecutive_losses = 3;
    cfg.cooldown_hours         = 24.0;
    cfg.risk_per_trade         = 1.0;
    cfg.enable_mean_reversion  = true;

    cfg.kama_period            = 7;
    cfg.kama_fast_period       = 2;
    cfg.kama_slow_period       = 30;
    cfg.kama_window_period     = 4;
    cfg.kama_use_filter        = false;
    cfg.kama_filter_strength   = 50.0;
    cfg.kama_filter_diff_pts   = 50.0;

    cfg.ema20_period           = 20;
    cfg.ema50_period           = 50;
    cfg.rsi_period             = 4;
    cfg.atr_period             = 7;
    cfg.adx_period             = 7;
    cfg.bb_period              = 14;
    cfg.bb_deviation           = 2.0;
    cfg.kc_ema_period          = 7;
    cfg.kc_atr_period          = 14;
    cfg.kc_multiplier          = 1.5;

    cfg.lot_size               = 0.01;
    return cfg;
}

#endif // ZORRO_CONFIGS_H