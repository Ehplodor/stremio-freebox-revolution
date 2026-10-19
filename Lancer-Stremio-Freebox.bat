@echo off
rem Lanceur unique : verifie tout, demarre Stremio, l'agent du PC, puis l'appli sur la tele.
rem Options (voir tools\launcher.py) : --nom "PC du salon", --player 192.168.0.42, --addon-test
title Stremio pour Freebox Player
cd /d "%~dp0"
where python >nul 2>nul
if errorlevel 1 (
    echo Python est introuvable. Installez-le depuis https://www.python.org/downloads/ ^(cocher "Add to PATH"^).
    pause
    exit /b 1
)
python -u tools\launcher.py %*
if errorlevel 1 pause
