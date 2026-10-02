@echo off
setlocal
REM ============================================================
REM  Hardstreet Admin - Generar INSTALADOR de Windows en 1 paso
REM
REM  Uso (desde cualquier terminal):
REM     build_installer.bat              -> usa version 1.0.1
REM     build_installer.bat 1.0.2        -> usa version 1.0.2
REM
REM  Requisitos: Flutter en PATH + Inno Setup 6 instalado.
REM  Resultado:  build\installer\HardstreetAdmin-setup-<version>.exe
REM ============================================================

set VERSION=%1
if "%VERSION%"=="" set VERSION=1.0.1

cd /d "%~dp0"

echo ============================================================
echo   Hardstreet Admin - build instalador v%VERSION%
echo ============================================================

echo.
echo [1/3] Compilando release de Windows...
REM "call" es OBLIGATORIO: flutter es un .bat y sin call el script no regresa.
call flutter build windows --release --build-name=%VERSION%
if errorlevel 1 goto :error

echo.
echo [2/3] Empaquetando instalador (Inno Setup)...
set "ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=C:\Program Files\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" (
    echo ERROR: Inno Setup 6 no encontrado. Instalalo con:
    echo     winget install JRSoftware.InnoSetup
    goto :error
)
"%ISCC%" /DHS_VERSION=%VERSION% windows\hardstreet_admin.iss
if errorlevel 1 goto :error

echo.
echo [3/3] Listo.
set "OUT=%~dp0build\installer\HardstreetAdmin-setup-%VERSION%.exe"
if exist "%OUT%" (
    echo.
    echo   INSTALADOR GENERADO:
    echo   %OUT%
) else (
    echo ERROR: no se encontro el instalador esperado en build\installer\
    goto :error
)
echo.
exit /b 0

:error
echo.
echo *** BUILD FALLIDO (revisa los mensajes de arriba) ***
exit /b 1
