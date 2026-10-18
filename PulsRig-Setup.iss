; PulsRig - Installationsdatei (Inno Setup). Gebaut wird sie von PulsRig-Paket.ps1, das Version und Dateien liefert:
; die Dateien des Programms liegen dann in dist\PulsRig.

#ifndef AppVersion
  #define AppVersion "0.5 Beta"
#endif
#ifndef VersionName
  #define VersionName "0.5-Beta"
#endif

[Setup]
AppId={{8B6C1F0E-5A0D-4B7E-9C55-2F1D7A3E6B11}
; ein laufendes PulsRig setzt dieses Kennzeichen (siehe PulsRig.ps1); Setup und Deinstallation bitten dann, es zu schließen
AppMutex=PulsRig-8B6C1F0E-Laeuft
AppName=PulsRig
AppVersion={#AppVersion}
AppVerName=PulsRig {#AppVersion}
AppPublisher=PulsRig
DefaultDirName={autopf}\PulsRig
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=admin
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=dist
OutputBaseFilename=PulsRig-Setup-{#VersionName}
SetupIconFile=PulsRig.ico
UninstallDisplayIcon={app}\PulsRig.ico
UninstallDisplayName=PulsRig {#AppVersion}
InfoBeforeFile=PulsRig-Testzettel.txt
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

; Aktualisieren über eine ältere Fassung: deren Programmdateien zuerst entfernen, damit keine Datei übrig bleibt, die es
; in der neuen Fassung nicht mehr gibt. Einstellungen und Ergebnisse liegen im Benutzerordner und bleiben erhalten.
[InstallDelete]
Type: files; Name: "{app}\PulsRig*.ps1"
Type: files; Name: "{app}\Treiber-*.ps1"
Type: files; Name: "{app}\*.xaml"
Type: files; Name: "{app}\*.cs"
Type: files; Name: "{app}\*.bat"
Type: files; Name: "{app}\PulsRig-Bau.txt"
Type: filesandordirs; Name: "{app}\Sensoren"

[Files]
Source: "dist\PulsRig-Programm\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Gestartet wird über PulsRig.exe (die Hülle aus PulsRig-Start.cs), nicht mehr über powershell.exe
[Icons]
Name: "{autoprograms}\PulsRig"; Filename: "{app}\PulsRig.exe"; WorkingDir: "{app}"; IconFilename: "{app}\PulsRig.ico"; Comment: "PulsRig - Treiber, Boost, Werkzeuge"
Name: "{autodesktop}\PulsRig"; Filename: "{app}\PulsRig.exe"; WorkingDir: "{app}"; IconFilename: "{app}\PulsRig.ico"; Comment: "PulsRig - Treiber, Boost, Werkzeuge"; Tasks: desktopicon

; Lädt PulsRig eine neue Fassung selbst, startet es das Setup still (/SILENT /PULSRIGUPDATE=1). Der Eintrag
; "PulsRig starten" der letzten Seite entfällt dann; dafür startet diese Zeile das Programm wieder.
; Beim Entfernen: Helfer beenden, seine Aufgabe und seinen Autostart-Eintrag löschen
[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM PulsRig.exe"; Flags: runhidden; RunOnceId: "HelferBeenden"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""PulsRig Helfer"" /F"; Flags: runhidden; RunOnceId: "HelferAufgabe"
Filename: "{sys}\reg.exe"; Parameters: "delete HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v PulsRig-Helfer /f"; Flags: runhidden; RunOnceId: "HelferAutostart"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\Update"

[Code]
function IsSelfUpdate: Boolean;
begin
  Result := ExpandConstant('{param:PULSRIGUPDATE|0}') = '1';
end;

{ Der Helfer neben der Uhr ist ein zweites PulsRig.exe ohne Fenster und ohne das Kennzeichen des Programms:
  Vor dem Kopieren wird er beendet, sonst ließe sich die Datei nicht ersetzen. PulsRig startet ihn danach wieder. }
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM PulsRig.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;

[Run]
Filename: "{app}\PulsRig.exe"; WorkingDir: "{app}"; Flags: nowait runasoriginaluser; Check: IsSelfUpdate
Filename: "{app}\PulsRig.exe"; WorkingDir: "{app}"; Description: "PulsRig starten"; Flags: postinstall nowait skipifsilent
