@echo off
rem run_tests.bat -- run the bitarray test suite.  Run build.bat first.
rem Written by Claude (an AI model made by Anthropic) for Eric Taylor.  Run on two 64-bit Windows 10 machines with Visual Studio 2022: see README.md.
rem
rem   run_tests.bat --tclsh C:\path\to\bin\tclsh91.exe
rem Options:
rem   --tclsh FILE    the Tcl 9.1 shell to test with (use the one you built against); default: %%TCLSH%% or the first
rem                   tclsh91.exe, tclsh90.exe or tclsh.exe on your PATH, if it is Tcl 9
rem   --lib FILE      the extension to load (default: bitarray.dll next to this file)
rem   -h, --help
rem Expected last line:   bitarray.test:	Total	315	Passed	308	Skipped	7	Failed	0   (1 reads /proc; 6 are the core-bug tests: run them with  tclsh91 tests\bitarray.test -constraints coreTypeLoss)
rem (one test, mem-1.1, is skipped on Windows because it reads /proc)
setlocal EnableExtensions
set "HERE=%~dp0"
set "TCLSH_ARG="
set "LIB=%HERE%bitarray.dll"

:args
if "%~1"=="" goto argsdone
if /i "%~1"=="--tclsh" goto a_tclsh
if /i "%~1"=="--lib" goto a_lib
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
echo run_tests.bat: unknown argument: %~1 1>&2
exit /b 2
:a_tclsh
if "%~2"=="" goto needarg
set "TCLSH_ARG=%~2"
shift
shift
goto args
:a_lib
if "%~2"=="" goto needarg
set "LIB=%~2"
shift
shift
goto args
:needarg
echo run_tests.bat: %~1 needs an argument 1>&2
exit /b 2

:argsdone
set "T=%TCLSH_ARG%"
if not defined T set "T=%TCLSH%"
if defined T goto have_t
for %%N in (tclsh91.exe tclsh90.exe tclsh.exe) do if not defined T for /f "delims=" %%P in ('where %%N 2^>nul') do if not defined T set "T=%%P"
if defined T goto have_t
echo run_tests.bat: no Tcl shell on your PATH; say which one with --tclsh C:\path\to\bin\tclsh91.exe 1>&2
exit /b 1
:have_t
if exist "%T%" goto t_exists
echo run_tests.bat: %T% is not a file 1>&2
exit /b 1
:t_exists
set "PROBE=%TEMP%\bitarray_probe_%RANDOM%.tcl"
> "%PROBE%" echo puts [info patchlevel]
set "V="
"%T%" "%PROBE%" > "%PROBE%.out" 2>&1
set /p V=<"%PROBE%.out"
del "%PROBE%" "%PROBE%.out" >nul 2>&1
if defined V goto probed
echo run_tests.bat: could not run %T% 1>&2
exit /b 1
:probed
if "%V:~0,2%"=="9." goto isnine
echo run_tests.bat: %T% is Tcl "%V%"; bitarray needs Tcl 9.1 (trunk) 1>&2
exit /b 1
:isnine
if exist "%LIB%" goto have_lib
echo run_tests.bat: %LIB% not found -- run build.bat first 1>&2
exit /b 1
:have_lib
echo tclsh: %T%   (Tcl %V%)
echo lib:   %LIB%
cd /d "%HERE%"
set "BITARRAY_LIB=%LIB%"
"%T%" tests\bitarray.test
exit /b %ERRORLEVEL%

:usage
echo run_tests.bat -- run the bitarray test suite.  Run build.bat first.
echo.
echo   run_tests.bat --tclsh C:\path\to\bin\tclsh91.exe
echo.
echo   --tclsh FILE    the Tcl 9.1 shell to test with (use the one you built against)
echo   --lib FILE      the extension to load (default: bitarray.dll next to this file)
echo   -h, --help
echo.
echo Expected last line:   bitarray.test:  Total 315  Passed 308  Skipped 7  Failed 0
echo (one test, mem-1.1, is skipped on Windows because it reads /proc)
exit /b 0
