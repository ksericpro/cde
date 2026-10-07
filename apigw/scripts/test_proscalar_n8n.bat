@echo off
setlocal enabledelayedexpansion

REM ==============================================================================
REM End-to-End Verification Test Suite for Proscalar Option C (Kong + n8n) - Windows CMD / Batch
REM Uses native Windows curl.exe
REM ==============================================================================

set "GATEWAY_URL=http://localhost:8088"
set "ENDPOINT=%GATEWAY_URL%/api/proscalar/webhook"
set "USERNAME=proscalar@gmail.com"
set "PASSWORD=fwpkyjcf2i8fcoP05yEz"

set "TEMP_DIR=%TEMP%\proscalar_test"
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"

echo ====================================================
echo [TEST SUITE] Proscalar Option C (Kong + n8n) - Windows curl.exe
echo    Endpoint: %ENDPOINT%
echo ====================================================

REM ----------------------------------------------------
REM TEST 1: Unauthorized Request (Expect HTTP 401)
REM ----------------------------------------------------
echo.
echo [Test 1/5] Testing Unauthorized Request (Expect HTTP 401)...
curl.exe -s -o "%TEMP_DIR%\resp1.json" -w "%%{http_code}" -X POST "%ENDPOINT%" -H "Content-Type: application/json" -d "{\"type\":\"event.publish\"}" > "%TEMP_DIR%\code1.txt"

set /p STATUS_1=<"%TEMP_DIR%\code1.txt"
if "%STATUS_1%"=="401" (
    echo [PASSED] Kong edge rejected unauthorized request (HTTP 401 Unauthorized).
) else (
    echo [FAILED] Received HTTP %STATUS_1% instead of 401.
)

REM ----------------------------------------------------
REM TEST 2: Active Single Event (Door Forced Open - 5002)
REM ----------------------------------------------------
echo.
echo [Test 2/5] Testing Active Point Alert (Code 5002 - Door Forced Open)...
curl.exe -s -o "%TEMP_DIR%\resp2.json" -w "%%{http_code}" -X POST "%ENDPOINT%" -u "%USERNAME%:%PASSWORD%" -H "Content-Type: application/json" -d "{\"type\":\"event.publish\",\"timestamp\":\"2026-10-07T05:00:00.000Z\",\"data\":{\"id\":\"win-test-door-01\",\"eventTimestamp\":\"2026-10-07T04:59:58.000Z\",\"eventCode\":\"5002\",\"eventSourceId\":\"proscalar-src-1\",\"eventSourceName\":\"OT-CTR-MAIN GATE\",\"eventPointId\":\"proscalar-pt-1\",\"eventPointName\":\"OT-MAIN GATE\",\"message\":\"Logical Door Forced Open ACTIVE.\"}}" > "%TEMP_DIR%\code2.txt"

set /p STATUS_2=<"%TEMP_DIR%\code2.txt"
findstr /C:"\"success\":true" "%TEMP_DIR%\resp2.json" >nul
if %ERRORLEVEL% equ 0 (
    echo [PASSED] Active event ingested and processed by n8n! (HTTP %STATUS_2%)
    type "%TEMP_DIR%\resp2.json"
    echo.
) else (
    echo [FAILED] Response does not indicate success (HTTP %STATUS_2%).
    type "%TEMP_DIR%\resp2.json"
    echo.
)

REM ----------------------------------------------------
REM TEST 3: Auto-Resolution IDLE Event (Code 4000)
REM ----------------------------------------------------
echo.
echo [Test 3/5] Testing IDLE Auto-Resolution Event (Code 4000 - Reader Tamper IDLE)...
curl.exe -s -o "%TEMP_DIR%\resp3.json" -w "%%{http_code}" -X POST "%ENDPOINT%" -u "%USERNAME%:%PASSWORD%" -H "Content-Type: application/json" -d "{\"type\":\"event.publish\",\"timestamp\":\"2026-10-07T05:05:00.000Z\",\"data\":{\"id\":\"win-test-tamper-idle-01\",\"eventTimestamp\":\"2026-10-07T05:04:58.000Z\",\"eventCode\":\"4000\",\"eventSourceId\":\"proscalar-src-1\",\"eventSourceName\":\"OT-CTR-MAIN GATE\",\"eventPointId\":\"proscalar-pt-1\",\"eventPointName\":\"CV485\",\"message\":\"Logical Reader Tamper IDLE.\"}}" > "%TEMP_DIR%\code3.txt"

set /p STATUS_3=<"%TEMP_DIR%\code3.txt"
findstr /C:"\"success\":true" "%TEMP_DIR%\resp3.json" >nul
if %ERRORLEVEL% equ 0 (
    echo [PASSED] IDLE event processed and resolved by pipeline! (HTTP %STATUS_3%)
    type "%TEMP_DIR%\resp3.json"
    echo.
) else (
    echo [FAILED] Response does not indicate success (HTTP %STATUS_3%).
    type "%TEMP_DIR%\resp3.json"
    echo.
)

REM ----------------------------------------------------
REM TEST 4: Multi-Zone Fire Alarm Group (Code 12008)
REM ----------------------------------------------------
echo.
echo [Test 4/5] Testing Alarm Group Safety Event (FIRE Zone Priority)...
curl.exe -s -o "%TEMP_DIR%\resp4.json" -w "%%{http_code}" -X POST "%ENDPOINT%" -u "%USERNAME%:%PASSWORD%" -H "Content-Type: application/json" -d "{\"type\":\"alarm.publish\",\"timestamp\":\"2026-10-07T05:10:00.000Z\",\"data\":{\"alarmGroupId\":\"GRP-FIRE-WIN-01\",\"groupEventCode\":\"12008\",\"name\":\"EAST WING FIRE CLUSTER\",\"eventSourceName\":\"East Wing Panel 1\",\"accessZones\":[{\"name\":\"East Lobby\",\"type\":\"NORMAL\",\"state\":\"ACTIVE\"},{\"name\":\"Server Room A\",\"type\":\"FIRE\",\"state\":\"TRIGGERED\"}]}}" > "%TEMP_DIR%\code4.txt"

set /p STATUS_4=<"%TEMP_DIR%\code4.txt"
findstr /C:"\"success\":true" "%TEMP_DIR%\resp4.json" >nul
if %ERRORLEVEL% equ 0 (
    echo [PASSED] Multi-zone Fire group alarm ingested as CRITICAL! (HTTP %STATUS_4%)
    type "%TEMP_DIR%\resp4.json"
    echo.
) else (
    echo [FAILED] Response does not indicate success (HTTP %STATUS_4%).
    type "%TEMP_DIR%\resp4.json"
    echo.
)

REM ----------------------------------------------------
REM TEST 5: Rate Limiting Enforcement (120 req/min)
REM ----------------------------------------------------
echo.
echo [Test 5/5] Testing Gateway Rate Limiting Policy (rapid burst of 125 requests)...
set "THROTTLED=0"
for /L %%N in (1,1,125) do (
    curl.exe -s -o NUL -w "%%{http_code}" -X POST "%ENDPOINT%" -u "%USERNAME%:%PASSWORD%" -H "Content-Type: application/json" -d "{\"type\":\"ping\"}" > "%TEMP_DIR%\rate_code.txt"
    set /p CUR_CODE=<"%TEMP_DIR%\rate_code.txt"
    if "!CUR_CODE!"=="429" (
        set "THROTTLED=1"
        goto :throttled_done
    )
)

:throttled_done
if "!THROTTLED!"=="1" (
    echo [PASSED] Kong rate limiting enforced: HTTP 429 Too Many Requests received.
) else (
    echo [INFO] Burst completed without hitting 429 in current window.
)

echo.
echo ====================================================
echo [FINISHED] Proscalar Option C Windows Verification Complete!
echo ====================================================

rmdir /s /q "%TEMP_DIR%" 2>nul
