#property copyright "Gemini AI"
#property link ""
#property version "2.06"
#property strict

#include <Trade\Trade.mqh>

//--- INPUTS
input double InpRiskPercent = 0.5;                // Risk per trade (% of balance)
input double InpDailyLimit = 1.0;                 // Daily profit/loss stop (%)
input double InpATR_StopMult = 1.2;               // Stop Loss ATR multiplier (Noise-adjusted)
input double InpATR_TakeMult = 2.5;               // Take Profit ATR multiplier
input int InpEMA_Fast_Period = 21;                // Fast EMA period
input int InpEMA_Slow_Period = 50;                // Slow EMA period
input int InpATR_Period = 14;                     // ATR period
input int InpADX_Period = 14;                     // ADX period
input double InpATR_DistanceMult = 0.6;           // Distance from EMA50 multiplier
input double InpADX_Minimum = 23.0;               // ADX minimum value
input bool InpUseBreakEven = true;                // Enable Break Even
input double InpStrongRegimeRiskMultiplier = 1.5; // Risk multiplier when ATR and Slope both true
input int InpMinRegimeScore = 2;                  // Minimum regime score required
input int InpMinEntryScore = 3;                   // Minimum entry score required
input double InpRiskMultiplierLevel2 = 1.3;       // Risk multiplier when total score >= 5
input double InpRiskMultiplierLevel3 = 1.6;       // Risk multiplier when total score >= 6
input int InpMinFlexScore = 2;                    // Minimum flexible score required
input double InpFlexRiskLevel2 = 1.3;             // Risk multiplier when flex score >= 3
input double InpFlexRiskLevel3 = 1.6;             // Risk multiplier when flex score >= 4
input int InpRSI_Period = 14;                     // RSI period
input double InpRSI_BuyLevel = 42.0;              // RSI pullback threshold for BUY (Deeper pullback)
input double InpRSI_SellLevel = 58.0;             // RSI pullback threshold for SELL (Deeper pullback)
input double InpRSI_MaxBuyLevel = 60.0;           // Avoid overextended buys
input double InpRSI_MinSellLevel = 40.0;          // Avoid overextended sells

//--- GLOBALS
int hEMA_Fast, hEMA_Slow, hATR, hADX, hRSI;
CTrade Trade;
int Magic = 123456;
datetime lastTradeCandleTime = 0;

//--- DATA STRUCTURES
struct IndicatorData
{
    double emaFast[3];
    double emaSlow[6];
    double adx[2];
    double plusDI[2];
    double minusDI[2];
    double atr[11];
    double rsi[3];
};

//--- INITIALIZATION
int OnInit()
{
    if (_Symbol != "EURUSD" && _Symbol != "GBPUSD")
        return INIT_FAILED;
    if (_Period != PERIOD_M15)
        return INIT_FAILED;

    hEMA_Fast = iMA(_Symbol, _Period, InpEMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
    hEMA_Slow = iMA(_Symbol, _Period, InpEMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
    hATR = iATR(_Symbol, _Period, InpATR_Period);
    hADX = iADX(_Symbol, _Period, InpADX_Period);
    hRSI = iRSI(_Symbol, _Period, InpRSI_Period, PRICE_CLOSE);

    if (hEMA_Fast == INVALID_HANDLE || hEMA_Slow == INVALID_HANDLE || hATR == INVALID_HANDLE || hADX == INVALID_HANDLE || hRSI == INVALID_HANDLE)
        return INIT_FAILED;

    Trade.SetExpertMagicNumber(Magic);
    return INIT_SUCCEEDED;
}

//--- DEINITIALIZATION
void OnDeinit(const int reason)
{
    IndicatorRelease(hEMA_Fast);
    IndicatorRelease(hEMA_Slow);
    IndicatorRelease(hATR);
    IndicatorRelease(hADX);
    IndicatorRelease(hRSI);
}

//--- MAIN EXECUTION
void OnTick()
{
    if (!IsNewCandle())
        return;

    if (PositionSelect(_Symbol))
    {
        if (PositionGetInteger(POSITION_MAGIC) == Magic)
        {
            if (InpUseBreakEven)
            {
                ManageBreakEven();
            }
            return;
        }
    }

    datetime serverTime = TimeTradeServer();
    MqlDateTime dt;
    TimeToStruct(serverTime, dt);
    if (dt.hour < 6 || dt.hour >= 22)
        return;

    if (!CheckDailyLimits())
        return;

    IndicatorData data;
    if (!FillData(data))
        return;

    MqlRates rates[3];
    if (CopyRates(_Symbol, _Period, 0, 3, rates) < 3)
        return;
    ArraySetAsSeries(rates, true);

    if (rates[1].time == lastTradeCandleTime)
        return;

    double c1 = rates[1].close;
    double c2 = rates[2].close;

    double emaF1 = data.emaFast[1];
    double emaF2 = data.emaFast[2];

    double emaS1 = data.emaSlow[1];
    double emaS5 = data.emaSlow[5];

    double atr1 = data.atr[1];
    double atr10 = data.atr[10];

    double adx1 = data.adx[1];
    double pDI1 = data.plusDI[1];
    double mDI1 = data.minusDI[1];

    double rsi1 = data.rsi[1];
    double rsi2 = data.rsi[2];

    double atrThreshold = (_Symbol == "EURUSD") ? 0.0008 : 0.0012;
    if (atr1 <= atrThreshold)
        return;

    bool hardBuy =
        (emaF1 > emaS1) &&
        (adx1 > InpADX_Minimum) &&
        (c1 > emaS1);

    bool hardSell =
        (emaF1 < emaS1) &&
        (adx1 > InpADX_Minimum) &&
        (c1 < emaS1);

    if (!hardBuy && !hardSell)
        return;

    int buyFlexScore = 0;
    if (emaS1 > emaS5)
        buyFlexScore++;
    if (atr1 > atr10)
        buyFlexScore++;
    if (pDI1 > mDI1)
        buyFlexScore++;
    if (c2 < emaF2 && c1 > emaF1)
        buyFlexScore++;
    if (MathAbs(c1 - emaS1) > (InpATR_DistanceMult * atr1))
        buyFlexScore++;
    if (rsi2 <= InpRSI_BuyLevel && rsi1 > rsi2 && rsi1 < InpRSI_MaxBuyLevel)
        buyFlexScore++;
    if (rates[1].low > rates[2].low)
        buyFlexScore++;

    int sellFlexScore = 0;
    if (emaS1 < emaS5)
        sellFlexScore++;
    if (atr1 > atr10)
        sellFlexScore++;
    if (mDI1 > pDI1)
        sellFlexScore++;
    if (c2 > emaF2 && c1 < emaF1)
        sellFlexScore++;
    if (MathAbs(c1 - emaS1) > (InpATR_DistanceMult * atr1))
        sellFlexScore++;
    if (rsi2 >= InpRSI_SellLevel && rsi1 < rsi2 && rsi1 > InpRSI_MinSellLevel)
        sellFlexScore++;
    if (rates[1].high < rates[2].high)
        sellFlexScore++;

    bool allowBuy = hardBuy && (buyFlexScore >= InpMinFlexScore);
    bool allowSell = hardSell && (sellFlexScore >= InpMinFlexScore);

    if (allowBuy)
    {
        double riskMultiplier = 1.0;

        if (buyFlexScore >= 4)
            riskMultiplier = InpFlexRiskLevel3;
        else if (buyFlexScore >= 3)
            riskMultiplier = InpFlexRiskLevel2;

        ExecuteMarketOrder(ORDER_TYPE_BUY, atr1, rates[1].time, riskMultiplier);
    }

    if (allowSell)
    {
        double riskMultiplier = 1.0;

        if (sellFlexScore >= 4)
            riskMultiplier = InpFlexRiskLevel3;
        else if (sellFlexScore >= 3)
            riskMultiplier = InpFlexRiskLevel2;

        ExecuteMarketOrder(ORDER_TYPE_SELL, atr1, rates[1].time, riskMultiplier);
    }
}

//--- LOGIC HELPERS
bool FillData(IndicatorData &d)
{
    if (CopyBuffer(hEMA_Fast, 0, 0, 3, d.emaFast) < 3)
        return false;
    ArraySetAsSeries(d.emaFast, true);

    if (CopyBuffer(hEMA_Slow, 0, 0, 6, d.emaSlow) < 6)
        return false;
    ArraySetAsSeries(d.emaSlow, true);

    if (CopyBuffer(hADX, 0, 0, 2, d.adx) < 2)
        return false;
    ArraySetAsSeries(d.adx, true);

    if (CopyBuffer(hADX, 1, 0, 2, d.plusDI) < 2)
        return false;
    ArraySetAsSeries(d.plusDI, true);

    if (CopyBuffer(hADX, 2, 0, 2, d.minusDI) < 2)
        return false;
    ArraySetAsSeries(d.minusDI, true);

    if (CopyBuffer(hATR, 0, 0, 11, d.atr) < 11)
        return false;
    ArraySetAsSeries(d.atr, true);

    if (CopyBuffer(hRSI, 0, 0, 3, d.rsi) < 3)
        return false;
    ArraySetAsSeries(d.rsi, true);

    return true;
}

bool CheckDailyLimits()
{
    datetime serverTime = TimeTradeServer();
    MqlDateTime dt;
    TimeToStruct(serverTime, dt);
    dt.hour = 0;
    dt.min = 0;
    dt.sec = 0;
    datetime dayStart = StructToTime(dt);

    HistorySelect(dayStart, serverTime);

    double dailyProfit = 0;
    int tradesToday = 0;
    uint total = HistoryDealsTotal();

    for (uint i = 0; i < total; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if (HistoryDealGetInteger(ticket, DEAL_MAGIC) == Magic && HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
        {
            long entryType = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if (entryType == DEAL_ENTRY_OUT)
            {
                tradesToday++;
                dailyProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
            }
        }
    }

    if (PositionSelect(_Symbol) && PositionGetInteger(POSITION_MAGIC) == Magic)
    {
        tradesToday++;
    }

    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double startOfDayBalance = currentBalance - dailyProfit;
    double limitMoney = startOfDayBalance * (InpDailyLimit / 100.0);

    if (dailyProfit >= limitMoney || dailyProfit <= -limitMoney)
        return false;
    if (tradesToday >= 2)
        return false;

    return true;
}

void ExecuteMarketOrder(ENUM_ORDER_TYPE type, double atr, datetime candleTime, double riskMultiplier)
{
    if (SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) != SYMBOL_TRADE_MODE_FULL)
        return;

    double slDist = InpATR_StopMult * atr;
    if (slDist <= 0)
        return;

    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

    if (tickValue <= 0 || tickSize <= 0)
        return;

    double tpDist = InpATR_TakeMult * atr;
    double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double sl = (type == ORDER_TYPE_BUY) ? price - slDist : price + slDist;
    double tp = (type == ORDER_TYPE_BUY) ? price + tpDist : price - tpDist;

    double baseRisk = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
    double riskMoney = baseRisk * riskMultiplier;

    double lot = riskMoney / ((slDist / tickSize) * tickValue);

    double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double stepVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    lot = MathFloor(lot / stepVol) * stepVol;

    if (lot < minVol)
        lot = minVol;
    if (lot <= 0)
        return;

    lot = MathMin(lot, maxVol);

    if (Trade.PositionOpen(_Symbol, type, lot, price, sl, tp))
    {
        lastTradeCandleTime = candleTime;
    }
    else
    {
        int err = GetLastError();
        ResetLastError();
    }
}

void ManageBreakEven()
{
    double entry = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    double tp = PositionGetDouble(POSITION_TP);
    double curPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;

    double r1 = MathAbs(entry - sl);

    if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
    {
        if (curPrice >= entry + r1 && sl < entry)
        {
            Trade.PositionModify(_Symbol, entry + spread, tp);
        }
    }
    else
    {
        if (curPrice <= entry - r1 && sl > entry)
        {
            Trade.PositionModify(_Symbol, entry - spread, tp);
        }
    }
}

bool IsNewCandle()
{
    static datetime lastTime = 0;
    datetime currTime = iTime(_Symbol, _Period, 0);
    if (lastTime != currTime)
    {
        lastTime = currTime;
        return true;
    }
    return false;
}