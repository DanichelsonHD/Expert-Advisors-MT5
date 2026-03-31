// Variable list for eval.c ////////////////////////////////
#ifndef EVARS_H
#define EVARS_H
#include <eval.h>

#define VR(x)	V.x
#define VI(x)	(int)V.x
#define _optimize(x) optv(&(x))
var optv(var* Parameter);
void assetLoop();

struct { // need a struct to keep variables in order
var _Bar_Period; //= 60, 0.1..1440; Basic timeframe in minutes
var _LookBack_Bars; //= 250; Lookback period 
var _WFO_Cycles; //= 10; WFO cycles in the backtest period 
var _WFO_OOS; //= 15, 5..50; Out-of-sample period in % 
var _Oversampling; //=0, 0..5; 0-None, >1-number of oversampling cycles
var _Backtest_Mode; //= 1, -1..3; -1-Zero cost, 1-Bar based, 2-Minute based, 3-Tick based 
var _Backtest_Start; //= 20200101; Backtest start date 
var _Backtest_End; //= 20251231; Backtest end date 
var _Train_Mode; //= 1, 1..3; 1-Ascent (fast), 2-Genetic, 3-Brute Force 
var _Objective; //= 0, 0..6; 0-Default, 1-PRR, 1-R2*PRR, 2-Profit/DD, 3-Profit/Invest, 4-Profit/Day, 5-Profit/Trade 
var _Criteria; //= 17, 1..21; Sort summary by field number (default: Return%), 0-unsorted
var _MRC_Cycles; //= 200; Montecarlo Reality Check cycles 
var _Max_Threads; //= -2; Number of CPU cores for WFO (-2 -> all but 2) 
var _Investment; //= 0, 0..5; 0-Default, 1-Lots, 2-Margin, 3-OptimalF, 4-Balance%, 5-Sqrt Reinvest
var _Phantom; //= 0, 0..50; 0-None, 5..50 Time period for equity curve trading
var _Verbose; //= 1; 0-No log (fastest), 1..3-Verbosity, 15-Diag, 17-Alert on error
#define END_OF_VARS	} V;	

#define NV		15	// # of the last system variable
#define N_WFO	2
#define N_OOS	3
#define N_START	6
#define N_END	7
#define N_CORES	12
#define N_INVEST 13

#endif //ndef EVARS_H