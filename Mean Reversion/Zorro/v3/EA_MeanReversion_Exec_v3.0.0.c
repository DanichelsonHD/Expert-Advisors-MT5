// =============================================================================
// MeanReversion_Exec.c
// Zorro execution wrapper — ZERO strategy logic
// Reads signal from MeanReversion_Logic.dll and executes
// =============================================================================

#include <zorro.h>

// -----------------------------------------------------------------------------
// DLL structs — must mirror MeanReversion_Logic.cpp exactly
// Lite-C has no bool: use int (0/1)
// -----------------------------------------------------------------------------
typedef struct {
    double close[10];
    double high[10];
    double low[10];
    double open[10];
    double rsi[10];
    double bbUpper[10];
    double bbLower[10];
    double smaLong[10];
    double smaBB[10];
    double smaMedium[10];
    int    barIndex;
    int    numOpenLong;
    int    numOpenShort;
    int    openTradeBar;
} BarSnapshot;

typedef struct {
    int    RSI_Period;
    double RSI_Overbought;
    double RSI_Oversold;
    int    BB_Period;
    double BB_Deviation;
    int    SMA_Long_Period;
    int    SMA_BB_Period;
    int    SMA_Medium_Period;
    int    EnableLongs;
    int    EnableShorts;
    int    EnableWithTrend;
    int    EnableAgainstTrend;
    int    MAX_STATE_BARS;
} LogicParams;

// =============================================================================
// DLL function declarations
// Zorro loads these from EA_MeanReversion_Logic_v3.dll at startup
// =============================================================================
int   EvaluateBar(BarSnapshot* bar, LogicParams* params);
void  ResetState(void);
int   GetLogicVersion(void);

// -----------------------------------------------------------------------------
// Signal codes
// -----------------------------------------------------------------------------
#define SIGNAL_HOLD  0
#define SIGNAL_BUY   1
#define SIGNAL_SELL  2
#define SIGNAL_CLOSE 3

// -----------------------------------------------------------------------------
// Stop / TP configuration (execution-layer only, no strategy logic)
// -----------------------------------------------------------------------------
var  Exec_Stop_Buffer;
var  Exec_Stop_Lookback;
var  Exec_Safety_TP;

// -----------------------------------------------------------------------------
// Series (needed to populate BarSnapshot for DLL)
// -----------------------------------------------------------------------------
vars _close, _high, _low, _open;
vars _rsi, _bbUpper, _bbLower;
vars _smaLong, _smaBB, _smaMedium;

// -----------------------------------------------------------------------------
// Active params struct (filled once in run, reused)
// -----------------------------------------------------------------------------
LogicParams gParams;

// =============================================================================
// setupParams — mirrors v2.3.0 optimizeCalls, no optimize() here
// To run optimization, expose these via Zorro's slider or optimize() as needed
// =============================================================================
void setupParams()
{
    gParams.RSI_Period        = 4;
    gParams.RSI_Overbought    = 75;
    gParams.RSI_Oversold      = 25;
    gParams.BB_Period         = 21;
    gParams.BB_Deviation      = 2.0;
    gParams.SMA_Long_Period   = 200;
    gParams.SMA_BB_Period     = 21;   // = BB_Period
    gParams.SMA_Medium_Period = 50;
    gParams.EnableLongs       = 1;
    gParams.EnableShorts      = 1;
    gParams.EnableWithTrend   = 1;
    gParams.EnableAgainstTrend= 0;
    gParams.MAX_STATE_BARS    = 3;

    // Execution-layer stop config
    Exec_Stop_Lookback = 4;
    Exec_Stop_Buffer   = 130 / 10.0 * PIP;
    Exec_Safety_TP     = 0;  // 0 = disabled; set to e.g. 10*ATR(14) if needed
}

// =============================================================================
// setRun() — Initial Zorro setup (called once at startup)
// =============================================================================
void setRun()
{
    // Zorro initialization
    BarPeriod = 15;              // 15-minute bars
    StartDate = 20230101;        // Start date
    Capital   = 10000;           // Account size
    LookBack  = 400;             // Must be >= SMA(200) + buffer = 199 + 100
    NumCores  = 4;
    Slippage  = 2;

    
    // Trade constraints (critical for single-trade management)
    MaxLong   = 1;               // Max 1 long trade
    MaxShort  = 1;               // Max 1 short trade
    
    // Risk and behavior
    //RiskLimit = 99999;           // Unlimited for testing
    
    set(PARAMETERS | PLOTNOW | LOGFILE | TICKS);

    // Initialize parameters
    setupParams();
}

// =============================================================================
// defineSeries
// =============================================================================
void defineSeries()
{
    _close    = series(priceClose(0));
    _high     = series(priceHigh(0));
    _low      = series(priceLow(0));
    _open     = series(priceOpen(0));

    // Order matters: define longest period first (SMA 200)
    _smaLong  = series(SMA(_close, 200));    // Must be called before other SMA
    _rsi      = series(RSI(_close, 4));      // RSI(4)
    _bbUpper  = series(BBands(_close, 21, 2.0, 2.0, 0));
    _bbLower  = series(BBands(_close, 21, -2.0, -2.0, 0));
    _smaBB    = series(SMA(_close, 21));
    _smaMedium= series(SMA(_close, 50));
}

// =============================================================================
// fillSnapshot — populates BarSnapshot from Zorro series for DLL call
// =============================================================================
void fillSnapshot(BarSnapshot* b)
{
    int i;
    
    // Safeguard: check if series are ready (have valid data)
    if (!_close || !_rsi || !_bbUpper || !_bbLower || 
        !_smaLong || !_smaBB || !_smaMedium)
    {
        // Series not initialized yet
        b->barIndex = Bar;
        b->numOpenLong = NumOpenLong;
        b->numOpenShort = NumOpenShort;
        b->openTradeBar = 0;
        return;
    }
    
    for (i = 0; i < 10; i++)
    {
        b->close[i]    = _close[i];
        b->high[i]     = _high[i];
        b->low[i]      = _low[i];
        b->open[i]     = _open[i];
        b->rsi[i]      = _rsi[i];
        b->bbUpper[i]  = _bbUpper[i];
        b->bbLower[i]  = _bbLower[i];
        b->smaLong[i]  = _smaLong[i];
        b->smaBB[i]    = _smaBB[i];
        b->smaMedium[i]= _smaMedium[i];
    }

    b->barIndex     = Bar;
    b->numOpenLong  = NumOpenLong;
    b->numOpenShort = NumOpenShort;

    // Find nBarOpen of the first open trade for duration check
    b->openTradeBar = 0;
    TRADE* tr = forTrade(0);
    if (tr && (tr->flags & TR_OPEN))
        b->openTradeBar = tr->nBarOpen;
}

// =============================================================================
// executeSignal — pure execution, zero decision logic
// =============================================================================
void executeSignal(int signal)
{
    if (signal == SIGNAL_CLOSE)
    {
        exitLong();
        exitShort();
        return;
    }

    if (signal == SIGNAL_BUY && NumOpenLong == 0)
    {
        Stop       = MinVal(_low, Exec_Stop_Lookback) - Exec_Stop_Buffer;
        TakeProfit = Exec_Safety_TP;
        enterLong();
        return;
    }

    if (signal == SIGNAL_SELL && NumOpenShort == 0)
    {
        Stop       = MaxVal(_high, Exec_Stop_Lookback) + Exec_Stop_Buffer;
        TakeProfit = Exec_Safety_TP;
        enterShort();
        return;
    }
    // SIGNAL_HOLD: do nothing
}

// =============================================================================
// run() — execution engine only
// =============================================================================
DLLFUNC void run()
{
    static int initialized = 0;

    // Initialize once per test run (parameters only)
    if (!initialized)
    {
        initialized = 1;
        setupParams();
    }

    // Define series EVERY bar (Zorro requirement)
    // series() must be called every bar to maintain history
    defineSeries();

    plot("BB_Upper",   _bbUpper,  MAIN | LINE, BLUE);
    plot("BB_Lower",   _bbLower,  MAIN | LINE, BLUE);
    plot("SMA200",     _smaLong,  MAIN | LINE, ORANGE);
    plot("SMABB",     _smaBB,  MAIN | LINE, BLUE);
    plot("RSI",        _rsi,      NEW  | LINE, RED);

    // Wait for enough bars (SMA(200) requires 199+ bars of history)
    if (Bar < 200) return;

    // Fill snapshot and ask DLL for decision
    BarSnapshot snap;
    fillSnapshot(&snap);

    // Only call DLL if snapshot has valid data
    if (snap.barIndex > 0)
    {
        int signal = EvaluateBar(&snap, &gParams);
        
        // Execute whatever the DLL decided
        executeSignal(signal);
    }
}
