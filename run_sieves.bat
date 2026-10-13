@echo off
rem run_sieves.bat -- check and time six prime-sieve variants.  Run build.bat first.
rem Written by Claude (an AI model made by Anthropic) for Eric Taylor.  Run once on 64-bit Windows with Visual Studio 2022: see README.md.
rem
rem   run_sieves.bat --tclsh C:\path\to\bin\tclsh91.exe
rem Frank van Bakel's Tcl sieve (variant A) is included unchanged as sieve\frank_sieve.tcl.
rem Options:
rem   --tclsh FILE    the Tcl 9.1 shell; default: %%TCLSH%% or the first tclsh91.exe, tclsh90.exe or tclsh.exe on your PATH
rem   --sieve FILE    use this copy of Frank's file instead of sieve\frank_sieve.tcl
rem   --lib FILE      the extension to load (default: bitarray.dll next to this file)
rem   -h, --help
rem The run takes about a minute.  Nothing is written here (a temporary file is made in %%TEMP%% and removed).
setlocal EnableExtensions
set "HERE=%~dp0"
set "TCLSH_ARG="
set "FRANK=%HERE%sieve\frank_sieve.tcl"
set "LIB=%HERE%bitarray.dll"

:args
if "%~1"=="" goto argsdone
if /i "%~1"=="--tclsh" goto a_tclsh
if /i "%~1"=="--sieve" goto a_sieve
if /i "%~1"=="--lib" goto a_lib
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
echo run_sieves.bat: unknown argument: %~1 1>&2
exit /b 2
:a_tclsh
if "%~2"=="" goto needarg
set "TCLSH_ARG=%~2"
shift
shift
goto args
:a_sieve
if "%~2"=="" goto needarg
set "FRANK=%~2"
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
echo run_sieves.bat: %~1 needs an argument 1>&2
exit /b 2

:argsdone
set "T=%TCLSH_ARG%"
if not defined T set "T=%TCLSH%"
if defined T goto have_t
for %%N in (tclsh91.exe tclsh90.exe tclsh.exe) do if not defined T for /f "delims=" %%P in ('where %%N 2^>nul') do if not defined T set "T=%%P"
if defined T goto have_t
echo run_sieves.bat: no Tcl shell on your PATH; say which one with --tclsh C:\path\to\bin\tclsh91.exe 1>&2
exit /b 1
:have_t
if exist "%T%" goto t_exists
echo run_sieves.bat: %T% is not a file 1>&2
exit /b 1
:t_exists
set "PROBE=%TEMP%\bitarray_probe_%RANDOM%.tcl"
> "%PROBE%" echo puts [info patchlevel]
set "V="
"%T%" "%PROBE%" > "%PROBE%.out" 2>&1
set /p V=<"%PROBE%.out"
del "%PROBE%" "%PROBE%.out" >nul 2>&1
if defined V goto probed
echo run_sieves.bat: could not run %T% 1>&2
exit /b 1
:probed
if "%V:~0,2%"=="9." goto isnine
echo run_sieves.bat: %T% is Tcl "%V%"; bitarray needs Tcl 9.1 (trunk) 1>&2
exit /b 1
:isnine
if exist "%LIB%" goto have_lib
echo run_sieves.bat: %LIB% not found -- run build.bat first 1>&2
exit /b 1
:have_lib
if exist "%FRANK%" goto have_frank
echo run_sieves.bat: %FRANK% not found (it should be sieve\frank_sieve.tcl; pass another copy with --sieve FILE) 1>&2
exit /b 1
:have_frank
set "TMPF=%TEMP%\frank_procs_%RANDOM%.tcl"
"%T%" "%HERE%sieve\procs_only.tcl" "%FRANK%" "%TMPF%"
if not errorlevel 1 goto have_procs
del "%TMPF%" >nul 2>&1
exit /b 1
:have_procs
echo sieve file: %FRANK%
cd /d "%HERE%"
set "BITARRAY_LIB=%LIB%"
set "FRANK_PROCS=%TMPF%"
"%T%" sieve\run_sieves.tcl
set "RC=%ERRORLEVEL%"
del "%TMPF%" >nul 2>&1
exit /b %RC%

:usage
echo run_sieves.bat -- check and time six prime-sieve variants.  Run build.bat first.
echo.
echo   run_sieves.bat --tclsh C:\path\to\bin\tclsh91.exe
echo.
echo   --tclsh FILE    the Tcl 9.1 shell
echo   --sieve FILE    use this copy of Frank's file instead of sieve\frank_sieve.tcl
echo   --lib FILE      the extension to load (default: bitarray.dll next to this file)
echo   -h, --help
echo.
echo The run takes about a minute.
exit /b 0
