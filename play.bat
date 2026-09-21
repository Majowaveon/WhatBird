@echo off
rem Normal start of the Godot build (with menu). Usage:
rem   play.bat            menu start
rem   play.bat --play     skip menu, enter the formal level directly
setlocal
cd /d "%~dp0"

where godot >nul 2>nul
if errorlevel 1 (
    echo [play] godot not found. Install Godot 4.5.1 and add it to PATH.
    pause
    exit /b 1
)

rem Fresh clones need an import pass before the game can run
if not exist "godot\.godot" (
    echo [play] First run: importing assets...
    godot --headless --path godot --editor --import >nul
)

if "%~1"=="" (
    godot --path godot
) else (
    godot --path godot -- %*
)
if errorlevel 1 pause
