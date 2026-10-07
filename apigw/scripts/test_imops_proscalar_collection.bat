@echo off
REM ==============================================================================
REM 1-Click Windows Batch Runner for imops_proscalar.json (6 Webhook Scenarios)
REM ==============================================================================

set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%test_imops_proscalar_collection.ps1" %*
if errorlevel 1 pause
