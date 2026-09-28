@echo off
rem Start Kisapper with evidence logging enabled.
rem Chinese word-order bugs can only be located by comparing what was typed with what the buffer holds.
rem Double-clicking bin\Kisapper.exe directly does NOT log anything.
setlocal
set KISAPPER_STATE_FILE=%TEMP%\kisapper-live.txt
set KISAPPER_TRACE_FILE=%TEMP%\kisapper-trace.txt
set KISAPPER_DUMP_FILE=%TEMP%\kisapper-dump.txt
if exist "%KISAPPER_STATE_FILE%" del "%KISAPPER_STATE_FILE%"
if exist "%KISAPPER_TRACE_FILE%" del "%KISAPPER_TRACE_FILE%"
if exist "%KISAPPER_DUMP_FILE%" del "%KISAPPER_DUMP_FILE%"
start "" "%~dp0bin\Kisapper.exe"
echo Kisapper started with logging. Keep the window open after typing. Logs:
echo   %KISAPPER_TRACE_FILE%
echo   %KISAPPER_DUMP_FILE%
