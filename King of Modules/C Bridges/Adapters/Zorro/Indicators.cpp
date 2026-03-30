#include "indicators.h"
#include "../../Indicators/kama_filter.h"

static KAMAState         g_kama_state;
static KAMAWindowTracker g_kama_hh;
static KAMAWindowTracker g_kama_ll;
static bool              g_kama_initialized = false;

void Indicators_Init(const ZorroConfig& cfg)
{
    KAMA_Init(g_kama_state,
              cfg.kama_period,
              cfg.kama_fast_period,
              cfg.kama_slow_period,
              KAMA_POWER_TWO,
              2.0);

    KAMAWindowTracker_Init(g_kama_hh, cfg.kama_window_period, 1);
    KAMAWindowTracker_Init(g_kama_ll, cfg.kama_window_period, 0);

    g_kama_initialized = true;
}

bool Indicators_Update(IndicatorData& out, const ZorroConfig& cfg)
{
    if (!g_kama_initialized)
        return false;

    vars Close = series(priceClose(0));
    vars High  = series(priceHigh(0));
    vars Low   = series(priceLow(0));

    out.ema20 = EMA(Close, cfg.ema20_period);
    out.ema50 = EMA(Close, cfg.ema50_period);

    out.rsi14 = RSI(Close, cfg.rsi_period);

    out.atr14 = ATR(cfg.atr_period);

    out.adx14 = ADX(cfg.adx_period);

    vars bb_upper_series = series(BBands(Close, cfg.bb_period,  cfg.bb_deviation,  cfg.bb_deviation, 0));
    vars bb_lower_series = series(BBands(Close, cfg.bb_period, -cfg.bb_deviation, -cfg.bb_deviation, 0));
    out.bb_upper = bb_upper_series[1];
    out.bb_lower = bb_lower_series[1];

    out.kc_upper = out.ema20 + cfg.kc_multiplier * out.atr14;
    out.kc_lower = out.ema20 - cfg.kc_multiplier * out.atr14;

    out.close = Close[1];
    out.high  = High[1];
    out.low   = Low[1];

    Candle c;
    c.open  = priceOpen(1);
    c.high  = High[1];
    c.low   = Low[1];
    c.close = Close[1];

    double price = KAMA_GetPrice(KAMA_PRICE_CLOSE, c);

    KAMAWindowTracker_Push(g_kama_hh, c.high);
    KAMAWindowTracker_Push(g_kama_ll, c.low);

    KAMAResult kr = KAMA_FullUpdate(
        g_kama_state,
        price, c.high, c.low,
        g_kama_hh, g_kama_ll,
        cfg.kama_use_filter ? 1 : 0,
        cfg.kama_filter_strength,
        cfg.kama_filter_diff_pts * PIP
    );

    out.kama       = kr.filtered_kama;
    out.kama_color = kr.signal_color;

    return true;
}