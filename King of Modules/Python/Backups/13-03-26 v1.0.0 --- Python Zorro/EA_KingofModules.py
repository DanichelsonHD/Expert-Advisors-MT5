import time
import sys
from datetime import datetime, timezone
 
import MetaTrader5 as mt5
import pandas as pd
 
from Config import cfg
from Indicators import get_atr
from Stops import manage_trailing_stop
from Takes import manage_takes
from Entries import entries_engine, is_within_trading_hours_for_symbol
 
 
# ---------------------------------------------------------------------------
# Constants — mirror top-level EA settings
# ---------------------------------------------------------------------------
 
SYMBOL    = "EURUSD"    # Change to your symbol
TIMEFRAME = mt5.TIMEFRAME_H1   # Change to your timeframe
BARS      = 300         # How many bars to fetch on every tick
 
 
# ---------------------------------------------------------------------------
# Global state — mirrors g_initialBalance, g_currentScaledLot
# ---------------------------------------------------------------------------
 
g_initial_balance:   float = 0.0
g_current_scaled_lot: float = 0.0
 
 
# ---------------------------------------------------------------------------
# OnInit equivalent
# ---------------------------------------------------------------------------
 
def on_init() -> bool:
    """
    Mirrors OnInit().
    Connects to MT5, validates the symbol, and configures global state.
    Returns True on success, False on failure.
    """
    global g_initial_balance, g_current_scaled_lot
 
    if not mt5.initialize():
        print(f"MT5 initialize() failed. Error: {mt5.last_error()}")
        return False
 
    # Validate symbol
    if not mt5.symbol_select(SYMBOL, True):
        print(f"symbol_select({SYMBOL}) failed. Error: {mt5.last_error()}")
        mt5.shutdown()
        return False
 
    # Mirrors: g_initialBalance = AccountInfoDouble(ACCOUNT_BALANCE)
    account = mt5.account_info()
    if account is None:
        print("account_info() failed.")
        mt5.shutdown()
        return False
 
    g_initial_balance    = account.balance
    g_current_scaled_lot = cfg.initial_lot
 
    print(
        f"on_init OK | symbol={SYMBOL} | timeframe={TIMEFRAME} | "
        f"balance={g_initial_balance:.2f} | magic={cfg.magic_number}"
    )
    return True
 
 
# ---------------------------------------------------------------------------
# OnDeinit equivalent
# ---------------------------------------------------------------------------
 
def on_deinit() -> None:
    """
    Mirrors OnDeinit().
    Releases MT5 connection.
    No indicator handles to release in Python (computed on-demand).
    """
    mt5.shutdown()
    print("on_deinit OK")
 
 
# ---------------------------------------------------------------------------
# Data fetch helper
# ---------------------------------------------------------------------------
 
def fetch_rates(symbol: str, timeframe: int, bars: int) -> pd.DataFrame | None:
    """
    Fetches OHLCV data from MT5 and returns a DataFrame.
    Mirrors CopyRates usage throughout the MQL5 modules.
 
    Columns: open, high, low, close, tick_volume, spread, real_volume
    Index:   datetime (UTC)
    """
    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, bars)
    if rates is None or len(rates) == 0:
        print(f"copy_rates_from_pos failed. Error: {mt5.last_error()}")
        return None
 
    df = pd.DataFrame(rates)
    df["time"] = pd.to_datetime(df["time"], unit="s", utc=True)
    df.set_index("time", inplace=True)
    return df
 
 
# ---------------------------------------------------------------------------
# OnTick equivalent
# ---------------------------------------------------------------------------
 
def on_tick() -> None:
    """
    Mirrors OnTick().
 
    Structure (identical to MQL5):
      1. Position management runs ALWAYS (no time filter):
           - ManageTrailingStop(atr)
           - ManageTakes()
      2. Entry logic respects time filter:
           - EntriesEngine()
    """
    rates = fetch_rates(SYMBOL, TIMEFRAME, BARS)
    if rates is None:
        return
 
    # --- 1. Position management — always runs ---
    atr_result = get_atr(rates)
    if atr_result is not None:
        atr_val, _atr_avg = atr_result
        manage_trailing_stop(atr_val, SYMBOL)
 
    manage_takes(rates, SYMBOL)
 
    # --- 2. Entry logic — time-filtered ---
    if cfg.use_time_filter and not is_within_trading_hours_for_symbol(SYMBOL):
        return
 
    entries_engine(SYMBOL, rates)
 
 
# ---------------------------------------------------------------------------
# Main event loop
# ---------------------------------------------------------------------------
 
def run(tick_interval_seconds: float = 1.0) -> None:
    """
    Simple polling loop that calls on_tick() at a fixed interval.
 
    In a production setup you may prefer:
      - A scheduler (APScheduler, asyncio)
      - MT5's own DLL callback integration
      - A WebSocket price feed trigger
 
    tick_interval_seconds : how often to poll (default 1 s).
    """
    if not on_init():
        sys.exit(1)
 
    print(f"EA running. Polling every {tick_interval_seconds}s. Ctrl+C to stop.")
 
    try:
        while True:
            on_tick()
            time.sleep(tick_interval_seconds)
    except KeyboardInterrupt:
        print("\nStopped by user.")
    finally:
        on_deinit()
 
 
# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
 
if __name__ == "__main__":
    run(tick_interval_seconds=1.0)
 