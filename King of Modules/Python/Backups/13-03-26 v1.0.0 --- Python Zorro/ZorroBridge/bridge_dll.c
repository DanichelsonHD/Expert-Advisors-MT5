///////////////////////////////////////////////////////////////////////////////
// bridge_dll.c
// Optional DLL approach — compile with MinGW on Windows
//
// This DLL embeds Python directly so Zorro can call signal functions
// WITHOUT needing a running ZorroBridgeServer.py process.
//
// HOW TO COMPILE (Windows, MinGW-w64):
//   1. Install MinGW-w64 and Python 3.10+ (64-bit)
//   2. Find your Python include and lib paths, e.g.:
//        C:\Python310\include
//        C:\Python310\libs
//   3. Run from cmd:
//        gcc -shared -o bridge.dll bridge_dll.c ^
//            -I"C:\Python310\include" ^
//            -L"C:\Python310\libs" ^
//            -lpython310 ^
//            -Wall -O2
//   4. Copy bridge.dll to your Zorro/Strategy/ folder
//   5. Copy python310.dll (from C:\Python310\) to Zorro/Strategy/ as well
//
// Then in your Zorro Lite-C script:
//   int  bridge_init(char* params_json);   -> 1=ok, 0=fail
//   int  bridge_bar(char* bar_json);       -> signal: 1, -1, or 0
//   void bridge_reset();
//   void bridge_quit();
///////////////////////////////////////////////////////////////////////////////

#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <windows.h>
#include <stdio.h>
#include <string.h>

// ---------------------------------------------------------------------------
// DLL export macro
// ---------------------------------------------------------------------------
#define EXPORT __declspec(dllexport)

// ---------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------
static int    g_py_initialized = 0;
static PyObject *g_py_module   = NULL;   // bridge_dll_helper Python module
static PyObject *g_fn_init     = NULL;
static PyObject *g_fn_bar      = NULL;
static PyObject *g_fn_reset    = NULL;

// ---------------------------------------------------------------------------
// Internal: call a Python function with one string arg, returns int
// ---------------------------------------------------------------------------
static int call_py_func_str(PyObject *fn, const char *arg)
{
    if (!fn) return -1;

    PyObject *py_arg  = PyUnicode_FromString(arg);
    PyObject *py_result = PyObject_CallOneArg(fn, py_arg);
    Py_XDECREF(py_arg);

    if (!py_result) {
        PyErr_Print();
        return -1;
    }

    int result = (int)PyLong_AsLong(py_result);
    Py_DECREF(py_result);
    return result;
}

// ---------------------------------------------------------------------------
// bridge_dll_helper.py
// This tiny Python module is embedded as a string and exec'd at init.
// It imports your actual EA modules and exposes three functions.
// Edit STRATEGY_PATH to point to your king_of_modules folder.
// ---------------------------------------------------------------------------
static const char *HELPER_CODE =
    "import sys, json\n"
    "\n"
    "# ---- EDIT THIS PATH ----\n"
    "STRATEGY_PATH = r'C:\\Users\\YourName\\king_of_modules'\n"
    "# -------------------------\n"
    "\n"
    "if STRATEGY_PATH not in sys.path:\n"
    "    sys.path.insert(0, STRATEGY_PATH)\n"
    "\n"
    "from collections import deque\n"
    "import pandas as pd\n"
    "from Config import cfg, EAConfig, Signal, StopMode, TakeMode\n"
    "from Indicators import get_atr\n"
    "from Strategies.MeanReversion import signal_mean_reversion, EntryState\n"
    "from Strategies.KamaTrend import signal_kama_trend\n"
    "from Strategies.Pullback  import signal_pullback\n"
    "from Strategies.Breakout  import signal_breakout\n"
    "import Strategies.MeanReversion as _mr_module\n"
    "\n"
    "BUFFER_SIZE = 300\n"
    "MIN_BARS    = 100\n"
    "_buf = deque(maxlen=BUFFER_SIZE)\n"
    "\n"
    "def _to_df():\n"
    "    if len(_buf) < MIN_BARS:\n"
    "        return None\n"
    "    df = pd.DataFrame(list(_buf))\n"
    "    df['time'] = pd.to_datetime(df['time'], unit='s', tz='UTC')\n"
    "    df.set_index('time', inplace=True)\n"
    "    return df\n"
    "\n"
    "def _apply_params(params):\n"
    "    valid = {f for f in cfg.__dataclass_fields__}\n"
    "    for k, v in params.items():\n"
    "        if k not in valid: continue\n"
    "        if k == 'stop_mode':  v = StopMode(int(v))\n"
    "        elif k == 'take_mode': v = TakeMode(int(v))\n"
    "        else:\n"
    "            ft = type(getattr(cfg, k))\n"
    "            try: v = ft(v)\n"
    "            except: pass\n"
    "        setattr(cfg, k, v)\n"
    "\n"
    "def dll_init(params_json_str):\n"
    "    try:\n"
    "        params = json.loads(params_json_str)\n"
    "        _apply_params(params)\n"
    "        _buf.clear()\n"
    "        _mr_module._mr_state = EntryState.IDLE\n"
    "        return 1\n"
    "    except Exception as e:\n"
    "        print(f'dll_init error: {e}')\n"
    "        return 0\n"
    "\n"
    "def dll_bar(bar_json_str):\n"
    "    try:\n"
    "        bar = json.loads(bar_json_str)\n"
    "        _buf.append(bar)\n"
    "        df = _to_df()\n"
    "        if df is None: return 0\n"
    "        t = df.index[-1]\n"
    "        if cfg.use_mr_strategy:\n"
    "            s = signal_mean_reversion(df, t)\n"
    "            if s != Signal.NONE: return int(s)\n"
    "        if cfg.use_kt_strategy:\n"
    "            s = signal_kama_trend(df)\n"
    "            if s != Signal.NONE: return int(s)\n"
    "        return 0\n"
    "    except Exception as e:\n"
    "        print(f'dll_bar error: {e}')\n"
    "        return 0\n"
    "\n"
    "def dll_reset():\n"
    "    _buf.clear()\n"
    "    _mr_module._mr_state = EntryState.IDLE\n"
    "    return 1\n";


// ---------------------------------------------------------------------------
// EXPORT: bridge_init
// params_json: JSON string with EAConfig fields
// Returns: 1 = success, 0 = failure
// ---------------------------------------------------------------------------
EXPORT int bridge_init(const char *params_json)
{
    if (!g_py_initialized)
    {
        Py_Initialize();
        if (!Py_IsInitialized()) {
            fprintf(stderr, "bridge_dll: Py_Initialize() failed\n");
            return 0;
        }
        g_py_initialized = 1;
    }

    // Exec the helper code in a fresh module
    PyObject *main_module = PyImport_AddModule("__main__");
    PyObject *global_dict = PyModule_GetDict(main_module);

    PyObject *result = PyRun_String(
        HELPER_CODE, Py_file_input, global_dict, global_dict
    );

    if (!result) {
        PyErr_Print();
        fprintf(stderr, "bridge_dll: Failed to exec helper code\n");
        return 0;
    }
    Py_DECREF(result);

    // Get function references
    g_fn_init  = PyDict_GetItemString(global_dict, "dll_init");
    g_fn_bar   = PyDict_GetItemString(global_dict, "dll_bar");
    g_fn_reset = PyDict_GetItemString(global_dict, "dll_reset");

    if (!g_fn_init || !g_fn_bar || !g_fn_reset) {
        fprintf(stderr, "bridge_dll: Failed to get function references\n");
        return 0;
    }

    return call_py_func_str(g_fn_init, params_json);
}


// ---------------------------------------------------------------------------
// EXPORT: bridge_bar
// bar_json: JSON string {"time":..., "open":..., "high":..., "low":...,
//                        "close":..., "volume":...}
// Returns: 1=BUY, -1=SELL, 0=NONE
// ---------------------------------------------------------------------------
EXPORT int bridge_bar(const char *bar_json)
{
    if (!g_py_initialized || !g_fn_bar) return 0;
    return call_py_func_str(g_fn_bar, bar_json);
}


// ---------------------------------------------------------------------------
// EXPORT: bridge_reset
// Resets Python strategy state between optimization runs
// ---------------------------------------------------------------------------
EXPORT void bridge_reset(void)
{
    if (!g_py_initialized || !g_fn_reset) return;

    PyObject *result = PyObject_CallNoArgs(g_fn_reset);
    Py_XDECREF(result);
}


// ---------------------------------------------------------------------------
// EXPORT: bridge_quit
// ---------------------------------------------------------------------------
EXPORT void bridge_quit(void)
{
    if (g_py_initialized) {
        Py_Finalize();
        g_py_initialized = 0;
        g_fn_init  = NULL;
        g_fn_bar   = NULL;
        g_fn_reset = NULL;
    }
}


// ---------------------------------------------------------------------------
// DllMain — required for Windows DLLs
// ---------------------------------------------------------------------------
BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved)
{
    return TRUE;
}
