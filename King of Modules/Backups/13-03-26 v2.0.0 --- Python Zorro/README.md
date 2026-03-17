# EA_KingofModules — Python Translation

Python translation of the `EA_KingofModules` MQL5 Expert Advisor system.  
Original authors: Daniel Pereira & Lucas Mattos | Version 1.20

---

## Project Structure

```
king_of_modules/
│
├── ea.py                        ← Main entry point  (EA_KingofModules.mq5)
├── config.py                    ← All parameters    (Inputs.mqh)
├── indicators.py                ← All indicators    (Indicators.mqh)
├── entries.py                   ← Entry engine      (Entries.mqh)
├── stops.py                     ← SL & trailing     (Stops.mqh)
├── takes.py                     ← TP management     (Takes.mqh)
├── requirements.txt
│
└── strategies/
    ├── mean_reversion.py        ← Mean Reversion    (MeanReversion.mqh)
    ├── kama_trend.py            ← KAMA Trend        (KamaTrend.mqh)
    ├── pullback.py              ← Pullback (stub)   (Pullback.mqh)
    ├── breakout.py              ← Breakout (stub)   (Breakout.mqh)
    └── rsi_exhaustion.py        ← RSI Exhaustion    (RSIExhaustion.mqh)
```

---

## MQL5 → Python Module Map

| MQL5 File              | Python File                        | Role                          |
|------------------------|------------------------------------|-------------------------------|
| `EA_KingofModules.mq5` | `ea.py`                            | Lifecycle + event loop        |
| `Inputs.mqh`           | `config.py`                        | All input parameters          |
| `Indicators.mqh`       | `indicators.py`                    | RSI, ATR, Keltner, KAMA       |
| `Entries.mqh`          | `entries.py`                       | Entry orchestrator            |
| `Stops.mqh`            | `stops.py`                         | SL calculation + trailing     |
| `Takes.mqh`            | `takes.py`                         | TP calculation + KAMA exit    |
| `MeanReversion.mqh`    | `strategies/mean_reversion.py`     | Mean Reversion strategy       |
| `KamaTrend.mqh`        | `strategies/kama_trend.py`         | KAMA Trend strategy           |
| `Pullback.mqh`         | `strategies/pullback.py`           | Pullback stub                 |
| `Breakout.mqh`         | `strategies/breakout.py`           | Breakout stub                 |
| `RSIExhaustion.mqh`    | `strategies/rsi_exhaustion.py`     | RSI Exhaustion (unwired)      |

---

## Key MQL5 → Python Concept Mappings

| MQL5 Concept                    | Python Equivalent                                      |
|---------------------------------|--------------------------------------------------------|
| `OnInit()`                      | `on_init()` in `ea.py`                                 |
| `OnTick()`                      | `on_tick()` in `ea.py` — called in polling loop        |
| `OnDeinit()`                    | `on_deinit()` in `ea.py`                               |
| `iRSI`, `iATR`, `iADX`         | Pure pandas/numpy implementations in `indicators.py`   |
| `iCustom("Keltner Channel")`    | `compute_keltner()` in `indicators.py`                 |
| `iCustom("KAMA with filter")`   | `compute_kama()` in `indicators.py`                    |
| `CopyBuffer(handle, buf, ...)`  | `iloc` slicing on computed pandas Series               |
| `CopyRates()`                   | `mt5.copy_rates_from_pos()` → `pd.DataFrame`           |
| `CTrade.Buy() / .Sell()`        | `mt5.order_send()` with `TRADE_ACTION_DEAL`            |
| `CTrade.PositionModify()`       | `mt5.order_send()` with `TRADE_ACTION_SLTP`            |
| `CTrade.PositionClose()`        | `mt5.order_send()` with counter-direction market order |
| `CPositionInfo.Select()`        | `mt5.positions_get(symbol=...)`                        |
| `static datetime lastBar`       | Module-level `_last_bar_time` variable                 |
| `static int hATR50`             | Computed inline from the rates DataFrame               |
| `_Symbol`, `_Period`            | `SYMBOL`, `TIMEFRAME` constants in `ea.py`             |
| `SYMBOL_POINT`                  | `mt5.symbol_info(symbol).point`                        |
| `SYMBOL_DIGITS`                 | `mt5.symbol_info(symbol).digits`                       |
| `SYMBOL_TRADE_STOPS_LEVEL`      | `mt5.symbol_info(symbol).trade_stops_level`            |
| `AccountInfoDouble(BALANCE)`    | `mt5.account_info().balance`                           |
| `TimeCurrent()`                 | `mt5.symbol_info_tick(symbol).time` (Unix timestamp)   |
| `ENUM_SIGNAL`                   | `Signal(IntEnum)` in `config.py`                       |
| `ENUM_STOP_MODE`                | `StopMode(IntEnum)` in `config.py`                     |
| `ENUM_TAKE_MODE`                | `TakeMode(IntEnum)` in `config.py`                     |
| `ENUM_KAMA_REGIME`              | `KamaRegime(IntEnum)` in `config.py`                   |

---

## Configuration

All parameters are in `config.py` inside the `EAConfig` dataclass.

```python
# config.py
cfg = EAConfig(
    lot_size            = 0.1,
    magic_number        = 123456,
    use_mr_strategy     = True,   # Enable Mean Reversion
    use_kt_strategy     = True,   # Enable KAMA Trend
    stop_mode           = StopMode.TRAILING,
    stop_multiplier     = 2.0,
    use_time_filter     = True,
    start_hour          = 8,
    end_hour            = 20,
    # ... all other parameters
)
```

---

## Setup & Run

```bash
# 1. Install dependencies (Windows required for MetaTrader5 package)
pip install -r requirements.txt

# 2. Open MetaTrader 5 terminal and log in to your account

# 3. Edit ea.py: set your SYMBOL and TIMEFRAME
SYMBOL    = "EURUSD"
TIMEFRAME = mt5.TIMEFRAME_H1

# 4. Edit config.py: enable your desired strategies and parameters

# 5. Run the EA
python ea.py
```

---

## Architecture Notes

### Indicator Computation
In MQL5, indicators are computed by the terminal via handles (`iRSI`, `iATR`,  
etc.) and values are read with `CopyBuffer()`. In Python, all indicators are  
computed from scratch on each tick using the fetched OHLCV DataFrame. The  
formulas use **Wilder smoothing** (via `ewm(alpha=1/period, adjust=False)`) to  
match MQL5's built-in behaviour exactly.

### Bar Gate Pattern
MQL5 uses `static datetime lastBar` to fire logic once per new bar.  
Python mirrors this with module-level `_last_bar_time` variables.  
The gate in `entries_engine()` compares the current bar's index timestamp.

### CopyBuffer Offset Convention
MQL5's `CopyBuffer(handle, buf, offset=1, count=N)` skips the live (forming)  
bar and returns `N` closed bars. In Python this maps to `iloc[-N-1:-1]` on  
the sorted DataFrame (most recent closed bar = `iloc[-2]` when offset=1).

### Static Indicator Handles
MQL5 strategies use `static int hATR50 = INVALID_HANDLE` for lazy  
initialisation of secondary indicators. In Python, there are no handles —  
`compute_atr(rates, 50)` is called directly and is stateless.

### Trailing Stop vs Initial SL
In `TRAILING` stop mode:
- The initial SL is set identically to `FIXED` mode (ATR-based).
- `manage_trailing_stop()` then moves the SL on every tick.
- This matches MQL5 where `GetStopLoss()` returns 0 for TRAILING  
  (the trail function manages it exclusively).

### RSIExhaustion Strategy
`RSIExhaustion.mqh` is translated but **not wired** into `entries_engine()`  
because it has no corresponding flag in `Inputs.mqh` and no call in  
`Entries.mqh` in the original source. Add a `use_re_strategy` flag to  
`EAConfig` and the corresponding call in `entries_engine()` to enable it.

### Pullback & Breakout Stubs
Both `Pullback.mqh` and `Breakout.mqh` return `SIGNAL_NONE` unconditionally  
in the source. Their Python equivalents are stubs ready for implementation.

---

## Important Differences vs MQL5 Runtime

| Aspect                  | MQL5 EA                          | Python                                    |
|-------------------------|----------------------------------|-------------------------------------------|
| Tick delivery           | Terminal pushes ticks            | Polling loop (`time.sleep`)               |
| Indicator computation   | Terminal-managed, cached         | Recomputed from DataFrame each tick       |
| Bar time reference      | `iTime(_Symbol, _Period, 0)`     | `rates.index[-1]` (latest bar timestamp)  |
| Thread safety           | Single-threaded by design        | Single-threaded polling loop              |
| Order filling           | `ORDER_FILLING_IOC`              | `mt5.ORDER_FILLING_IOC` (preserved)       |
| Slippage                | `SetDeviationInPoints(10)`       | `"deviation": 10` in order request        |
| Missing: Lot scaling    | `g_initialBalance`, `g_currentScaledLot` | Scaffolded; logic not in source   |
