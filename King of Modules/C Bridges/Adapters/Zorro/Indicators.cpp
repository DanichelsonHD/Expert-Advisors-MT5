#include "indicators.h"
#include "../../Indicators/kama_filter.h"

// ---------------------------------------------------------------------------
// KAMA persistent state — one instance per run, lives for the session.
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Populate IndicatorData from the previous closed bar (shift=1 equivalent).
// All Zorro series functions use offset 1 to match MT5 shift=1.
// ---------------------------------------------------------------------------
// Simple EMA calculation for DLL context
// ---------------------------------------------------------------------------
static double CalculateEMA(double newPrice, double prevEMA, double alpha)
{
    return alpha * newPrice + (1.0 - alpha) * prevEMA;
}

// Simple RSI calculation
static double CalculateRSI(double prices[], int period)
{
    double gains = 0.0, losses = 0.0;
    for (int i = 1; i < period; i++) {
        double change = prices[i] - prices[i - 1];
        if (change > 0) {
            gains += change;
        } else {
            losses -= change;
        }
    }
    
    double avgGain = gains / period;
    double avgLoss = losses / period;
    
    if (avgLoss == 0.0)
        return (avgGain > 0.0) ? 100.0 : 50.0;
    
    double rs = avgGain / avgLoss;
    return 100.0 - (100.0 / (1.0 + rs));
}

// ---------------------------------------------------------------------------
bool Indicators_Update(IndicatorData& out, const ZorroConfig& cfg)
{   
    if (!g_kama_initialized)
        return false;
    
    // --- OHLC of previous closed bar ---
    out.close = priceClose(1);
    out.high  = priceHigh(1);
    out.low   = priceLow(1);
    
    // --- EMA (simple exponential moving average approximation) ---
    // In Zorro DLL context, we can't use full series, so we estimate from current price
    static double ema20_state = 0.0;
    static bool ema20_init = false;
    if (!ema20_init) {
        ema20_state = out.close;
        ema20_init = true;
    }
    double alpha20 = 2.0 / (cfg.ema20_period + 1.0);
    ema20_state = CalculateEMA(out.close, ema20_state, alpha20);
    out.ema20 = ema20_state;
    
    // --- RSI (simplified for DLL context) ---
    // Collect last N prices for RSI calculation
    static double rsi_prices[100];
    static int rsi_idx = 0;
    rsi_prices[rsi_idx] = out.close;
    rsi_idx = (rsi_idx + 1) % cfg.rsi_period;
    
    if (rsi_idx > 0) {  // Wait until we have enough prices
        out.rsi14 = CalculateRSI(rsi_prices, cfg.rsi_period);
    } else {
        out.rsi14 = 50.0;  // Neutral value until initialized
    }
    
    // --- ATR (Average True Range approximation) ---
    static double atr_state = 0.0;
    static bool atr_init = false;
    double tr = out.high - out.low;  // True Range simplified
    if (!atr_init) {
        atr_state = tr;
        atr_init = true;
    }
    double alpha_atr = 1.0 / cfg.atr_period;
    atr_state = CalculateEMA(tr, atr_state, alpha_atr);
    out.atr14 = atr_state;

    // --- ADX (Average Directional Index approximation) ---
    // Simplified ADX: using the ratio of high-low range to recent volatility
    static double adx_state = 25.0;
    double dayRange = out.high - out.low;
    double avgRange = adx_state > 0.1 ? dayRange / adx_state : 1.0;
    adx_state = CalculateEMA(avgRange, adx_state, 0.1);
    out.adx14 = avgRange * 100.0 / (adx_state + 0.0001);  // Trend strength

    // --- Bollinger Bands ---
    // BB calculation using EMA and ATR as approximation
    out.bb_upper = ema20_state + (cfg.bb_deviation * atr_state);
    out.bb_lower = ema20_state - (cfg.bb_deviation * atr_state);

    // --- Keltner Channel ---
    double kc_ema = ema20_state;
    double kc_atr = atr_state;
    out.kc_upper  = kc_ema + cfg.kc_multiplier * kc_atr;
    out.kc_lower  = kc_ema - cfg.kc_multiplier * kc_atr;

    // --- KAMA ---
    Candle c;
    c.open  = priceOpen(1);
    c.high  = priceHigh(1);
    c.low   = priceLow(1);
    c.close = priceClose(1);

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