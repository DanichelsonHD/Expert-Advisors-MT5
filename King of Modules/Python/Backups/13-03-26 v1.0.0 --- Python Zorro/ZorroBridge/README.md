# Zorro ↔ Python Bridge — EA_KingofModules

Two integration paths. Choose one.

---

## Path A — Socket Bridge (recommended for beginners)

No compilation needed. Python stays as Python.

```
[Zorro Test/Optimize]
        │
        │  TCP localhost:7777
        │
[ZorroBridgeServer.py]
        │
[king_of_modules/  ← your EA Python files]
```

### Setup

**1. Folder layout on your machine:**
```
C:\king_of_modules\
    Config.py
    Indicators.py
    Entries.py
    Stops.py
    Takes.py
    Strategies\
        __init__.py
        MeanReversion.py
        KamaTrend.py
        Pullback.py
        Breakout.py
        RSIExhaustion.py
    zorro_bridge\
        ZorroBridgeServer.py     ← start this first
        KingOfModules.c          ← copy to Zorro/Strategy/
```

**2. Edit ZorroBridgeServer.py:**
```python
# Line ~14 — adjust the import path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
# This assumes ZorroBridgeServer.py is one level inside king_of_modules/
# If it's elsewhere, use the absolute path:
sys.path.insert(0, r"C:\king_of_modules")
```

**3. Copy KingOfModules.c to your Zorro Strategy folder:**
```
C:\Zorro\Strategy\KingOfModules.c
```

**4. Start the Python server:**
```cmd
cd C:\king_of_modules\zorro_bridge
python ZorroBridgeServer.py
```
You should see:
```
[ZorroBridge] Listening on 127.0.0.1:7777
[ZorroBridge] Waiting for Zorro connection...
```

**5. Open Zorro:**
- Asset: EURUSD
- Select script: KingOfModules
- Click **[Test]** → backtest runs
- Click **[Optimize]** → parameter sweep runs

---

## Path B — DLL Bridge (faster, no running server needed)

Python is embedded inside `bridge.dll`. Zorro loads it directly.

### Files
```
bridge_dll.c         ← C source for the DLL
compile_dll.bat      ← compilation script
KingOfModules_DLL.c  ← Zorro script that uses the DLL
```

### Step 1 — Install prerequisites

- **MinGW-w64** (64-bit GCC for Windows)
  https://github.com/niXman/mingw-builds-binaries/releases
  Download: `x86_64-*-release-win32-seh-*.7z`
  Extract to `C:\mingw64\`

- **Python 3.10+ (64-bit)**
  https://www.python.org/downloads/windows/
  Install to `C:\Python310\`

### Step 2 — Edit paths in bridge_dll.c

Open `bridge_dll.c` and find:
```c
"STRATEGY_PATH = r'C:\\Users\\YourName\\king_of_modules'\n"
```
Change it to your actual path, e.g.:
```c
"STRATEGY_PATH = r'C:\\Trading\\king_of_modules'\n"
```

### Step 3 — Edit paths in compile_dll.bat

```bat
set PYTHON_DIR=C:\Python310      ← your Python install
set MINGW_BIN=C:\mingw64\bin     ← your MinGW bin folder
set ZORRO_STRATEGY=C:\Zorro\Strategy
```

### Step 4 — Compile

```cmd
compile_dll.bat
```

On success:
```
SUCCESS: bridge.dll compiled.
Done. Files copied to Zorro/Strategy/.
```

### Step 5 — Copy Zorro script

```
Copy KingOfModules_DLL.c  →  C:\Zorro\Strategy\
```

### Step 6 — Run in Zorro

- Select script: **KingOfModules_DLL**
- Click **[Test]** or **[Optimize]**

---

## Optimization Parameters

Both scripts use `slider()` calls (currently commented out).
To activate a parameter sweep, uncomment the lines in the `INITRUN` block:

```c
// In KingOfModules.c or KingOfModules_DLL.c, INITRUN block:
slider(1, p_rsi_period,      10, 20,   1,    "RSI Period");
slider(2, p_rsi_oversold,    20, 40,   5,    "RSI Oversold");
slider(3, p_rsi_overbought,  60, 80,   5,    "RSI Overbought");
slider(4, p_stop_multiplier,  1.0, 3.0, 0.25, "Stop Multiplier");
slider(5, p_atr_mr_mult,     0.8, 1.2,  0.05, "ATR MR Filter");
slider(6, p_kama_period,      10, 20,   2,    "KAMA Period");
slider(7, p_adx_comparison,   18, 28,   2,    "ADX Threshold");
```

Zorro will sweep all combinations and report the best set.
Use **[Optimize]** mode in Zorro, then click **[Result]** to see the surface.

---

## Protocol Reference (Socket Bridge)

All messages are newline-delimited JSON over TCP localhost:7777.

| Direction      | Message                                      | Meaning                    |
|----------------|----------------------------------------------|----------------------------|
| Zorro → Python | `{"cmd":"init","params":{...}}`              | Start session, set params  |
| Zorro → Python | `{"cmd":"bar","bar":{time,open,high,low,close,volume}}` | Feed one bar  |
| Zorro → Python | `{"cmd":"reset"}`                            | Reset state (new opt run)  |
| Zorro → Python | `{"cmd":"quit"}`                             | End session                |
| Python → Zorro | `{"status":"ok","signal":1}`                 | BUY signal                 |
| Python → Zorro | `{"status":"ok","signal":-1}`                | SELL signal                |
| Python → Zorro | `{"status":"ok","signal":0}`                 | No signal                  |
| Python → Zorro | `{"status":"error","msg":"..."}`             | Error                      |

---

## Comparison

| Feature               | Socket Bridge (Path A)    | DLL Bridge (Path B)         |
|-----------------------|---------------------------|-----------------------------|
| Setup complexity      | Low                       | Medium (needs GCC)          |
| Speed (backtesting)   | ~1-3ms per bar            | ~0.1ms per bar              |
| Requires server       | Yes (ZorroBridgeServer.py)| No                          |
| Debug Python code     | Easy (print to console)   | Harder (stdout captured)    |
| Recompile needed?     | Never                     | On every C change           |
| Works on Linux/Mac?   | Python side yes, Zorro no | No (Windows DLL only)       |
| Recommended for       | Development, testing      | Production optimization     |
