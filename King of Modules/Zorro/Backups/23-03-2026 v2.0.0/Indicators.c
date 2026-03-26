// =========================================================
// FILE: Indicators.c
// ROLE: Single source of truth — series storage,
//       indicator computation, signal functions
// =========================================================

#ifndef INDICATORS_C
#define INDICATORS_C

// ---------------------------------------------------------
// GLOBAL SERIES — all read via getter functions only
// ---------------------------------------------------------
vars g_Close;
vars g_EMA20;
vars g_EMA50;
vars g_RSI14;
vars g_ATR14;
vars g_ATR50;
vars g_ADX14;
vars g_BBUpper;
vars g_BBLower;
vars g_KCUpper;
vars g_KCLower;
vars g_STValue;
vars g_STState;

// ---------------------------------------------------------
// SUPERTREND — internal persistent state
// ---------------------------------------------------------
static var _st_prevFinalUpper = 0.0;
static var _st_prevFinalLower = 0.0;
static var _st_prevST         = 0.0;
static int _st_initialized    = 0;

// ---------------------------------------------------------
// UTILITY: Highest high / lowest low over N previous bars
//          index 1 = most recent completed bar (excludes [0])
// ---------------------------------------------------------
var HighestHigh(int period)
{
    var hi = High[1];
    int i;
    for(i = 2; i <= period; i++)
        if(High[i] > hi) hi = High[i];
    return hi;
}

var LowestLow(int period)
{
    var lo = Low[1];
    int i;
    for(i = 2; i <= period; i++)
        if(Low[i] < lo) lo = Low[i];
    return lo;
}

// ---------------------------------------------------------
// SUPERTREND — internal bar-by-bar computation
// ---------------------------------------------------------
void UpdateSuperTrend()
{
    var hl2        = (High[0] + Low[0]) / 2.0;
    var atrVal     = ATR(ST_Period);
    var basicUpper = hl2 + ST_Mult * atrVal;
    var basicLower = hl2 - ST_Mult * atrVal;

    var finalUpper, finalLower, stVal;
    int stState;

    if(!_st_initialized)
    {
        finalUpper      = basicUpper;
        finalLower      = basicLower;
        stVal           = basicUpper;   // start bearish
        stState         = -1;
        _st_initialized = 1;
    }
    else
    {
        // FinalUpper: only move down, or reset on breach
        finalUpper = (basicUpper < _st_prevFinalUpper || Close[1] > _st_prevFinalUpper)
                     ? basicUpper : _st_prevFinalUpper;

        // FinalLower: only move up, or reset on breach
        finalLower = (basicLower > _st_prevFinalLower || Close[1] < _st_prevFinalLower)
                     ? basicLower : _st_prevFinalLower;

        if(_st_prevST == _st_prevFinalUpper)    // previous: bearish
        {
            if(Close[0] > finalUpper) {
                stVal   = finalLower;            // flip → bullish
                stState = 1;
            } else {
                stVal   = finalUpper;            // stay bearish
                stState = -1;
            }
        }
        else                                    // previous: bullish
        {
            if(Close[0] < finalLower) {
                stVal   = finalUpper;            // flip → bearish
                stState = -1;
            } else {
                stVal   = finalLower;            // stay bullish
                stState = 1;
            }
        }
    }

    _st_prevFinalUpper = finalUpper;
    _st_prevFinalLower = finalLower;
    _st_prevST         = stVal;

    g_STValue = series(stVal);
    g_STState = series((var)stState);
}

// ---------------------------------------------------------
// UPDATE ALL SERIES — raw price wrapper (called first)
// ---------------------------------------------------------
void UpdateAllSeries()
{
    // Wrap Zorro's built-in Close array into a tracked series
    // NOTE: Indicator computations use Close[] directly for
    //       full historical warmup; g_Close provides getter access
    g_Close = series(Close[0]);
}

// ---------------------------------------------------------
// UPDATE INDICATORS — all derived computations
// NOTE: EMA / RSI / SMA / StdDev use Close[] (Zorro built-in
//       vars array) so warmup is fully handled by Zorro
//       through the LookBack period.
// ---------------------------------------------------------
void UpdateIndicators()
{
    // --- EMA ---
    g_EMA20 = series(EMA(Close, EMA_Fast));
    g_EMA50 = series(EMA(Close, EMA_Slow));

    // --- RSI ---
    g_RSI14 = series(RSI(Close, RSI_Period));

    // --- ATR (uses built-in High / Low / Close) ---
    g_ATR14 = series(ATR(ATR_Period_1));
    g_ATR50 = series(ATR(ATR_Period_2));

    // --- ADX (uses built-in High / Low / Close) ---
    g_ADX14 = series(ADX(ADX_Period));

    // --- Bollinger Bands ---
    {
        var bbMid = SMA(Close, BB_Period);
        var bbStd = StdDev(Close, BB_Period);
        g_BBUpper = series(bbMid + BB_StdDev * bbStd);
        g_BBLower = series(bbMid - BB_StdDev * bbStd);
    }

    // --- Keltner Channel ---
    {
        var kcMid = EMA(Close, KC_Period);
        var kcAtr = ATR(KC_Period);
        g_KCUpper = series(kcMid + KC_Mult * kcAtr);
        g_KCLower = series(kcMid - KC_Mult * kcAtr);
    }

    // --- SuperTrend ---
    UpdateSuperTrend();
}

// ---------------------------------------------------------
// DATA ACCESS FUNCTIONS
// ---------------------------------------------------------
var getClose()   { return g_Close[0];   }
var getEMA20()   { return g_EMA20[0];   }
var getEMA50()   { return g_EMA50[0];   }
var getRSI()     { return g_RSI14[0];   }
var getATR14()   { return g_ATR14[0];   }
var getATR50()   { return g_ATR50[0];   }
var getADX()     { return g_ADX14[0];   }
var getBBUpper() { return g_BBUpper[0]; }
var getBBLower() { return g_BBLower[0]; }
var getKCUpper() { return g_KCUpper[0]; }
var getKCLower() { return g_KCLower[0]; }

int getSTState()     { return (int)g_STState[0]; }
int getSTPrevState() { return (int)g_STState[1]; }

// ---------------------------------------------------------
// SIGNAL FUNCTIONS — VOLATILITY
// ---------------------------------------------------------
int isVolatilityHigh() { return g_ATR14[0] > g_ATR50[0]; }
int isVolatilityLow()  { return g_ATR14[0] < g_ATR50[0]; }

// ---------------------------------------------------------
// SIGNAL FUNCTIONS — REGIME
// ---------------------------------------------------------
int isTrending()   { return g_ADX14[0] >= ADX_Trending_Min; }
int isRanging()    { return g_ADX14[0] <  ADX_Ranging_Max;  }
int isTransition() { return (g_ADX14[0] >= ADX_Ranging_Max &&
                             g_ADX14[0] <  ADX_Trending_Min);  }

// ---------------------------------------------------------
// SIGNAL FUNCTIONS — BB + KC
// ---------------------------------------------------------
int isSqueeze()   { return (g_BBUpper[0] < g_KCUpper[0] &&
                            g_BBLower[0] > g_KCLower[0]); }
int isExpansion() { return !isSqueeze(); }

// ---------------------------------------------------------
// SIGNAL FUNCTIONS — EXHAUSTION (Price-based)
// Close below BOTH BB lower AND KC lower → exhaustion buy
// Close above BOTH BB upper AND KC upper → exhaustion sell
// ---------------------------------------------------------
int isExhaustionBuy()
{
    return (Close[0] < g_BBLower[0] && Close[0] < g_KCLower[0]);
}

int isExhaustionSell()
{
    return (Close[0] > g_BBUpper[0] && Close[0] > g_KCUpper[0]);
}

// ---------------------------------------------------------
// SIGNAL FUNCTIONS — RSI (parametric)
// ---------------------------------------------------------
int isOverbought(var level) { return g_RSI14[0] > level; }
int isOversold(var level)   { return g_RSI14[0] < level; }

int isOverboughtDefault() { return isOverbought(RSI_Overbought_Default); }
int isOversoldDefault()   { return isOversold(RSI_Oversold_Default);     }

// ---------------------------------------------------------
// SIGNAL FUNCTIONS — SUPERTREND
// ---------------------------------------------------------
int isSTBull()     { return getSTState()     ==  1; }
int isSTBear()     { return getSTState()     == -1; }
int isSTFlipBull() { return (getSTState() ==  1 && getSTPrevState() == -1); }
int isSTFlipBear() { return (getSTState() == -1 && getSTPrevState() ==  1); }

// ---------------------------------------------------------
// SIGNAL FUNCTIONS — EMA
// ---------------------------------------------------------
int isAboveEMA50() { return Close[0] > g_EMA50[0]; }
int isBelowEMA50() { return Close[0] < g_EMA50[0]; }

// ---------------------------------------------------------
// SIGNAL FUNCTIONS — EXTENDED (used by specific strategies)
// ---------------------------------------------------------

// BO: ADX expanding
int isADXRising() { return g_ADX14[0] > g_ADX14[1]; }

// BO: Structure breaks
int isStructureBreakUp()   { return Close[0] > HighestHigh(BO_StructureLookback); }
int isStructureBreakDown() { return Close[0] < LowestLow(BO_StructureLookback);   }

// PB: Price within PB_EMAProximityPct% of EMA20
int isPriceNearEMA20()
{
    var ema  = g_EMA20[0];
    if(ema == 0.0) return 0;
    var dist = (Close[0] - ema);
    if(dist < 0.0) dist = -dist;    // fabs
    return (dist / ema * 100.0) <= PB_EMAProximityPct;
}

// PB: RSI in neutral zone [PB_RSI_Low, PB_RSI_High]
int isRSINeutral()
{
    return (g_RSI14[0] >= PB_RSI_Low && g_RSI14[0] <= PB_RSI_High);
}

#endif // INDICATORS_C
