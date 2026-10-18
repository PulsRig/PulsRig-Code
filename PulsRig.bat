@echo off
rem Startet PulsRig. Das Konsolenfenster bleibt verborgen, Adminrechte fragt das Programm selbst an.
rem Die Zeile mit COMPlus begrenzt den Vorrat der Speicherverwaltung von .NET auf 16 MB (spart rund 70 MB).
set COMPlus_GCgen0MaxBudget=1000000
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0PulsRig.ps1"
