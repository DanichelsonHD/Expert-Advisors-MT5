from datetime import datetime, timezone
 
import MetaTrader5 as mt5
import pandas as pd
 
from Config import cfg, Signal
from Indicators import get_atr
from Stops import get_stop_loss
from Takes import calculate_take_profit
 
from Strategies.MeanReversion  import signal_mean_reversion
from Strategies.Pullback       import signal_pullback
from Strategies.Breakout       import signal_breakout
from Strategies.KamaTrend      import signal_kama_trend
 
 
# ---------------------------------------------------------------------------
# Time Filter — IsWithinTradingHours
# ---------------------------------------------------------------------------
 
def is_within_trading_hours() -> bool:
    """
    Mirrors IsWithinTradingHours().
    Uses MT5 server time (broker time), equivalent to TimeCurrent() in MQL5.
    """
    server_time = mt5.symbol_info_tick(mt5.symbols_get()[0].name)
    # Fallback: use UTC system time if tick unavailable
    now_hour = datetime.now(timezone.utc).hour
 
    try:
        # mt5.symbol_info_tick().time is a Unix timestamp (server/broker time)
        tick = mt5.symbol_info_tick(mt5.symbols_get()[0].name)
        now_hour = datetime.utcfromtimestamp(tick.time).hour
    except Exception:
        pass
 
    return cfg.start_hour <= now_hour < cfg.end_hour
 
 
def is_within_trading_hours_for_symbol(symbol: str) -> bool:
    """
    Preferred version: uses the symbol's own tick time (server time).
    Mirrors: TimeToStruct(TimeCurrent(), dt); dt.hour >= start && dt.hour < end
    """
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        return False
    hour = datetime.utcfromtimestamp(tick.time).hour
    return cfg.start_hour <= hour < cfg.end_hour
 
 
# ---------------------------------------------------------------------------
# Position Counter — CountOpenPositions
# ---------------------------------------------------------------------------
 
def count_open_positions(symbol: str) -> int:
    """
    Counts EA-owned open positions on symbol.
    Mirrors CountOpenPositions().
    """
    positions = mt5.positions_get(symbol=symbol)
    if not positions:
        return 0
    return sum(
        1 for p in positions
        if p.magic == cfg.magic_number
    )
 
 
# ---------------------------------------------------------------------------
# Trade Execution — ExecuteEntry
# ---------------------------------------------------------------------------
 
def execute_entry(
    signal:  Signal,
    atr:     float,
    symbol:  str,
    rates:   pd.DataFrame,
) -> None:
    """
    Mirrors ExecuteEntry().
    Respects InpMaxSimultaneousTrades limit.
    Sends a market order with computed SL and optional TP.
    """
    if signal == Signal.NONE:
        return
 
    if count_open_positions(symbol) >= cfg.max_simultaneous_trades:
        return
 
    order_type = (
        mt5.ORDER_TYPE_BUY if signal == Signal.BUY else mt5.ORDER_TYPE_SELL
    )
 
    sl  = get_stop_loss(order_type, atr, symbol, rates)
    tp  = calculate_take_profit(order_type, rates, symbol)
    lot = cfg.lot_size
 
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        print(f"execute_entry: tick unavailable for {symbol}")
        return
 
    if order_type == mt5.ORDER_TYPE_BUY:
        price = tick.ask
    else:
        price = tick.bid
 
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
        "comment":      "KingOfModules",
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
# Entries Engine — EntriesEngine (bar-gated orchestrator)
# ---------------------------------------------------------------------------
 
# Module-level bar gate (mirrors 'static datetime s_lastBarTime = 0' in MQL5)
_last_bar_time = None
 
 
def entries_engine(symbol: str, rates: pd.DataFrame) -> None:
    """
    Mirrors EntriesEngine().
 
    Called on every tick; internally gated to fire once per new bar.
    Each active strategy is evaluated independently and may trigger
    an entry up to the global simultaneous-trade limit.
 
    Parameters
    ----------
    symbol : trading symbol (e.g. "EURUSD")
    rates  : DataFrame with sufficient OHLCV history (at least 100+ bars)
    """
    global _last_bar_time
 
    # Bar gate — only proceed on a new closed bar
    current_bar_time = rates.index[-1]   # timestamp of the most recent bar
    if current_bar_time == _last_bar_time:
        return
    _last_bar_time = current_bar_time
 
    # ATR required by all entry executions
    atr_result = get_atr(rates)
    if atr_result is None:
        return
    atr_val, _atr_avg = atr_result
 
    # -----------------------------------------------------------------------
    # Strategy evaluation — each is independent (matches MQL5 EntriesEngine)
    # Order and enable flags exactly mirror the original.
    # -----------------------------------------------------------------------
 
    # 1. Mean Reversion
    s = signal_mean_reversion(rates, current_bar_time)
    if s != Signal.NONE and cfg.use_mr_strategy:
        execute_entry(s, atr_val, symbol, rates)
 
    # 2. Trend Pullback (stub)
    s = signal_pullback(rates)
    if s != Signal.NONE and cfg.use_tp_strategy:
        execute_entry(s, atr_val, symbol, rates)
 
    # 3. Trendline Breakout (stub)
    s = signal_breakout(rates)
    if s != Signal.NONE and cfg.use_tb_strategy:
        execute_entry(s, atr_val, symbol, rates)
 
    # 4. KAMA Trend
    s = signal_kama_trend(rates)
    if s != Signal.NONE and cfg.use_kt_strategy:
        execute_entry(s, atr_val, symbol, rates)