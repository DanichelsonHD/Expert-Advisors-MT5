@echo off
REM ============================================================
REM compile_dll.bat
REM Compiles bridge_dll.c into bridge.dll using MinGW-w64
REM
REM PRE-REQUISITES:
REM   1. MinGW-w64 installed (64-bit GCC)
REM      Download: https://www.mingw-w64.org/downloads/
REM      Recommended: winlibs-x86_64 standalone build
REM
REM   2. Python 3.10+ (64-bit) installed
REM      https://www.python.org/downloads/windows/
REM
REM   3. Edit PYTHON_DIR below to match your Python install path
REM ============================================================

REM ---- EDIT THESE PATHS ----
set PYTHON_DIR=C:\Python310
set MINGW_BIN=C:\mingw64\bin
set ZORRO_STRATEGY=C:\Zorro\Strategy
REM ---------------------------

set PYTHON_INCLUDE=%PYTHON_DIR%\include
set PYTHON_LIBS=%PYTHON_DIR%\libs
set PYTHON_VER=python310

REM Find python version automatically (optional)
REM for /f "tokens=*" %%i in ('python -c "import sys; print(f'python{sys.version_info.major}{sys.version_info.minor}')"') do set PYTHON_VER=%%i

echo.
echo ============================================================
echo  Compiling bridge.dll
echo  Python: %PYTHON_DIR%
echo  MinGW:  %MINGW_BIN%
echo ============================================================
echo.

%MINGW_BIN%\gcc -shared -o bridge.dll bridge_dll.c ^
    -I"%PYTHON_INCLUDE%" ^
    -L"%PYTHON_LIBS%" ^
    -l%PYTHON_VER% ^
    -Wall -O2 ^
    -Wl,--out-implib,bridge.lib

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Compilation failed. Check paths above.
    echo.
    pause
    exit /b 1
)

echo.
echo SUCCESS: bridge.dll compiled.
echo.

REM Copy DLL and Python runtime to Zorro Strategy folder
echo Copying files to %ZORRO_STRATEGY% ...
copy /Y bridge.dll "%ZORRO_STRATEGY%\bridge.dll"
copy /Y "%PYTHON_DIR%\%PYTHON_VER%.dll" "%ZORRO_STRATEGY%\%PYTHON_VER%.dll"

echo.
echo Done. Files copied to Zorro/Strategy/.
echo.
echo Next steps:
echo   1. Copy KingOfModules_DLL.c to %ZORRO_STRATEGY%\
echo   2. Edit STRATEGY_PATH in bridge_dll.c to point to your king_of_modules folder
echo   3. Recompile if you changed bridge_dll.c
echo   4. Open Zorro, select KingOfModules_DLL, click [Test]
echo.
pause
