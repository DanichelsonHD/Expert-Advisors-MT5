#property strict

#include "Configs.mqh"
#include "../../Indicators/kama_filter.h"
#include "../../Core/Engine.h"

// ---------------------------------------------------------------------------
// Indicator handles — created in OnInit, released in OnDeinit.
// ---------------------------------------------------------------------------
int g_h_ema20   = INVALID_HANDLE;
int g_h_ema50   = INVALID_HANDLE;
int g_h_rsi     = INVALID_HANDLE;
int g_h_atr     = INVALID_HANDLE;
int g_h_adx     = INVALID_HANDLE;
int g_h_bb      = INVALID_HANDLE;
int g_h_kc_ema  = INVALID_HANDLE;
int g_h_kc_atr  = INVALID_HANDLE;

// ---------------------------------------------------------------------------
// KAMA state — lives here, persists across bars.
// ---------------------------------------------------------------------------
KAMAState           g_kama_state;
KAMAWindowTracker   g_kama_hh;
KAMAWindowTracker   g_kama_ll;

bool Indicators_Init(const string symbol, const ENUM_TIMEFRAMES tf)
{
    g_h_ema20  = iMA(symbol, tf, InpEMA20_Period,  0, MODE_EMA, PRICE_CLOSE);
    g_h_ema50  = iMA(symbol, tf, InpEMA50_Period,  0, MODE_EMA, PRICE_CLOSE);
    g_h_rsi    = iRSI(symbol, tf, InpRSI_Period,   PRICE_CLOSE);
    g_h_atr    = iATR(symbol, tf, InpATR_Period);
    g_h_adx    = iADX(symbol, tf, InpADX_Period);
    g_h_bb     = iBands(symbol, tf, InpBB_Period, 0, InpBB_Deviation, PRICE_CLOSE);
    g_h_kc_ema = iMA(symbol, tf, InpKC_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    g_h_kc_atr = iATR(symbol, tf, InpKC_ATR_Period);

    if (g_h_ema20 == INVALID_HANDLE || g_h_ema50  == INVALID_HANDLE ||
        g_h_rsi   == INVALID_HANDLE || g_h_atr    == INVALID_HANDLE ||
        g_h_adx   == INVALID_HANDLE || g_h_bb     == INVALID_HANDLE ||
        g_h_kc_ema== INVALID_HANDLE || g_h_kc_atr == INVALID_HANDLE)
    {
        return false;
    }

    KAMA_Init(g_kama_state,
              InpKAMA_Period,
              InpKAMA_FastPeriod,
              InpKAMA_SlowPeriod,
              KAMA_POWER_TWO,
              2.0);

    KAMAWindowTracker_Init(g_kama_hh, InpKAMA_WindowPeriod, 1);
    KAMAWindowTracker_Init(g_kama_ll, InpKAMA_WindowPeriod, 0);

    return true;
}

void Indicators_Deinit()
{
    if (g_h_ema20  != INVALID_HANDLE) { IndicatorRelease(g_h_ema20);  g_h_ema20  = INVALID_HANDLE; }
    if (g_h_ema50  != INVALID_HANDLE) { IndicatorRelease(g_h_ema50);  g_h_ema50  = INVALID_HANDLE; }
    if (g_h_rsi    != INVALID_HANDLE) { IndicatorRelease(g_h_rsi);    g_h_rsi    = INVALID_HANDLE; }
    if (g_h_atr    != INVALID_HANDLE) { IndicatorRelease(g_h_atr);    g_h_atr    = INVALID_HANDLE; }
    if (g_h_adx    != INVALID_HANDLE) { IndicatorRelease(g_h_adx);    g_h_adx    = INVALID_HANDLE; }
    if (g_h_bb     != INVALID_HANDLE) { IndicatorRelease(g_h_bb);     g_h_bb     = INVALID_HANDLE; }
    if (g_h_kc_ema != INVALID_HANDLE) { IndicatorRelease(g_h_kc_ema); g_h_kc_ema = INVALID_HANDLE; }
    if (g_h_kc_atr != INVALID_HANDLE) { IndicatorRelease(g_h_kc_atr); g_h_kc_atr = INVALID_HANDLE; }
}

// ---------------------------------------------------------------------------
// Populate an IndicatorData snapshot for the given shift.
// shift=0 → current closed bar (recommended on new-bar trigger).
// Returns false if any CopyBuffer call fails.
// ---------------------------------------------------------------------------
bool Indicators_Update(IndicatorData &out, int shift = 1)
{
    double buf[1];

    if (CopyBuffer(g_h_ema20,  0, shift, 1, buf) < 1) return false; out.ema20    = buf[0];
    if (CopyBuffer(g_h_ema50,  0, shift, 1, buf) < 1) return false; out.ema50    = buf[0];
    if (CopyBuffer(g_h_rsi,    0, shift, 1, buf) < 1) return false; out.rsi14    = buf[0];
    if (CopyBuffer(g_h_atr,    0, shift, 1, buf) < 1) return false; out.atr14    = buf[0];
    if (CopyBuffer(g_h_adx,    0, shift, 1, buf) < 1) return false; out.adx14    = buf[0];

    if (CopyBuffer(g_h_bb, 1,  shift, 1, buf) < 1) return false; out.bb_upper = buf[0];
    if (CopyBuffer(g_h_bb, 2,  shift, 1, buf) < 1) return false; out.bb_lower = buf[0];

    double kc_ema_val[1], kc_atr_val[1];
    if (CopyBuffer(g_h_kc_ema, 0, shift, 1, kc_ema_val) < 1) return false;
    if (CopyBuffer(g_h_kc_atr, 0, shift, 1, kc_atr_val) < 1) return false;
    out.kc_upper = kc_ema_val[0] + InpKC_Multiplier * kc_atr_val[0];
    out.kc_lower = kc_ema_val[0] - InpKC_Multiplier * kc_atr_val[0];

    // OHLC for KAMA
    MqlRates rates[1];
    if (CopyRates(_Symbol, PERIOD_CURRENT, shift, 1, rates) < 1) return false;
    out.close = rates[0].close;
    out.high  = rates[0].high;
    out.low   = rates[0].low;

    Candle c;
    c.open  = rates[0].open;
    c.high  = rates[0].high;
    c.low   = rates[0].low;
    c.close = rates[0].close;

    double price = KAMA_GetPrice(KAMA_PRICE_CLOSE, c);
    KAMAWindowTracker_Push(g_kama_hh, c.high);
    KAMAWindowTracker_Push(g_kama_ll, c.low);

    KAMAResult kr = KAMA_FullUpdate(
        g_kama_state,
        price, c.high, c.low,
        g_kama_hh, g_kama_ll,
        InpKAMA_UseFilter ? 1 : 0,
        InpKAMA_FilterStrength,
        InpKAMA_FilterDiffPts * _Point
    );

    out.kama       = kr.filtered_kama;
    out.kama_color = kr.signal_color;

    return true;
}