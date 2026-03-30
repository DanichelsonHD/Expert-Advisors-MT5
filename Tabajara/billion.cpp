#include <zorro.h>

// Variáveis otimizáveis
int MA_Period;
int SuperTrend_ATR_Period;
double SuperTrend_Multiplier;
int RSI_Period;
int RSI_Buy_Level_Low;
int RSI_Buy_Entry_Level;
int RSI_Sell_Level_High;
int RSI_Sell_Entry_Level;
int EMA_RSI_Period;
int EMA_Period;
double SL_Multiplier;
double TP_Multiplier;
int Trail_EMA_Period;
int LookBackPeriod;
double Min_SL;
double Max_SL;
double riskPerTrade;
bool Use_EMA_Filter;

// Variáveis globais
vars rsi, emaRSI, closePrices, emaTrail;
var CustomStopLoss, CustomTakeProfit;
static bool crossedBelowLowLevel = false;
static bool crossedAboveHighLevel = false;

// Função para configurar parâmetros iniciais e otimizáveis
void setupParameters() {
	StartDate = 2006;
	Hedge = 2;
	MaxLong = -1;
	MaxShort = -1;
	set(PARAMETERS | PLOTNOW);
	BarPeriod = 1440; // Barras diárias
	NumWFOCycles = 6;
	NumCores = 6;


}

void optimizeCalls() {
	MA_Period = optimize(200, 50, 300, 10, 0);                // SMA
	SuperTrend_ATR_Period = optimize(14, 5, 20, 1, 0);        // ATR para SuperTrend
	SuperTrend_Multiplier = optimize(30, 10, 50, 5, 0) / 10.0; // Multiplicador SuperTrend
	RSI_Period = optimize(14, 5, 35, 1, 0);                   // Período do RSI
	RSI_Buy_Level_Low = optimize(30, 30, 40, 5, 1);           // Nível inferior de compra
	RSI_Buy_Entry_Level = optimize(50, 40, 60, 5, 0);         // Nível de entrada para compra
	RSI_Sell_Level_High = optimize(70, 60, 80, 5, 0);         // Nível superior de venda
	RSI_Sell_Entry_Level = optimize(50, 40, 60, 5, 0);        // Nível de entrada para venda
	EMA_RSI_Period = optimize(10, 5, 20, 1, 0);               // EMA no RSI
	EMA_Period = optimize(20, 10, 50, 5, 0);                  // EMA para validação
	Trail_EMA_Period = optimize(50, 20, 100, 10, 0);          // EMA para trailing stop
	LookBackPeriod = optimize(120, 50, 200, 10, 0);          // Período de lookback
	Min_SL = optimize(10, 5, 20, 1, 0);                      // Valor mínimo de SL
	Max_SL = optimize(100, 50, 200, 10, 0);                  // Valor máximo de SL
	riskPerTrade = optimize(10, 2, 20, 1, 0) / 1000.0;        // Risco por trade
	Use_EMA_Filter = false;                                    // Filtro de EMA
}
// Definir Séries
void defineSeries() {
	closePrices = series(priceClose(0));
	rsi = series(RSI(closePrices, RSI_Period));
	emaRSI = series(EMA(rsi, EMA_RSI_Period));
	emaTrail = series(EMA(closePrices, Trail_EMA_Period));
}

// Determinar Tendência com SMA e SuperTrend
bool isUptrend() {
	vars ma = series(SMA(closePrices, MA_Period));
	vars atr = series(ATR(SuperTrend_ATR_Period));
	var superTrend = ma[0] - SuperTrend_Multiplier * atr[0];
	return closePrices[0] > fmax(ma[0], superTrend);
}

// Sinal de Entrada para Long (Compra)
// Verificar Condição de Entrada para Long (Compra)
bool entryLongSignal() {
	// Verifica se o RSI cruzou abaixo do nível de compra configurável
	if (rsi[0] < RSI_Buy_Level_Low) {
		crossedBelowLowLevel = true;
	}

	// Verifica se o RSI cruzou para cima do nível de compra e depois do nível de entrada
	if (crossedBelowLowLevel && crossOver(rsi, RSI_Buy_Entry_Level)) {
		crossedBelowLowLevel = false;
		crossedAboveHighLevel = false;

		// Confirmação pela EMA do RSI se estiver habilitada
		if (!Use_EMA_Filter || (emaRSI[0] > 50)) {
			return true; // Sinal de compra
		}
	}
	return false;
}

// Sinal de Entrada para Short (Venda)
// Verificar Condição de Entrada para Short (Venda)
bool entryShortSignal() {


	// Verifica se o RSI cruzou acima do nível de venda configurável
	if (rsi[0] > RSI_Sell_Level_High) {
		crossedAboveHighLevel = true;
	}

	// Verifica se o RSI cruzou para baixo do nível de venda e depois do nível de entrada
	if (crossedAboveHighLevel && crossUnder(rsi, RSI_Sell_Entry_Level)) {
		crossedAboveHighLevel = false;
		crossedBelowLowLevel = false;

		// Confirmação pela EMA do RSI se estiver habilitada
		if (!Use_EMA_Filter || (emaRSI[0] < 50)) {
			return true; // Sinal de venda
		}
	}
	return false;
}

// Calcular SL e TP
void calculateSLTP(bool isLong) {
	if (isLong) {
		// Calcula a distância entre o preço atual e o menor preço no período de lookback
		var distanceToLL = priceClose(0) - LL(LookBackPeriod, 0);

		// Garante que o Stop Loss está dentro dos limites mínimo e máximo
		CustomStopLoss = fmax(
			fmin(distanceToLL, Max_SL * PIP),
			Min_SL * PIP
		);
	}
	else {
		// Calcula a distância entre o preço atual e o maior preço no período de lookback
		var distanceToHH = HH(LookBackPeriod, 0) - priceClose(0);

		// Garante que o Stop Loss está dentro dos limites mínimo e máximo
		CustomStopLoss = fmax(
			fmin(distanceToHH, Max_SL * PIP),
			Min_SL * PIP
		);
	}

	// Calcula o Take Profit como múltiplo da distância ao Stop Loss
	var distance = abs(priceClose(0) - CustomStopLoss);
	CustomTakeProfit = priceClose(0) + (isLong ? distance : -distance);
}



// Calcular Tamanho da Posição
var calculateLotSize() {
	var distanceToSL = abs(priceClose(0) - CustomStopLoss);
	return riskPerTrade * Equity / (distanceToSL * PIP);
}

// Função Principal
DLLFUNC void run() {
	LookBack = 400;

	setupParameters();
	optimizeCalls();
	defineSeries();
	plot("RSI", rsi, NEW | LINE, RED);
	plot("EMA_RSI", emaRSI, NEW | LINE, BLUE);

	// Sinal de Compra
	if (isUptrend()) {
		if (entryLongSignal()) {
			if (is(TESTMODE))
				printf("Sinal de compra detectado\n");
			calculateSLTP(true);
			LotAmount = calculateLotSize();
			Stop = CustomStopLoss;
			TakeProfit = CustomTakeProfit;
			enterLong();
			if (is(TESTMODE))
				printf("Posição de compra aberta com Stop Loss configurado em: %.5f e Take Profit em: %.5f Entrada em: %.5f \n", CustomStopLoss, CustomTakeProfit, closePrices[0]);
		}
	}
	// Sinal de Venda
	else {
		if (entryShortSignal()) {
			//if (is(TESTMODE))
				//printf("Sinal de venda detectado\n");
			calculateSLTP(false);
			LotAmount = calculateLotSize();
			Stop = CustomStopLoss;
			TakeProfit = CustomTakeProfit;
			enterShort();
			//	if (is(TESTMODE))
				//	printf("Posição de venda aberta com Stop Loss configurado em: %.5f e Take Profit em: %.5f Entrada em: %.5f \n", CustomStopLoss, CustomTakeProfit, closePrices[0]);
		}
	}

	// Implementação do Trailing Stop usando EMA
	for (open_trades) {
		if (TradeIsOpen && TradeProfit > 0) { // Ajusta trailing stop apenas para trades lucrativos
			if (TradeIsLong) {
				TradeStopLimit = fmax(TradeStopLimit, emaTrail[0]);
			}
			else if (TradeIsShort) {
				TradeStopLimit = fmin(TradeStopLimit, emaTrail[0]);
			}
			plot("Stop", TradeStopLimit, MAIN | LINE | MINV, RED);
		}
	}
}
