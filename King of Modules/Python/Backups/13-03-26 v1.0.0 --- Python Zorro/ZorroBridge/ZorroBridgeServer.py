"""
ZorroBridgeServer.py
====================
TCP socket server that acts as the Python engine for Zorro backtesting.

Architecture:
    Zorro (Lite-C script)
        │
        │  TCP socket  localhost:7777
        │
        ▼
    ZorroBridgeServer.py   ← this file
        │
        ├── Config.py          (parameters injected by Zorro)
        ├── Indicators.py      (all indicator computation)
        └── Strategies/        (MeanReversion, KamaTrend, etc.)

Protocol (newline-delimited JSON):
    Zorro → Python:
        {"cmd": "init",   "params": { ...EAConfig fields... }}
        {"cmd": "bar",    "bar": { "time":..., "open":..., "high":...,
                                   "low":..., "close":..., "volume":... }}
        {"cmd": "reset"}        ← resets strategy state between runs
        {"cmd": "quit"}

    Python → Zorro:
        {"status": "ok"}
        {"status": "ok", "signal": 1}    1=BUY, -1=SELL, 0=NONE
        {"status": "error", "msg": "..."}

Usage:
    python ZorroBridgeServer.py           (default port 7777)
    python ZorroBridgeServer.py 7778      (custom port)
"""

import sys
import json
import socket
import traceback
from collections import deque
from typing import Optional

import pandas as pd
import numpy as np

# ---------------------------------------------------------------------------
# Add parent folder to path so we can import the EA modules
# Edit this path to match your project layout
# ---------------------------------------------------------------------------
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from Config import cfg, EAConfig, Signal, StopMode, TakeMode
from Indicators import get_atr
from Strategies.MeanReversion import (
    signal_mean_reversion,
    EntryState,
    _mr_state,
)
from Strategies.KamaTrend import signal_kama_trend
from Strategies.Pullback   import signal_pullback
from Strategies.Breakout   import signal_breakout

import Strategies.MeanReversion as _mr_module   # for state reset


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULT_PORT = 7777
BUFFER_SIZE  = 300          # bars kept in rolling window (matches EA BARS=300)
MIN_BARS     = 100          # minimum bars before signals are evaluated


# ---------------------------------------------------------------------------
# Rolling bar buffer
# ---------------------------------------------------------------------------

class BarBuffer:
    """
    Maintains a rolling window of OHLCV bars as a pandas DataFrame.
    Zorro feeds bars one at a time; we keep the last BUFFER_SIZE.
    """

    COLUMNS = ["open", "high", "low", "close", "volume"]

    def __init__(self, maxlen: int = BUFFER_SIZE):
        self._buf: deque = deque(maxlen=maxlen)

    def push(self, bar: dict) -> None:
        self._buf.append({
            "time":   pd.Timestamp(bar["time"], unit="s", tz="UTC"),
            "open":   float(bar["open"]),
            "high":   float(bar["high"]),
            "low":    float(bar["low"]),
            "close":  float(bar["close"]),
            "volume": float(bar.get("volume", 0)),
        })

    def to_dataframe(self) -> Optional[pd.DataFrame]:
        if len(self._buf) < MIN_BARS:
            return None
        df = pd.DataFrame(list(self._buf))
        df.set_index("time", inplace=True)
        return df

    def __len__(self) -> int:
        return len(self._buf)

    def clear(self) -> None:
        self._buf.clear()


# ---------------------------------------------------------------------------
# Config injection
# ---------------------------------------------------------------------------

def apply_params(params: dict) -> None:
    """
    Injects Zorro-supplied parameters into the global cfg singleton.
    Only keys that exist in EAConfig are accepted — unknown keys are ignored.
    Enum fields (stop_mode, take_mode) accept integer values.
    """
    valid_fields = {f.name for f in cfg.__dataclass_fields__.values()}  # type: ignore

    for key, value in params.items():
        if key not in valid_fields:
            continue

        # Enum coercion
        if key == "stop_mode":
            value = StopMode(int(value))
        elif key == "take_mode":
            value = TakeMode(int(value))
        else:
            # Coerce to the declared type
            field_type = type(getattr(cfg, key))
            try:
                value = field_type(value)
            except (TypeError, ValueError):
                pass

        setattr(cfg, key, value)


# ---------------------------------------------------------------------------
# Strategy state reset
# ---------------------------------------------------------------------------

def reset_strategy_state() -> None:
    """
    Resets all persistent (static) strategy state.
    Called by Zorro between optimization runs or at the start of each backtest.
    """
    _mr_module._mr_state = EntryState.IDLE

    # Reset bar gate in entries (if imported)
    try:
        import Entries as _entries_module
        _entries_module._last_bar_time = None
    except ImportError:
        pass


# ---------------------------------------------------------------------------
# Signal computation
# ---------------------------------------------------------------------------

def compute_signal(rates: pd.DataFrame) -> int:
    """
    Evaluates all active strategies against the current bar window.
    Returns the first non-NONE signal found (matches MQL5 priority order).

    Returns: 1 (BUY), -1 (SELL), 0 (NONE)
    """
    current_bar_time = rates.index[-1]

    # Mean Reversion
    if cfg.use_mr_strategy:
        s = signal_mean_reversion(rates, current_bar_time)
        if s != Signal.NONE:
            return int(s)

    # Trend Pullback (stub)
    if cfg.use_tp_strategy:
        s = signal_pullback(rates)
        if s != Signal.NONE:
            return int(s)

    # Trendline Breakout (stub)
    if cfg.use_tb_strategy:
        s = signal_breakout(rates)
        if s != Signal.NONE:
            return int(s)

    # KAMA Trend
    if cfg.use_kt_strategy:
        s = signal_kama_trend(rates)
        if s != Signal.NONE:
            return int(s)

    return 0


# ---------------------------------------------------------------------------
# Request handlers
# ---------------------------------------------------------------------------

def handle_init(payload: dict, buf: BarBuffer) -> dict:
    params = payload.get("params", {})
    apply_params(params)
    buf.clear()
    reset_strategy_state()
    print(f"[INIT] MR={cfg.use_mr_strategy} KT={cfg.use_kt_strategy} "
          f"stop_mode={cfg.stop_mode} lot={cfg.lot_size}")
    return {"status": "ok"}


def handle_bar(payload: dict, buf: BarBuffer) -> dict:
    bar = payload.get("bar")
    if bar is None:
        return {"status": "error", "msg": "missing 'bar' field"}

    buf.push(bar)

    rates = buf.to_dataframe()
    if rates is None:
        # Not enough bars yet — return NONE without error
        return {"status": "ok", "signal": 0}

    signal = compute_signal(rates)
    return {"status": "ok", "signal": signal}


def handle_reset(buf: BarBuffer) -> dict:
    buf.clear()
    reset_strategy_state()
    return {"status": "ok"}


# ---------------------------------------------------------------------------
# Server loop
# ---------------------------------------------------------------------------

def serve(port: int = DEFAULT_PORT) -> None:
    buf = BarBuffer(maxlen=BUFFER_SIZE)

    server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_sock.bind(("127.0.0.1", port))
    server_sock.listen(1)

    print(f"[ZorroBridge] Listening on 127.0.0.1:{port}")
    print(f"[ZorroBridge] Waiting for Zorro connection...")

    while True:
        conn, addr = server_sock.accept()
        print(f"[ZorroBridge] Zorro connected from {addr}")
        conn.settimeout(60.0)

        try:
            _serve_connection(conn, buf)
        except Exception:
            traceback.print_exc()
        finally:
            conn.close()
            print(f"[ZorroBridge] Connection closed. Waiting for next run...")


def _serve_connection(conn: socket.socket, buf: BarBuffer) -> None:
    """Handles one complete Zorro session (one backtest run)."""
    leftover = ""

    while True:
        try:
            chunk = conn.recv(4096).decode("utf-8")
        except socket.timeout:
            print("[ZorroBridge] Connection timed out.")
            break

        if not chunk:
            break   # Zorro disconnected

        leftover += chunk

        # Process all complete newline-delimited JSON messages
        while "\n" in leftover:
            line, leftover = leftover.split("\n", 1)
            line = line.strip()
            if not line:
                continue

            try:
                payload = json.loads(line)
            except json.JSONDecodeError as e:
                response = {"status": "error", "msg": f"JSON parse error: {e}"}
                _send(conn, response)
                continue

            cmd = payload.get("cmd", "")

            if cmd == "init":
                response = handle_init(payload, buf)
            elif cmd == "bar":
                response = handle_bar(payload, buf)
            elif cmd == "reset":
                response = handle_reset(buf)
            elif cmd == "quit":
                _send(conn, {"status": "ok"})
                return
            else:
                response = {"status": "error", "msg": f"unknown cmd: {cmd}"}

            _send(conn, response)


def _send(conn: socket.socket, obj: dict) -> None:
    msg = json.dumps(obj) + "\n"
    conn.sendall(msg.encode("utf-8"))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    serve(port)
