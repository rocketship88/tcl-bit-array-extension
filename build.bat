@echo off
rem build.bat -- build bitarray.dll with Microsoft Visual C (Visual Studio 2022).
rem Written by Claude (an AI model made by Anthropic) for Eric Taylor.  Run once on 64-bit Windows with Visual Studio 2022: see README.md.
rem
rem   build.bat --tclsh C:\path\to\bin\tclsh91.exe
rem   build.bat --tcl-prefix C:\path\to\tcl-install-directory
rem Options:
rem   --tclsh FILE        the Tcl 9.1 shell you will run it with; the install directory is found from it
rem   --tcl-prefix DIR    the install directory itself (it holds include\tcl.h and lib\tclstub.lib)
rem   --out FILE          where to write the DLL (default: bitarray.dll next to this file)
rem   -h, --help
rem Without --tclsh or --tcl-prefix it uses %%TCLSH%% or the first tclsh91.exe, tclsh90.exe or tclsh.exe on your PATH.
rem If cl.exe is not on your PATH it looks for Visual Studio with vswhere and sets up the compiler itself.
rem Use the 64-bit or the 32-bit setup to match the tclsh (this script picks vcvars64 or vcvars32 from the tclsh).
setlocal EnableExtensions
set "HERE=%~dp0"
set "TCLSH_ARG="
set "PREFIX_ARG="
set "OUT=%HERE%bitarray.dll"

:args
if "%~1"=="" goto argsdone
if /i "%~1"=="--tclsh" goto a_tclsh
if /i "%~1"=="--tcl-prefix" goto a_prefix
if /i "%~1"=="--out" goto a_out
if /i "%~1"=="-h" goto usage
if /i "%~1"=="--help" goto usage
echo build.bat: unknown argument: %~1 1>&2
goto usage_err
:a_tclsh
if "%~2"=="" goto needarg
set "TCLSH_ARG=%~2"
shift
shift
goto args
:a_prefix
if "%~2"=="" goto needarg
set "PREFIX_ARG=%~2"
shift
shift
goto args
:a_out
if "%~2"=="" goto needarg
set "OUT=%~2"
shift
shift
goto args
:needarg
echo build.bat: %~1 needs an argument 1>&2
exit /b 2

:argsdone
rem ---- find a Tcl 9 shell (also gives us the install directory and 32/64 bit) ----
set "T=%TCLSH_ARG%"
if not defined T if defined PREFIX_ARG goto probe_prefix
if not defined T set "T=%TCLSH%"
if defined T goto have_t
for %%N in (tclsh91.exe tclsh90.exe tclsh.exe) do if not defined T for /f "delims=" %%P in ('where %%N 2^>nul') do if not defined T set "T=%%P"
if defined T goto have_t
echo build.bat: no Tcl shell found on your PATH.  Say where Tcl 9.1 is with one of: 1>&2
echo     build.bat --tclsh C:\path\to\bin\tclsh91.exe 1>&2
echo     build.bat --tcl-prefix C:\path\to\tcl-install-directory 1>&2
exit /b 1

:probe_prefix
rem only --tcl-prefix was given: look for its tclsh to learn the version and 32/64 bit
for %%N in (tclsh91.exe tclsh90.exe) do if not defined T if exist "%PREFIX_ARG%\bin\%%N" set "T=%PREFIX_ARG%\bin\%%N"
if defined T goto have_t
echo build.bat: no tclsh91.exe in %PREFIX_ARG%\bin ; give the shell too with --tclsh 1>&2
exit /b 1

:have_t
if exist "%T%" goto t_exists
echo build.bat: %T% is not a file 1>&2
exit /b 1
:t_exists
set "PROBE=%TEMP%\bitarray_probe_%RANDOM%.tcl"
> "%PROBE%" echo puts "[info patchlevel] $tcl_platform(pointerSize) [file nativename [file dirname [file dirname [info nameofexecutable]]]]"
set "PROBEOUT="
"%T%" "%PROBE%" > "%PROBE%.out" 2>&1
set /p PROBEOUT=<"%PROBE%.out"
del "%PROBE%" "%PROBE%.out" >nul 2>&1
if defined PROBEOUT goto probed
echo build.bat: could not run %T% 1>&2
exit /b 1
:probed
set "PATCH=" & set "PTR=" & set "TPREFIX="
for /f "tokens=1,2,* delims= " %%A in ("%PROBEOUT%") do set "PATCH=%%A" & set "PTR=%%B" & set "TPREFIX=%%C"
if "%PATCH:~0,2%"=="9." goto isnine
echo build.bat: %T% is not Tcl 9 (it said: %PROBEOUT%); bitarray needs Tcl 9.1 1>&2
exit /b 1
:isnine
set "PREFIX=%PREFIX_ARG%"
if not defined PREFIX set "PREFIX=%TPREFIX%"
set "ARCH=x64"
if "%PTR%"=="4" set "ARCH=x86"
echo tclsh:   %T%   (Tcl %PATCH%, %ARCH%)

rem ---- check the headers and the stubs library ----
if exist "%PREFIX%\include\tcl.h" goto have_h
echo build.bat: %PREFIX%\include\tcl.h not found; is %PREFIX% the directory Tcl was installed into? 1>&2
exit /b 1
:have_h
findstr /c:"TCL_OBJTYPE_V2" "%PREFIX%\include\tcl.h" >nul
if not errorlevel 1 goto have_v2
echo build.bat: %PREFIX%\include\tcl.h has no TCL_OBJTYPE_V2; it is too old, bitarray needs Tcl 9.1 (trunk) 1>&2
exit /b 1
:have_v2
set "STUB=%PREFIX%\lib\tclstub.lib"
if exist "%STUB%" goto have_stub
echo build.bat: %STUB% not found.  The stubs libraries under %PREFIX%\lib are: 1>&2
dir /b "%PREFIX%\lib\*stub*" 1>&2
exit /b 1
:have_stub
echo headers: %PREFIX%\include
echo stubs:   %STUB%

rem ---- the compiler ----
where cl >nul 2>&1
if errorlevel 1 goto find_vs
if not defined VSCMD_ARG_TGT_ARCH goto have_cl
if /i "%VSCMD_ARG_TGT_ARCH%"=="%ARCH%" goto have_cl
echo build.bat: this prompt builds for %VSCMD_ARG_TGT_ARCH% but %T% is %ARCH%. 1>&2
echo Open the "%ARCH% Native Tools Command Prompt for VS 2022" and run build.bat again. 1>&2
exit /b 1

:find_vs
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%VSWHERE%" goto have_vswhere
echo build.bat: cl.exe is not on your PATH and Visual Studio was not found. 1>&2
echo Open the "%ARCH% Native Tools Command Prompt for VS 2022" and run build.bat there. 1>&2
exit /b 1
:have_vswhere
set "VSOUT=%TEMP%\bitarray_vs_%RANDOM%.txt"
"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath > "%VSOUT%" 2>&1
set "VSDIR="
set /p VSDIR=<"%VSOUT%"
del "%VSOUT%" >nul 2>&1
if defined VSDIR goto have_vsdir
echo build.bat: Visual Studio with the C++ tools was not found (vswhere found nothing). 1>&2
echo Open the "%ARCH% Native Tools Command Prompt for VS 2022" and run build.bat there. 1>&2
exit /b 1
:have_vsdir
set "VCVARS=%VSDIR%\VC\Auxiliary\Build\vcvars64.bat"
if "%ARCH%"=="x86" set "VCVARS=%VSDIR%\VC\Auxiliary\Build\vcvars32.bat"
if exist "%VCVARS%" goto have_vcvars
echo build.bat: %VCVARS% not found 1>&2
exit /b 1
:have_vcvars
echo compiler: setting up with %VCVARS%
call "%VCVARS%" >nul
where cl >nul 2>&1
if not errorlevel 1 goto have_cl
echo build.bat: cl.exe is still not available after %VCVARS% 1>&2
exit /b 1

:have_cl
set "OBJDIR=%TEMP%\bitarray_build_%RANDOM%"
mkdir "%OBJDIR%"
cl /nologo /utf-8 /O2 /W3 /MD /LD /DUSE_TCL_STUBS /I"%PREFIX%\include" "%HERE%bitarray.c" /Fo"%OBJDIR%\\" /Fe"%OUT%" /link /NOLOGO /IMPLIB:"%OBJDIR%\bitarray.lib" "%STUB%"
set "RC=%ERRORLEVEL%"
rmdir /s /q "%OBJDIR%" >nul 2>&1
if not "%RC%"=="0" goto failed
echo built %OUT%
exit /b 0
:failed
echo build.bat: the compile failed (see the messages above) 1>&2
exit /b 1

:usage
setlocal
echo build.bat -- build bitarray.dll with Microsoft Visual C (Visual Studio 2022)
echo.
echo   build.bat --tclsh C:\path\to\bin\tclsh91.exe
echo   build.bat --tcl-prefix C:\path\to\tcl-install-directory
echo.
echo   --tclsh FILE        the Tcl 9.1 shell you will run it with; the install directory is found from it
echo   --tcl-prefix DIR    the install directory itself (it holds include\tcl.h and lib\tclstub.lib)
echo   --out FILE          where to write the DLL (default: bitarray.dll next to this file)
echo   -h, --help
echo.
echo Without --tclsh or --tcl-prefix it uses the TCLSH environment variable or the first tclsh91.exe,
echo tclsh90.exe or tclsh.exe on your PATH.  If cl.exe is not on your PATH it sets up Visual Studio itself.
exit /b 0
:usage_err
exit /b 2
