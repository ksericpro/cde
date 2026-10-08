@echo off
REM ==============================================================================
REM 1-Click Windows Batch Runner for Proscalar Option C (Kong + n8n) Test Suite
REM ==============================================================================

set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%test_proscalar_n8n.ps1" %*
if errorlevel 1 pause
