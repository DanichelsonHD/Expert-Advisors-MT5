#include <windows.h>
#include <math.h>
#include <string.h>
#include <stdio.h>

// =============================================================================
// MeanReversion_Logic.cpp
// Decision engine — compiled as DLL, called by Zorro each bar
// Outputs: 0=HOLD  1=BUY  2=SELL  3=CLOSE
// =============================================================================

#define LOGIC_API __declspec(dllexport)

// -----------------------------------------------------------------------------
// Signal codes
// -----------------------------------------------------------------------------
#define SIGNAL_HOLD  0
#define SIGNAL_BUY   1
#define SIGNAL_SELL  2
#define SIGNAL_CLOSE 3

// -----------------------------------------------------------------------------
// Parameters (set by Zorro via SetParams before each bar)
// -----------------------------------------------------------------------------
struct LogicParams
{
    // RSI
    int    RSI_Period;
    double RSI_Overbought;
    double RSI_Oversold;

    // Bollinger Bands
    int    BB_Period;
    double BB_Deviation;

    // SMAs
    int    SMA_Long_Period;   // 200
    int    SMA_BB_Period;     // = BB_Period
    int    SMA_Medium_Period; // 50

    // Toggles
    int EnableLongs;
    int EnableShorts;
    int EnableWithTrend;
    int EnableAgainstTrend;

    // State window
    int MAX_STATE_BARS;
};

// -----------------------------------------------------------------------------
// Bar snapshot — Zorro fills this and passes it each bar
// All arrays: [0] = current bar, [1] = 1 bar ago, etc.
// Size 10 covers all lookback needs in this strategy
// -----------------------------------------------------------------------------
struct BarSnapshot
{
    double close[10];
    double high[10];
    double low[10];
    double open[10];

    double rsi[10];
    double bbUpper[10];
    double bbLower[10];
    double smaLong[10];    // SMA200
    double smaBB[10];      // SMA21
    double smaMedium[10];  // SMA50

    int    barIndex;       // current Zorro Bar value
    int    numOpenLong;
    int    numOpenShort;
    int    openTradeBar;   // nBarOpen of the oldest open trade (0 if none)
};

// -----------------------------------------------------------------------------
// Internal state (persists across bars — DLL stays loaded)
// -----------------------------------------------------------------------------
static bool  s_longExhausted  = false;
static int   s_longBars       = 0;
static bool  s_shortExhausted = false;
static int   s_shortBars      = 0;
static bool  s_initialized    = false;

// =============================================================================
// DLL boilerplate
// =============================================================================
BOOL APIENTRY DllMain(HMODULE h, DWORD reason, LPVOID r)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        s_longExhausted  = false;
        s_longBars       = 0;
        s_shortExhausted = false;
        s_shortBars      = 0;
        s_initialized    = true;
    }
    return TRUE;
}

// =============================================================================
// Internal: trend regime (slope-confirmed, same as v2.3.0 step 5)
// =============================================================================
static void getRegime(const BarSnapshot* b, bool* isBull, bool* isBear)
{
    bool priceAbove = b->close[0] > b->smaLong[0];
    bool slopeUp    = b->smaLong[0] > b->smaLong[1];
    *isBull =  priceAbove &&  slopeUp;
    *isBear = !priceAbove && !slopeUp;
}

// =============================================================================
// Internal: exhaustion + recovery entry logic (preserved from v2.3.0)
// =============================================================================
static bool checkEntryLong(const BarSnapshot* b, const LogicParams* p)
{
    double bbLow = b->bbLower[0];

    if (!s_longExhausted &&
        b->rsi[0] < p->RSI_Oversold &&
        b->close[0] <= bbLow)
    {
        s_longExhausted = true;
        s_longBars = 0;
    }

    if (s_longExhausted)
        s_longBars++;

    if (s_longBars > p->MAX_STATE_BARS)
        s_longExhausted = false;

    if (s_longExhausted &&
        b->rsi[0] > p->RSI_Oversold &&
        b->close[0] >= bbLow)
    {
        s_longExhausted = false;
        return true;
    }

    return false;
}

static bool checkEntryShort(const BarSnapshot* b, const LogicParams* p)
{
    double bbHigh = b->bbUpper[0];

    if (!s_shortExhausted &&
        b->rsi[0] > p->RSI_Overbought &&
        b->close[0] >= bbHigh)
    {
        s_shortExhausted = true;
        s_shortBars = 0;
    }

    if (s_shortExhausted)
        s_shortBars++;

    if (s_shortBars > p->MAX_STATE_BARS)
        s_shortExhausted = false;

    if (s_shortExhausted &&
        b->rsi[0] < p->RSI_Overbought &&
        b->close[0] <= bbHigh)
    {
        s_shortExhausted = false;
        return true;
    }

    return false;
}

// =============================================================================
// Internal: exit conditions (preserved from v2.3.0 manageTrades logic)
// =============================================================================
static bool shouldCloseLong(const BarSnapshot* b, const LogicParams* p)
{
    // 40-bar duration cap
    if (b->openTradeBar > 0 && (b->barIndex - b->openTradeBar) > 40)
        return true;

    // Overbought exit
    bool overbought = b->rsi[0] >= p->RSI_Overbought ||
                      b->close[0] >= b->bbUpper[0];
    if (overbought)
        return true;

    return false;
}

static bool shouldCloseShort(const BarSnapshot* b, const LogicParams* p)
{
    // 40-bar duration cap
    if (b->openTradeBar > 0 && (b->barIndex - b->openTradeBar) > 40)
        return true;

    // Oversold exit
    bool oversold = b->rsi[0] <= p->RSI_Oversold ||
                    b->close[0] <= b->bbLower[0];
    if (oversold)
        return true;

    return false;
}

// =============================================================================
// EXPORTED FUNCTION: EvaluateBar
// Called by Zorro every bar. Returns signal integer.
// Zorro passes in current indicators + state; DLL returns decision.
// =============================================================================
extern "C" LOGIC_API int EvaluateBar(
    const BarSnapshot* bar,
    const LogicParams* params)
{
    if (!bar || !params) return SIGNAL_HOLD;

    bool isBull, isBear;
    getRegime(bar, &isBull, &isBear);

    // ------------------------------------------------------------------
    // CLOSE check — runs before entry, same priority as v2.3.0
    // ------------------------------------------------------------------
    if (bar->numOpenLong > 0 && shouldCloseLong(bar, params))
        return SIGNAL_CLOSE;

    if (bar->numOpenShort > 0 && shouldCloseShort(bar, params))
        return SIGNAL_CLOSE;

    // ------------------------------------------------------------------
    // LONG entry
    // ------------------------------------------------------------------
    if (bar->numOpenLong == 0 && params->EnableLongs)
    {
        bool isWithTrend    = isBull;
        bool isAgainstTrend = isBear;

        bool gateOk = (!isWithTrend    || params->EnableWithTrend) &&
                      (!isAgainstTrend || params->EnableAgainstTrend);

        if (gateOk && checkEntryLong(bar, params))
            return SIGNAL_BUY;
    }

    // ------------------------------------------------------------------
    // SHORT entry
    // ------------------------------------------------------------------
    if (bar->numOpenShort == 0 && params->EnableShorts)
    {
        bool isWithTrend    = isBear;
        bool isAgainstTrend = isBull;

        bool gateOk = (!isWithTrend    || params->EnableWithTrend) &&
                      (!isAgainstTrend || params->EnableAgainstTrend);

        if (gateOk && checkEntryShort(bar, params))
            return SIGNAL_SELL;
    }

    return SIGNAL_HOLD;
}

// =============================================================================
// EXPORTED FUNCTION: ResetState
// Call when starting a new backtest run to clear static state
// =============================================================================
extern "C" LOGIC_API void ResetState()
{
    s_longExhausted  = false;
    s_longBars       = 0;
    s_shortExhausted = false;
    s_shortBars      = 0;
}

// =============================================================================
// EXPORTED FUNCTION: GetLogicVersion
// =============================================================================
extern "C" LOGIC_API int GetLogicVersion()
{
    return 230; // v2.3.0
}
