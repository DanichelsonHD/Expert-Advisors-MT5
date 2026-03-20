"""
KING QUANT 5.0 — Backtest Engine
Receives signal, SL, and TP from KOM's entries_engine().
"""

import pandas as pd
from dataclasses import dataclass
from typing import Optional

from Config import cfg
from Logger import get_logger

logger = get_logger(__name__)


# ---------------------------------------------------------------------------
# Backtest-specific constants (not in KOM cfg — backtest-only concerns)
# ---------------------------------------------------------------------------

BACKTEST_INITIAL_CAPITAL    = 10000.0
BACKTEST_COMMISSION_PER_LOT = 7.0
BACKTEST_SLIPPAGE_POINTS    = 3
BACKTEST_SPREAD_POINTS      = 20
BACKTEST_FILL_MODEL         = "CLOSE"
BACKTEST_SINGLE_TRADE_MODE  = True

_POINT_VALUE = cfg.symbol_point


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class OpenPosition:
    direction:   str
    entry_time:  pd.Timestamp
    entry_price: float
    stop_loss:   float
    take_profit: float
    lot_size:    float


@dataclass
class TradeResult:
    direction:   str
    entry_time:  pd.Timestamp
    exit_time:   pd.Timestamp
    entry_price: float
    exit_price:  float
    lot_size:    float
    net_pnl:     float
    equity_after: float


# ---------------------------------------------------------------------------
# BacktestEngine
# ---------------------------------------------------------------------------

class BacktestEngine:

    def __init__(self, initial_capital: float = BACKTEST_INITIAL_CAPITAL):
        self.initial_capital  = initial_capital
        self.equity           = initial_capital
        self.open_position: Optional[OpenPosition] = None
        self.trade_list:    list[TradeResult]       = []
        self.equity_curve:  list[float]             = []

    def process_bar(
        self,
        ts:          pd.Timestamp,
        row:         pd.Series,
        kom_signal:  Optional[dict],
    ) -> None:
        """
        Process a single bar.

        Parameters
        ----------
        ts         : timestamp of the bar
        row        : OHLCV series for the bar (must have high, low, close)
        kom_signal : dict returned by entries_engine(), or None
                     Keys: "signal" (str), "sl" (float), "tp" (float), "atr" (float)
        """
        # 1. Check exit on open position before considering new entry
        if self.open_position is not None:
            self._check_exit(ts, row)

        # 2. Open new position if no position open and KOM provided a signal
        if (
            self.open_position is None
            and kom_signal is not None
            and kom_signal["signal"] in ("BUY", "SELL")
        ):
            if BACKTEST_SINGLE_TRADE_MODE or self.open_position is None:
                price = self._apply_slippage(kom_signal["signal"], float(row["close"]))
                self._open_trade(
                    ts,
                    kom_signal["signal"],
                    price,
                    kom_signal["sl"],
                    kom_signal["tp"],
                )

        self.equity_curve.append(self.equity)

    def finalize(self, last_ts: pd.Timestamp, last_close: float) -> None:
        """Force-close any remaining open position at the last bar's close."""
        if self.open_position is not None:
            self._close_trade(last_ts, last_close)

    # -----------------------------------------------------------------------
    # Internal helpers
    # -----------------------------------------------------------------------

    def _apply_slippage(self, direction: str, price: float) -> float:
        slip = (BACKTEST_SPREAD_POINTS + BACKTEST_SLIPPAGE_POINTS) * _POINT_VALUE
        if direction == "BUY":
            return price + slip
        return price - slip

    def _open_trade(
        self,
        ts:        pd.Timestamp,
        direction: str,
        price:     float,
        sl:        float,
        tp:        float,
    ) -> None:
        lot = cfg.lot_size
        self.open_position = OpenPosition(
            direction=direction,
            entry_time=ts,
            entry_price=price,
            stop_loss=sl,
            take_profit=tp,
            lot_size=lot,
        )
        logger.info(
            "OPEN %s | time=%s | price=%.5f | sl=%.5f | tp=%.5f | lot=%.2f",
            direction, ts, price, sl, tp, lot,
        )

    def _check_exit(self, ts: pd.Timestamp, row: pd.Series) -> None:
        pos = self.open_position
        hi  = float(row["high"])
        lo  = float(row["low"])

        if pos.direction == "BUY":
            if pos.stop_loss > 0.0 and lo <= pos.stop_loss:
                self._close_trade(ts, pos.stop_loss)
            elif pos.take_profit > 0.0 and hi >= pos.take_profit:
                self._close_trade(ts, pos.take_profit)
        else:
            if pos.stop_loss > 0.0 and hi >= pos.stop_loss:
                self._close_trade(ts, pos.stop_loss)
            elif pos.take_profit > 0.0 and lo <= pos.take_profit:
                self._close_trade(ts, pos.take_profit)

    def _close_trade(self, ts: pd.Timestamp, exit_price: float) -> None:
        pos  = self.open_position
        diff = exit_price - pos.entry_price

        if pos.direction == "SELL":
            diff = -diff

        # PnL: diff / point * pip_value_per_lot * lot
        pnl = (diff / _POINT_VALUE) * 1.0 * pos.lot_size
        commission = BACKTEST_COMMISSION_PER_LOT * pos.lot_size
        net_pnl = pnl - commission

        self.equity += net_pnl

        trade = TradeResult(
            direction=pos.direction,
            entry_time=pos.entry_time,
            exit_time=ts,
            entry_price=pos.entry_price,
            exit_price=exit_price,
            lot_size=pos.lot_size,
            net_pnl=net_pnl,
            equity_after=self.equity,
        )
        self.trade_list.append(trade)
        self.open_position = None

        logger.info(
            "CLOSE %s | exit=%s | price=%.5f | pnl=%.2f | equity=%.2f",
            trade.direction, ts, exit_price, net_pnl, self.equity,
        )


# ---------------------------------------------------------------------------
# BacktestResults
# ---------------------------------------------------------------------------

class BacktestResults:

    def __init__(
        self,
        trades:          list[TradeResult],
        equity_curve:    list[float],
        initial_capital: float,
    ):
        self.trade_list      = trades
        self.equity_curve    = equity_curve
        self.initial_capital = initial_capital

    def summary(self) -> str:
        if not self.trade_list:
            return "No trades executed."

        net_pnl    = sum(t.net_pnl for t in self.trade_list)
        wins       = [t for t in self.trade_list if t.net_pnl > 0]
        losses     = [t for t in self.trade_list if t.net_pnl <= 0]
        win_rate   = len(wins) / len(self.trade_list) * 100

        avg_win    = sum(t.net_pnl for t in wins)  / len(wins)  if wins   else 0.0
        avg_loss   = sum(t.net_pnl for t in losses) / len(losses) if losses else 0.0

        return (
            f"\n{'='*50}\n"
            f"  BACKTEST RESULTS\n"
            f"{'='*50}\n"
            f"  Trades       : {len(self.trade_list)}\n"
            f"  Wins         : {len(wins)}  |  Losses: {len(losses)}\n"
            f"  Win Rate     : {win_rate:.1f}%\n"
            f"  Avg Win      : ${avg_win:.2f}\n"
            f"  Avg Loss     : ${avg_loss:.2f}\n"
            f"  Net PnL      : ${net_pnl:.2f}\n"
            f"  Final Equity : ${self.initial_capital + net_pnl:.2f}\n"
            f"{'='*50}\n"
        )
