from datetime import datetime, timezone
from typing import Optional

import pandas as pd

from Config import cfg, Signal
from Indicators import get_atr
from Stops import get_stop_loss
from Takes import calculate_take_profit

from Strategies.MeanReversion import signal_mean_reversion
from Strategies.Pullback      import signal_pullback
from Strategies.Breakout      import signal_breakout
from Strategies.KamaTrend     import signal_kama_trend

try:
    import MetaTrader5 as mt5
    _MT5_AVAILABLE = True
except ImportError:
    _MT5_AVAILABLE = False


# ---------------------------------------------------------------------------
# Signal translation — KOM Signal enum → KQ5 string constants
# ---------------------------------------------------------------------------

_SIGNAL_MAP: dict[Signal, str] = {
    Signal.BUY:  "BUY",
    Signal.SELL: "SELL",
    Signal.NONE: "NO_TRADE",
}


def signal_to_str(signal: Signal) -> str:
    return _SIGNAL_MAP.get(signal, "NO_TRADE")


# ---------------------------------------------------------------------------
# Time Filter
# ---------------------------------------------------------------------------

def is_within_trading_hours_for_symbol(symbol: str) -> bool:
    if _MT5_AVAILABLE and (cfg.enable_live_feed or cfg.enable_trading):
        tick = mt5.symbol_info_tick(symbol)
        if tick is not None:
            hour = datetime.utcfromtimestamp(tick.time).hour
            return cfg.start_hour <= hour < cfg.end_hour
    # Backtest: use bar timestamp — caller passes rates; fallback to UTC now
    hour = datetime.now(timezone.utc).hour
    return cfg.start_hour <= hour < cfg.end_hour


# ---------------------------------------------------------------------------
# Position Counter (live only)
# ---------------------------------------------------------------------------

def count_open_positions(symbol: str) -> int:
    if not _MT5_AVAILABLE or not (cfg.enable_live_feed or cfg.enable_trading):
        return 0
    positions = mt5.positions_get(symbol=symbol)
    if not positions:
        return 0
    return sum(1 for p in positions if p.magic == cfg.magic_number)


# ---------------------------------------------------------------------------
# Trade Execution — live path only
# ---------------------------------------------------------------------------

def execute_entry(
    signal:    Signal,
    atr:       float,
    symbol:    str,
    rates:     pd.DataFrame,
) -> None:
    if signal == Signal.NONE:
        return

    if not _MT5_AVAILABLE or not (cfg.enable_live_feed or cfg.enable_trading):
        return

    if count_open_positions(symbol) >= cfg.max_simultaneous_trades:
        return

    order_type = mt5.ORDER_TYPE_BUY if signal == Signal.BUY else mt5.ORDER_TYPE_SELL

    sl  = get_stop_loss(order_type, atr, symbol, rates)
    tp  = calculate_take_profit(order_type, rates, symbol)
    lot = cfg.lot_size

    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        print(f"execute_entry: tick unavailable for {symbol}")
        return

    price = tick.ask if order_type == mt5.ORDER_TYPE_BUY else tick.bid

    request = {
        "action":       mt5.TRADE_ACTION_DEAL,
        "symbol":       symbol,
        "volume":       lot,
        "type":         order_type,
        "price":        price,
        "sl":           sl,
        "tp":           tp,
        "deviation":    10,
        "magic":        cfg.magic_number,
        "comment":      cfg.order_comment,
        "type_time":    mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }

    result = mt5.order_send(request)
    if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
        code = result.retcode if result else "N/A"
        print(f"execute_entry: order_send failed. retcode={code}")
    else:
        direction = "BUY" if order_type == mt5.ORDER_TYPE_BUY else "SELL"
        print(
            f"execute_entry: {direction} sent. "
            f"ticket={result.order} price={price:.5f} sl={sl:.5f} tp={tp:.5f}"
        )


# ---------------------------------------------------------------------------
# Bar gate state
# ---------------------------------------------------------------------------

_last_bar_time = None


# ---------------------------------------------------------------------------
# Entries Engine
# ---------------------------------------------------------------------------

def entries_engine(
    symbol: str,
    rates:  pd.DataFrame,
) -> Optional[dict]:
    """
    Called once per bar (gated internally).

    Live mode  : evaluates active strategies, calls execute_entry(), returns None.
    Backtest mode : evaluates active strategies, returns the first triggered
                    signal as a dict for BacktestEngine to consume, or None.

    Return dict schema:
        {
            "signal": str,   # "BUY" | "SELL" | "NO_TRADE"
            "sl":     float,
            "tp":     float,
            "atr":    float,
        }
    """
    global _last_bar_time

    current_bar_time = rates.index[-1]
    if current_bar_time == _last_bar_time:
        return None
    _last_bar_time = current_bar_time

    atr_result = get_atr(rates)
    if atr_result is None:
        return None
    atr_val, _atr_avg = atr_result

    # ORDER_TYPE_BUY = 0, ORDER_TYPE_SELL = 1 (numeric, no MT5 import needed)
    _BUY  = 0
    _SELL = 1

    strategies = []

    if cfg.use_mr_strategy:
        strategies.append(signal_mean_reversion(rates, current_bar_time))

    if cfg.use_tp_strategy:
        strategies.append(signal_pullback(rates))

    if cfg.use_tb_strategy:
        strategies.append(signal_breakout(rates))

    if cfg.use_kt_strategy:
        strategies.append(signal_kama_trend(rates))

    for s in strategies:
        if s == Signal.NONE:
            continue

        order_type = _BUY if s == Signal.BUY else _SELL
        sl = get_stop_loss(order_type, atr_val, symbol, rates)
        tp = calculate_take_profit(order_type, rates, symbol)

        if cfg.enable_backtest:
            return {
                "signal": signal_to_str(s),
                "sl":     sl,
                "tp":     tp,
                "atr":    atr_val,
            }

        # Live path — execute and keep evaluating remaining strategies
        execute_entry(s, atr_val, symbol, rates)

    return None
