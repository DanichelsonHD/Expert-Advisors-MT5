//+------------------------------------------------------------------+
//| kama_filter.h                                               |
//| MQL5-compatible port of kama_filter.h v3.0                       |
//| DO NOT modify kama_filter.h — this is a separate adaptation.     |
//+------------------------------------------------------------------+
#ifndef KAMA_FILTER_H
#define KAMA_FILTER_H

#ifdef __MQL5__
    #define KAMA_FUNC
    #define KAMA_SQRT(x) MathSqrt(x)
    #define KAMA_POW(x,y) MathPow(x,y)
#else
    #include <math.h>
    #define KAMA_FUNC static inline
    #define KAMA_SQRT(x) sqrt(x)
    #define KAMA_POW(x,y) pow(x,y)
#endif

#ifndef KAMA_MAX_PERIOD
  #define KAMA_MAX_PERIOD 200
#endif

#define KAMA__RING_BUF_SIZE (KAMA_MAX_PERIOD + 1)
#define KAMA__DEQUE_CAP     (KAMA_MAX_PERIOD + 1)
#define KAMA_PRIV

#define KAMA_ORDER_ASSERT(cond, msg) ((void)0)

#define KAMA__EPS 1e-9

//--- Candle
struct Candle
{
    double open;
    double high;
    double low;
    double close;
};

//--- KAMAPriceType
enum KAMAPriceType
{
    KAMA_PRICE_CLOSE    = 0,
    KAMA_PRICE_OPEN     = 1,
    KAMA_PRICE_HIGH     = 2,
    KAMA_PRICE_LOW      = 3,
    KAMA_PRICE_MEDIAN   = 4,
    KAMA_PRICE_TYPICAL  = 5,
    KAMA_PRICE_WEIGHTED = 6
};

//--- KAMAPowerMode
enum KAMAPowerMode
{
    KAMA_POWER_HALF   = 0,
    KAMA_POWER_ONE    = 1,
    KAMA_POWER_TWO    = 2,
    KAMA_POWER_THREE  = 3,
    KAMA_POWER_CUSTOM = 4
};

//--- KAMARing
struct KAMARing
{
    double buf[KAMA__RING_BUF_SIZE];
    int    wpos;
    int    count;
    int    cap;
    double sum;
};

//--- KAMADequeEntry
struct KAMADequeEntry
{
    int    bar_idx;
    double value;
};

//--- KAMAWindowTracker
struct KAMAWindowTracker
{
    KAMADequeEntry entries[KAMA__DEQUE_CAP];
    int            head;
    int            tail;
    int            window;
    int            is_max;
    int            bar_count;
};

//--- KAMACore
struct KAMACore
{
    double       fastend;
    double       slowend;
    KAMAPowerMode power_mode;
    double       custom_power;
    int          period;
    int          initialized;
    int          bar_count;
    double       prev_kama;
    double       prev_price;
    double       noise_sum;
    double       signal;
    KAMARing     diff_ring;
    KAMARing     price_ring;
};

//--- KAMAFilterState
struct KAMAFilterState
{
    int      slow_period;
    double   kama_diff_sum;
    double   prev_val;
    KAMARing kama_diff_ring;
};

//--- KAMASignalState
struct KAMASignalState
{
    int prev_color;
};

//--- KAMAState
struct KAMAState
{
    KAMACore        _core;
    KAMAFilterState _filt;
    KAMASignalState _sig;
};

//--- KAMAResult
struct KAMAResult
{
    double raw_kama;
    double filtered_kama;
    int    signal_color;
};

//--- Accessor macros
#define KAMA_PREV_KAMA(s)      ((s)._core.prev_kama)
#define KAMA_PREV_PRICE(s)     ((s)._core.prev_price)
#define KAMA_NOISE_SUM(s)      ((s)._core.noise_sum)
#define KAMA_SIGNAL_VAL(s)     ((s)._core.signal)
#define KAMA_FASTEND(s)        ((s)._core.fastend)
#define KAMA_SLOWEND(s)        ((s)._core.slowend)
#define KAMA_POWER_MODE(s)     ((s)._core.power_mode)
#define KAMA_INITIALIZED(s)    ((s)._core.initialized)
#define KAMA_BAR_COUNT(s)      ((s)._core.bar_count)
#define KAMA_PREV_VAL(s)       ((s)._filt.prev_val)
#define KAMA_KAMA_DIFF_SUM(s)  ((s)._filt.kama_diff_sum)
#define KAMA_PREV_COLOR(s)     ((s)._sig.prev_color)

//--- Deque navigation macros
#define KAMA__DQ_NEXT(i)   (((i) + 1) % KAMA__DEQUE_CAP)
#define KAMA__DQ_PREV(i)   (((i) + KAMA__DEQUE_CAP - 1) % KAMA__DEQUE_CAP)
#define KAMA__DQ_EMPTY(t)  ((t).head == (t).tail)

//+------------------------------------------------------------------+
KAMA_FUNC double kama__fast_pow(double base, double exp_val)
{
    double d;
    d = exp_val - 0.5; if (d < 0.0) d = -d; if (d < KAMA__EPS) return KAMA_SQRT(base);
    d = exp_val - 1.0; if (d < 0.0) d = -d; if (d < KAMA__EPS) return base;
    d = exp_val - 2.0; if (d < 0.0) d = -d; if (d < KAMA__EPS) return base * base;
    d = exp_val - 3.0; if (d < 0.0) d = -d; if (d < KAMA__EPS) return base * base * base;
    return KAMA_POW(base, exp_val);
}

KAMA_FUNC double kama__apply_power(double base, KAMAPowerMode mode, double custom_exp)
{
    switch (mode)
    {
        case KAMA_POWER_HALF:   return KAMA_SQRT(base);
        case KAMA_POWER_ONE:    return base;
        case KAMA_POWER_TWO:    return base * base;
        case KAMA_POWER_THREE:  return base * base * base;
        case KAMA_POWER_CUSTOM:
        default:                return kama__fast_pow(base, custom_exp);
    }
}

KAMA_FUNC double kama__abs(double x) { return (x < 0.0) ? -x : x; }

//+------------------------------------------------------------------+
KAMA_FUNC void KAMARing_Init(KAMARing &r, int capacity)
{
    r.cap   = (capacity > KAMA__RING_BUF_SIZE) ? KAMA__RING_BUF_SIZE : capacity;
    r.wpos  = 0;
    r.count = 0;
    r.sum   = 0.0;
    for (int i = 0; i < KAMA__RING_BUF_SIZE; ++i) r.buf[i] = 0.0;
}

KAMA_FUNC void KAMARing_Push(KAMARing &r, double value)
{
    if (r.count == r.cap)
        r.sum -= r.buf[r.wpos];
    else
        ++r.count;

    r.buf[r.wpos] = value;
    r.wpos        = (r.wpos + 1) % r.cap;
    r.sum        += value;
}

KAMA_FUNC double KAMARing_LookBack(const KAMARing &r, int k)
{
    if (k < 0 || k >= r.count) return 0.0;
    int idx = (r.wpos - 1 - k + r.cap * 2) % r.cap;
    return r.buf[idx];
}

//+------------------------------------------------------------------+
KAMA_FUNC void KAMAWindowTracker_Init(KAMAWindowTracker &t, int window, int is_max)
{
    t.head      = 0;
    t.tail      = 0;
    t.window    = window;
    t.is_max    = is_max;
    t.bar_count = 0;
}

KAMA_FUNC void KAMAWindowTracker_Push(KAMAWindowTracker &t, double value)
{
    int cur = t.bar_count++;

    while (!KAMA__DQ_EMPTY(t) &&
           t.entries[t.head].bar_idx <= cur - t.window)
        t.head = KAMA__DQ_NEXT(t.head);

    if (t.is_max)
    {
        while (!KAMA__DQ_EMPTY(t) &&
               t.entries[KAMA__DQ_PREV(t.tail)].value <= value)
            t.tail = KAMA__DQ_PREV(t.tail);
    }
    else
    {
        while (!KAMA__DQ_EMPTY(t) &&
               t.entries[KAMA__DQ_PREV(t.tail)].value >= value)
            t.tail = KAMA__DQ_PREV(t.tail);
    }

    t.entries[t.tail].bar_idx = cur;
    t.entries[t.tail].value   = value;
    t.tail = KAMA__DQ_NEXT(t.tail);
}

KAMA_FUNC int KAMAWindowTracker_Query(const KAMAWindowTracker &t, double &out_value)
{
    if (KAMA__DQ_EMPTY(t)) return 0;
    out_value = t.entries[t.head].value;
    return 1;
}

KAMA_FUNC double KAMAWindowTracker_QueryRaw(const KAMAWindowTracker &t)
{
    return t.entries[t.head].value;
}

//+------------------------------------------------------------------+
KAMA_FUNC int KAMA_IsWarmupComplete(const KAMAState &s)
{
    return s._core.bar_count >= s._core.period;
}

KAMA_FUNC void KAMA_Init(KAMAState &s,
                          int period, int fastPeriod, int slowPeriod,
                          KAMAPowerMode power_mode, double custom_power)
{
    int p  = (period     < 2)              ? 2               : period;
          p = (p          > KAMA_MAX_PERIOD)? KAMA_MAX_PERIOD : p;
    int fp = (fastPeriod < 1)              ? 1               : fastPeriod;
    int sp = (slowPeriod < fp)             ? fp              : slowPeriod;
        sp = (sp         > KAMA_MAX_PERIOD)? KAMA_MAX_PERIOD : sp;

    if (power_mode == KAMA_POWER_CUSTOM && custom_power <= 0.0)
        custom_power = 2.0;

    s._core.period       = p;
    s._core.fastend      = 2.0 / ((double)fp + 1.0);
    s._core.slowend      = 2.0 / ((double)sp + 1.0);
    s._core.power_mode   = power_mode;
    s._core.custom_power = custom_power;
    s._core.initialized  = 0;
    s._core.bar_count    = 0;
    s._core.prev_kama    = 0.0;
    s._core.prev_price   = 0.0;
    s._core.noise_sum    = 0.0;
    s._core.signal       = 0.0;
    KAMARing_Init(s._core.diff_ring,  p);
    KAMARing_Init(s._core.price_ring, p + 1);

    s._filt.slow_period   = sp;
    s._filt.kama_diff_sum = 0.0;
    s._filt.prev_val      = 0.0;
    KAMARing_Init(s._filt.kama_diff_ring, sp);

    s._sig.prev_color = 0;
}

KAMA_FUNC void KAMA_Init2(KAMAState &s, int period, int fastPeriod, int slowPeriod)
{
    KAMA_Init(s, period, fastPeriod, slowPeriod, KAMA_POWER_TWO, 2.0);
}

KAMA_FUNC double KAMA_Update(KAMAState &s, double price)
{
    double diff, kama, kama_diff, efratio, sc;

    diff = (s._core.initialized != 0) ? kama__abs(price - s._core.prev_price) : 0.0;

    if (s._core.price_ring.count >= s._core.period)
        s._core.signal = kama__abs(price - KAMARing_LookBack(s._core.price_ring, s._core.period - 1));
    else
        s._core.signal = 0.0;

    KAMARing_Push(s._core.diff_ring, diff);
    s._core.noise_sum = s._core.diff_ring.sum;

    KAMARing_Push(s._core.price_ring, price);

    efratio = (s._core.noise_sum > 0.0) ? (s._core.signal / s._core.noise_sum) : 1.0;

    sc = kama__apply_power(
             efratio * (s._core.fastend - s._core.slowend) + s._core.slowend,
             s._core.power_mode, s._core.custom_power);

    if (s._core.initialized == 0)
    {
        kama          = price;
        kama_diff     = 0.0;
        s._core.initialized = 1;
    }
    else
    {
        kama      = s._core.prev_kama + sc * (price - s._core.prev_kama);
        kama_diff = kama__abs(kama - s._core.prev_kama);
    }

    KAMARing_Push(s._filt.kama_diff_ring, kama_diff);
    s._filt.kama_diff_sum = s._filt.kama_diff_ring.sum;

    s._core.prev_kama  = kama;
    s._core.prev_price = price;
    s._core.bar_count++;

    s._filt.prev_val = kama;

    return kama;
}

KAMA_FUNC double KAMA_FilterValue(const KAMAState &s, double inpFilter)
{
    if (s._filt.slow_period == 0 ||
        s._filt.kama_diff_ring.count == 0) return 0.0;

    return inpFilter * s._filt.kama_diff_sum /
           (100.0 * (double)s._filt.slow_period);
}

KAMA_FUNC double KAMA_ApplyFilter(double current_kama,
                                   double prev_val,
                                   double high,
                                   double low,
                                   double highest_high,
                                   double lowest_low,
                                   double filterValue,
                                   double filterDiff,
                                   double prev_kama)
{
    double cAmaDiff = current_kama - prev_kama;
    double aAmaDiff = kama__abs(cAmaDiff);

    if (cAmaDiff > 0.0)
    {
        if (cAmaDiff < filterValue && high <= (highest_high + filterDiff))
            return prev_val;
    }
    else if (cAmaDiff < 0.0)
    {
        if (aAmaDiff < filterValue && low >= (lowest_low - filterDiff))
            return prev_val;
    }

    return current_kama;
}

KAMA_FUNC int KAMA_Color(double current, double previous, int prev_color)
{
    if (current > previous) return 2;
    if (current < previous) return 1;
    return prev_color;
}

KAMA_FUNC double KAMA_GetPrice(KAMAPriceType type, const Candle &c)
{
    switch (type)
    {
        case KAMA_PRICE_OPEN:     return c.open;
        case KAMA_PRICE_HIGH:     return c.high;
        case KAMA_PRICE_LOW:      return c.low;
        case KAMA_PRICE_MEDIAN:   return (c.high + c.low) / 2.0;
        case KAMA_PRICE_TYPICAL:  return (c.high + c.low + c.close) / 3.0;
        case KAMA_PRICE_WEIGHTED: return (c.high + c.low + c.close + c.close) / 4.0;
        case KAMA_PRICE_CLOSE:
        default:                  return c.close;
    }
}

KAMA_FUNC KAMAResult KAMA_FullUpdate(KAMAState &s,
                                      double price,
                                      double high,
                                      double low,
                                      KAMAWindowTracker &hh_tracker,
                                      KAMAWindowTracker &ll_tracker,
                                      int    use_filter,
                                      double inpFilter,
                                      double filterDiff)
{
    KAMAResult result;

    double old_kama  = s._core.prev_kama;
    double old_val   = s._filt.prev_val;
    int    old_color = s._sig.prev_color;

    result.raw_kama = KAMA_Update(s, price);

    if (use_filter != 0)
    {
        double highest_high = 0.0;
        double lowest_low   = 0.0;
        int hh_valid = KAMAWindowTracker_Query(hh_tracker, highest_high);
        int ll_valid = KAMAWindowTracker_Query(ll_tracker, lowest_low);

        if (hh_valid != 0 && ll_valid != 0)
        {
            double fv            = KAMA_FilterValue(s, inpFilter);
            result.filtered_kama = KAMA_ApplyFilter(
                result.raw_kama, old_val,
                high, low,
                highest_high, lowest_low,
                fv, filterDiff, old_kama);
        }
        else
        {
            result.filtered_kama = result.raw_kama;
        }
    }
    else
    {
        result.filtered_kama = result.raw_kama;
    }

    result.signal_color = KAMA_Color(result.filtered_kama, old_val, old_color);

    s._filt.prev_val  = result.filtered_kama;
    s._sig.prev_color = result.signal_color;

    return result;
}

#undef KAMA__DQ_NEXT
#undef KAMA__DQ_PREV
#undef KAMA__DQ_EMPTY

#endif // KAMA_FILTER_H