@echo off
rem Doppelklick: Menue mit Treibersuche und allen Werkzeugen.
rem Mit Parametern (z.B. -ScanOnly, -Install, -Tool FixAudio) laeuft direkt der gewuenschte Schritt.
rem Adminrechte fordert das Skript selbst per UAC-Abfrage an.
if "%~1"=="" goto menu
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Treiber-Scan.ps1" -WaitAtEnd %*
goto :eof

:menu
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Treiber-Scan.ps1" -Menu -WaitAtEnd
