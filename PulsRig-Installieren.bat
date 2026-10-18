@echo off
rem Installiert PulsRig nach "C:\Program Files\PulsRig". Adminrechte fragt das Skript selbst an.
rem Entfernen: PulsRig-Installieren.bat -Entfernen
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PulsRig-Installieren.ps1" %*
