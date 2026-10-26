# PulsRig – Quelltext

Windows-Programm für Treiber, Boost, Hardware-Prüfungen und Werkzeuge: sucht neuere Treiber (Windows Update, NVIDIA, AMD, Microsoft-Katalog), schafft vor dem Spielen Platz, misst Temperaturen, testet die Hardware unter Last, vergleicht Benchmarks über die Zeit und erklärt Abstürze.

- **Setup und Updates:** [PulsRig/PulsRig](https://github.com/PulsRig/PulsRig) · **Webseite:** https://pulsrig.de
- **Kontakt:** pulsrig.hilfe@gmail.com

![PulsRig im Aussehen Nacht Puls](bilder/start.png)

## Aufbau

WPF-App auf .NET 10 im Ordner `CSharp`: `PulsRig.App` (Oberfläche), `PulsRig.Core` (Logik ohne Oberfläche), `PulsRig.Tests`. Last und Benchmark, Temperatur, Aufzeichnung sowie Controller und Maus liegen als `PulsRig-*.cs` im Hauptordner. `PulsRig-Start.cs` ist die Hülle `PulsRig.exe`, die die App startet und den Helfer neben der Uhr enthält.

## Aus dem Quelltext starten

- Windows 10 oder 11, .NET 10 SDK
- Starten: `dotnet run --project CSharp\PulsRig.App` (ohne Adminrechte läuft es eingeschränkt)
- Prüfen: `dotnet test CSharp\PulsRig.slnx`
- Setup und ZIP bauen: `PulsRig-Paket.ps1` (braucht Inno Setup 7)

Wichtig beim Ändern: Die `.ps1`-Dateien (Bauskripte, englische Texte in `CSharp\PulsRig.App\Englisch.ps1`) bleiben **UTF-8 mit BOM**, sonst gehen die Umlaute kaputt.

## Lizenz

PulsRig steht unter der **GNU General Public License 3.0** (siehe `LICENSE`). Die Bausteine im Ordner `Sensoren` (LibreHardwareMonitor, MPL-2.0; .NET-Pakete, MIT) gehören ihren Urhebern und stehen unter ihren eigenen Lizenzen, siehe `Sensoren/LIZENZEN.txt`. Den Treiber PawnIO liefert PulsRig nicht mit; er wird nur auf Wunsch über sein offizielles Setup installiert.

---

**English:** Source code of PulsRig, a Windows tool for drivers, game boost, hardware checks and utilities (C#, WPF on .NET 10). The interface is German with an English translation. Licensed under GPL-3.0; third-party components in `Sensoren/` keep their own licenses. Releases: [PulsRig/PulsRig](https://github.com/PulsRig/PulsRig).
