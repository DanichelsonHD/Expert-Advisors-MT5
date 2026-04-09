//+------------------------------------------------------------------+
//|                                   MR_VisualDiagnostic_v1.mq5    |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers     7
#property indicator_plots       6

#property indicator_label1      "KC Upper"
#property indicator_type1       DRAW_LINE
#property indicator_color1      clrSteelBlue
#property indicator_style1      STYLE_SOLID
#property indicator_width1      1

#property indicator_label2      "KC Lower"
#property indicator_type2       DRAW_LINE
#property indicator_color2      clrSteelBlue
#property indicator_style2      STYLE_SOLID
#property indicator_width2      1

#property indicator_label3      "KC Mid"
#property indicator_type3       DRAW_LINE
#property indicator_color3      clrSlateGray
#property indicator_style3      STYLE_DOT
#property indicator_width3      1

#property indicator_label4      "KAMA"
#property indicator_type4       DRAW_COLOR_LINE
#property indicator_color4      clrLime,clrRed,clrGray
#property indicator_style4      STYLE_SOLID
#property indicator_width4      2

#property indicator_label5      "Buy Signal"
#property indicator_type5       DRAW_ARROW
#property indicator_color5      clrDodgerBlue
#property indicator_width5      2

#property indicator_label6      "Sell Signal"
#property indicator_type6       DRAW_ARROW
#property indicator_color6      clrOrangeRed
#property indicator_width6      2

//--- Object prefix
#define OBJ_PFX "MR_VD1_"

//--- Inputs
input group  "=== Keltner Channel ==="
input int    KC_EMA_Period        = 20;
input int    KC_ATR_Period        = 10;
input double KC_Multiplier        = 1.5;

input group  "=== ATR Stop Model ==="
input int    ATR_Period           = 14;
input double ATR_Multiplier       = 2.0;
input int    Stop_Buffer_Points   = 0;

input group  "=== KAMA With Filter ==="
input int    KAMA_Period          = 10;
input int    KAMA_Fast            = 2;
input int    KAMA_Slow            = 30;
input int    KAMA_Filter_Period   = 5;

input group  "=== RSI (Signal Markers) ==="
input int    RSI_Period           = 14;
input double RSI_Overbought       = 70.0;
input double RSI_Oversold         = 30.0;

input group  "=== Visual Controls ==="
input bool   Show_ATR_Stop_Lines  = true;
input bool   Show_Regime_Label    = true;
input bool   Show_Signal_Markers  = true;

//--- Buffers
double g_kc_upper[];
double g_kc_lower[];
double g_kc_mid[];
double g_kama[];
double g_kama_clr[];
double g_buy[];
double g_sell[];

//--- Handles
int g_kc_ema_handle    = INVALID_HANDLE;
int g_kc_atr_handle    = INVALID_HANDLE;
int g_atr_stop_handle  = INVALID_HANDLE;
int g_rsi_handle       = INVALID_HANDLE;

//--- State
int g_prev_bars = 0;

//+------------------------------------------------------------------+
void CreateObjects()
{
    if(Show_ATR_Stop_Lines)
    {
        if(ObjectFind(0, OBJ_PFX "ATR_Long") < 0)
        {
            ObjectCreate(0, OBJ_PFX "ATR_Long", OBJ_HLINE, 0, 0, 0.0);
            ObjectSetInteger(0, OBJ_PFX "ATR_Long", OBJPROP_COLOR,      clrLimeGreen);
            ObjectSetInteger(0, OBJ_PFX "ATR_Long", OBJPROP_STYLE,      STYLE_DASH);
            ObjectSetInteger(0, OBJ_PFX "ATR_Long", OBJPROP_WIDTH,      1);
            ObjectSetInteger(0, OBJ_PFX "ATR_Long", OBJPROP_SELECTABLE, false);
            ObjectSetString (0, OBJ_PFX "ATR_Long", OBJPROP_TOOLTIP,    "ATR Long Stop");
        }
        if(ObjectFind(0, OBJ_PFX "ATR_Short") < 0)
        {
            ObjectCreate(0, OBJ_PFX "ATR_Short", OBJ_HLINE, 0, 0, 0.0);
            ObjectSetInteger(0, OBJ_PFX "ATR_Short", OBJPROP_COLOR,      clrOrangeRed);
            ObjectSetInteger(0, OBJ_PFX "ATR_Short", OBJPROP_STYLE,      STYLE_DASH);
            ObjectSetInteger(0, OBJ_PFX "ATR_Short", OBJPROP_WIDTH,      1);
            ObjectSetInteger(0, OBJ_PFX "ATR_Short", OBJPROP_SELECTABLE, false);
            ObjectSetString (0, OBJ_PFX "ATR_Short", OBJPROP_TOOLTIP,    "ATR Short Stop");
        }
    }

    if(ObjectFind(0, OBJ_PFX "ATR_Label") < 0)
    {
        ObjectCreate(0, OBJ_PFX "ATR_Label", OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, OBJ_PFX "ATR_Label", OBJPROP_CORNER,     CORNER_LEFT_UPPER);
        ObjectSetInteger(0, OBJ_PFX "ATR_Label", OBJPROP_XDISTANCE,  10);
        ObjectSetInteger(0, OBJ_PFX "ATR_Label", OBJPROP_YDISTANCE,  20);
        ObjectSetInteger(0, OBJ_PFX "ATR_Label", OBJPROP_COLOR,      clrWhite);
        ObjectSetInteger(0, OBJ_PFX "ATR_Label", OBJPROP_FONTSIZE,   9);
        ObjectSetInteger(0, OBJ_PFX "ATR_Label", OBJPROP_SELECTABLE, false);
        ObjectSetString (0, OBJ_PFX "ATR_Label", OBJPROP_TEXT,       "ATR: --");
    }

    if(Show_Regime_Label)
    {
        if(ObjectFind(0, OBJ_PFX "Regime") < 0)
        {
            ObjectCreate(0, OBJ_PFX "Regime", OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, OBJ_PFX "Regime", OBJPROP_CORNER,     CORNER_LEFT_UPPER);
            ObjectSetInteger(0, OBJ_PFX "Regime", OBJPROP_XDISTANCE,  10);
            ObjectSetInteger(0, OBJ_PFX "Regime", OBJPROP_YDISTANCE,  38);
            ObjectSetInteger(0, OBJ_PFX "Regime", OBJPROP_COLOR,      clrYellow);
            ObjectSetInteger(0, OBJ_PFX "Regime", OBJPROP_FONTSIZE,   9);
            ObjectSetInteger(0, OBJ_PFX "Regime", OBJPROP_SELECTABLE, false);
            ObjectSetString (0, OBJ_PFX "Regime", OBJPROP_TEXT,       "--");
        }
    }
}

//+------------------------------------------------------------------+
void DeleteObjects()
{
    ObjectDelete(0, OBJ_PFX "ATR_Long");
    ObjectDelete(0, OBJ_PFX "ATR_Short");
    ObjectDelete(0, OBJ_PFX "ATR_Label");
    ObjectDelete(0, OBJ_PFX "Regime");
}

//+------------------------------------------------------------------+
int OnInit()
{
    SetIndexBuffer(0, g_kc_upper,  INDICATOR_DATA);
    SetIndexBuffer(1, g_kc_lower,  INDICATOR_DATA);
    SetIndexBuffer(2, g_kc_mid,    INDICATOR_DATA);
    SetIndexBuffer(3, g_kama,      INDICATOR_DATA);
    SetIndexBuffer(4, g_kama_clr,  INDICATOR_COLOR_INDEX);
    SetIndexBuffer(5, g_buy,       INDICATOR_DATA);
    SetIndexBuffer(6, g_sell,      INDICATOR_DATA);

    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);

    PlotIndexSetInteger(4, PLOT_ARROW,       233);
    PlotIndexSetInteger(5, PLOT_ARROW,       234);
    PlotIndexSetInteger(4, PLOT_ARROW_SHIFT,  5);
    PlotIndexSetInteger(5, PLOT_ARROW_SHIFT, -5);

    if(!Show_Signal_Markers)
    {
        PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_NONE);
        PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_NONE);
    }

    g_kc_ema_handle   = iMA  (_Symbol, PERIOD_CURRENT, KC_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    g_kc_atr_handle   = iATR (_Symbol, PERIOD_CURRENT, KC_ATR_Period);
    g_atr_stop_handle = iATR (_Symbol, PERIOD_CURRENT, ATR_Period);
    g_rsi_handle      = iRSI (_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);

    if(g_kc_ema_handle   == INVALID_HANDLE ||
       g_kc_atr_handle   == INVALID_HANDLE ||
       g_atr_stop_handle == INVALID_HANDLE ||
       g_rsi_handle      == INVALID_HANDLE)
    {
        Print("MR_VisualDiagnostic_v1: Handle creation failed.");
        return INIT_FAILED;
    }

    CreateObjects();

    IndicatorSetString(INDICATOR_SHORTNAME, "MR_VisualDiag_v1");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_kc_ema_handle   != INVALID_HANDLE) { IndicatorRelease(g_kc_ema_handle);   g_kc_ema_handle   = INVALID_HANDLE; }
    if(g_kc_atr_handle   != INVALID_HANDLE) { IndicatorRelease(g_kc_atr_handle);   g_kc_atr_handle   = INVALID_HANDLE; }
    if(g_atr_stop_handle != INVALID_HANDLE) { IndicatorRelease(g_atr_stop_handle); g_atr_stop_handle = INVALID_HANDLE; }
    if(g_rsi_handle      != INVALID_HANDLE) { IndicatorRelease(g_rsi_handle);      g_rsi_handle      = INVALID_HANDLE; }

    DeleteObjects();
}

//+------------------------------------------------------------------+
double ComputeKAMAStep(const double &close[],
                       const double  prev_kama,
                       const int     bar,
                       const double  fast_sc,
                       const double  slow_sc)
{
    double direction  = MathAbs(close[bar] - close[bar - KAMA_Period]);
    double volatility = 0.0;

    for(int k = bar - KAMA_Period + 1; k <= bar; k++)
        volatility += MathAbs(close[k] - close[k - 1]);

    double er = (volatility > 0.0) ? (direction / volatility) : 0.0;
    double sc = MathPow(er * (fast_sc - slow_sc) + slow_sc, 2.0);

    return prev_kama + sc * (close[bar] - prev_kama);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
    const int min_bars = MathMax(
        MathMax(KC_EMA_Period, KC_ATR_Period),
        MathMax(ATR_Period, KAMA_Period + KAMA_Filter_Period + 1)
    );

    if(rates_total < min_bars + 1)
        return 0;

    const int start   = (prev_calculated > 0) ? (prev_calculated - 1) : 0;
    const int to_copy = rates_total - start;

    //--- Copy KC EMA
    double tmp_ema[];
    if(CopyBuffer(g_kc_ema_handle, 0, 0, to_copy, tmp_ema) != to_copy)
        return prev_calculated;

    //--- Copy KC ATR
    double tmp_kc_atr[];
    if(CopyBuffer(g_kc_atr_handle, 0, 0, to_copy, tmp_kc_atr) != to_copy)
        return prev_calculated;

    //--- Copy ATR Stop
    double tmp_atr_stop[];
    if(CopyBuffer(g_atr_stop_handle, 0, 0, to_copy, tmp_atr_stop) != to_copy)
        return prev_calculated;

    //--- Copy RSI (only when needed)
    double tmp_rsi[];
    if(Show_Signal_Markers)
    {
        if(CopyBuffer(g_rsi_handle, 0, 0, to_copy, tmp_rsi) != to_copy)
            return prev_calculated;
    }

    //--- Keltner Channel
    for(int i = start; i < rates_total; i++)
    {
        const int j    = rates_total - 1 - i;
        g_kc_mid[i]    = tmp_ema[j];
        g_kc_upper[i]  = tmp_ema[j] + KC_Multiplier * tmp_kc_atr[j];
        g_kc_lower[i]  = tmp_ema[j] - KC_Multiplier * tmp_kc_atr[j];
    }

    //--- KAMA
    const double fast_sc = 2.0 / (KAMA_Fast + 1.0);
    const double slow_sc = 2.0 / (KAMA_Slow + 1.0);

    int kama_start;
    if(prev_calculated <= KAMA_Period)
    {
        for(int i = 0; i < KAMA_Period; i++)
        {
            g_kama[i]     = EMPTY_VALUE;
            g_kama_clr[i] = 2;
        }
        g_kama[KAMA_Period]     = close[KAMA_Period];
        g_kama_clr[KAMA_Period] = 2;
        kama_start = KAMA_Period + 1;
    }
    else
    {
        kama_start = prev_calculated - 1;
    }

    for(int i = kama_start; i < rates_total; i++)
    {
        g_kama[i] = ComputeKAMAStep(close, g_kama[i - 1], i, fast_sc, slow_sc);

        const int filter_ref = i - KAMA_Filter_Period;
        if(filter_ref >= KAMA_Period && g_kama[filter_ref] != EMPTY_VALUE)
        {
            if(g_kama[i] > g_kama[filter_ref])
                g_kama_clr[i] = 0;   // rising  -> green
            else if(g_kama[i] < g_kama[filter_ref])
                g_kama_clr[i] = 1;   // falling -> red
            else
                g_kama_clr[i] = 2;   // flat    -> gray
        }
        else
        {
            g_kama_clr[i] = 2;
        }
    }

    //--- Signal markers
    if(Show_Signal_Markers)
    {
        for(int i = start; i < rates_total; i++)
        {
            const int    j       = rates_total - 1 - i;
            const double rsi_val = tmp_rsi[j];

            g_buy[i]  = EMPTY_VALUE;
            g_sell[i] = EMPTY_VALUE;

            if(rsi_val < RSI_Oversold  && close[i] < g_kc_lower[i])
                g_buy[i]  = low[i];

            if(rsi_val > RSI_Overbought && close[i] > g_kc_upper[i])
                g_sell[i] = high[i];
        }
    }
    else
    {
        for(int i = start; i < rates_total; i++)
        {
            g_buy[i]  = EMPTY_VALUE;
            g_sell[i] = EMPTY_VALUE;
        }
    }

    //--- Object updates: only on new closed bar
    if(rates_total != g_prev_bars && rates_total >= 2)
    {
        g_prev_bars = rates_total;

        // CopyBuffer index 1 == bar[rates_total-2] (last closed bar)
        if(to_copy >= 2)
        {
            const double atr_val    = tmp_atr_stop[1];
            const double close_prev = close[rates_total - 2];
            const double stop_buf   = Stop_Buffer_Points * _Point;

            //--- ATR label
            const string atr_text =
                "ATR(" + IntegerToString(ATR_Period) + "): " +
                DoubleToString(atr_val, _Digits) +
                "  [" + DoubleToString(atr_val / _Point, 0) + " pts]";
            ObjectSetString(0, OBJ_PFX "ATR_Label", OBJPROP_TEXT, atr_text);

            //--- ATR stop lines
            if(Show_ATR_Stop_Lines)
            {
                const double long_stop  = close_prev - ATR_Multiplier * atr_val - stop_buf;
                const double short_stop = close_prev + ATR_Multiplier * atr_val + stop_buf;
                ObjectSetDouble(0, OBJ_PFX "ATR_Long",  OBJPROP_PRICE, long_stop);
                ObjectSetDouble(0, OBJ_PFX "ATR_Short", OBJPROP_PRICE, short_stop);
            }

            //--- Regime detection
            if(Show_Regime_Label)
            {
                const int    avg_len    = MathMin(ATR_Period, to_copy - 1);
                double       atr_sum    = 0.0;
                for(int k = 1; k <= avg_len; k++)
                    atr_sum += tmp_atr_stop[k];
                const double atr_avg    = (avg_len > 0) ? (atr_sum / (double)avg_len) : atr_val;

                const int    kama_slope = (int)g_kama_clr[rates_total - 1];

                string regime_text;
                color  regime_color;

                if(atr_val > atr_avg * 1.5)
                {
                    regime_text  = "High Volatility";
                    regime_color = clrOrange;
                }
                else if(kama_slope == 0)
                {
                    regime_text  = "Trend Mode (Up)";
                    regime_color = clrLime;
                }
                else if(kama_slope == 1)
                {
                    regime_text  = "Trend Mode (Down)";
                    regime_color = clrRed;
                }
                else
                {
                    regime_text  = "Mean Reversion Mode";
                    regime_color = clrAqua;
                }

                ObjectSetString (0, OBJ_PFX "Regime", OBJPROP_TEXT,  regime_text);
                ObjectSetInteger(0, OBJ_PFX "Regime", OBJPROP_COLOR, regime_color);
            }
        }

        ChartRedraw(0);
    }

    return rates_total;
}