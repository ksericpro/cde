@echo off
REM ==============================================================================
REM End-to-End Verification Test Suite for Proscalar Option C (Kong + n8n)
REM Windows Batch Launcher using curl.exe
REM ==============================================================================

set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%test_proscalar_curl.ps1" %*
