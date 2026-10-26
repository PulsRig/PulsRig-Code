# PulsRig → C#: Bestandsaufnahme (Schritt 1)

Stand 25.10.2026. Noch kein Code, nur die Lage vor dem Umbau.

## Umfang

| Art | Dateien | Zeilen (ca.) |
|---|---|---|
| PowerShell (`.ps1`, ohne Werkzeuge zum Bauen/Testen) | 44 | 26 000 |
| davon Texte Englisch (`PulsRig-Englisch.ps1`) | 1 | 2 400 |
| Oberfläche (`PulsRig.xaml`) | 1 | 2 300 |
| C# schon vorhanden (`.cs`) | 6 | 1 600 |
| Inline-C# in `Add-Type -TypeDefinition` | 3 Stellen | – |

Gut 700 PowerShell-Funktionen. Die größten Blöcke sind `PulsRig.ps1` (113), `Treiber-Werkzeuge.ps1` (67),
`PulsRig-Ansichten.ps1` (66), `PulsRig-Bento.ps1` (61), `PulsRig-Hardware.ps1` und `Treiber-Scan.ps1` (je 59).

## Was schon C# ist

| Datei | Klassen | Wie geladen |
|---|---|---|
| `PulsRig-Start.cs` | `PulsRigStart`, `PulsRigHelper` | mit `csc.exe` in `PulsRig.exe` (Start mit eingebauter PowerShell + Helfer neben der Uhr) |
| `PulsRig-Temperatur.cs` | `PulsRigCpuTemp` | in `PulsRig.exe` und per `Add-Type` (`PulsRig-Temperatur.ps1`), nutzt LibreHardwareMonitor |
| `PulsRig-Aufzeichnung.cs` | `PulsRigRecorder` | in `PulsRig.exe` (Aufzeichnung beim Spielen) |
| `PulsRig-Last.cs` | `PulsRigStress` | `Add-Type` aus `PulsRig-Hardware.ps1` (Stabilitätstest) |
| `PulsRig-Benchmark.cs` | `PulsRigBench` | `Add-Type` aus `PulsRig-Benchmark.ps1` |
| `PulsRig-Eingabe.cs` | `PulsRigPad`, `PulsRigMouse` | `Add-Type` aus `PulsRig-Eingabe.ps1` (XInput, Raw Input) |
| inline | Interop-Hilfen | `Treiber-Werkzeuge.ps1` (Z. 109, 261), `PulsRig-Hardware.ps1` (Z. 394) |

Alles zielt auf .NET Framework 4 und wird mit dem `csc.exe` gebaut, den Windows mitbringt. Visual Studio und ein SDK
sind dafür bisher nicht nötig.

## Aufbau des Programms

```
PulsRig.exe (PulsRigStart) ── eingebaute PowerShell ── PulsRig.ps1
   │                                                     ├─ lädt PulsRig.xaml (WPF)
   │                                                     ├─ Sprache, Skins, Ringe, Ergebnisse (früh)
   │                                                     ├─ 27 Bereichsdateien per Get-AppCode (Z. 3019–3045)
   │                                                     └─ Hintergrund-Runspace
   │                                                          ├─ PulsRig-Arbeit-Start.ps1  (lädt Treiber-Werkzeuge/-Scan)
   │                                                          ├─ PulsRig-Arbeit-Scan / -Update / -Werkzeug / -Export
   │                                                          └─ PulsRig-Arbeit-Neuinstallation
   └─ PulsRigHelper (Uhr, Autostart/Aufgabe) ── PulsRig-Hintergrund.ps1 (-Boost Ein/Aus, -Wochenscan)
```

Alle Dateien teilen sich einen Bereich (`$script:`). Die Oberfläche greift direkt auf Elemente und Variablen zu, eine
Trennung zwischen Logik und Anzeige gibt es bisher nur zwischen Runspace (Arbeit) und Fenster.

## Funktionsbereiche

**L** = reine Logik (leicht zu übertragen), **O** = eng mit der Oberfläche verwoben, **S** = sicherheitskritisch.

| Bereich | Dateien | Art | Bemerkung |
|---|---|---|---|
| Datenträger/Netz-Abfragen | `Treiber-Werkzeuge.ps1` (`Get-DiskList` … `Get-NetIPv4List`) | L | CIM, klar abgegrenzt → **erster Kandidat** |
| Treiber-Scan, Updates, Katalog, NVIDIA/AMD | `Treiber-Scan.ps1`, `PulsRig-Arbeit-Scan/-Update.ps1` | L, S | Downloads, Signaturprüfung, Wiederherstellungspunkt |
| Werkzeuge (Audio, Geräte, Netz, Auflösung, Laufzeiten, HVCI) | `Treiber-Werkzeuge.ps1` | L, S | |
| Boost | `Treiber-Werkzeuge.ps1`, `PulsRig-Hintergrund.ps1`, `-Arbeit-Werkzeug.ps1` | L, S | `$script:BoostServices`, schließt nie Programme |
| Speicherplatz freigeben | `Treiber-Werkzeuge.ps1` (`Get-CleanTargets` …) | L, S | kein Papierkorb, keine Junctions |
| Hardware: Laufwerke, RAM, Sensoren, Bericht | `PulsRig-Hardware.ps1` | L + O gemischt | Abfrage und Anzeige stecken in denselben Funktionen |
| Stabilitätstest, Benchmark, Eingabe | `PulsRig-Hardware/-Benchmark/-Eingabe.ps1` + `.cs` | großteils C# | Rechenkern ist schon C# |
| Temperatur, Aufzeichnung, Verlauf, Verschleiß | `PulsRig-Temperatur/-Aufzeichnung/-Verlauf/-Verschleiss.ps1` | L | teils schon C# |
| Abstürze, Probezeit, Änderungen, Problem, Diagnose | gleichnamige `.ps1` | L + O | Ereignisprotokoll, ZIP, Mail |
| Spielcheck, Spiele, Aufrüsten, Standby, Akku, Strom, Monitor, Ping | gleichnamige `.ps1` | L + O | eher klein (100–300 Zeilen) |
| Autostart, Helfer, Treiberschutz, Neuinstallation | gleichnamige `.ps1` | L, S | Aufgabenplanung, Adminrechte |
| Oberfläche: Fenster, Seiten, Dialoge, Animation | `PulsRig.ps1`, `PulsRig-Ansichten.ps1`, `-Startseite.ps1` | O | |
| Skins, Themen, Bento, Ringe | `PulsRig-Skins/-Bento/-Ringe.ps1` | O | hängt mit dem neuen Design (Reihe Q) zusammen |
| Sprache | `PulsRig-Sprache.ps1`, `PulsRig-Englisch.ps1` | L | → später `.resx` oder ein Wörterbuch |
| Bauen, Tests, Veröffentlichen | `PulsRig-Paket/-Tests/-Probelauf/-Quellcode/-Hochladen/-Installieren.ps1` | – | bleiben vorerst PowerShell |

## Tests heute

`PulsRig-Tests.ps1` zieht einzelne Funktionen aus den Dateien, ohne das Programm zu starten, und prüft rund 100 Fälle
(NVIDIA-Version, Katalogsuche, RAM-Takt/Kanäle/Steckplätze, Chipsatz, Versionen, Pfade ohne Kontonamen).
`PulsRig-Probelauf.ps1` dazu, `-Snapshot` für die Oberfläche. Die Tabu-Regeln (Boost, Speicherplatz) sind heute
**nicht** als Test abgesichert, das sollte vor dem Umbau nachgeholt werden.

## Was zu entscheiden ist

1. **Zielplattform: entschieden am 25.10.2026 für modernes .NET (statt .NET Framework 4.8).** Folgen:
   - Windows PowerShell 5.1 läuft auf .NET Framework und kann .NET-8-Bibliotheken nicht laden. Für den schrittweisen
     Umbau wird `PulsRig.Core` daher zweifach gebaut: **net48** (lädt in 5.1) und **net10.0-windows**. Erst die neue
     Oberfläche (`PulsRig.App`) läuft auf .NET 10.
   - **Fassung: .NET 10** (Langzeitsupport bis 11/2028), entschieden am 25.10.2026 – .NET 8 bekommt nur bis
     10.11.2026 Updates.
   - Zum Bauen braucht es das .NET SDK; `csc.exe` von Windows reicht dann nicht mehr.
2. **Werkzeug zum Bauen:** weiter `csc.exe` über `PulsRig-Paket.ps1` oder `.csproj` mit `msbuild`/`dotnet build`.
   Ab mehreren Bibliotheken ist `.csproj` übersichtlicher.
3. **Reihenfolge:** Vorschlag wie besprochen – Datenträger/Netz-Abfragen → Sensoren/Messschleife → Boost und
   Speicherplatz (mit Tests der Tabu-Regeln) → übrige Werkzeuge → Treiber-Scan → Oberfläche zuletzt.

## Risiken

- Gemeinsamer `$script:`-Bereich: viele Funktionen lesen Variablen, die sie nicht als Parameter bekommen. Wer
  überträgt, muss das je Funktion aufdecken.
- `PulsRig-Hardware.ps1` und `PulsRig.ps1` mischen Abfrage und Anzeige, die müssen vor oder beim Übertragen getrennt
  werden.
- Speicher: Ziel bleibt wenig RAM, die Ersatzfunktionen für `Get-PhysicalDisk` & Co. müssen auch in C# schlank bleiben.

## Schritt 2: Projektgerüst (25.10.2026)

Ordner `CSharp/` mit `PulsRig.slnx`:

| Projekt | Ziel | Inhalt |
|---|---|---|
| `PulsRig.Core` | .NET Standard 2.0, C# latest | Logik ohne Oberfläche; bisher nur `PulsRigInfo` als Platzhalter |
| `PulsRig.App` | .NET 10, WPF | leeres Fenster aus der Vorlage, verweist auf Core |
| `PulsRig.Tests` | .NET 10, xUnit | verweist auf Core |

Bauen: `dotnet build` und `dotnet test` im Ordner `CSharp`. Geprüft: Bauen ohne Warnung, Test grün, und
`Add-Type -Path …\PulsRig.Core.dll` lädt die Bibliothek in Windows PowerShell 5.1. `bin/` und `obj/` stehen in
`.gitignore`. `PulsRig-Paket.ps1` baut die Projektmappe noch nicht mit, das kommt mit dem ersten echten Modul.

## Schritt 3: Datenträger- und Netz-Abfragen (25.10.2026)

- `PulsRig.Core/Laufwerke.cs` und `Netzwerk.cs`: Umwandlung der CIM-Rohwerte in die Wörter von Get-PhysicalDisk/
  Get-NetAdapter, dazu die Abfrage „Suchzeit/TRIM“ direkt am Laufwerk (früher Inline-C# `PulsRigDisk.Probe`).
- Die CIM-Abfrage selbst bleibt beim Aufrufer (in PowerShell `Get-CimInstance`). So braucht Core keine Bibliothek für
  WMI, und die neue Oberfläche kann dieselben Klassen später mit ihrer eigenen Abfrage nutzen.
- `Treiber-Werkzeuge.ps1`: `Get-DiskList` & Co. behalten Namen und Ausgabe, rufen intern `[PulsRig.Core.*]`.
  `Import-PulsRigCore` lädt die DLL neben dem Programm (`DD_ProgramDir`, Programmordner von PulsRig.exe) oder in der
  Werkstatt aus `CSharp\PulsRig.Core\bin\…`. `ConvertTo-CimWord`, `ConvertTo-DriveLetter` und `Resolve-DiskMedia`
  entfallen.
- `PulsRig-Paket.ps1` baut die Projektmappe, führt die C#-Tests aus und legt `PulsRig.Core.dll` ins ZIP und neben
  `PulsRig.exe` (damit auch ins Setup).
- Geprüft: 28 C#-Tests grün; Ausgabe alt/neu auf diesem PC gleich (nur der freie Platz hatte sich bewegt); Paket gebaut;
  DLL lädt aus `dist\PulsRig-Programm`; Snapshots ohne Fehler, die WD-Festplatte („Unspecified“) wird weiter erkannt.

## Schritt 4: Messschleife der Sensoren (25.10.2026)

- `PulsRig.Core` wird jetzt für **net48 und net10.0-windows** gebaut statt für .NET Standard 2.0: Leistungszähler
  gibt es in .NET Standard nur über ein Zusatzpaket, das in PowerShell 5.1 nicht sauber lädt. PowerShell nimmt die
  Fassung aus `bin\…\net48`, die neue Oberfläche die aus `net10.0-windows`.
- `PulsRig.Core/Messung.cs`: nvidia-smi (Grafikkarte), Last, stärkster Kern, Takt und belegter Arbeitsspeicher;
  `Next()` liefert jede Sekunde eine Hashtable mit denselben Schlüsseln wie früher. Den Pfad zu nvidia-smi und den
  Grundtakt sucht der Aufrufer, damit der Probelauf auf vorgetäuschten Systemen (`PulsRig-Fremdsystem.ps1`) weiter greift.
- Bleibt in PowerShell: Temperatur und Leistung des Prozessors (`PulsRigCpuTemp`, braucht LibreHardwareMonitor) und die
  gestellten Werte im Probelauf. Die Schleife in `PulsRig-Hardware.ps1` ist von rund 100 auf 35 Zeilen geschrumpft.
- `PulsRig.ps1` hat `Get-CoreDll` (wo liegt die DLL), die Messschleife bekommt den Pfad als Argument.
- Geprüft: 32 C#-Tests grün (auch ein echter Takt); in PowerShell 5.1 liefert die Messung alle Werte inklusive
  RTX 3080, und `Dispose()` beendet den eigenen nvidia-smi.

## Schritt 5: Boost und Speicherplatz, zuerst die Tabu-Regeln (25.10.2026)

- Zuerst Tests gegen den alten PowerShell-Code (`PulsRig-Tests.ps1`, 112 grün): der automatische Boost hält nur Dienste
  aus `$script:BoostServices` oder fremder Hersteller an, schließt nie Programme (auch wenn die Einstellungsdatei welche
  nennt), lässt unsichere Namen weg. Aufräumen betritt keine Junction, die Zielliste enthält keinen Papierkorb, keine
  Speicherabbilder, keinen Treiberspeicher, und die Installer-Suche fasst `Backup_*`/`Auto-Sicherung_*` nicht an.
- Dafür herausgezogen: `New-AutoBoostPlan` (vorher inline in `PulsRig-Hintergrund.ps1`) und `Get-CleanTargetList`.
- `Boost.cs`: `IsSafeName`, `IsAllowed(name, liste, befehlszeile, windir)`. Die WMI-Abfrage bleibt in PowerShell.
- `Aufraeumen.cs`: `CleanableFiles(pfad, tage)` ersetzt `Get-CleanableFiles`; neu als zweite Sicherung: `$Recycle.Bin`,
  `Minidump`, `LiveKernelReports`, `DriverStore`, `Backup_*`, `Auto-Sicherung_*` und `MEMORY.DMP` werden auch dann
  ausgelassen, wenn sie in einem Zielordner liegen.
- Anhalten der Dienste und Löschen der Dateien bleiben in PowerShell.
- `PulsRig-Paket.ps1` führt die PowerShell-Tests jetzt nach `dotnet build` aus, weil sie die DLL laden.
- Geprüft: 41 C#-Tests grün (mit echter Junction), Paket gebaut, Aufräum-Suche auf dem echten PC, Snapshots ohne Fehler.

## Schritt 6, erster Block: Prüfungen der Werkzeuge (25.10.2026)

- `Werkzeuge.cs` mit vier kleinen Klassen, je eine Frage "was ist erlaubt / was stimmt":
  - `Downloads.IsAllowed` – nur https und nur erlaubte Rechner (aus `Save-SignedDownload`; Laden und
    Signaturprüfung bleiben in PowerShell).
  - `Treiber.HvciIssues`, `ResolveDriverPath`, `ResolveServicePath` – Prüfung der Treiberdateien auf Kernisolierung
    und Pfade aus WMI.
  - `Geraete.IsCleanable` – welche getrennten Geräte "Ungültige Gerätedaten bereinigen" entfernen darf.
  - `Anzeige.SelectRefreshRate` – Bildwiederholrate für die empfohlene Auflösung.
- Die PowerShell-Funktionen behalten Namen und Rückgabe und rufen Core auf.
- Geprüft: 71 C#-Tests (u. a. selbst gebaute PE-Dateien, Rechner mit täuschend ähnlichem Namen), 117 PowerShell-Tests;
  alte und neue HVCI-Prüfung an allen 451 Treibern in `System32\drivers` sowie die Pfade aller Dienste und
  Kerneltreiber ergeben dasselbe.
- Noch offen in Schritt 6: Ton, Netzwerk, Laufzeiten (Spiel-DLLs), Systeminformationen, Offline-Paket, Verlauf – dort
  steckt viel Abfrage und Ausgabe ineinander, das wird in eigenen Blöcken getrennt.

## Schritt 6, zweiter Block: Ton, Bildschirm, Netzwerk, Laufzeiten (25.10.2026)

- `Interop.cs`: die Anbindung an Lautstärke und Bildschirmmodi (vorher `Initialize-Interop`, bei jedem Aufruf per
  `Add-Type` neu übersetzt) liegt jetzt fertig übersetzt in Core, als `PulsRig.Core.Audio` und `PulsRig.Core.Display`.
  `Initialize-Interop` und der Namensraum `TreiberScan` sind weg.
- `Laufzeiten.cs`: welche Visual-C++-Pakete zählen und ob eine Fassung fehlt, veraltet oder vorhanden ist. Die
  Registry liest weiter PowerShell, ebenso die Prüfung der DirectX-, XNA- und OpenAL-Dateien.
- `Netzwerk.cs` erweitert: Standardroute, brauchbare Adresse (keine 169.254.x.x), DHCP, Antwort von nslookup,
  Antwort des Verbindungstests von Microsoft, `TcpPort` (vorher `Test-TcpPort`).
- Geprüft: 79 C#-Tests, 121 PowerShell-Tests (u. a. Laufzeiten auf einem vorgetäuschten PC). Am echten PC liefern alt
  und neu dasselbe: alle Laufzeiten, alle fünf Netzwerkprüfungen, Stummschaltung und Lautstärke, beide Bildschirme mit
  empfohlener Auflösung und Rate.
- Danach offen in Schritt 6: Systeminformationen, Offline-Paket, Verlauf, Treibersicherung (siehe dritter Block).

## Schritt 6, dritter Block: Systeminformationen, Offline-Paket, Verlauf (25.10.2026)

- `Systeminfo.cs` mit drei Klassen:
  - `Systeminfo` – Platzhalter statt Hersteller, Art und Zustand der Laufwerke in Wörtern, echte Größe des
    Grafikspeichers, Treiberdatum der Grafikkarte, Treiber von Drittherstellern.
  - `OfflinePaket` – ursprüngliche Paketnamen aus pnputil, Startdatei und LIESMICH des Pakets, Fehlermeldung beim
    Export.
  - `Verlauf` – was bei Windows Update als Treiber zählt, Ergebnis in Wörtern, Geräte eines Pakets.
- Die Abfragen (CIM, Registry, Windows Update, pnputil, DriverStore) und das Schreiben der Dateien bleiben in
  PowerShell; `Get-SystemInfoLines`, `Get-SystemInfoData`, `Get-DriverHistory`, `Get-OfflinePackageSize` und
  `New-OfflinePackage` behalten Namen und Ausgabe.
- Geprüft: 96 C#-Tests. Am echten PC liefern alt und neu dasselbe (40 Textzeilen, 99 Tabellenzeilen, 8 Treiber-Updates,
  34 Treiberpakete, 3,7 GB Offline-Paket); nur der freie Platz hatte sich zwischen den Läufen bewegt.
- Noch offen in Schritt 6: Treibersicherung und Wiederherstellen, Gerätefehler, Benutzerführung der Werkzeuge
  (`Invoke-*Tool`), die viel Ausgabe enthält und mit der Oberfläche umzieht.

## Schritt 6, vierter Block: Treibersicherung, Wiederherstellen, Gerätefehler (25.10.2026)

- `Sicherung.cs` mit zwei Klassen:
  - `Sicherung` – welche Ordner als Sicherung gelten, Auswahl der Sicherung per Nummer, Name der automatischen
    Sicherung, welche Pakete vor einem Update gesichert werden (nur `oemNN.inf`), Treiberpakete aus pnputil
    (vorher `Get-DriverPackages`).
  - `Geraetefehler` – Tabelle der Fehlercodes des Geräte-Managers mit Bedeutung und Abhilfe.
- `Invoke-RestoreTool`, `Backup-ReplacedDrivers`, `Get-DriverPackages` und `Invoke-FixDevicesTool` nutzen Core;
  pnputil, Wiederherstellungspunkt, Treibersuche und alle Eingriffe an Geräten bleiben in PowerShell.
- Die Tabelle der Fehlercodes steht bis Schritt 7 doppelt: `Get-DeviceError` in `Treiber-Scan.ps1` bleibt, weil das
  Scan-Skript auch ohne Werkzeuge läuft. Ein PowerShell-Test hält beide gleich.
- Geprüft: 110 C#-Tests, 123 PowerShell-Tests. Am echten PC liefern alt und neu dasselbe (Codes 0 bis 60, 80
  Treiberpakete, Sicherungsordner).
- Noch offen in Schritt 6: nur die Benutzerführung der Werkzeuge (`Invoke-*Tool`), die mit der Oberfläche umzieht.

## Schritt 7, erster Block: Treiber-Scan – Texte, Katalog, Hersteller-Seiten (25.10.2026)

- `Scan.cs` mit vier Klassen:
  - `ScanText` – Kürzen, Datum (Platzhalter vor 1990 = kein Datum), Treiberversion mit Datum, Dateinamen,
    Fehler von Windows Update in Wörtern, Titel von Windows Update mit übersetzter Geräteart.
  - `ScanGeraete` – Chipsatz-Gerät ohne Treiber, Suche nach dem Treiber des Mainboards, Schlüssel für den Grafikschutz.
  - `Katalog` – Suchbegriff aus der Hardware-ID, Adresse der Suche, Trefferseite des Microsoft-Katalogs.
  - `Hersteller` – NVIDIA-Versionsnummer, Seite der Radeon-Karte, neueste Adrenalin-Fassung, Chipsatz und Seite
    bei AMD, Version, Größe und Datum des Chipsatz-Pakets.
- Die Tabelle der Gerätefehler steht jetzt nur noch in Core; `Get-DeviceError` ruft sie ab. Die Ergebnisklasse heißt
  `FehlerInfo` – PowerShell unterscheidet bei Typnamen nicht nach Groß- und Kleinschreibung, `GeraeteFehler` und
  `Geraetefehler` wären derselbe Name.
- Die Funktionen in `Treiber-Scan.ps1` behalten Namen und Ausgabe. Abfragen, Downloads, Signaturprüfung und
  Installation bleiben in PowerShell. `Import-PulsRigCore` kommt aus `Treiber-Werkzeuge.ps1`, das immer mitgeladen wird.
- Geprüft: 143 C#-Tests, 123 PowerShell-Tests. Alt und neu mit echten Eingaben vom PC verglichen (193 Treiber,
  194 Geräte, 200 Titel aus dem Update-Verlauf, fünf echte Katalogseiten mit 99 Treffern, echte AMD-Seiten): alle
  17 Gruppen identisch.
- Noch offen in Schritt 7: Auswahl der Katalogtreffer (`Select-CatalogCandidate`, `Select-MissingDriverRow`),
  Zuordnung von Gerät und Treiber (`Find-DeviceName`, `Find-InstalledDriver`), Ausschlüsse (`Test-Excluded`),
  Zwischenspeicher des Katalogs, NVIDIA-Produktliste.

## Schritt 7, zweiter Block: Katalogauswahl, Zuordnung, Ausschlüsse (25.10.2026)

- `Scan.cs` erweitert:
  - `KatalogAuswahl` – welcher Katalogeintrag als Hinweis taugt (gleiche Treiberlinie, neuer) und welcher einem
    Gerät ohne Treiber hilft (passende Windows-Fassung, keine Firmware, Zusätze zuletzt).
  - `Zuordnung` – Gerätename zu einer Kennung aus Windows Update, installierter Treiber zu einer Kennung,
    Ausschlüsse aus den Einstellungen mit Mustern wie bei PowerShell `-like`.
- Sortiert wird wie bisher mit `List.Sort` (so arbeitet `Sort-Object`): Der Katalog führt ein Paket oft mehrfach mit
  gleicher Version und gleichem Datum (je Windows-Fassung). Eine stabile Sortierung hätte dann einen anderen dieser
  gleichwertigen Einträge gewählt als bisher.
- Treffer sind durchgehend `PulsRig.Core.KatalogTreffer`, auch die aus dem Zwischenspeicher des Katalogs
  (`ConvertTo-CatalogRows`). Datei und Format des Zwischenspeichers bleiben gleich.
- Geprüft: 154 C#-Tests, 123 PowerShell-Tests. Alt und neu mit echten Daten verglichen (Treiber, Geräte und
  Update-Titel vom PC, fünf Katalogseiten): 1990 Auswahlen, 50 Geräte ohne Treiber, je 204 Zuordnungen und 1827
  Ausschlussprüfungen identisch.
- Damit ist die Auswertung des Treiber-Scans in Core. In PowerShell bleiben Abfragen, Zwischenspeicher, Downloads,
  Signaturprüfung, Installation und die Bildschirmausgabe, dazu die NVIDIA-Produktliste (XML, eng mit den Abrufen
  verwoben).

## Schritt 8: Oberfläche – Plan (25.10.2026)

Die neue Oberfläche (`PulsRig.App`, WPF auf .NET 10) bekommt **nur das Design Reihe Q** („Nacht-Bento“, Lila-Nacht)
aus dem Entwurf https://claude.ai/artifact/J5wvVB66nxLQL5V5Wvfxjo. Klassisch, Original und die übrigen Skins kommen
nicht mit, andere Designs erst später. Bewegungen laufen als Storyboards, nicht in Timer-Schritten. Das
PowerShell-Programm bleibt das ausgelieferte Programm, bis die neue Oberfläche alles kann.

Was eine Seite braucht und heute noch in PowerShell abfragt oder ausführt (CIM-Abfragen, Downloads, Aktionen), zieht
mit dieser Seite nach Core oder in die App.

Blöcke:
1. Rahmen und Startseite
2. Hardware mit den Detailseiten
3. Scan und Treiber
4. Boost
5. Werkzeuge mit „Etwas reparieren“ und den übrigen Absichten
6. Optionen, Englisch, Helfer neben der Uhr
7. Paket: die App statt `PulsRig.ps1` ausliefern

## Schritt 8, erster Block: Rahmen und Startseite (25.10.2026)

- `Theme.xaml`: Farben, Verläufe, Grund mit zwei Lichtflecken, flache Knöpfe, Kachel mit Anheben beim Überfahren,
  Blinken. Schriften wie im Entwurf: Sora und JetBrains Mono. Ohne diese Schriften greifen Segoe UI Variable und
  Cascadia Mono; die Schriften werden noch nicht mitgeliefert.
- `MainWindow`: randloses Fenster mit runden Ecken, Leiste (Scan, Boost, Werkzeuge, Hardware, Optionen), Titelzeile
  mit Zurück, Weg-Leiste, „Überwachung läuft“ und „Ohne Adminrechte“. Der Weg ist ein Stapel wie im Entwurf: Zurück
  geht genau eine Ebene, ein Klick in die Weg-Leiste springt auf diese Ebene, die Leiste springt auf die Hauptseite.
  Seitenwechsel wie `.z-in`/`.z-out` (0,45 s, cubic-bezier(.2,.8,.2,1)).
- `HomePage`: Mosaik mit 6 × 3 Kacheln. SCAN-Bereich mit Herzmonitor-Ring (vier Spuren, Atmen), Grafikkarte, Gaming-Check,
  Stabil, Laufwerke, „Was sich geändert hat“, Treiber, Boost und Werkzeuge.
  - Echt sind bisher die Grafikkarte (nvidia-smi über `PulsRig.Core.Messung`, Verlauf aus 40 Werten) und die
    Laufwerke (`DriveInfo`, ohne CIM). Die anderen Kacheln zeigen „–“, bis ihre Seite gebaut ist.
  - `-Demo` zeigt die Werte des Entwurfs.
  - Der Scan-Knopf tut noch nichts.
- Die übrigen Seiten sind Platzhalter.
- Geprüft:
  - Bauen ohne Warnung, 154 C#-Tests.
  - Bilder mit und ohne `-Demo` mit dem Entwurf verglichen, die echte Temperatur kommt an.
  - Leiste, Weg-Leiste und Zurück über die Bedienungshilfen von Windows gesteuert.
  - nvidia-smi endet beim Seitenwechsel und beim Schließen.

### Nachtrag zum ersten Block: Schriften und Scan-Ablauf (25.10.2026)

- Sora und JetBrains Mono liegen jetzt in `PulsRig.App/Schriften` und sind ins Programm eingebettet. Es sind die
  variablen Fassungen aus google/fonts, alle Strichstärken sind enthalten. Die Lizenz ist die SIL Open Font License 1.1;
  die Lizenztexte liegen bei und werden neben das Programm kopiert. `App.OnStartup` setzt die Schriften, Stile
  greifen per `DynamicResource` darauf zu.
- Der Scan läuft als Ereignis wie im Entwurf (`HomePage.Scan.cs`):
  - Ein Fortschrittsring außen, oben beginnend, füllt sich in 8 s.
  - Drei Lichtwellen laufen dauernd aus dem Knopf. Die Kacheln leuchten in der Reihenfolge und mit den Verzögerungen
    von `.s-d1` bis `.s-d8` auf.
  - Prozentzahl und „Prüft …“ mit dem Hersteller zählen mit.
  - Am Ende kommen Lichtstoß, zwei Wellen und 14 Funken. Die Treiber-Kachel federt und behält einen rosa Rand.
  - Ein zweiter Klick bricht ab.
  - Die Zeiten sind die des Entwurfs: Wellen und Funken nach cubic-bezier(.2,.7,.3,1) (`Easing.cs`).
- Geprüft wird beim Scan noch nichts, die Prüfung kommt mit Block 3. Ohne `-Demo` sagt die Überschrift das am Ende.
- Der Kachel-Stil hat jetzt Skalierung und Verschiebung. Werte aus Stilen sind eingefroren, deshalb bekommt jede
  Kachel eine eigene Kopie, an der Anheben, Aufleuchten und Federn hängen.
- Geprüft:
  - Bauen ohne Warnung.
  - Bilder bei 1, 4, 8 und 10 s mit dem Entwurf verglichen, mit und ohne `-Demo`.
  - Abbrechen und erneuter Scan ohne Fehler, und die Treiber-Kachel setzt sich zurück.

## Schritt 8, Block 2a: Hardware mit den Detailseiten (25.10.2026)

Block 2 ist zweigeteilt. 2a bringt die Seiten und die Abfragen, die schon da waren oder leicht zu übertragen sind.
2b bringt Stabilitätstest, Abstürze und Bericht & Diagnose, denn dafür müssen der Testlauf, das Ereignisprotokoll und das
ZIP-Paket nach C# wandern.

- **Core: `Speicher.cs`** – der Arbeitsspeicher, abgelöst aus `PulsRig-Hardware.ps1`:
  - Steckplätze aus der Rohtabelle des BIOS (SMBIOS Art 17), Reihenfolge ohne BIOS.
  - Kanal aus dem Namen und Single-/Dual-Channel.
  - Ob die Riegel richtig stecken (A2/B2) und welcher Platz besser wäre.
  - Takt aus der Typenbezeichnung und Urteil über XMP/DOCP/EXPO.
  - Hersteller und Bauart.
- **PowerShell:** `Get-MemoryRated`, `Get-MemoryProfile`, `Get-MemoryChannelKey`, `Get-MemoryChannels`,
  `Get-MemoryPlacement` und `Get-MemoryLayout` behalten Namen und Rückgabe und rufen Core. Die Abfrage `Memory` lässt
  die BIOS-Tabelle, Hersteller und Bauart von Core lesen. Neu sind die Helfer `ConvertTo-MemoryModules` und
  `ConvertTo-MemorySlots`.
- **App:**
  - `Abfragen.cs` liest Prozessor, Grafikkarte, Arbeitsspeicher, Laufwerke und Bildschirme. Dafür nimmt sie
    System.Management und die Klassen MSFT_* direkt, ohne Get-PhysicalDisk & Co.
  - `Hw` hält die Ergebnisse im Zwischenspeicher. `Live` ist eine gemeinsame Messung für alle Seiten: nvidia-smi läuft
    nur, solange eine Seite zuschaut.
- **Seiten wie im Entwurf:**
  - Übersicht mit 4 × 2 Kacheln.
  - Detailseiten nach einer Vorlage: große Kachel mit Verlauf, Balken, Kalender, Liste oder Steckplätzen, vier
    Faktenkacheln, „Was du tun kannst“ und „Kurz erklärt“.
  - Laufwerke als eine Karte je Buchstabe.
  - Riegel als Bild im richtigen Steckplatz, mit Bausteinen, Kontaktleiste und Lichtschimmer. Falsch gesteckte Riegel
    und der bessere Platz sind gelb markiert.
- **Echte Werte:**
  - Grafikkarte und Prozessor live.
  - Arbeitsspeicher, Laufwerke und Bildschirm aus den Abfragen.
  - Knöpfe, deren Ziel erst später kommt, sind gedimmt und nennen den Block.
  - `-Demo` zeigt alle acht Seiten mit den Werten des Entwurfs.
  - `-Seite hw/ram` öffnet eine Seite direkt, für Bilder und Tests.
- **Noch nicht in 2a:**
  - Temperatur des Prozessors (LibreHardwareMonitor).
  - Störungen der Laufwerke, Speichertest und Hardwarefehler aus dem Ereignisprotokoll.
  - Tempo messen.
- **Geprüft:**
  - Alt und neu mit dem echten BIOS dieses PCs und gebauten Fällen verglichen: 329 Ergebnisse identisch (Takt, Profil,
    Kanäle, Steckplätze, BIOS-Tabelle, Hersteller).
  - 176 C#-Tests, 123 PowerShell-Tests.
  - Bilder aller Seiten mit und ohne `-Demo`.
  - Nach dem Schließen läuft kein nvidia-smi mehr.
  - Probelauf (`-Snapshot`) des PowerShell-Programms ohne Fehler, Arbeitsspeicher richtig und falsch gesteckt wie
    vorher. Dafür hat `PulsRig.ps1` jetzt ein eigenes `Import-PulsRigCore` (die Oberfläche hatte Core bisher nicht
    geladen, nur die Abfragen).

## Schritt 8, Block 2b: Stabilitätstest, Abstürze, Bericht & Diagnose (25.10.2026)

- **Core: `Abstuerze.cs`** – abgelöst aus `PulsRig-Abstuerze.ps1`:
  - Fehlercodes der Bluescreens in Worten (Tabelle) und die Art der Ursache mit Erklärung und nächstem Schritt.
  - Befunde für Fenster, Karte und Bericht.
  - Helfer zum Lesen der Ereignisse (Fehlercode, Modul im Grafiktreiber, doppelte Bluescreens).
- **Core: `Laufwerkstempo.cs`** – die Tempomessung, vorher `PulsRigDiskTest` per Add-Type in der Abfrage `DriveSpeed`.
- **PowerShell:**
  - `Get-BugCheck` behält Namen und Rückgabe und ruft Core, `Get-CrashKind` ersetzt die Tabelle `$script:CrashKinds`.
  - Die Abfrage `DriveSpeed` misst über Core.
  - Das Lesen des Ereignisprotokolls bleibt in PowerShell.
- **App:**
  - `Ereignisse.cs` liest das Ereignisprotokoll wie `Get-WinEvent`: Abstürze der letzten 30 Tage, Störungen der
    Laufwerke, letzter Speichertest und Hardwarefehler (WHEA, 90 Tage).
  - `Belastung.cs` ist der Stabilitätstest mit denselben Abbruchregeln wie `Update-Stress`:
    - Rechenfehler, 90 °C an der Grafikkarte, 98 °C am Prozessor, Takteinbruch, Ausfall der Überwachung.
    - Die Last kommt aus `PulsRig-Last.cs`, als verlinkte Datei. Dafür hat die App `UseWindowsForms`.
    - Das Ergebnis liegt in `%LOCALAPPDATA%\PulsRig\Neu\Stabilitaetstest.json`. Vor dem Start steht dort
      „ausgefallen“, damit ein Absturz mitten im Test nach dem Neustart dasteht.
  - Die Temperatur des Prozessors läuft über `PulsRig-Temperatur.cs`, ebenfalls verlinkt. LibreHardwareMonitor wird
    zur Laufzeit aus dem Ordner `Sensoren` geladen, nicht mitkopiert.
  - `Tempotest.cs`: Tempo messen je Laufwerk.
  - `Bericht.cs`: Prüfungen und Urteil wie `Get-ReportChecks` und `Get-ReportVerdict`.
- **Seiten:**
  - Stabilitätstest mit Balken der Temperatur. Kurz testen (5 min), gründlich testen (30 min), Auswahl Prozessor,
    Grafikkarte oder beides.
  - Abstürze mit 30 Kästchen, Bluescreens, Ursache, Grafik-Aussetzern und Ausschalten. Die Knöpfe folgen dem Befund.
  - Bericht & Diagnose mit allen Prüfungen. „Nachholen“ führt zur ersten offenen Prüfung.
  - Laufwerke mit Störungen und Tempo. Prozessor mit Temperatur, oder mit dem Grund, warum es keine gibt.
- **Noch offen:**
  - Die ZIP-Datei mit Prüfbericht und Diagnose (erledigt mit Block 3a).
  - „Vorige Treiberfassung zurückholen“ kommt mit den Werkzeugen (Block 5).
  - PawnIO freischalten.
  - Staub-Warnung aus dem Stabilitätstest.
  - Die Ergebnisse von Tempo und Test sind getrennt von denen des PowerShell-Programms.
- **Geprüft:**
  - Fehlercodes, Befunde und Berichtszeilen der Abstürze alt und neu verglichen: identisch.
  - 199 C#-Tests, 123 PowerShell-Tests.
  - Stabilitätstest in der App kurz laufen lassen: Grafiklast, Temperatur, Rechenproben, Beenden beim Schließen. Danach
    läuft kein Prozess mehr.
  - Tempomessung über Core mit einer kleinen Testdatei; die Datei ist danach weg.
  - Probelauf (`-Snapshot`) des PowerShell-Programms ohne Fehler, 127 Bilder wie vorher, Abstürze gleich gelesen.
## Schritt 8, Block 3a: Scan, Treiber-Seite und ZIP-Datei des Berichts (25.10.2026)

- **ZIP-Datei** (`Diagnosepaket.cs`), wie `Save-ReportZip` und `New-DiagnosePackage`:
  - Inhalt: Prüfbericht als Webseite (Vorlage wie `$script:ReportTemplate`, Farben der Reihe Q), `Angaben.txt`, der
    letzte Scan und das Ergebnis des Stabilitätstests.
  - Benutzername und Name des PCs werden ersetzt wie bei `Hide-DiagnoseNames`.
  - Ablage auf dem Desktop, sonst in Downloads, sonst im Datenordner. Danach zeigt der dritte Knopf die Datei im Ordner.
  - Das Verschicken per Mail kommt mit den Optionen.
- **Scan** (`Treiberscan.cs`), wie `PulsRig-Arbeit-Scan.ps1`:
  - Läuft auf einem eigenen STA-Thread, weil Windows Update COM spricht.
  - Fragt Geräte und Treiber ab (Datum aus der Registrierung wie `Get-DriverDate`), dazu Gerätefehler mit
    Chipsatz-Suche und Windows Update (direkt bei Microsoft, dann die Standardquelle, dazu die optionalen Updates).
  - Fragt NVIDIA, den AMD-Chipsatz und Radeon. Der Grafiktreiber von NVIDIA fällt aus der Liste von Windows Update.
  - Fragt den Microsoft-Katalog: Hinweise je Treiberlinie, Treiber für Geräte ohne Treiber (höchstens 8). Der
    Zwischenspeicher `%TEMP%\PulsRig-Katalog.json` gilt einen Tag und wird mit dem PowerShell-Programm geteilt.
  - Das Ergebnis liegt in `%LOCALAPPDATA%\PulsRig\Neu\Letzter-Scan.json`.
  - Nicht übernommen: das Verstecken der Angebote für geschützte Grafikkarten, weil es etwas ändert. Es kommt mit 3b,
    ebenso die Spielkomponenten, die zu den Werkzeugen gehören.
- **Seiten:**
  - Neue Seite „Treiber“ (`TreiberPage.cs`) nach der Werkzeugliste des Entwurfs.
    - Links stehen Urteil, Stand und Quellen; Quellen ohne Antwort sind gelb.
    - Rechts stehen Zeilen in vier Abschnitten: neuer verfügbar, Gerätefehler, Hinweise aus dem Katalog, aktuell.
    - Die Knöpfe öffnen nur die Seite des Herstellers, Windows Update oder den Geräte-Manager.
  - Startseite:
    - Der Scan-Knopf startet den echten Scan, Ring und Prozentzahl folgen seinem Fortschritt.
    - Ein zweiter Klick während des Scans öffnet die Treiber-Seite.
    - Die Kacheln „Treiber“ und „Was sich geändert hat“ zeigen den letzten Scan. „Was sich geändert hat“ nennt die
      zuletzt installierten Treiber von Drittherstellern; der Verlauf mit Tagesbildern kommt mit den Werkzeugen.
- **Block 3b:** Laden, Signaturprüfung und Installation mit Bestätigung, Wiederherstellungspunkt, Schutz der
  Grafikkarte vor Windows Update, Ausschlüsse.
- **Geprüft:**
  - Scan alt (Funktionen aus `Treiber-Scan.ps1`) und neu am PC verglichen, mit und ohne Zwischenspeicher des Katalogs:
    identisch. Verglichen wurden 194 Geräte, 37 von Drittherstellern, keine Gerätefehler, kein Angebot von Windows
    Update, NVIDIA 621.01 und AMD-Chipsatz 8.09.28.1124 (beide aktuell) und 3 Katalog-Hinweise.
  - Das PowerShell-Programm liest den von der App geschriebenen Zwischenspeicher.
  - ZIP-Datei erstellt und ausgepackt: Benutzername und PC-Name kommen nicht vor. Die Testdatei vom Desktop ist
    wieder gelöscht.
  - 199 C#-Tests; Bilder von Startseite (während und nach dem Scan), Treiber-Seite echt und mit `-Demo` und Bericht &
    Diagnose.

## Schritt 8, Block 3b: Laden, Prüfen und Installieren (25.10.2026)

- **`Treiberinstallation.cs`** (wie `Treiber-Scan.ps1` und `Treiber-Werkzeuge.ps1`):
  - Windows Update: gewählte Angebote frisch per UpdateID suchen, laden und installieren. Firmware/BIOS nie,
    Angebote mit offener Lizenz werden übersprungen. Neustartbedarf wird gemeldet.
  - NVIDIA: Download nur von `*.nvidia.com`, Signatur `O=NVIDIA Corporation` (WinVerifyTrust plus Herausgeber),
    Start unter Dateisperre wie `Start-SignedInstaller`; den Assistenten bedient der Nutzer.
  - Wiederherstellungspunkt vor jeder Treiberinstallation über WMI `SystemRestore.CreateRestorePoint` (Art 10).
  - Schutz der Grafikkarte: Schalter je Karte, versteckt bzw. zeigt die Display-Angebote von Windows Update; der
    Scan versteckt neu angebotene Treiber geschützter Karten vorher.
  - Laufzeitbibliotheken: Status wie `Get-RuntimeStatus`, Installer nur von Microsoft-Adressen mit
    Microsoft-Signatur (auch das Ziel einer aka.ms-Weiterleitung wird geprüft).
  - Einstellungen in `%LOCALAPPDATA%\PulsRig\Neu\Einstellungen.json` mit den Schlüsseln aus
    `PulsRig-Einstellungen.json` (`Ignored`, `GpuShield`, `RestorePoint`).
- **Treiber-Seite:** „Installieren“ bzw. „Alle installieren“ mit Rückfrage im Stil der Reihe Q, nur mit Adminrechten
  und nie während eines Scans. Ein ✕ blendet ein Angebot aus. Neue Abschnitte: Grafiktreiber schützen,
  Laufzeitbibliotheken, Ausgeschlossen (mit „Wieder anbieten“). AMD-Chipsatz, Radeon und Katalog öffnen weiter die
  Seite, wie im PowerShell-Programm.
- **Noch offen:** Katalog-Pakete direkt installieren (`Install-CatalogDriver`, braucht die Katalog-Kennung im
  Scan-Ergebnis), automatische Sicherung der ersetzten Treiber (`Backup-ReplacedDrivers`), Einstellung für den
  Wiederherstellungspunkt in der Oberfläche.
- **Geprüft:** Build ohne neue Warnungen, 199 Tests bestanden. Nicht geprüft: Ansicht am Bildschirm und echte
  Installation (bewusst nichts installiert).
- **Nachtrag 3b (Katalog und Sicherung):**
  - Katalog-Pakete direkt installieren wie `Install-CatalogDriver`: für Geräte ohne Treiber (Code 28) und für
    Katalog-Hinweise mit echtem Treibercode. Den Eintrag sucht PulsRig beim Klick frisch (die Kennung steht nicht im
    gemeinsamen Zwischenspeicher), prüft Adresse, Prüfsumme, Microsoft-Signatur und ob ein INF das Gerät nennt;
    gearbeitet wird in einem gesperrten Ordner unter ProgramData, installiert mit `pnputil /add-driver /install`.
  - Sicherung der ersetzten Treiber wie `Backup-ReplacedDrivers` vor Windows-Update- und Katalog-Installationen:
    nur oemNN.inf, je Paket höchstens 300 MB, nach `%LOCALAPPDATA%\PulsRig\Neu\Sicherungen\Auto-Sicherung_…`.
  - Ein Scan-Ergebnis von vorher kennt die Suchbegriffe noch nicht; dort öffnet der Knopf bis zum nächsten Scan den Katalog.
  - Weiter offen: Schalter für Wiederherstellungspunkt und Sicherung in der Oberfläche.
- **Nachtrag 3b (Schalter):** Abschnitt „Sicherheit beim Installieren“ auf der Treiber-Seite mit Schaltern für
  Wiederherstellungspunkt und Sicherung der ersetzten Treiber (`RestorePoint`, `AutoBackup` in `Einstellungen.json`).

## Schritt 8, Block 5a: Werkzeuge – Übersicht und Listen (25.10.2026)

- **`WerkzeugePage.cs`** nach dem Entwurf: Übersicht `tools` mit den vier Absichten als Kacheln (Etwas reparieren
  doppelt breit) und der Empfehlung „Treiber sichern“ mit dem Alter der letzten Sicherung; je Absicht die Liste
  (`repair`, `clean`, `manage`, `games`) mit Absicht links und Werkzeugzeilen rechts. Hinweise aus echten Werten
  (Gerätefehler des letzten Scans, Zahl der Sicherungen).
- **`Werkzeuglauf.cs`:**
  - In C#: Treiber sichern (wie `Backup-InstalledDrivers`, dazu eine ZIP-Datei, „Ordner zeigen“) und Treiber
    zurückholen (wie `Invoke-RestoreTool`, neueste Sicherung, mit Rückfrage, Wiederherstellungspunkt, nur mit
    Adminrechten). Sicherungen liegen in `%LOCALAPPDATA%\PulsRig\Neu\Sicherungen`, dort auch die automatischen.
  - Übergang: Ton, Netzwerk, Bildauflösung, Gerätefehler, Speicherplatz, Gerätedaten, Offline-Paket, Inkompatible
    Treiber und Systeminformationen starten `Treiber-Scan.ps1 -Tool …` in einem eigenen PowerShell-Fenster; dort
    prüft das Werkzeug und fragt vor jeder Änderung (die Tabu-Regeln bleiben so unberührt).
  - Spielkomponenten öffnen die Treiber-Seite (Abschnitt Laufzeitbibliotheken).
  - Noch „Folgt“: Standby-Detektiv, Autostart aufräumen, Treiberverlauf, Gaming-Check, Spiele & Aufzeichnung
    (sie stecken in der Oberfläche von `PulsRig.ps1`, nicht in `-Tool`).
- `Bestaetigung.cs`: die Rückfrage im Stil der Reihe Q, gemeinsam für Treiber- und Werkzeugseiten.
- **Geprüft:** Build, 199 Tests, Bilder der Seiten Werkzeuge, Treiber verwalten, Etwas reparieren und Treiber. Kein
  Werkzeug ausgeführt.
- **Block 5b:** die Übergangs-Werkzeuge und die fünf „Folgt“ nach C# holen, jeweils mit Ergebnis auf der Seite.

## Schritt 8, Block 5b: Werkzeuge prüfen und beheben in C# (25.10.2026)

- **`Werkzeugpruefung.cs`:** neun Werkzeuge aus `Treiber-Werkzeuge.ps1` mit gleichem Ablauf: erst prüfen (Zeilen mit
  ✓/!), dann Schritte vorschlagen; optionale Schritte (wie `Confirm-Action -Optional`) bekommen eine eigene Frage.
  Ton, Gerätefehler (mit Windows-Update-Suche für genau diese Geräte), Gerätedaten, Netzwerk (drei Stufen, Winsock
  nur auf eigene Frage), Bildauflösung (Modus erst testen, dann setzen), Inkompatible Treiber, Speicherplatz (Core
  entscheidet nach den Tabu-Regeln), Offline-Paket und Systeminformationen.
- `Geraeteliste.cs`: alle Geräteeinträge mit „angeschlossen“ über die SetupAPI, weil WMI abgesteckte Geräte nicht
  kennt. Am PC wie `Get-PnpDevice`: 368 Einträge, 173 abwesend, 24 bereinigbar – alt und neu gleich.
- Seite: „Prüfen“ zeigt das Ergebnis unter der Zeile, „Beheben“ fragt mit der Liste aller Schritte; ändernde Schritte
  nur mit Adminrechten. Nach dem Ausführen steht je Schritt ✓ oder ✕ da, und das Werkzeug prüft neu.
- `-Pruefen <Datei>`: alle neun Prüfungen ohne Schritte, Ergebnis in die Datei (für Tests und Vergleiche).
- Der Übergang über `Treiber-Scan.ps1 -Tool` wird nicht mehr gebraucht (`Werkzeuglauf.Bridge` bleibt als Rückfall).
- **Noch offen (Block 5c):** alte Treiberpakete beim Speicherplatz (`Get-OldDriverPackages`, braucht DISM),
  Standby-Detektiv, Autostart aufräumen, Treiberverlauf, Gaming-Check, Spiele & Aufzeichnung.
- **Geprüft:** Build, 199 Tests, alle Prüfungen am PC ohne Fehler. Keine Schritte ausgeführt.

## Schritt 8, Block 5c: die übrigen Werkzeuge (25.10.2026)

- **`Werkzeugpruefung.Einblicke.cs`:** fünf weitere Werkzeuge, jetzt kein „Folgt“ mehr in der Werkzeugliste.
  - Standby-Detektiv wie `PulsRig-Standby.ps1`: Aufwachen der letzten 14 Tage (Feldnamen aus dem XML des Ereignisses), wer
    wecken darf, Aufweck-Timer, Standby-Zeit und was wach hält (`powercfg /requests`, nur mit Adminrechten). Ändert
    nichts; die Knöpfe öffnen Geräte-Manager, Energieoptionen und Energiesparen.
  - Autostart wie `PulsRig-Autostart.ps1`: Run-Schlüssel und Autostart-Ordner, Umschalten wie der Task-Manager über
    `StartupApproved` (sofort, ohne Rückfrage; für alle Benutzer nur mit Adminrechten).
  - Treiberverlauf wie `Get-DriverHistory`: Treiber aus dem Verlauf von Windows Update und Treiberpakete nach Datum.
  - Gaming-Check wie `PulsRig-Spielcheck.ps1`: sieben Punkte mit Ampel und Wert von 0 bis 100. Ändert nichts, am BIOS
    nie etwas; die Knöpfe öffnen die Seite von Windows.
  - Spiele & Aufzeichnung wie `PulsRig-Spiele.ps1`: Spiele aus `GameConfigStore` mit Laufwerk, letzter Aufzeichnung und
    Boost; „aufzeichnen“ schreibt wie dort nur `RecordList` in die Einstellungen des PowerShell-Programms.
- Speicherplatz: alte Treiberpakete wie `Get-OldDriverPackages`, aber ohne DISM: gelesen aus
  `HKLM\SYSTEM\DriverDatabase`, unabhängig von der Sprache. Je Treiber bleiben die zwei neuesten Fassungen, Benutztes
  immer; entfernt wird mit `pnputil /delete-driver` ohne `/force`, als eigener Schritt mit eigener Frage.
- Core: `Einblicke.cs` (Treiberspeicher, Standby, Autostart, Spielcheck) mit 29 Tests.
- `Schritt` hat jetzt `Admin` und `Ask`: Seiten öffnen und Umschalten geht ohne Adminrechte und ohne Rückfrage.
- Läufe der Werkzeuge in einem STA-Thread (für Windows Update und WScript.Shell).
- **Offen:** Bei Spielen fehlen die Temperaturen der letzten Sitzung (`Read-Recording`); das kommt mit der Aufzeichnung.
- **Geprüft:** Build (auch net48), 228 Tests, alle 14 Prüfungen am PC ohne Fehler, Gaming-Check auf der Seite angesehen.
  Alte Treiberpakete: keine (kein Treiber liegt dreimal vor, wie `pnputil /enum-drivers` bestätigt). Nichts ausgeführt.

## Schritt 8, Block 4: Boost (25.10.2026)

- **`BoostPage.cs`** nach dem Entwurf: links die Spiel-Beschleunigung mit Ring und rundem Knopf, rechts sechs Kacheln
  mit echten Werten (Energieplan, freier Speicher, Dienste, gewählte Programme bzw. größte Verbraucher, Boost-Spiele,
  Gaming-Check). Die Startseite zeigt den echten Zustand; ihr Schalter führt zur Boost-Seite.
- **`Spielboost.cs`** wie `Invoke-GameBoostTool` / `Invoke-GameBoostOff`: Spielmodus, Höchstleistung, Dienste nur aus
  `Core.Boost.Services` oder von fremden Herstellern (`Core.Boost.IsAllowed`), Programme nur die unter Einrichten
  gewählten (`Boost.Apps`) und erst nach der Rückfrage, die alle Änderungen auflistet; nie aus `Core.Boost.Keep`.
  Schließen wie `Stop-AppGroup` (8 Sekunden, ein Fenster mit „Speichern?“ bleibt offen). Zurückgestellt wird nur, was
  sich geändert hat. Dienste anhalten und wieder starten nur mit Adminrechten.
- Zustand in `Spiel-Beschleunigung.json` beim PowerShell-Programm, gleiche Felder: Jedes der beiden Programme schaltet
  den Boost des anderen aus. **`Altdaten.cs`**: gemeinsame Einstellungen (`PulsRig-Einstellungen.json`), geschrieben
  werden nur einzelne Schlüssel.
- Core `Boost.cs`: `Services`, `Keep`, `Plans` (powercfg /list), `IsFast`.
- **Offen:** „Einrichten“ (Programme, Dienste, Boost-Spiele wählen) gibt es nur im PowerShell-Programm; der
  automatische Boost bleibt beim Helfer.
- **Geprüft:** Seite am PC angesehen (Ultimative Leistung erkannt, 5 Dienste, 2 gewählte Programme, 5 Boost-Spiele).
  Eingeschaltet wurde der Boost nicht.

## Schritt 8, Block 6: Optionen, Englisch, Helfer (25.10.2026)

- **`OptionenPage.cs`** nach dem Entwurf: Aussehen (nur Reihe Q), Sprache, Bewegung (Aus, Ruhig, Normal, Lebendig wie
  `Update-Motion`), Überwachung und Schnellzugriff (Treiberverlauf, Zielordner, Kurzanleitung, Über PulsRig).
  Gespeichert wird in den Einstellungen des PowerShell-Programms (`Language`, `Motion`/`Animations`, `Helper`,
  `WeeklyScan`, `AutoBoost`, `RecordGames`).
- **Englisch:** Core `Sprache.cs` liest `PulsRig-Englisch.ps1` ohne PowerShell (Wörter, Muster, Zerlegen an „ · “ wie
  `T`), die Datei steckt als Ressource in der App. `Texte.cs` übersetzt jeden TextBlock, sobald er erscheint oder sich
  ändert; Unübersetztes landet in `Unuebersetzt.txt`. `PulsRig-Englisch.ps1` hat 183 Wörter und 25 Muster für die neue
  Oberfläche dazubekommen (ohne bestehende Übersetzungen zu ändern). Alle Seiten in Englisch durchgesehen: übrig sind
  nur Namen von Geräten und Programmen. Texte in den Ergebnissen der Werkzeuge sind noch nicht alle übersetzt.
  `PULSRIG_SPRACHE=en` schaltet nur für einen Start um.
- **`Helfer.cs`** wie `PulsRig-Helfer.ps1`: Start mit Windows als Aufgabe mit höchsten Rechten (über XML wie
  `Register-ScheduledTask`: kein Zeitlimit, auch im Akkubetrieb) oder als Autostart-Eintrag, nur im installierten
  Programm. Der Helfer selbst bleibt in `PulsRig.exe`.
- Version in Core (`PulsRigInfo.Version`, Test gegen `PulsRig.ps1`).
- **Geprüft:** 231 Tests, Optionen und alle Seiten auf Englisch am PC angesehen. Den Helfer einzurichten ließ sich
  hier nicht prüfen: Er geht nur im installierten Programm.

## Schritt 8, Block 7: Paket mit der neuen Oberfläche (25.10.2026)

- `PulsRig-Paket.ps1` veröffentlicht `PulsRig.App` eigenständig (samt .NET, win-x64) nach `App\` im Programmordner.
- `PulsRig.exe` (`PulsRig-Start.cs`) startet ohne Schalter `App\PulsRig.App.exe`; `-Klassisch`, ein Neustart des
  PowerShell-Programms (mit `-File`) und `-Snapshot` bleiben bei der bisherigen Oberfläche. Fehlt die App, startet wie
  bisher PulsRig.ps1. `-Helfer` und die Arbeit ohne Fenster sind unverändert.
- Setup: Verknüpfung „PulsRig (klassisch)“, der Ordner `App` wird beim Aktualisieren ersetzt. Die App setzt dasselbe
  Kennzeichen wie PulsRig.ps1 (`PulsRig-8B6C1F0E-Laeuft`), Setup bittet also, sie zu schließen. „Ohne Adminrechte“
  in der Titelzeile startet sie als Administrator neu.
- Die ZIP-Datei bleibt bei den losen Skripten (klassisch).
- **Nachgeholt (siehe unten):** Boost einrichten, Suche nach neuen PulsRig-Fassungen, Stromverbrauch,
  Benchmark, Ping, Sensorfenster mit Aufzeichnungen. „PulsRig (klassisch)“ bleibt für alles Übrige.

## Schritt 8, Nachtrag: die sechs fehlenden Teile (25.10.2026)

- **Boost einrichten** (`BoostSetupPage.cs`, Knopf „Einrichten“ auf der Boost-Seite) wie `Open-BoostSheet`: Reiter
  Programme, Dienste, Weitere, Spiele zum Ankreuzen, „Empfohlene Auswahl“ (Spiele bleiben), „Nur speichern“ und
  „Speichern und Boost starten“ (mit der üblichen Rückfrage). Angeboten werden Programme außerhalb von `Boost.Keep`,
  Dienste aus der eigenen Liste oder fremder Hersteller ohne die geschützten (`Boost.IsServiceKept`, wie
  `$script:BoostServiceKeep`); Vorschläge wie `$script:BoostSuggestApps`. Gespeichert in `Boost` und `BoostGames`.
  „Zwischenablage leeren“ macht jetzt auch der Boost der App.
- **Neue Fassung** (`Neuefassung.cs`, Core `Fassung`) wie `Start-VersionCheck` / `Open-UpdateSheet`: beim Start einmal
  `version.json` bei GitHub, nur mit Baudatum (`PulsRig-Bau.txt` legt das Paket jetzt neben die App) und Einstellung
  `UpdateCheck` (Schalter unter Optionen). Hinweis in der Titelzeile; geladen nur auf Knopfdruck, nur eine Setup-Datei
  aus den eigenen Releases mit SHA-256 und 200 KB bis 60 MB, nie mehr als angekündigt, gestartet nur bei passender
  Größe und Prüfsumme (`/SILENT /PULSRIGUPDATE=1`). Mit Adminrechten im Programmordner unter `Update`.
- **Stromverbrauch** (`StromPage.cs`, Core `Strom`) wie `PulsRig-Strom.ps1`: Teile gemessen oder geschätzt, Kosten aus
  dem Mittel seit dem Öffnen, Strompreis und Nutzung am Tag, FPS-Limit-Vergleich (10 s Vorlauf, 30 s Messung, PulsRig
  stellt kein Limit um).
- **Benchmark** (`BenchPage.cs`) mit derselben Messung (`PulsRig-Benchmark.cs` ist in die App eingebunden) und dem
  Laufwerk über `Tempotest`. Läufe in `History.Benchmarks` der gemeinsamen Ergebnisdatei (`Ergebnisse` in
  `Altdaten.cs`, nur dieser Teil wird geschrieben), Vergleich, Umstände und Verlauf wie `Get-BenchSummary`. Am PC
  zeigt sie die bisherigen Läufe; einen neuen Lauf habe ich nicht gestartet.
- **Ping-Test** (`PingPage.cs`, Core `Ping`/`Pingziel`) wie `PulsRig-Ping.ps1`: Router und drei DNS-Anbieter, 20 Runden
  gleichzeitig, Einordnung zu Hause / Internet, WLAN oder Kabel. Am PC: Kabel, Internet 12 ms, alles grün.
- **Sensoren** (`SensorPage.cs`, Core `Aufzeichnung`): „Live“ mit sechs Kacheln und Verlauf der letzten Minute,
  „Spielsitzungen“ mit Diagramm, Zusammenfassung (wie `Get-RecordingSummary`, Drosseln wie `Get-ThrottleShare`),
  Stromkosten der Sitzung und Auswahl der letzten acht. Am PC liest sie die Sitzungen des Helfers.
- Einstieg: Ping-Test unter „Etwas reparieren“, Benchmark, Stromverbrauch und Sensoren unter „Fürs Spielen“.
- Seiten mit laufenden Werten bauen sich nicht mitten in einem Klick neu auf.
- Englisch: 37 Wörter und 15 Muster dazu.
- **Geprüft:** 246 Tests, alle Seiten am PC angesehen, Reiter über die Bedienungshilfen von Windows bedient. Nicht
  ausgeführt: Boost, Benchmark-Lauf, Speichern der Boost-Auswahl. Die Suche nach neuen Fassungen läuft nur im gebauten
  Programm (mit Baudatum) und ist am PC nicht ausprobiert.

### Nachtrag: Temperatur des Prozessors in der App (25.10.2026)

- Im Bericht vom 25.10. 15:34 (mit Adminrechten) fehlte die Temperatur des Prozessors. Ursache: Die App lud
  `Sensoren\LibreHardwareMonitorLib.dll`, die Fassung für .NET Framework 4.7.2; unter .NET 10 bricht `Computer.Open()`
  mit `MissingMethodException` (Mutex mit MutexSecurity) ab, und `PulsRig-Temperatur.cs` schluckte das still.
- Die App nutzt jetzt das NuGet-Paket LibreHardwareMonitorLib 0.9.6 (Fassung für .NET 10, dieselbe Version);
  `System.Management` dafür auf 10.0.2. Der Ordner Sensoren bleibt unverändert für das PowerShell-Programm.
  In einem Testprogramm unter .NET 10 öffnet die Bibliothek den Ryzen 7 5800X3D und findet „Core (Tctl/Tdie)“.
- `PulsRigCpuTemp.Error` merkt sich die Ausnahme; das Diagnose-Paket nennt Quelle, Grund und Fehler der Temperatur,
  und statt „1.0.0.0“ die Fassung mit Baudatum.
- **Geprüft:** mit Adminrechten in der App am PC – die Temperatur des Prozessors wird angezeigt.

### Nachtrag: am PC ausprobiert (25.10.2026)

- **Boost einrichten, Boost an und aus, Benchmark:** vom Nutzer in der gebauten App getestet. Die Auswahl landet in
  `PulsRig-Einstellungen.json`, die fünf Dienste wurden angehalten und beim Ausschalten wieder gestartet (gleiche
  Startzeit der Dienstprozesse; Windows 11 schreibt das Ereignis 7036 nicht mehr), Spotify wurde geschlossen, der
  Benchmark-Lauf steht in `History.Benchmarks`.
- **Neue Fassung:** In einer Kopie der App mit älterem Baudatum erscheint „Neue Fassung verfügbar“. Fehler: Der Klick
  darauf tat nichts, weil `DragMove` der Titelzeile die Maus einfängt; dasselbe beim Knopf „Ohne Adminrechte“.
  Behoben in `TitleBar_MouseDown`. Danach kommt die Rückfrage mit 2,7 MB. Installiert wurde nicht (das hätte die
  neuere Installation durch den Bau von 01:23 ersetzt); die Setup-Datei aus dem Release passt in Größe und SHA-256
  zu `version.json`.

### Nachtrag: kleine Lücken geschlossen (25.10.2026)

- **Spiele & Aufzeichnung:** Jede Zeile zeigt wie `New-GameRow` die letzte Sitzung mit Datum und Dauer, die höchsten
  Temperaturen von Prozessor und Grafikkarte und „kein Drosseln“ bzw. „zu warm oder gedrosselt“ (dann gelb).
  Gelesen mit geteiltem Zugriff über `SensorPage.Read`, ausgewertet mit `Aufzeichnung.Summary`.
- **Englisch der Werkzeuge:** Alle 14 Prüfungen (`Werkzeugpruefung.Check`) einmal am PC durchlaufen lassen (nur
  prüfen, nichts ausgeführt) und jeden angezeigten Text durch die Wortliste geschickt. `PulsRig-Englisch.ps1` hat
  dafür 140 Wörter (dazu die Texte der Gerätefehler und des Standby-Detektivs) und 41 Muster dazubekommen. Übrig sind
  nur Namen von Geräten, Programmen, Spielen und Pfade. Der Sprach-Test zählt jetzt 672 Muster.
- **Knöpfe, die noch auf Block 5 warteten:** „Autostart prüfen“ (Prozessor) führt zu Aufräumen, „Gaming-Check“
  (Bildschirm) zu Fürs Spielen, „Zurückholen“ bei Abstürzen nach einem Treiber zu Treiber verwalten.
- **Nur noch in PulsRig (klassisch):**
  - Monitor-Test mit acht Testbildern (Knopf auf der Bildschirm-Seite bleibt grau, mit Hinweis)
  - Akku-Seite (Kapazität, Ladezyklen, Laufzeit)
  - Controller- und Maus-Test (`PulsRig-Eingabe`)
  - Aufrüst-Berater (eine Minute im Spiel messen)
  - „Was ist los?“ auf der Startseite (`PulsRig-Problem.ps1`)
  - Verschleiß-Vergleich der Kühlung (`PulsRig-Verschleiss.ps1`)
  - Probezeit nach Treiber-Updates mit Warnung auf der Startseite (`PulsRig-Probezeit.ps1`)
  - geführte Neuinstallation (`PulsRig-Neuinstallation.ps1`)
  - die übrigen Skins (der Helfer läuft inzwischen ohne PowerShell, siehe unten)
- **Geprüft:** 246 C#-Tests, 123 PowerShell-Tests. Die neue Spiele-Zeile und die englischen Texte über die Prüfungen
  am PC kontrolliert, die App selbst danach nicht angesehen.

## Helfer ohne PowerShell (25.10.2026)

- Der Helfer selbst (Symbol, Menü, Spielerkennung, Aufzeichnung) war schon C# in `PulsRig.exe`. PowerShell brauchte
  er nur noch für `-Boost` und `-Wochenscan` (`PulsRig-Hintergrund.ps1`).
- **`Hintergrund.cs`** in der App: `PulsRig.App.exe -Boost Ein|Aus [-Spiel Name]` und `-Wochenscan` laufen ohne
  Fenster, mit denselben Rückgabewerten, und schreiben in `PulsRig-Hintergrund.log`. `PulsRig.exe` reicht diese
  Aufrufe an `App\PulsRig.App.exe` weiter. Fehlt die App, läuft es wie bisher in PowerShell.
- Der automatische Boost (`Spielboost.OnQuietly`) schließt nie Programme und leert nie die Zwischenablage. Dienste
  nimmt er nur über `Prepare` (also `Core.Boost.IsAllowed`). Ist nichts umzustellen, bleibt er aus. Das Spiel steht
  als `Game` im Zustand.
- Der Wochenscan (`Treiberscan.Weekly`) zählt wie das Skript: keine Firmware (außer unter Optionen gewählt), keine
  ausgeschlossenen Treiber, Grafiktreiber von NVIDIA nur einmal. Er speichert auch das Ergebnis für die Treiber-Seite.
- **Geprüft:** Wochenscan am PC ohne Fenster: Rückgabe 0, Protokoll geschrieben. 246 C#-Tests und 123
  PowerShell-Tests bestanden, `PulsRig.exe` lässt sich mit csc bauen. **Nicht geprüft:** der Boost über den Helfer.
  Er braucht Adminrechte und das installierte Programm.

## Probezeit, „Was ist los?“, Verschleiß, Monitor-, Controller- und Maus-Test (25.10.2026)

- **Probezeit** (`Core/Probezeit.cs`, `Probezeitlauf.cs`): Beim Start liest die App im Hintergrund die Treiberstände von
  Grafik, Netzwerk, Ton und Speicher-Controllern, dazu die Installationszeiten (UserPnp 20001) und die Abstürze.
  Sie schreibt die Probezeiten fort, wie `Update-Probation`, in `History.Drivers` und `History.Probation` der
  Ergebnisdatei (dieselben Felder). Ist ein Treiber auffällig, steht das auf der Startseite oben unter „Was sich
  geändert hat“. Klick führt zu Abstürzen, × blendet aus (`ProbeWarnHidden`). Bei Abstürzen steht der Befund im
  Tipp, mit „Zurückholen“. Installationen aus der App setzen `History.LastInstall`.
- **„Was ist los?“** (`ProblemPage.cs`, unter Werkzeuge → Etwas reparieren): sechs Probleme, je Zeile der bekannte
  Stand (Scan, Stabilitätstest, Probezeit, Kühlung, Abstürze, Speicher, Laufwerke, Platz auf C:). Dazu „Schon
  gefunden“ aus den Abstürzen und Spiele auf Festplatten. Die Knöpfe führen zur passenden Seite. Werkzeuge mit
  Prüfung führen zu ihrer Liste, gestartet werden sie dort.
- **Verschleiß** (`Core/Verschleiss.cs`, `Verschleissdaten.cs`): dritter Reiter unter Sensoren.
  - Messpunkte aus abgeschlossenen Spielsitzungen und Stabilitätstests ab 5 Minuten (`History.Thermal`).
  - Vergleich alt gegen neu wie `Get-CoolingTrend` und SSD-Lebensdauer wie `Get-SsdLife`.
  - Die App schreibt jetzt auch den Laufwerksverlauf je Tag (`History.Disks`, wie `Add-DriveHistory`).
- **Monitor-Test** (`Monitortest.cs`): acht Bilder im Vollbild auf dem Bildschirm der App. Erreichbar über die
  Bildschirm-Seite und „Was ist los?“.
- **Controller und Maus** (`EingabePage.cs`): Messung mit `PulsRig-Eingabe.cs` (in die App eingebunden). Das
  Ergebnis kommt beim Verlassen nach `Cards.Input`. Erreichbar unter Fürs Spielen und über „Was ist los?“.
- **Englisch:** 7 Wörter und 1 Muster dazu (673 Muster). Die übrigen Texte kannte die Wortliste schon aus dem
  klassischen Programm.
- **Nur noch in PulsRig (klassisch):** Akku-Seite, Aufrüst-Berater, geführte Neuinstallation, die übrigen Skins.
- **Geprüft:**
  - 256 C#-Tests (neu: Probezeit, Verschleiß), 123 PowerShell-Tests.
  - Probezeit am PC: Ergebnisdatei geschrieben, zwei laufende Probezeiten weitergeführt.
  - Am PC angesehen: „Was ist los?“, der Reiter Verschleiß, Controller (verbunden erkannt) und das erste Bild des
    Monitor-Tests.
  - **Nicht geprüft:** die Warnung bei einem auffälligen Treiber (am PC gab es keinen) und der Maus-Reiter.

## Akku, Aufrüst-Berater und Neuinstallation (25.10.2026)

- **Akku** (`Core/Akku.cs`, `AkkuPage.cs`, Route `battery`): liest `powercfg /batteryreport /xml` wie `PulsRig-Akku.ps1`,
  ohne Bericht die Akku-Klassen von WMI. Zustand, Ladezyklen, Laufzeit, Verlauf je Monat, Tipps und der ausführliche
  Bericht im Browser. Erreichbar über „Was ist los?“ → Sonstiges, nur wenn ein Akku da ist (`PULSRIG_AKKU` zeigt die
  Zeile auch ohne Akku).
- **Aufrüst-Berater** (`Core/Aufruesten.cs`, `AufruestPage.cs`, Route `upgrade`): 10 s Vorlauf, eine Minute Messung
  über die Messschleife, Urteil wie `Get-UpgradeVerdict`, Bestandsaufnahme mit Steckplätzen und dem Laufwerk des
  laufenden Spiels. Unter Fürs Spielen und „Was ist los?“ → Ist langsam.
- **Neuinstallation** (`Core/Neuinstallation.cs`, `NeuinstallPage.cs`, Route `reinstall`, unter Treiber verwalten):
  - Vorher: Ordner `Neuinstallation_<Datum>` mit Offline-Paket (`Werkzeugpruefung.OfflinePackage`, jetzt eigene
    Funktion), `Programme.json` aus `winget export` und LIESMICH. Nur mit Adminrechten.
  - Danach: sucht Sicherungen im Zielordner und auf den Laufwerken (oberste Ebene und eine darunter) oder per
    Ordnerwahl. Treiber mit pnputil (nur mit Adminrechten, mit Rückfrage), Spielkomponenten führen zur Treiber-Seite,
    Programme zum Abhaken und nacheinander mit winget.
  - Der Notfall-Stick bleibt vorerst klassisch: er kopiert das PowerShell-Programm auf den Stick.
- **Englisch:** 56 Wörter und 31 Muster (704 Muster). Dabei aufgefallen: das Muster für „pnputil meldet Code … -
  einzelne Treiber …“ wurde vom allgemeineren „… meldet Code …“ verdeckt; es steht jetzt zusätzlich weiter oben.
- **Nur noch in PulsRig (klassisch):** Notfall-Stick und die übrigen Skins.
- **Geprüft:**
  - 276 C#-Tests (neu: Akku, Aufrüsten, Neuinstallation), 123 PowerShell-Tests.
  - Am PC: Aufrüst-Berater mit einer Messung (dabei einen Absturz beim Countdown gefunden und behoben), Akku-Seite
    ohne Akku, Neuinstallation mit einer echten Programmliste aus `winget export` (58 Programme, Abhaken).
  - **Nicht geprüft:** Akku mit echtem Akku (nur der Bericht im Test), Sicherung erstellen und Treiber einspielen
    (brauchen Adminrechte) und das Installieren mit winget.

## Nachprüfung am PC (25.10.2026)

- **Neuinstallation mit Adminrechten:** Sicherung erstellt (`Neu\Neuinstallation_…` mit Offline-Paket, 160 Treiber,
  3,2 GB, `Programme.json` mit 58 Programmen, LIESMICH), Treiber per pnputil eingespielt und ein Programm mit winget
  installiert – alles ohne Fehler. Das Fenster mit Adminrechten hat der Nutzer bedient.
- **Warnung bei auffälligem Treiber:** mit einem eingesetzten Eintrag (RTX 3080, 5 Abstürze) und schreibgeschützter
  Ergebnisdatei, sonst setzt der Abgleich beim Start ihn gleich zurück. Warnung auf der Startseite, Klick führt zu
  Abstürze mit „Zurückholen“ und der Erklärung, das Kreuz blendet sie aus. Daten danach wiederhergestellt.
- **Maus-Reiter:** Klicks je Taste werden gezählt, die Abfragerate mit der echten Maus hat der Nutzer geprüft.
- **Weiter offen:** Akku mit echtem Akku (nur an einem Laptop).

## Notfall-Stick (25.10.2026)

- **Notfall-Stick** (`Core/Neuinstallation.cs` → `Notfallstick`, dritter Reiter in `NeuinstallPage.cs`, Route `stick`,
  unter Treiber verwalten): kopiert den Programmordner (PulsRig.exe, App\, Sensoren\, ohne Deinstaller) nach
  `<Stick>\PulsRig`, prüft den Platz (`Werkzeugpruefung.OfflineSize`, jetzt eigene Funktion) und legt das
  Offline-Paket in `Treiber\`, dazu `LIESMICH-Notfall-Stick.txt`. Geht nur aus dem installierten PulsRig
  (`Altdaten.ProgramRoot`) und mit Adminrechten.
- **Ohne Installation:** Liegt der Programmordner nicht unter „Programme“, schreibt die App wie PulsRig.ps1 nach
  `Treiber\` daneben (`Altdaten.Portable`, auch für `Belastung.Folder`).
- **Englisch:** 1 Wort und 4 Muster (708 Muster), die übrigen Texte kannte die Wortliste vom klassischen Stick.
- **Nur noch in PulsRig (klassisch):** die übrigen Skins.
- **Geprüft:**
  - 286 C#-Tests (neu: Notfall-Stick), 123 PowerShell-Tests.
  - Am PC mit nachgebautem Paket und Adminrechten: Stick F: eingerichtet (160 Treiber, 3,2 GB, App, LIESMICH),
    danach PulsRig.exe vom Stick gestartet – die App läuft und schreibt ihre Ergebnisse nach `F:\PulsRig\Treiber`.
  - **Nicht geprüft:** Start vom Stick auf einem fremden PC und „zu wenig Platz“ (der Stick hatte 114 GB frei).
