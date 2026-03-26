#ifndef ZORRO_INDICATORS_H
#define ZORRO_INDICATORS_H

#include "configs.h"
#include "../../Core/Engine.h"

void Indicators_Init(const ZorroConfig& cfg);
bool Indicators_Update(IndicatorData& out, const ZorroConfig& cfg);

#endif // ZORRO_INDICATORS_H