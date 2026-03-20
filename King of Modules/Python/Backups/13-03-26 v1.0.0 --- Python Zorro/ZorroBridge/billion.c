#include <zorro.h> // Importa a biblioteca do Zorro para funções de trading e variáveis

// Parâmetros configuráveis
const int MA_Period = 200;
const int SuperTrend_ATR_Period = 14;
const double SuperTrend_Multiplier = 3.0;
const int RSI_Buy_Level_Low = 30;       // Nível inferior de compra
const int RSI_Buy_Entry_Level = 55;     // Nível de entrada para compra
const int RSI_Sell_Level_High = 70;     // Nível superior de venda
const int RSI_Sell_Entry_Level = 45;    // Nível de entrada para venda
const int EMA_RSI_Period = 10;          // Período da EMA aplicada ao RSI
const int EMA_Period = 20;              // Período da EMA para validação de entrada
const double SL_Multiplier = 1.5;
const double TP_Multiplier = 3.0;
const int Trail_EMA_Period = 50;
const int LookBackPeriod = 120; // Lookback period para cálculo do Stop Loss
const double Min_SL = 10; // Valor mínimo de SL em pontos
const double Max_SL = 100; // Valor máximo de SL em pontos
const double riskPerTrade = 0.01; // Percentual ajustável de risco por trade
bool Use_EMA_Filter = true;       // Controle de habilitação da EMA aplicada ao RSI

// Variáveis Globais para Séries e SL/TP
vars rsi, emaRSI, closePrices, emaTrail;
var CustomStopLoss, CustomTakeProfit;
static bool crossedBelowLowLevel = false;
static bool crossedAboveHighLevel = false;

// Função para configurar parâmetros iniciais
void setupParameters() {
	StartDate = 2006;
	Hedge = 0;
	MaxLong = 1;  // Permite apenas uma posição longa
	MaxShort = 1; // Permite apenas uma posição curta
	set(PARAMETERS | PLOTNOW);
	BarPeriod = 1440; // Barras diárias
}

// Função para Definir Séries de Preços, RSI e EMA do RSI
void defineSeries() {
	closePrices = series(priceClose(0));
	rsi = series(RSI(closePrices, 14));                // Série do RSI
	emaRSI = series(EMA(rsi, EMA_RSI_Period));         // EMA aplicada ao RSI
	emaTrail = series(EMA(closePrices, Trail_EMA_Period)); // Série para trailing stop
}

// Função para Determinar Tendência usando Média Móvel e SuperTrend ATR
bool isUptrend() {
	vars ma = series(SMA(closePrices, MA_Period));
	vars atr = series(ATR(SuperTrend_ATR_Period));
	var superTrend = ma[0] - SuperTrend_Multiplier * atr[0];
	return closePrices[0] > fmax(ma[0], superTrend);
}

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

// Função para Calcular Stop Loss e Take Profit
void calculateSLTP(bool isLong) {
	if (isLong) {
		CustomStopLoss = fmax(fmin(LL(LookBackPeriod, 0), Max_SL * PIP), Min_SL * PIP);
	}
	else {
		CustomStopLoss = fmax(fmin(HH(LookBackPeriod, 0), Max_SL * PIP), Min_SL * PIP);
	}

	var distance = abs(priceClose(0) - CustomStopLoss);
	CustomTakeProfit = priceClose(0) + (isLong ? distance : -distance) * TP_Multiplier;
}

// Função para Calcular o Tamanho da Posição Baseado no Capital e SL
var calculateLotSize() {
	var distanceToSL = abs(priceClose(0) - CustomStopLoss);
	return riskPerTrade * Equity / (distanceToSL * PIP);
}

// Função Principal para Executar a Estratégia
DLLFUNC void run() {
	setupParameters();
	defineSeries();
	plot("RSI", rsi, NEW | LINE, RED);
	plot("EMA_RSI", emaRSI, NEW | LINE, BLUE);

	// Sinal de Compra
	if (isUptrend()) {
		if (entryLongSignal()) {
			if (is(TESTMODE))
				printf("Sinal de entrada longa detectado\n");
			calculateSLTP(true);
			LotAmount = calculateLotSize();
			Stop = CustomStopLoss;
			TakeProfit = CustomTakeProfit;
			enterLong();
			if (is(TESTMODE))
				printf("Posição longa aberta com Stop Loss configurado em: %.5f e Take Profit em: %.5f Entrada em: %.5f \n", CustomStopLoss, CustomTakeProfit, closePrices[0]);
		}
	}
	// Sinal de Venda
	else {
		if (entryShortSignal()) {
			if (is(TESTMODE))
				printf("Sinal de entrada curta detectado\n");
			calculateSLTP(false);
			LotAmount = calculateLotSize();
			Stop = CustomStopLoss;
			TakeProfit = CustomTakeProfit;
			enterShort();
			if (is(TESTMODE))
				printf("Posição curta aberta com Stop Loss configurado em: %.5f e Take Profit em: %.5f Entrada em: %.5f \n", CustomStopLoss, CustomTakeProfit, closePrices[0]);
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
