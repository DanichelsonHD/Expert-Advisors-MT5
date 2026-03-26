//+------------------------------------------------------------------+
//|                                                   Indicators.mqh |
//+------------------------------------------------------------------+
#ifndef INDICATORS_MQH
#define INDICATORS_MQH

#include "Configs.mqh"

//+------------------------------------------------------------------+
//| Indicator handles                                                |
//+------------------------------------------------------------------+
static int _hEMA20   = INVALID_HANDLE;
static int _hEMA50   = INVALID_HANDLE;
static int _hRSI     = INVALID_HANDLE;
static int _hATR14   = INVALID_HANDLE;
static int _hATR50   = INVALID_HANDLE;
static int _hADX     = INVALID_HANDLE;
static int _hBB      = INVALID_HANDLE;
static int _hKAMA    = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Indicator values (bar 1 = last finalized bar)                   |
//+------------------------------------------------------------------+
static double _ema20        = 0.0;
static double _ema50        = 0.0;
static double _rsi          = 0.0;
static double _atr14        = 0.0;
static double _atr50        = 0.0;
static double _adx          = 0.0;
static double _bbUpper      = 0.0;
static double _bbLower      = 0.0;
static double _bbMiddle     = 0.0;
static double _bbUpperPrev  = 0.0;
static double _bbLowerPrev  = 0.0;
static double _kamaVal      = 0.0;
static double _kamaValPrev  = 0.0;
static double _kamaColor    = 0.0;
static double _kamaColorPrev= 0.0;
static double _closed       = 0.0;

//--- Keltner Channel (manual calculation, no native handle)
static double _kcUpper      = 0.0;
static double _kcLower      = 0.0;
static double _kcEMA        = 0.0;
static double _kcATR        = 0.0;

//+------------------------------------------------------------------+
//| Initialize all indicator handles                                 |
//+------------------------------------------------------------------+
bool IndicatorsInit()
{
   _hEMA20 = iMA(_Symbol, _Period, InpEMA20Period, 0, MODE_EMA, PRICE_CLOSE);
   _hEMA50 = iMA(_Symbol, _Period, InpEMA50Period, 0, MODE_EMA, PRICE_CLOSE);
   _hRSI   = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   _hATR14 = iATR(_Symbol, _Period, InpATR14Period);
   _hATR50 = iATR(_Symbol, _Period, InpATR50Period);
   _hADX   = iADX(_Symbol, _Period, InpADXPeriod);
   _hBB    = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   _hKAMA  = iCustom(_Symbol, _Period, "KAMA with filter",
                     InpKAMAPeriod,
                     InpKAMAFastPeriod,
                     InpKAMASlowPeriod,
                     InpKAMAPower,
                     InpKAMAFilter,
                     InpKAMAFilterPeriod,
                     InpKAMAFilterDiff,
                     PRICE_CLOSE);

   if (_hEMA20  == INVALID_HANDLE) return false;
   if (_hEMA50  == INVALID_HANDLE) return false;
   if (_hRSI    == INVALID_HANDLE) return false;
   if (_hATR14  == INVALID_HANDLE) return false;
   if (_hATR50  == INVALID_HANDLE) return false;
   if (_hADX    == INVALID_HANDLE) return false;
   if (_hBB     == INVALID_HANDLE) return false;
   if (_hKAMA   == INVALID_HANDLE) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Release all indicator handles                                    |
//+------------------------------------------------------------------+
void IndicatorsDeinit()
{
   if (_hEMA20  != INVALID_HANDLE) { IndicatorRelease(_hEMA20);  _hEMA20  = INVALID_HANDLE; }
   if (_hEMA50  != INVALID_HANDLE) { IndicatorRelease(_hEMA50);  _hEMA50  = INVALID_HANDLE; }
   if (_hRSI    != INVALID_HANDLE) { IndicatorRelease(_hRSI);    _hRSI    = INVALID_HANDLE; }
   if (_hATR14  != INVALID_HANDLE) { IndicatorRelease(_hATR14);  _hATR14  = INVALID_HANDLE; }
   if (_hATR50  != INVALID_HANDLE) { IndicatorRelease(_hATR50);  _hATR50  = INVALID_HANDLE; }
   if (_hADX    != INVALID_HANDLE) { IndicatorRelease(_hADX);    _hADX    = INVALID_HANDLE; }
   if (_hBB     != INVALID_HANDLE) { IndicatorRelease(_hBB);     _hBB     = INVALID_HANDLE; }
   if (_hKAMA   != INVALID_HANDLE) { IndicatorRelease(_hKAMA);   _hKAMA   = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| Update all indicator values from last finalized bar              |
//+------------------------------------------------------------------+
bool IndicatorsUpdate()
{
   double buf[2];

   _closed = iClose(_Symbol, _Period, 1);

   //--- EMA 20
   if (CopyBuffer(_hEMA20, 0, 1, 1, buf) < 1) return false;
   _ema20 = buf[0];

   //--- EMA 50
   if (CopyBuffer(_hEMA50, 0, 1, 1, buf) < 1) return false;
   _ema50 = buf[0];

   //--- RSI
   if (CopyBuffer(_hRSI, 0, 1, 1, buf) < 1) return false;
   _rsi = buf[0];

   //--- ATR 14
   if (CopyBuffer(_hATR14, 0, 1, 1, buf) < 1) return false;
   _atr14 = buf[0];

   //--- ATR 50
   if (CopyBuffer(_hATR50, 0, 1, 1, buf) < 1) return false;
   _atr50 = buf[0];

   //--- ADX (buffer 0 = ADX main line)
   if (CopyBuffer(_hADX, 0, 1, 1, buf) < 1) return false;
   _adx = buf[0];

   //--- Bollinger Bands (bar 1 and bar 2 for expansion check)
   if (CopyBuffer(_hBB, 1, 1, 1, buf) < 1) return false;  // upper
   _bbUpper = buf[0];
   if (CopyBuffer(_hBB, 2, 1, 1, buf) < 1) return false;  // lower
   _bbLower = buf[0];
   if (CopyBuffer(_hBB, 0, 1, 1, buf) < 1) return false;  // middle
   _bbMiddle = buf[0];
   if (CopyBuffer(_hBB, 1, 2, 1, buf) < 1) return false;  // upper bar 2
   _bbUpperPrev = buf[0];
   if (CopyBuffer(_hBB, 2, 2, 1, buf) < 1) return false;  // lower bar 2
   _bbLowerPrev = buf[0];

   //--- Keltner Channel (manual: EMA20 +/- ATR14 * multiplier)
   _kcEMA   = _ema20;
   _kcATR   = _atr14;
   _kcUpper = _kcEMA + InpKCMultiplier * _kcATR;
   _kcLower = _kcEMA - InpKCMultiplier * _kcATR;

   //--- KAMA value (buffer 0) and color (buffer 1), bars 1 and 2
   double kamaBuf[2];
   if (CopyBuffer(_hKAMA, 0, 1, 2, kamaBuf) < 2) return false;
   _kamaValPrev = kamaBuf[0];  // bar 2 (older)
   _kamaVal     = kamaBuf[1];  // bar 1 (last finalized)

   if (CopyBuffer(_hKAMA, 1, 1, 2, kamaBuf) < 2) return false;
   _kamaColorPrev = kamaBuf[0]; // bar 2
   _kamaColor     = kamaBuf[1]; // bar 1

   return true;
}

//+------------------------------------------------------------------+
//| Volatility                                                       |
//+------------------------------------------------------------------+
bool isVolatilityHigh() { return _atr14 > _atr50; }
bool isVolatilityLow()  { return _atr14 < _atr50; }

//+------------------------------------------------------------------+
//| Regime                                                           |
//+------------------------------------------------------------------+
bool isTrending()    { return _adx > InpADXTrending; }
bool isRanging()     { return _adx < InpADXRanging; }
bool isTransition()  { return _adx >= InpADXRanging && _adx <= InpADXTrending; }

//+------------------------------------------------------------------+
//| BB + KC                                                          |
//+------------------------------------------------------------------+
bool isSqueeze()
{
   return _bbUpper < _kcUpper && _bbLower > _kcLower;
}

bool isExpansion()
{
   double bbWidthNow  = _bbUpper  - _bbLower;
   double bbWidthPrev = _bbUpperPrev - _bbLowerPrev;
   return bbWidthNow > bbWidthPrev;
}

bool isExhaustionBuy()
{
   double close1 = _closed;
   return close1 < _bbLower && close1 < _kcLower;
}

bool isExhaustionSell()
{
   double close1 = _closed;
   return close1 > _bbUpper && close1 > _kcUpper;
}

//+------------------------------------------------------------------+
//| RSI                                                              |
//+------------------------------------------------------------------+
bool isOverbought() { return _rsi > InpRSIOverbought; }
bool isOversold()   { return _rsi < InpRSIOversold; }
bool isRSIPullbackZone() { return _rsi >= InpRSIPullbackLow && _rsi <= InpRSIPullbackHigh; }

//+------------------------------------------------------------------+
//| KAMA                                                             |
//+------------------------------------------------------------------+
bool isKAMABull()     { return _kamaColor == 2.0; }
bool isKAMABear()     { return _kamaColor == 1.0; }
bool isKAMAFlipBull() { return _kamaColor == 2.0 && _kamaColorPrev == 1.0; }
bool isKAMAFlipBear() { return _kamaColor == 1.0 && _kamaColorPrev == 2.0; }

//+------------------------------------------------------------------+
//| EMA                                                              |
//+------------------------------------------------------------------+
bool isAboveEMA50()
{
   double close1 = _closed;
   return close1 > _ema50;
}

bool isBelowEMA50()
{
   double close1 = _closed;
   return close1 < _ema50;
}

bool isPriceNearEMA20()
{
   double close1 = _closed;
   return MathAbs(close1 - _ema20) <= _atr14;
}

//+------------------------------------------------------------------+
//| Accessors for raw values (used by Stops/Takes)                  |
//+------------------------------------------------------------------+
double GetATR14()      { return _atr14; }
double GetKAMAVal()    { return _kamaVal; }
double GetBBUpper()    { return _bbUpper; }
double GetBBLower()    { return _bbLower; }
double GetKCUpper()    { return _kcUpper; }
double GetKCLower()    { return _kcLower; }
double GetEMA20()      { return _ema20; }
double GetEMA50()      { return _ema50; }
double GetRSI()        { return _rsi; }
double GetADX()        { return _adx; }
double GetClosed()     { return _closed; }

#endif
