## Neu in 0.7 Beta

**Stromverbrauch und Stromkosten**
- Neues Werkzeug „Stromverbrauch“: zeigt, was der PC gerade zieht und was das im Jahr kostet. Die Grafikkarte misst PulsRig bei NVIDIA direkt, den Prozessor über die freigeschaltete Prozessor-Temperatur, den Rest schätzt es.
- Strompreis und Nutzung am Tag lassen sich einstellen.
- FPS-Limit-Vergleich: Im Spiel einmal ohne und einmal mit Bildraten-Limit messen. PulsRig zeigt, wie viel Watt das Limit spart und was das im Jahr ausmacht. Das Limit stellst du selbst im Spiel oder Treiber ein.
- Jede aufgezeichnete Spielsitzung nennt den Verbrauch in kWh und was sie gekostet hat.

**Neuinstallation von Windows**
- Neues Werkzeug „Neuinstallation“ unter Treiber verwalten. Vorher sichert es in einen Ordner alle Treiber als Offline-Paket und die Liste der Programme, die winget kennt.
- Danach findet PulsRig den Ordner auch auf dem USB-Stick und führt durch die Schritte: Treiber einspielen, Spielkomponenten prüfen, Programme abhaken und per winget installieren.

**Treiber**
- Radeon-Grafikkarten (RX 5000 bis 9000, Vega): Der Scan fragt jetzt direkt bei AMD nach dem neuesten Adrenalin-Treiber, statt nur auf die Seite zu verweisen.

**Weniger Arbeitsspeicher**
- PulsRig gibt nach dem Start und beim Minimieren ungenutzten Arbeitsspeicher frei: im Leerlauf rund 120 statt 270 MB.

**Fehler behoben**
- Fenster wie Sensoren oder Laufwerke behalten im Aussehen Nacht-Bento ihre Größe und schrumpfen nicht mehr, wenn sich die Temperaturkurven bewegen.
- Das Suchfeld bei Werkzeuge schneidet die Schrift unten nicht mehr ab.
- Notebooks: Die Akku-Zeile steht jetzt auch im Aussehen Nacht-Bento in der Karte „Sensoren“, und der Akku wird auch erkannt, wenn Windows ihn auf dem üblichen Weg nicht meldet.
- Der Prüfbericht brach ab, wenn PulsRig keine Abstürze gefunden hatte.
- Hinweis für AVG und Avast: CyberCapture hält Setup oder Deinstallation manchmal zur Prüfung an. Das ist kein Virenfund – ein paar Stunden warten oder die Datei im Virenschutz als vertrauenswürdig markieren.

## Neu in 0.6 Beta

**Bericht & Diagnose**
- Die ZIP-Datei entsteht jetzt auch auf PCs, auf denen das bisher scheiterte: Lässt Windows nichts auf den Desktop schreiben (z. B. wegen überwachtem Ordnerzugriff oder OneDrive), landet sie im Ordner Downloads. Das Fenster sagt, wo sie liegt.
- Wird der Prüfbericht nicht fertig, kommen trotzdem die Angaben für die Fehlersuche in die Datei.

**Controller und Maus**
- Neues Werkzeug: Tasten und Sticks des Controllers prüfen, Stick-Drift messen, Vibration testen (Xbox-kompatible Controller).
- Für die Maus: Abfragerate in Hz beim schnellen Bewegen und ungewollte Doppelklicks einer verschlissenen Taste erkennen.

**Staub und Verschleiß**
- Hardware → Sensoren → Verschleiß vergleicht Temperaturen aus Spielsitzungen und Stabilitätstests über Wochen: Wird es bei gleicher Leistung wärmer oder drehen die Lüfter schneller, ist es Zeit zum Entstauben.
- Für SSDs schätzt PulsRig aus dem Anstieg der Abnutzung, wie lange sie bei diesem Tempo noch hält.

**Spielsitzungen**
- Der Helfer neben der Uhr zeichnet beim Spielen alle 5 Sekunden Temperatur, Last und Takt von Prozessor und Grafikkarte auf – für die Spiele, die unter Boost gewählt sind, oder per Rechtsklick für alles andere.
- Hardware → Sensoren → Spielsitzungen zeigt jede Sitzung als Diagramm und sagt, ob etwas zu heiß wurde oder gedrosselt hat.
- Neu „Deine Spiele“ (über „Was ist los?“ → Spiele ruckeln): jedes Spiel mit Laufwerk, letzter Sitzung, Höchsttemperaturen und ob gedrosselt wurde; ein Klick nimmt ein Spiel in die Aufzeichnung auf.

**Benchmark**
- Neu oben rechts auf der Hardware-Seite: misst in rund einer Minute Prozessor (ein Kern und alle Kerne), Arbeitsspeicher, Grafikkarte und das Windows-Laufwerk und gibt Punkte.
- Jeder Lauf wird gespeichert und mit dem davor verglichen – samt dem, was sich seitdem geändert hat (Grafiktreiber, Speichertakt, Energieplan, Windows, Boost) und ob der PC dabei wärmer wurde.
- Der Stabilitätstest belastet den Prozessor jetzt voll: Er rechnet dieselbe Aufgabe wie der Benchmark statt Prüfsummen, die viele Prozessoren mit sparsamen Spezialbefehlen erledigen (beim Ryzen 7 5800X3D rund 10 °C mehr).
- Auch die Grafikkarte wird jetzt voll belastet: Ein kleines Rechenprogramm auf der Karte (Shader) treibt sie bis an ihre Leistungsgrenze – bei einer RTX 3080 rund 365 statt 220 Watt.
- Erreicht der Prozessor seine Temperaturgrenze, erklären Benchmark und Prüfbericht das: Viele Prozessoren takten absichtlich bis dorthin hoch.

**Temperatur des Prozessors**
- Hardware → Sensoren zeigt jetzt auch Temperatur und Leistung des Prozessors. Windows gibt sie nicht heraus; „Freischalten“ installiert dafür den freien, signierten Treiber PawnIO über sein offizielles Setup (einmal, mit Adminrechten). Läuft Core Temp, übernimmt PulsRig dessen Werte.
- Der Stabilitätstest zeigt die Temperatur des Prozessors, bricht ab 98 °C ab, und der Prüfbericht nennt die Höchstwerte von Prozessor und Grafikkarte.
- Hinweis: Das Anti-Cheat von FACEIT hat PawnIO schon blockiert.

**Abstürze überall im Blick**
- Der Prüfbericht hat eine Zeile „Abstürze in 30 Tagen“: Bluescreens, plötzliches Ausgehen und Aussetzer des Grafiktreibers, mit Knopf zu den Einzelheiten.
- „Was ist los?“ zeigt unter „Stürzt ab“ und „Spiele ruckeln“ oben, was PulsRig schon gefunden hat, jeweils mit dem nächsten Schritt.

**Aufgeräumt**
- Die Leiste links ist kürzer: „Menü“ ist in „Optionen“ aufgegangen. Treiberverlauf, Zielordner, Kurzanleitung und „Über PulsRig“ stehen dort unter Allgemein → Schnellzugriff.
- Neu unter Optionen → Allgemein: Bewegung in vier Stufen – Aus, Ruhig, Normal, Lebendig.
- Hardware: Prüfbericht und Diagnose-Paket sind eine Karte „Bericht & Diagnose“. Ein Klick auf „Als ZIP speichern“ legt beides zusammen in eine Datei auf dem Desktop, danach geht sie per E-Mail.
- Hardware: Der Monitor-Test ist jetzt die Karte „Bildschirm“, der Akku steht auf Notebooks als Zeile in der Karte „Sensoren“.
- Werkzeuge: Die vier Reparaturen stehen in einer schmalen Reihe (Ton, Netzwerk, Bild, Geräte). Sichern, Wiederherstellen und Offline-Paket heißen zusammen „Treiber-Sicherung“.
- Namen: Das bisherige Aussehen heißt „Klassisch“, das Farbdesign von Nacht Puls „Nachtblau“ und sein Ring „Herzmonitor“.

**Ping-Test**
- Neu unter „Was ist los?“ → Internet: misst Verzögerung, Schwankung und verlorene Pakete zum eigenen Router und zu Cloudflare, Google und Quad9 (20 Runden, rund acht Sekunden).
- Sagt in einem Satz, wo ein Problem liegt: zu Hause (WLAN, Router) oder beim Anbieter, und ob der PC per WLAN oder Kabel verbunden ist.

**Neues Aussehen „Nacht Puls“**
- PulsRig sieht neu aus: tiefes Nachtblau, Cyan und Violett, Karten mit leuchtendem Rand.
- Um den SCAN-Knopf läuft ein Puls wie auf einem Herzmonitor; der Schein hinter dem Knopf pocht im selben Takt.
- Links eine schmale Leiste mit Symbolen statt der breiten Seitenleiste; das Schild für Adminrechte steht oben.
- Startseite: rechts Live-Werte von Grafikkarte, Prozessor und Arbeitsspeicher mit Kurve der letzten Minute, die neuesten Änderungen als Zeitleiste und der Gaming-Check als Ring.
- Werkzeuge: ein Suchfeld findet jedes Werkzeug beim Tippen.
- Hardware: die Karten zeigen nach einer Prüfung ein kleines Bild statt Stichpunkten, zum Beispiel Balken je Laufwerk, belegte Speicherplätze oder die letzten 30 Tage bei den Abstürzen.
- Das bisherige Aussehen gibt es weiter unter Optionen → Design → Skin „Klassisch“.

**Monitor-Test**
- Neue Karte „Bildschirm“ auf der Hardware-Seite: zeigt zuerst jeden Bildschirm mit Auflösung und Bildwiederholrate (und sagt, wenn er mehr Hz könnte), dann acht Bilder im Vollbild: Schwarz, Weiß, Rot, Grün, Blau, Grau, Farbverlauf und ein Bewegungsbild.
- Damit lassen sich tote und hängende Pixel, Lichthöfe, ungleichmäßige Ausleuchtung, Farbstufen und Schlieren erkennen. Weiter mit Leertaste oder Klick, Esc beendet.
- Auch unter „Was ist los?“ → Sonstiges.

**Akku-Bericht für Notebooks**
- Auf Notebooks steht in der Karte „Sensoren“ eine Zeile „Akku“ mit dem Zustand, zum Beispiel „Zustand 70 %“.
- Das Fenster zeigt, wie viel der Akku noch fasst (im Vergleich zu neu), die Ladezyklen, wie lange er laut Windows hält, den Verlauf der Kapazität über die Monate und Tipps zum Schonen.
- „Ausführlicher Bericht von Windows“ öffnet den Akku-Bericht von Windows im Browser.
- Auch unter „Was ist los?“ → Sonstiges und im Diagnose-Paket.

**Was ist los?**
- Neuer Knopf auf der Startseite: Problem wählen (Spiele ruckeln, stürzt ab, ist langsam, kein Ton, Internet, Sonstiges), PulsRig zeigt die passenden Prüfungen der Reihe nach.
- Jede Prüfung sagt, was PulsRig schon weiß, zum Beispiel „92 von 100“ oder „1 Vorfall · heute“, und führt mit einem Klick hin.
- Bei „Spiele ruckeln“ stehen die erkannten Spiele mit ihrem Laufwerk: liegt eins auf einer Festplatte statt einer SSD, sagt PulsRig das.

**Treiber**
- Festplatten, die Windows ohne Bauart meldet (etwa ältere WD-Platten), erkennt PulsRig jetzt selbst als Festplatte - wichtig für „Was ist los?“ → „Spiele ruckeln“.
- Speicherplatz freigeben löscht auf Wunsch auch den Shader-Cache von NVIDIA, AMD, Intel, DirectX und Steam (mit Hinweis: Spiele ruckeln danach beim ersten Start kurz).
- Speicherplatz freigeben entfernt auf Wunsch alte Treiberpakete aus dem Treiberspeicher von Windows (bei NVIDIA oft mehrere GB); je Treiber bleiben die zwei neuesten Fassungen, benutzte Pakete werden nie angefasst. Braucht Adminrechte.
- Bietet Windows Update einen alten NVIDIA-Treiber an, steht er nicht mehr zusätzlich neben dem neuesten direkt von NVIDIA.
- Fehlt der Chipsatz-Treiber, sagt PulsRig das jetzt ausdrücklich und nennt das Mainboard.
- Für Geräte ohne Treiber sieht PulsRig im Microsoft-Katalog nach und installiert den Treiber auf Nachfrage über „Beheben“.
- NVIDIA-Karten ab der RTX-40-Reihe werden gefunden.
- Treiber von Windows Update stehen mit verständlicher Geräteart in der Liste, zum Beispiel „Monitor“ statt „LCD“.
- Hinweise für Intel-Systeme und Radeon-Karten; die Startseite nennt nur die Quellen, die auf dem eigenen PC gefragt werden.
- Meldet ein Gerät einen Fehler, steht oben nicht mehr „Alles aktuell“.
- Treiber ohne echtes Datum (etwa Intels Chipsatz-Treiber mit „18.07.1968“) stehen als „ohne Datum“ in der Liste.

**Programm**
- PulsRig zeigt oben rechts an, wenn es eine neuere Fassung gibt. Geladen wird nichts von allein; abschaltbar in den Einstellungen.
- Das Setup erkennt ein offenes PulsRig und spielt eine neue Fassung sauber über die alte.
- Weniger belegter Arbeitsspeicher nach dem Stabilitätstest.
- Lange Texte in der Ergebnisliste werden umbrochen statt abgeschnitten.

**Hardware und Berichte**
- Arbeitsspeicher: Steckplätze auf Intel-Mainboards ab der 12. Generation werden richtig erkannt.
- Kontoname und Name des PCs stehen nicht mehr im Fenster, im Prüfbericht und in den Systeminformationen.
- Das Diagnose-Paket nennt das Baudatum und enthält die Ausgabe der Werkzeuge.
- Gibt Windows das Ereignisprotokoll nicht heraus, steht bei Laufwerken, Speichertest und Hardwarefehlern „nicht lesbar“ statt „in Ordnung“.
- Ohne Internet oder mit abgeschaltetem Windows Update heißen die Treiber „nicht geprüft“ statt „aktuell“.
- Die Karten der Hardware-Seite zeigen den Stand der letzten Prüfung, zum Beispiel „Bestanden · heute“ oder „1 auffällig · 13.10.“, statt nur „Verfügbar“.
- Hardware-Karten haben unten eine Zeile mit dem wichtigsten Wert, zum Beispiel „Höchstens 66 °C · 4,30 GHz“ oder „3 Laufwerke · 1,15 TB frei“.
- Werkzeuge: Der Treiberverlauf steht jetzt auch dort; beide Spalten sind gleich lang.
- Das Seitenmenü heißt nur noch „Menü“. Skins, Farben und Ring-Animation stehen an einer Stelle: Einstellungen → Design.
- PulsRig startet über eine eigene Programmdatei: Im Task-Manager steht „PulsRig“ statt „Windows PowerShell“.
- Im Programmordner liegt nur noch PulsRig.exe: Alle Programmdateien stecken darin.
- Neue Fassungen lädt und installiert PulsRig auf Knopfdruck selbst (Klick auf den Hinweis oben rechts). Gestartet wird die Datei nur, wenn Größe und Prüfsumme stimmen.
- PulsRig gibt es jetzt auch auf Englisch: Einstellungen → Allgemein → Sprache.
- Neu unter Werkzeuge: „Autostart“ (Programme, die mit Windows starten, ein- und ausschalten) und „Speicherplatz freigeben“ (temporäre Dateien, alte Downloads von Windows Update, Fehlerberichte).
- Boost: Die Boost-Seite zeigt, wie viel Arbeitsspeicher vor und nach dem Einschalten frei war.
- Neu: der Helfer neben der Uhr (Einstellungen → Hintergrund). Er startet mit Windows, schaltet den Boost per Rechtsklick, sieht einmal pro Woche nach neuen Treibern und kann den Boost automatisch einschalten, wenn ein gewähltes Spiel startet (Boost → Einrichten → Spiele).
- Laufwerke: Meldet ein Laufwerk Störungen oder ist es auffällig langsam, erscheint ein Hinweis auf der Startseite. Das Kreuz blendet ihn aus, bis sich etwas ändert.
- Laufwerke → Verlauf: PulsRig schreibt bei jedem Start einmal am Tag mit, wie es den Laufwerken geht (Störungen, Temperatur, Abnutzung, Tempo), und zeigt, ob etwas schlechter wird.
- Diagnose-Paket: Nach dem Erstellen öffnet „Per E-Mail schicken“ eine fertige Mail an pulsrig.hilfe@gmail.com und zeigt die ZIP-Datei zum Anhängen.
- Neu auf der Hardware-Seite: „Abstürze“ erklärt Bluescreens, plötzliches Ausschalten und Aussetzer des Grafiktreibers der letzten 30 Tage in einfachen Worten und schlägt den nächsten Schritt vor (Treiber suchen, vorige Fassung zurückholen, Speicher oder Laufwerke prüfen, Stabilitätstest).
- Neu: „BIOS“ zeigt Version, Datum und Alter und sucht auf Wunsch die Download-Seite des Herstellers. Einspielen muss man es selbst mit dem Werkzeug des Herstellers.
- Die Hardware-Seite hat jetzt acht Karten in zwei Reihen.
- Neu: Probezeit für Treiber. Ändert sich der Treiber von Grafikkarte, Netzwerk, Ton oder Speicher-Controller (durch PulsRig, Windows Update oder von Hand), beobachtet PulsRig sieben Tage lang, ob es seitdem mehr Abstürze gibt. Wenn ja, meldet die Startseite das und bietet die vorige Fassung an. Der Stand steht im Fenster „Abstürze“.
- Neu: „Was hat sich geändert?“ (dritte Kachel auf der Startseite). PulsRig merkt sich einmal am Tag Windows-Stand, Programme, Autostart, wichtige Treiber und Energieplan und zeigt, was seit gestern, seit 7 oder 30 Tagen neu, weg oder anders ist, dazu die Abstürze seit diesem Tag. Der Treiberverlauf ist von dort aus erreichbar.
- Neu: Gaming-Check (Boost-Seite, oben rechts). Eine Ampel-Liste mit sieben Punkten, die fürs Spielen zählen – Bildwiederholrate des Bildschirms, Resizable BAR, GPU-Planung, Kernisolierung, Energieplan, voller Takt des Arbeitsspeichers (XMP) und Spielmodus – und ein Wert von 0 bis 100. Jede Zeile führt zur Stelle, an der man es einstellt.
- Neu unter Werkzeuge: Standby-Detektiv. Er zeigt, was den PC in den letzten 14 Tagen aus dem Standby geweckt hat (Maus, Tastatur, Netzwerkkarte, geplante Aufgabe), welche Geräte ihn wecken dürfen und warum er nicht in den Standby geht. „Gerätedaten bereinigen“ steht jetzt bei den Treibern; der Treiberverlauf ist über „Was hat sich geändert?“ und das Menü erreichbar.
