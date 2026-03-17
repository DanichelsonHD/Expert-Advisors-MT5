///////////////////////////////////////////////////////////////////////////////
// KingOfModules_DLL.c
// Zorro script — uses bridge.dll (Python embedded) instead of socket
//
// Use this file if you compiled bridge_dll.c into bridge.dll.
// Place bridge.dll in Zorro/Strategy/.
///////////////////////////////////////////////////////////////////////////////

#include <default.c>

// DLL function declarations
int  bridge_init(string params_json);
int  bridge_bar(string bar_json);
void bridge_reset();
void bridge_quit();

///////////////////////////////////////////////////////////////////////////////
// PARAMETERS (same as KingOfModules.c)
///////////////////////////////////////////////////////////////////////////////
var p_use_mr          = 1;
var p_use_kt          = 0;
var p_stop_mode       = 0;
var p_stop_multiplier = 2.0;
var p_extra_points    = 5;
var p_lot_size        = 0.1;
var p_rsi_period      = 14;
var p_rsi_oversold    = 30.0;
var p_rsi_overbought  = 70.0;
var p_rsi_reset_thr   = 20.0;
var p_atr_period      = 14;
var p_atr_mr_mult     = 1.01;
var p_atr_kt_mult     = 0.775;
var p_kama_period     = 14;
var p_kama_fast       = 2;
var p_kama_slow       = 30;
var p_keltner_ema     = 20;
var p_keltner_factor  = 2.0;
var p_adx_period      = 14;
var p_adx_comparison  = 22.0;
var p_use_tp          = 0;
var p_tp_multiplier   = 2.0;
var p_max_trades      = 2;

int g_initialized = 0;

///////////////////////////////////////////////////////////////////////////////
// Reuse helpers from KingOfModules.c
///////////////////////////////////////////////////////////////////////////////

string build_init_cmd()
{
    string s[4096];
    sprintf(s,
        "{\"lot_size\":%.4f,"
        "\"magic_number\":123456,"
        "\"max_simultaneous_trades\":%d,"
        "\"use_mr_strategy\":%s,"
        "\"use_kt_strategy\":%s,"
        "\"use_tb_strategy\":false,"
        "\"use_tp_strategy\":false,"
        "\"stop_mode\":%d,"
        "\"stop_multiplier\":%.4f,"
        "\"extra_points\":%d,"
        "\"use_take_profit\":%s,"
        "\"tp_multiplier\":%.4f,"
        "\"rsi_period\":%d,"
        "\"rsi_oversold\":%.2f,"
        "\"rsi_overbought\":%.2f,"
        "\"rsi_reset_threshold\":%.2f,"
        "\"atr_period\":%d,"
        "\"atr_mr_trend_multiplier\":%.4f,"
        "\"atr_kt_trend_multiplier\":%.4f,"
        "\"kama_period\":%d,"
        "\"kama_fast_period\":%d,"
        "\"kama_slow_period\":%d,"
        "\"keltner_ema_period\":%d,"
        "\"keltner_atr_factor\":%.4f,"
        "\"adx_period\":%d,"
        "\"adx_comparison\":%.2f,"
        "\"use_atr_mr_trend_filter\":true,"
        "\"use_atr_kt_trend_filter\":true,"
        "\"use_adx_filter\":true"
        "}",
        p_lot_size, (int)p_max_trades,
        p_use_mr >= 0.5 ? "true" : "false",
        p_use_kt >= 0.5 ? "true" : "false",
        (int)p_stop_mode, p_stop_multiplier, (int)p_extra_points,
        p_use_tp >= 0.5 ? "true" : "false", p_tp_multiplier,
        (int)p_rsi_period, p_rsi_oversold, p_rsi_overbought, p_rsi_reset_thr,
        (int)p_atr_period, p_atr_mr_mult, p_atr_kt_mult,
        (int)p_kama_period, (int)p_kama_fast, (int)p_kama_slow,
        (int)p_keltner_ema, p_keltner_factor,
        (int)p_adx_period, p_adx_comparison
    );
    return s;
}

string build_bar_cmd()
{
    string s[512];
    sprintf(s,
        "{\"time\":%d,\"open\":%.6f,\"high\":%.6f,"
        "\"low\":%.6f,\"close\":%.6f,\"volume\":%.2f}",
        (int)bar(Time, 1),
        priceO(1), priceH(1), priceL(1), priceC(1), marketVol(1)
    );
    return s;
}

var calc_atr_stop(int direction)
{
    var atr_val   = ATR(p_atr_period);
    var stop_dist = atr_val * p_stop_multiplier + p_extra_points * Pip;
    if(direction == 1)  return priceC(1) - stop_dist;
    else                return priceC(1) + stop_dist;
}

var calc_atr_tp(int direction)
{
    if(p_use_tp < 0.5) return 0;
    var atr_val = ATR(p_atr_period);
    var tp_dist = atr_val * p_tp_multiplier;
    if(direction == 1) return priceC(1) + tp_dist;
    else               return priceC(1) - tp_dist;
}

void manage_trailing()
{
    if((int)p_stop_mode != 2) return;
    var atr_val    = ATR(p_atr_period);
    var trail_dist = atr_val * p_stop_multiplier + p_extra_points * Pip;
    for(open_trades) {
        if(TradeIsLong) {
            var new_sl = priceC(0) - trail_dist;
            if(new_sl > TradeStopLimit) TradeStopLimit = new_sl;
        } else {
            var new_sl = priceC(0) + trail_dist;
            if(TradeStopLimit == 0 || new_sl < TradeStopLimit)
                TradeStopLimit = new_sl;
        }
    }
}

int count_open_trades() { int n=0; for(open_trades) n++; return n; }

///////////////////////////////////////////////////////////////////////////////
// MAIN
///////////////////////////////////////////////////////////////////////////////

function run()
{
    if(is(INITRUN))
    {
        asset("EURUSD");
        BarPeriod  = 60;
        LookBack   = 200;
        StartDate  = 20220101;
        EndDate    = 20241231;
        Leverage   = 30;
        Spread     = 1.0 * Pip;

        // Optimization sliders (uncomment to sweep)
        // slider(1, p_rsi_period,     10, 20, 1, "RSI Period");
        // slider(2, p_rsi_oversold,   20, 40, 5, "RSI Oversold");
        // slider(3, p_stop_multiplier, 1.0, 3.0, 0.25, "Stop Mult");
        // slider(4, p_atr_mr_mult,    0.8, 1.2, 0.05, "ATR MR Mult");

        // Load DLL (must be in Zorro/Strategy/ folder)
        if(!load_library("bridge.dll")) {
            quit("Cannot load bridge.dll — compile it first.");
            return;
        }

        string init_json = build_init_cmd();
        if(!bridge_init(init_json)) {
            quit("bridge_init() failed.");
            return;
        }

        g_initialized = 1;
        printf("Bridge DLL: Init OK.");
        return;
    }

    if(is(EXITRUN))
    {
        bridge_quit();
        printf("Bridge DLL: Quit.");
        return;
    }

    if(is(FIRSTRUN))
    {
        bridge_reset();
        string init_json = build_init_cmd();
        bridge_init(init_json);
    }

    if(!g_initialized) return;

    manage_trailing();

    string bar_json = build_bar_cmd();
    int signal = bridge_bar(bar_json);

    if(signal == 0) return;
    if(count_open_trades() >= (int)p_max_trades) return;

    var sl, tp;

    if(signal == 1) {
        sl = calc_atr_stop(1);
        tp = calc_atr_tp(1);
        if(NumOpenLong > 0) return;
        enterLong(p_lot_size, 0, sl, tp > 0 ? tp - priceC(1) : 0);
    }
    else if(signal == -1) {
        sl = calc_atr_stop(-1);
        tp = calc_atr_tp(-1);
        if(NumOpenShort > 0) return;
        enterShort(p_lot_size, 0, sl, tp > 0 ? priceC(1) - tp : 0);
    }
}
