// Header for eval.c ///////////////////////////////////
#ifndef EVAL_H
#define EVAL_H
#ifdef _WIN32
#include <zorro.h>
#else
#include <default.c>
#endif
int oNumWFOCycles,oDataSplit;
#undef NumWFOCycles
#define NumWFOCycles oNumWFOCycles
#undef DataSplit
#define DataSplit	oDataSplit
#define run strategy	// replace with run() in eval.c
#define _exit return quit("!")
#endif