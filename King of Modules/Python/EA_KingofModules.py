"""
EA_KingofModules.py — Bridge
============================
Owns the bar loop in both backtest and live modes.
Feeds OHLCV slices into KOM's entries_engine(), then routes
the resulting signal dict to BacktestEngine or mt5_bridge.
"""

import os
import sys
import time

# Ensure CWD is the project root regardless of how the script is launched.
os.chdir(os.path.dirname(os.path.abspath(__file__)))

import pandas as pd

from Chart import plot_chart
from Config import cfg
from Logger import get_logger
from Indicators import get_atr
from Stops import manage_trailing_stop
from Takes import manage_takes
from Entries import entries_engine, is_within_trading_hours_for_symbol

logger = get_logger(__name__)


# ---------------------------------------------------------------------------
# Data loading — CSV (backtest) or MT5 live feed
# ---------------------------------------------------------------------------

def _load_csv(path: str) -> pd.DataFrame:
    if not os.path.exists(path):
        logger.error("CSV file not found: %s", path)
        sys.exit(1)

    df = pd.read_csv(path)

    if "time" not in df.columns:
        logger.error("CSV missing 'time' column: %s", path)
        sys.exit(1)

    df["time"] = pd.to_datetime(df["time"])
    df.set_index("time", inplace=True)
    df.sort_index(inplace=True)

    required = ["open", "high", "low", "close"]
    missing  = [c for c in required if c not in df.columns]
    if missing:
        logger.error("CSV missing columns %s in %s", missing, path)
        sys.exit(1)

    numeric_cols = required + (["tick_volume"] if "tick_volume" in df.columns else [])
    df[numeric_cols] = df[numeric_cols].apply(pd.to_numeric, errors="coerce")
    df.dropna(subset=required, inplace=True)

    logger.info(
        "Loaded %d bars from %s | %s → %s",
        len(df), path,
        df.index[0].strftime("%Y-%m-%d %H:%M"),
        df.index[-1].strftime("%Y-%m-%d %H:%M"),
    )
    return df


def _fetch_live_rates() -> pd.DataFrame:
    from mt5_bridge import fetch_ohlcv
    return fetch_ohlcv(symbol=cfg.symbol, timeframe_str="H1", n_bars=cfg.bars_to_fetch)


# ---------------------------------------------------------------------------
# Backtest run
# ---------------------------------------------------------------------------

def run_backtest() -> None:
    from BacktestEngine import BacktestEngine, BacktestResults, BACKTEST_INITIAL_CAPITAL

    logger.info("=== BACKTEST MODE ===")
    df = _load_csv(cfg.data_path_h1)

    # Need at least enough history for all indicators before we start evaluating
    warmup = 200
    if len(df) < warmup:
        logger.error("Not enough bars for warmup (need %d, got %d).", warmup, len(df))
        return

    engine = BacktestEngine(initial_capital=BACKTEST_INITIAL_CAPITAL)

    bars      = list(df.iterrows())
    n_bars    = len(bars)

    for i in range(warmup, n_bars):
        ts, row = bars[i]

        # Bounded slice — strategies see only the most recent N candles
        lookback = cfg.max_lookback_bars
        start = max(0, i + 1 - lookback)
        rates_slice = df.iloc[start : i + 1]

        # Time filter — use bar timestamp hour
        if cfg.use_time_filter:
            bar_hour = ts.hour
            if not (cfg.start_hour <= bar_hour < cfg.end_hour):
                engine.process_bar(ts, row, None)
                continue

        # Ask KOM for signal + SL + TP
        kom_signal = entries_engine(cfg.symbol, rates_slice)

        # Feed bar + signal to backtest engine
        engine.process_bar(ts, row, kom_signal)

    # Force-close any open position at the last bar
    last_ts, last_row = bars[-1]
    engine.finalize(last_ts, float(last_row["close"]))

    results = BacktestResults(engine.trade_list, engine.equity_curve, engine.initial_capital)
    print(results.summary())
    plot_chart(df, engine.trade_list)



# ---------------------------------------------------------------------------
# Live on_init / on_deinit / on_tick
# ---------------------------------------------------------------------------

_g_initial_balance: float = 0.0


def on_init() -> bool:
    from mt5_bridge import connect, get_account_info

    global _g_initial_balance

    if not connect():
        return False

    account = get_account_info()
    if not account:
        logger.error("Could not retrieve account info.")
        return False

    _g_initial_balance = account.get("balance", 0.0)
    logger.info(
        "on_init OK | symbol=%s | balance=%.2f | magic=%d",
        cfg.symbol, _g_initial_balance, cfg.magic_number,
    )
    return True


def on_deinit() -> None:
    from mt5_bridge import disconnect
    disconnect()
    logger.info("on_deinit OK")


def on_tick() -> None:
    from mt5_bridge import send_order_from_kom_signal

    rates = _fetch_live_rates()
    if rates is None or rates.empty:
        return

    # Position management — always runs
    atr_result = get_atr(rates)
    if atr_result is not None:
        atr_val, _ = atr_result
        manage_trailing_stop(atr_val, cfg.symbol, rates)

    manage_takes(rates, cfg.symbol)

    # Time filter
    if cfg.use_time_filter and not is_within_trading_hours_for_symbol(cfg.symbol):
        return

    # Get signal from KOM
    kom_signal = entries_engine(cfg.symbol, rates)

    if kom_signal is not None and kom_signal["signal"] != "NO_TRADE":
        send_order_from_kom_signal(kom_signal, symbol=cfg.symbol)


# ---------------------------------------------------------------------------
# Live polling loop
# ---------------------------------------------------------------------------

def run_live(tick_interval_seconds: float = 1.0) -> None:
    if not on_init():
        sys.exit(1)

    logger.info("EA running live. Polling every %.1fs. Ctrl+C to stop.", tick_interval_seconds)

    try:
        while True:
            on_tick()
            time.sleep(tick_interval_seconds)
    except KeyboardInterrupt:
        logger.info("Stopped by user.")
    finally:
        on_deinit()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    if cfg.enable_backtest:
        run_backtest()
    elif cfg.enable_live_feed or cfg.enable_trading:
        run_live(tick_interval_seconds=1.0)
    else:
        logger.error("No mode enabled. Set enable_backtest or enable_live_feed in Config.py.")
