# PulsRig - Englisch: die Übersetzung der Oberfläche. Wird von PulsRig-Sprache.ps1 geladen, wenn Englisch gewählt ist.
#
# Words: je Zeile ein Paar - links der deutsche Text genau so, wie er im Programm vorkommt (Groß- und Kleinschreibung
# zählt), rechts der englische. Patterns: Muster für Texte mit wechselnden Teilen; $1, $2 … setzen den gefundenen
# Teil ein, {T:1}, {T:2} … setzen ihn übersetzt ein. Das erste passende Muster gilt, deshalb stehen die genaueren oben.
# Zusammengesetzte Texte ("3 Laufwerke · 1,15 TB frei") zerlegt das Programm selbst und fragt jeden Teil einzeln an.
@{
    Words    = @(
        # --- Seitenleiste, Kopf, Allgemeines
        'Scan', 'Scan'
        'Boost', 'Boost'
        'Werkzeuge', 'Tools'
        'Hardware', 'Hardware'
        'Einstellungen', 'Settings'
        'Menü', 'Menu'
        'NEU', 'NEW'
        'AN', 'ON'
        'AUS', 'OFF'
        'Ohne Adminrechte', 'No admin rights'
        'Scannen und Probeläufe', 'Scans and dry runs'
        'Als Admin neu starten', 'Restart as admin'
        'Adminrechte aktiv', 'Admin rights active'
        'Alles freigeschaltet', 'Everything unlocked'
        'Schließen', 'Close'
        'Zurück', 'Back'
        'Ja', 'Yes'
        'Nein', 'No'
        'OK', 'OK'
        'Laden', 'Loading'
        'Laden …', 'Loading …'
        'Suchen', 'Search'
        'Suche', 'Search'
        'Starten', 'Start'
        'Anzeigen', 'Show'
        'Prüfen', 'Check'
        'Beheben', 'Fix'
        'Installieren', 'Install'
        'Sichern', 'Back up'
        'Neu einlesen', 'Refresh'
        'Neu installieren', 'Reinstall'
        'Probelauf', 'Dry run'
        'Probelauf starten', 'Start dry run'
        'Programm schließen', 'Close program'
        'Programme schließen', 'Close programs'
        'Per E-Mail schicken', 'Send by email'
        # --- Hardware-Seite mit 4 x 2 Karten, Abstürze, BIOS
        'Temperaturen, Lüfter und Auslastung live', 'Temperatures, fans and load live'
        'Grafikkarte, Lüfter', 'Graphics card, fans'
        'Prozessor: Last, Takt', 'CPU: load, clock'
        'Verlauf über 1 Minute', 'History over 1 minute'
        'Prozessor und Grafikkarte unter Volllast', 'CPU and graphics card at full load'
        'Prozessor-Volllast', 'CPU full load'
        'Grafik-Volllast', 'GPU full load'
        'Stopp bei Fehlern', 'Stops on errors'
        'Zustand, Belegung, Tempo und Verlauf', 'Health, usage, speed and history'
        'Zustand, Störungen', 'Health, faults'
        'Tempo und Verlauf', 'Speed and history'
        'Betriebsstunden', 'Power-on hours'
        'Riegel, Steckplätze', 'Modules, slots'
        'Voller Takt (XMP)', 'Full speed (XMP)'
        'Speichertest', 'Memory test'
        'Abstürze', 'Crashes'
        'Bluescreens und Aussetzer verstehen', 'Understand blue screens and dropouts'
        'Bluescreens erklärt', 'Blue screens explained'
        'Grafik-Aussetzer', 'Graphics dropouts'
        'Was jetzt hilft', 'What helps now'
        'Angaben für die Fehlersuche in einer Datei', 'Troubleshooting details in one file'
        'PC und Windows', 'PC and Windows'
        'Fehlerprotokoll', 'Error log'
        'Alle Ergebnisse als Bericht speichern', 'Save all results as a report'
        'Alles auf einer Seite', 'Everything on one page'
        'Zum Weitergeben', 'For sharing'
        'Version, Alter und Seite des Herstellers', 'Version, age and maker''s page'
        'Version und Datum', 'Version and date'
        'Alter in Worten', 'Age in plain words'
        'Link zum Hersteller', 'Link to the maker'
        'Jetzt ansehen', 'View now'
        'Noch nicht gelesen', 'Not read yet'
        'Bluescreens, plötzliches Ausschalten und Aussetzer der letzten 30 Tage', 'Blue screens, sudden shutdowns and dropouts of the last 30 days'
        'Lese das Ereignisprotokoll …', 'Reading the event log …'
        'Ein Treiber griff auf falschen Speicher zu', 'A driver accessed the wrong memory'
        'Ein Treiber hat einen Fehler nicht abgefangen', 'A driver did not catch an error'
        'Fehler in einem Systemaufruf', 'Error in a system call'
        'Ein Treiber hat Speicher falsch angefordert', 'A driver requested memory incorrectly'
        'Speicherverwaltung durcheinander', 'Memory management corrupted'
        'Ein Treiber wollte geschützten Speicher ausführen', 'A driver tried to execute protected memory'
        'Sicherheitsprüfung im Windows-Kern', 'Security check in the Windows kernel'
        'Ein Treiber hat das System zu lange blockiert', 'A driver blocked the system for too long'
        'Ein Treiber hing beim Standby oder Aufwachen', 'A driver hung during sleep or wake-up'
        'Fehler in der Speicherverwaltung', 'Error in memory management'
        'Zugriff auf Speicher, den es nicht gibt', 'Access to memory that does not exist'
        'Grafiktreiber reagierte nicht mehr', 'Graphics driver stopped responding'
        'Fehler im Grafiktreiber', 'Error in the graphics driver'
        'Fehler im Grafikspeicher', 'Error in graphics memory'
        'Die Hardware hat einen schweren Fehler gemeldet', 'The hardware reported a serious error'
        'Ein Prozessorkern hat nicht mehr geantwortet', 'A CPU core stopped responding'
        'Daten vom Laufwerk ließen sich nicht lesen', 'Data could not be read from the drive'
        'Fehler im Dateisystem', 'Error in the file system'
        'Unerwarteter Fehler beim Laufwerkszugriff', 'Unexpected error accessing the drive'
        'Ein wichtiger Windows-Prozess wurde beendet', 'An important Windows process was ended'
        'Meist ein Treiber. Treiber aktualisieren hilft oft.', 'Usually a driver. Updating drivers often helps.'
        'Grafiktreiber oder Grafikkarte. Eine neuere oder die vorige Treiberfassung hilft oft.', 'Graphics driver or graphics card. A newer or the previous driver version often helps.'
        'Oft der Arbeitsspeicher: ein zu scharfes XMP-Profil oder ein defekter Riegel.', 'Often the memory: an XMP profile set too tight or a faulty module.'
        'Hardware: Übertaktung, Spannung, Hitze oder Netzteil.', 'Hardware: overclocking, voltage, heat or power supply.'
        'Laufwerk, Kabel oder Anschluss, manchmal beschädigte Windows-Dateien.', 'Drive, cable or port, sometimes damaged Windows files.'
        'Seltener Fehlercode, meist steckt ein Treiber dahinter.', 'Rare error code, usually a driver is behind it.'
        'Strom', 'Power'
        'Speicher prüfen', 'Check memory'
        'Laufwerke prüfen', 'Check drives'
        'Zurückholen', 'Restore'
        'Vorige Treiberfassung zurückholen', 'Restore the previous driver version'
        'Fingen die Aussetzer nach einem Treiber-Update an, hilft oft die vorige Fassung. PulsRig hat Sicherungen davon.', 'If the dropouts began after a driver update, the previous version often helps. PulsRig has backups of it.'
        'PC ist plötzlich ausgegangen', 'PC suddenly switched off'
        'Ursachen: Strom weg, Netzteil, Hitze oder ein eingefrorener PC. Passiert es beim Spielen, zeigt der Stabilitätstest, ob die Hardware durchhält.', 'Causes: power loss, power supply, heat or a frozen PC. If it happens while gaming, the stability test shows whether the hardware holds up.'
        'Prozessor, Speicher oder Mainboard haben Windows einen Fehler gemeldet. Oft hilft es, Übertaktung und XMP zurückzunehmen.', 'CPU, memory or mainboard reported an error to Windows. Undoing overclocking and XMP often helps.'
        'Das Ereignisprotokoll ist nicht lesbar', 'The event log cannot be read'
        'Windows gibt es auf diesem PC nicht heraus. PulsRig einmal als Admin starten und neu einlesen.', 'Windows does not release it on this PC. Start PulsRig as admin once and refresh.'
        'Keine Abstürze in 30 Tagen', 'No crashes in 30 days'
        'Abstürze in 30 Tagen', 'Crashes in 30 days'
        'Zu den Abstürzen', 'To crashes'
        'SCHON GEFUNDEN', 'ALREADY FOUND'
        'Bluescreen', 'Blue screen'
        'Kein Bluescreen, kein plötzliches Ausschalten und keine Aussetzer des Grafiktreibers.', 'No blue screen, no sudden shutdown and no graphics driver dropouts.'
        'Das Ereignisprotokoll ließ sich nicht lesen.', 'The event log could not be read.'
        'Kein Bluescreen, kein plötzliches Ausschalten, keine Aussetzer des Grafiktreibers und keine Hardwarefehler.', 'No blue screen, no sudden shutdown, no graphics driver dropouts and no hardware errors.'
        'Ereignisprotokoll von Windows', 'Windows event log'
        'letzte 30 Tage', 'last 30 days'
        'keine Abstürze', 'no crashes'
        'Keine in 30 Tagen', 'None in 30 days'
        'Version, Alter und die Seite des Herstellers', 'Version, age and the maker''s page'
        'Lese das BIOS …', 'Reading the BIOS …'
        'Alter', 'Age'
        'BIOS-Hersteller', 'BIOS maker'
        'Nach neuerem BIOS sehen', 'Look for a newer BIOS'
        'Einspielen nur mit dem Werkzeug des Herstellers', 'Install only with the maker''s tool'
        'PulsRig spielt nie selbst ein BIOS ein. Ein Update lohnt sich bei Abstürzen, für einen neuen Prozessor oder bei Sicherheitslücken. Währenddessen darf der Strom nicht ausfallen.', 'PulsRig never installs a BIOS itself. An update is worth it for crashes, a new processor or security holes. The power must not fail meanwhile.'
        'Älter als drei Jahre: ein Blick auf die Seite des Herstellers lohnt sich', 'Older than three years: worth a look at the maker''s page'
        'Ein BIOS muss nicht immer das neueste sein, solange alles stabil läuft', 'A BIOS does not always need to be the newest as long as everything runs stable'
        'Der Browser ließ sich nicht öffnen', 'The browser could not be opened'
        'weniger als einen Monat', 'less than a month'
        '1 Monat', '1 month'
        '1 Jahr', '1 year'
        'neu', 'new'
        # --- Probezeit für neue Treiber
        'Grafiktreiber', 'graphics driver'
        'Netzwerktreiber', 'network driver'
        'Audiotreiber', 'audio driver'
        'Speichertreiber', 'storage driver'
        'läuft', 'running'
        'bestanden', 'passed'
        'Seit dem neuen Treiber mehr Abstürze', 'More crashes since the new driver'
        'Im Geräte-Manager das Gerät doppelklicken, dann Treiber → Vorheriger Treiber', 'In Device Manager, double-click the device, then Driver → Roll Back Driver'
        'von PulsRig installiert', 'installed by PulsRig'
        'von Windows Update oder von Hand', 'by Windows Update or by hand'
        'sieben Tage ohne Auffälligkeiten', 'seven days without problems'
        'seitdem keine Abstürze', 'no crashes since'
        'seitdem 1 Absturz oder Aussetzer', '1 crash or dropout since'
        'davor keine', 'none before'
        # --- Was hat sich geändert?
        'Was hat sich geändert?', 'What has changed?'
        'Ab heute mitgeschrieben', 'Recorded from today'
        'Unterschiede zu früheren Tagen, die PulsRig mitgeschrieben hat', 'Differences from earlier days that PulsRig recorded'
        'Seit gestern', 'Since yesterday'
        '7 Tage', '7 days'
        '30 Tage', '30 days'
        'Treiberverlauf', 'Driver history'
        'Windows wurde aktualisiert', 'Windows was updated'
        'installiert', 'installed'
        'nicht mehr installiert', 'no longer installed'
        'Neu im Autostart; lässt sich unter Werkzeuge → Autostart ausschalten', 'New in startup; can be switched off under Tools → Startup apps'
        'aus dem Autostart entfernt oder ausgeschaltet', 'removed from startup or switched off'
        'Anderer Energieplan', 'Different power plan'
        'Einzelheiten unter Hardware → Abstürze', 'Details under Hardware → Crashes'
        'PulsRig schreibt ab jetzt mit', 'PulsRig records from now on'
        'Mitgeschrieben wird bei jedem Start von PulsRig', 'Recorded every time PulsRig starts'
        'Windows, Programme, Autostart, wichtige Treiber und Energieplan sind wie damals, und es gab keine Abstürze.', 'Windows, programs, startup apps, important drivers and power plan are as they were, and there were no crashes.'
        'Der Reiter mit dem kürzeren Abstand zeigt sie einzeln.', 'The tab with the shorter span shows them one by one.'
        'Seit einer Woche unverändert', 'Unchanged for a week'
        '1 Änderung', '1 change'
        '1 Änderung in 7 Tagen', '1 change in 7 days'
        # --- Gaming-Check
        'Gaming-Check', 'Gaming check'
        'Gaming-Check starten', 'Start gaming check'
        'Ist der PC richtig eingestellt? Sieben Punkte, die fürs Spielen zählen', 'Is the PC set up right? Seven things that matter for gaming'
        'Neu prüfen', 'Check again'
        'Prüfe die Einstellungen …', 'Checking the settings …'
        'Bildwiederholrate', 'Refresh rate'
        'Anzeige öffnen', 'Open display'
        'Alle Bildschirme laufen mit der höchsten Rate, die sie bei dieser Auflösung können.', 'All displays run at the highest rate they support at this resolution.'
        'Windows nennt die Bildschirmmodi nicht.', 'Windows does not list the display modes.'
        'nicht prüfbar', 'not checkable'
        'Im BIOS „Above 4G Decoding“ und „Re-Size BAR“ einschalten: bringt in neuen Spielen ein paar Prozent.', 'Enable “Above 4G Decoding” and “Re-Size BAR” in the BIOS: gains a few percent in new games.'
        'Lässt sich nur bei NVIDIA-Grafikkarten auslesen.', 'Can only be read on NVIDIA graphics cards.'
        'GPU-Planung', 'GPU scheduling'
        'Die hardwarebeschleunigte GPU-Planung ist an. Sie ist Voraussetzung für Frame Generation (DLSS 3 und neuer).', 'Hardware-accelerated GPU scheduling is on. It is required for frame generation (DLSS 3 and newer).'
        'Unter Grafikeinstellungen einschalten und neu starten. Nötig für Frame Generation (DLSS 3 und neuer).', 'Turn it on under graphics settings and restart. Needed for frame generation (DLSS 3 and newer).'
        'Vorgabe', 'default'
        'Nicht festgelegt: Windows entscheidet selbst. Unter Grafikeinstellungen steht, ob sie an ist.', 'Not set: Windows decides itself. Graphics settings show whether it is on.'
        'Kernisolierung', 'Core isolation'
        'Schützt vor Schadtreibern, kostet in manchen Spielen 5–10 %. Abschalten ist eine Abwägung.', 'Protects against malicious drivers, costs 5–10 % in some games. Switching it off is a trade-off.'
        'Keine Bremse durch die Speicher-Integrität. Dafür fehlt dieser zusätzliche Schutz vor Schadtreibern.', 'No slowdown from memory integrity. In return this extra protection against malicious drivers is missing.'
        'Windows gibt den Zustand auf diesem PC nicht heraus.', 'Windows does not report the state on this PC.'
        'Der Prozessor darf jederzeit voll takten.', 'The CPU may run at full clock at any time.'
        'Bremst Prozessor und Grafik. Der Boost stellt fürs Spielen auf Höchstleistung um.', 'Slows down CPU and graphics. The boost switches to high performance for gaming.'
        'Boost einrichten', 'Set up boost'
        'Für ein Notebook die richtige Wahl; zum Spielen ans Netzteil.', 'The right choice for a laptop; plug in the charger for gaming.'
        'Für Spiele in Ordnung, taktet aber träger hoch. Der Boost stellt beim Spielen um.', 'Fine for games but clocks up more slowly. The boost switches while gaming.'
        'Windows nennt den aktiven Energieplan nicht.', 'Windows does not report the active power plan.'
        'Arbeitsspeicher (XMP)', 'Memory (XMP)'
        'Für welchen Takt die Riegel gebaut sind, verrät Windows bei diesem Modell nicht.', 'Windows does not reveal what speed these modules are built for.'
        'Windows gibt laufenden Spielen Vorrang und hält Updates zurück.', 'Windows gives running games priority and holds back updates.'
        'Einschalten: Windows gibt laufenden Spielen dann Vorrang.', 'Switch it on: Windows then gives running games priority.'
        'PulsRig ändert hier nichts: jede Zeile führt zur Stelle, an der man es einstellt', 'PulsRig changes nothing here: each row leads to the place where you set it'
        '1 zu prüfen', '1 to check'
        'Die Einstellungen von Windows ließen sich nicht öffnen', 'The Windows settings could not be opened'
        # --- Aussehen Nacht Puls: Startseite, Leiste, Werkzeugsuche
        'Nacht Puls', 'Night Pulse'
        'Nachtblau', 'Night Blue'
        'Herzmonitor', 'Heart Monitor'
        'Klassisch', 'Classic'
        'Ton', 'Sound'
        'Kein Ton, falsche Ausgabe', 'No sound, wrong output'
        'Netzwerk', 'Network'
        'Langsam oder weg', 'Slow or down'
        'Bild', 'Display'
        'Auflösung stimmt nicht', 'Wrong resolution'
        'Geräte', 'Devices'
        'Gelbes Warnzeichen', 'Yellow warning sign'
        'Treiber-Sicherung', 'Driver backup'
        'Sichern, zurückholen oder als Offline-Paket', 'Back up, restore or as an offline package'
        'Treiber und Komponenten', 'Drivers and components'
        'System', 'System'
        'Öffnen', 'Open'
        'Sicherungen landen im Zielordner (Optionen → Treiber)', 'Backups go to the target folder (Options → Drivers)'
        'Probelauf ohne Adminrechte', 'Dry run without admin rights'
        'Bildschirm', 'Display'
        'Bildwiederholrate und Testbilder im Vollbild', 'Refresh rate and full-screen test images'
        'Hz prüfen', 'Check Hz'
        'Acht Testbilder', 'Eight test images'
        'Pixelfehler finden', 'Find pixel faults'
        'Bericht & Diagnose', 'Report & diagnostics'
        'Prüfbericht und Fehlersuche in einem Zug', 'Test report and troubleshooting in one go'
        'Alle Prüfergebnisse', 'All test results'
        'Angaben zum PC', 'PC details'
        'Eine ZIP-Datei', 'One ZIP file'
        'Prüfergebnisse und Angaben für die Fehlersuche in einer ZIP-Datei', 'Test results and troubleshooting details in one ZIP file'
        'Als ZIP speichern', 'Save as ZIP'
        'Test öffnen', 'Open test'
        'Bericht und ZIP erstellen', 'Create report and ZIP'
        'Erst warten, bis der Bericht zusammengestellt ist', 'Please wait until the report is ready'
        'ansehen', 'view'
        'Schnellzugriff', 'Quick access'
        'Treiberverlauf, Zielordner, Kurzanleitung und Infos zu PulsRig', 'Driver history, target folder, quick guide and info about PulsRig'
        'Einstellungen, Design und Schnellzugriff · Änderungen gelten sofort', 'Settings, design and quick access · changes apply immediately'
        'Bewegung', 'Motion'
        'Ruhig', 'Calm'
        'Lebendig', 'Lively'
        'Ring, Puls und Übergänge. Aus spart Rechenzeit auf schwächeren PCs.', 'Ring, pulse and transitions. Off saves CPU time on slower PCs.'
        'Optionen', 'Options'
        'Guten Morgen', 'Good morning'
        'Guten Tag', 'Good afternoon'
        'Guten Abend', 'Good evening'
        'Hallo', 'Hello'
        'letzte Minute', 'last minute'
        'Prozessor-Takt', 'Processor clock'
        'Ganzen Verlauf zeigen', 'Show full history'
        'Sobald sich Treiber, Programme, der Autostart oder Windows ändern, steht es hier mit Datum.', 'As soon as drivers, programs, startup apps or Windows change, it shows up here with a date.'
        'von 100 Punkten', 'out of 100 points'
        'Alles gut eingestellt', 'Everything set up well'
        '1 Tipp', '1 tip'
        'Werkzeug suchen', 'Search tools'
        'Kein Werkzeug passt zu dieser Suche.', 'No tool matches this search.'
        # --- Ping-Test
        'Ping-Test', 'Ping test'
        'Wie schnell und stabil die Verbindung ist – zu Hause und ins Internet', 'How fast and stable the connection is – at home and to the internet'
        'Neu messen', 'Measure again'
        'Messe 20 Runden zu Router und Internet (etwa zehn Sekunden) …', 'Measuring 20 rounds to router and internet (about ten seconds) …'
        'EINORDNUNG', 'ASSESSMENT'
        'Keine Antwort aus dem Internet', 'No answer from the internet'
        'Keiner der drei Anbieter hat geantwortet. Entweder ist die Verbindung weg, oder eine Firewall blockiert Ping.', 'None of the three providers answered. Either the connection is down or a firewall blocks ping.'
        'Netzwerk reparieren', 'Repair network'
        'Das Problem liegt zu Hause', 'The problem is at home'
        'Schon bis zum Router schwankt die Verbindung oder verliert Pakete. Typisch für WLAN: näher an den Router, ein anderes Funkband (5 GHz) oder ein Netzwerkkabel helfen meist.', 'Already up to the router the connection fluctuates or loses packets. Typical for Wi-Fi: moving closer to the router, another band (5 GHz) or a network cable usually helps.'
        'Schon bis zum Router schwankt die Verbindung oder verliert Pakete. Kabel, Anschluss und Router prüfen; ein Neustart des Routers hilft oft.', 'Already up to the router the connection fluctuates or loses packets. Check cable, port and router; restarting the router often helps.'
        'Alles im grünen Bereich', 'All good'
        'Zu Hause stabil, der Weg ins Internet nicht', 'Stable at home, not on the way to the internet'
        'Bis zum Router ist alles in Ordnung; die Verzögerung oder die Aussetzer entstehen beim Anbieter oder auf dem Weg dorthin. Zu einer anderen Tageszeit noch einmal messen; bleibt es so, hilft nur der Anbieter.', 'Up to the router everything is fine; the delay or dropouts come from the provider or the route there. Measure again at another time of day; if it stays like this, only the provider can help.'
        'Verbunden über WLAN', 'Connected via Wi-Fi'
        'Verbunden über Kabel', 'Connected via cable'
        'Für Spiele ist ein Netzwerkkabel stabiler: WLAN schwankt durch Wände, Nachbarnetze und andere Geräte.', 'For gaming a network cable is more stable: Wi-Fi fluctuates due to walls, neighboring networks and other devices.'
        'Die stabilste Verbindung für Spiele.', 'The most stable connection for gaming.'
        'MESSUNG (20 RUNDEN JE ZIEL)', 'MEASUREMENT (20 ROUNDS PER TARGET)'
        'Router (zu Hause)', 'Router (home)'
        'keine Antwort', 'no answer'
        'unter 1 ms', 'below 1 ms'
        'SO LIEST MAN DAS', 'HOW TO READ THIS'
        'Ping (Verzögerung)', 'Ping (delay)'
        'Bis 30 ms ist sehr gut, bis 60 ms für die meisten Spiele in Ordnung. Zum Spieleserver kommt je nach Entfernung noch etwas dazu.', 'Up to 30 ms is very good, up to 60 ms fine for most games. Depending on distance, a bit more is added to the game server.'
        'Schwankung und Verlust', 'Jitter and loss'
        'Stärker als ein hoher Ping stören Sprünge und verlorene Pakete: Figuren springen, Treffer zählen nicht. Mehr als 1 % Verlust spürt man.', 'Jumps and lost packets hurt more than a high ping: characters teleport, hits don''t count. More than 1 % loss is noticeable.'
        'Gemessen mit Ping zu Router, Cloudflare, Google und Quad9', 'Measured with ping to router, Cloudflare, Google and Quad9'
        'Verzögerung, Schwankung und Verlust: zeigt, ob das Problem zu Hause (WLAN, Router) oder beim Anbieter liegt', 'Delay, jitter and loss: shows whether the problem is at home (Wi-Fi, router) or with the provider'
        'Messen', 'Measure'
        # --- Monitor-Test
        'Monitor-Test', 'Monitor test'
        'Tote Pixel, Lichthöfe und Schlieren im Vollbild prüfen', 'Check dead pixels, backlight bleed and ghosting in full screen'
        'Test starten', 'Start test'
        'BILDSCHIRME', 'DISPLAYS'
        'Lese die Bildschirme …', 'Reading the displays …'
        'Bildschirm', 'Display'
        'Einstellen', 'Adjust'
        'DIE BILDER DES TESTS', 'THE TEST SCREENS'
        'Schwarz', 'Black'
        'Weiß', 'White'
        'Rot', 'Red'
        'Grün', 'Green'
        'Blau', 'Blue'
        'Grau', 'Gray'
        'Farbverlauf', 'Gradient'
        'Bewegung', 'Motion'
        'Leuchtende Punkte sind hängende Pixel. Helle Flecken an den Rändern sind Lichthöfe – im dunklen Raum am besten zu sehen.', 'Glowing dots are stuck pixels. Bright patches at the edges are backlight bleed – best seen in a dark room.'
        'Dunkle Punkte sind tote Pixel. Gelbliche oder fleckige Bereiche zeigen eine ungleichmäßige Ausleuchtung.', 'Dark dots are dead pixels. Yellowish or blotchy areas show uneven backlighting.'
        'Ein Punkt in einer anderen Farbe ist ein defektes Subpixel.', 'A dot in a different color is a defective subpixel.'
        'Wolkige Flecken oder dunklere Ecken zeigen eine ungleichmäßige Ausleuchtung.', 'Cloudy patches or darker corners show uneven backlighting.'
        'Der Verlauf sollte gleichmäßig sein. Deutliche Stufen oder Streifen deuten auf wenig Farbtiefe oder eine falsche Einstellung.', 'The gradient should be smooth. Clear steps or bands point to low color depth or a wrong setting.'
        'Zieht der Block Schlieren oder einen Schatten hinter sich her? Ruckelt er, läuft der Bildschirm womöglich nicht mit seiner vollen Bildwiederholrate.', 'Does the block leave smears or a shadow behind it? If it stutters, the display may not run at its full refresh rate.'
        'Weiter mit Leertaste oder Klick, zurück mit Pfeil links, Esc beendet. Getestet wird der Bildschirm, auf dem PulsRig gerade steht.', 'Next with space or click, back with left arrow, Esc ends. The display PulsRig is on right now is tested.'
        'Leertaste oder Klick: weiter · Pfeil links: zurück · H: Hinweis · Esc: beenden', 'Space or click: next · Left arrow: back · H: hint · Esc: end'
        'Testversion', 'Beta'
        'Weiter mit Leertaste oder Klick, zurück mit Pfeil links, Esc beendet', 'Next with space or click, back with left arrow, Esc ends'
        'Getestet wird der Bildschirm, auf dem PulsRig steht', 'The display PulsRig is on gets tested'
        'Für einen anderen Bildschirm das Fenster von PulsRig vorher dorthin schieben.', 'For another display, move the PulsRig window there first.'
        'Fehler bitte mit dem Diagnose-Paket melden', 'Please report bugs with the diagnostics package'
        'Pixelfehler, Lichthof oder Schlieren?', 'Pixel defects, backlight bleed or ghosting?'
        'Der Monitor-Test zeigt Farbflächen und ein Bewegungsbild im Vollbild', 'The monitor test shows color screens and a motion image in full screen'
        # --- Akku-Bericht
        'Akku', 'Battery'
        'Wie viel der Akku noch fasst und wie lange er hält', 'How much the battery still holds and how long it lasts'
        'Ausführlicher Bericht von Windows', 'Detailed report from Windows'
        'Erstelle den Bericht …', 'Creating the report …'
        'Der Bericht liegt jetzt auch im Ordner von PulsRig', 'The report is now also in the PulsRig folder'
        'Windows hat keinen Bericht erstellt', 'Windows did not create a report'
        'Lese den Akku …', 'Reading the battery …'
        'Kein Akku gefunden', 'No battery found'
        'Dieser PC läuft am Netz - ein Akku-Bericht gibt es nur bei Notebooks und Tablets.', 'This PC runs on mains power - a battery report only exists on laptops and tablets.'
        'Windows gibt die Kapazität nicht heraus', 'Windows does not report the capacity'
        'Der Akku ist da, aber Windows meldet nicht, wie viel er noch fasst. Der ausführliche Bericht von Windows zeigt, was es weiß.', 'The battery is there, but Windows does not report how much it still holds. The detailed Windows report shows what it knows.'
        'Ein Zyklus ist einmal ganz leer und wieder voll, auch in Teilen. Übliche Akkus sind für 300 bis 1.000 Zyklen gebaut.', 'One cycle is fully empty and full again, also in parts. Typical batteries are built for 300 to 1,000 cycles.'
        'Das Netzteil ist angeschlossen.', 'The power adapter is connected.'
        'Das Notebook läuft gerade mit Akku.', 'The laptop is running on battery right now.'
        'Schätzung von Windows bei voller Ladung und üblicher Nutzung.', 'Windows estimate at full charge and typical use.'
        'VERLAUF DER KAPAZITÄT', 'CAPACITY HISTORY'
        'AKKU SCHONEN', 'BATTERY CARE'
        'Nicht dauernd auf 100 %', 'Not always at 100 %'
        'Viele Hersteller-Programme (Lenovo Vantage, MyASUS, Dell Power Manager, Acer Care Center) können das Laden bei 80 % stoppen. Das verlängert die Lebensdauer deutlich.', 'Many manufacturer apps (Lenovo Vantage, MyASUS, Dell Power Manager, Acer Care Center) can stop charging at 80 %. That extends the lifespan noticeably.'
        'Hitze meiden', 'Avoid heat'
        'Beim Spielen auf dem Schoß oder auf der Bettdecke wird es unter dem Notebook heiß; Wärme altert den Akku am stärksten.', 'Gaming on your lap or on a blanket makes it hot under the laptop; heat ages the battery the most.'
        'Werte aus der Akku-Schnittstelle von Windows', 'Values from the Windows battery interface'
        'Werte aus dem Akku-Bericht von Windows', 'Values from the Windows battery report'
        'Akku hält nicht mehr lange', 'Battery doesn''t last long anymore'
        'Wie viel der Akku noch fasst, wie oft er geladen wurde und wie lange er laut Windows hält', 'How much the battery still holds, how often it was charged and how long Windows says it lasts'
        'Testversion: Fehler mit dem Diagnose-Paket melden', 'Beta: report bugs with the diagnostics package'
        # --- Was ist los? (Problem zuerst)
        'Was ist los?', 'What''s wrong?'
        'Problem wählen: PulsRig zeigt, was es schon weiß, und was als Nächstes zu prüfen ist', 'Pick the problem: PulsRig shows what it already knows and what to check next'
        'Spiele ruckeln', 'Games stutter'
        'Stürzt ab', 'Crashes'
        'Ist langsam', 'Is slow'
        'Kein Ton', 'No sound'
        'Internet', 'Internet'
        'Sonstiges', 'Other'
        'DIE HÄUFIGSTEN URSACHEN', 'THE MOST COMMON CAUSES'
        'DEINE SPIELE', 'YOUR GAMES'
        'DER REIHE NACH', 'STEP BY STEP'
        'WEITERE PROBLEME', 'MORE PROBLEMS'
        'noch nicht geprüft', 'not checked yet'
        'unauffällig', 'unremarkable'
        'Bildwiederholrate, Energieplan, voller Takt des Speichers: sieben Einstellungen, die fürs Spielen zählen', 'Refresh rate, power plan, full memory speed: seven settings that matter for gaming'
        'Grafiktreiber aktuell?', 'Graphics driver up to date?'
        'Ein Scan prüft NVIDIA, AMD und Windows Update auf neuere Treiber', 'A scan checks NVIDIA, AMD and Windows Update for newer drivers'
        'Scan starten', 'Start scan'
        'Wird es zu heiß?', 'Running too hot?'
        'Der Stabilitätstest lastet Prozessor und Grafikkarte voll aus und misst, ob der Takt einbricht', 'The stability test puts full load on CPU and graphics card and measures whether the clock drops'
        'Testen', 'Test'
        'Programme im Hintergrund', 'Programs in the background'
        'Der Boost schaltet vor dem Spielen Dienste und speicherhungrige Programme ab', 'The boost switches off services and memory-hungry programs before you play'
        'Zum Boost', 'Go to boost'
        'Was startet mit Windows?', 'What starts with Windows?'
        'Jedes Programm im Autostart kostet Speicher und Rechenzeit, auch beim Spielen', 'Every startup program costs memory and CPU time, also while gaming'
        'Suche die Spiele …', 'Looking for games …'
        'Windows kennt noch keine Spiele', 'Windows doesn''t know any games yet'
        'Sobald ein Spiel einmal gelaufen ist, steht es hier mit dem Laufwerk, auf dem es liegt.', 'Once a game has run, it shows up here with the drive it is on.'
        'Festplatte', 'Hard disk'
        'Abstürze verstehen', 'Understand crashes'
        'Bluescreens, plötzliches Ausgehen und Grafik-Aussetzer der letzten 30 Tage, jeweils mit Erklärung', 'Blue screens, sudden power-offs and graphics dropouts of the last 30 days, each explained'
        'Neuer Treiber schuld?', 'New driver to blame?'
        'Seit einem neuen Treiber mehr Abstürze? PulsRig vergleicht die Tage davor und danach', 'More crashes since a new driver? PulsRig compares the days before and after'
        'Arbeitsspeicher testen', 'Test memory'
        'Fehlerhafter Speicher ist eine häufige Ursache für Bluescreens', 'Faulty memory is a common cause of blue screens'
        'Unter Last stabil?', 'Stable under load?'
        'Der Stabilitätstest zeigt, ob der PC bei voller Last abstürzt oder sich verrechnet', 'The stability test shows whether the PC crashes or miscalculates under full load'
        'Laufwerke in Ordnung?', 'Drives OK?'
        'Störungen und Zustand der Laufwerke aus dem Protokoll von Windows', 'Faults and health of the drives from the Windows log'
        'Viele Programme im Autostart machen den Start und den Alltag langsam', 'Many startup programs make startup and everyday use slow'
        'Ist das Laufwerk voll?', 'Is the drive full?'
        'Unter 10 Prozent freiem Platz wird Windows spürbar langsamer', 'Below 10 percent free space Windows gets noticeably slower'
        'Platz schaffen', 'Free up space'
        'Ein Laufwerk mit Störungen oder nachlassendem Tempo bremst alles aus', 'A drive with faults or dropping speed slows everything down'
        'Arbeitsspeicher voll?', 'Memory full?'
        'Die Boost-Seite zeigt, wie viel belegt ist und welche Programme am meisten brauchen', 'The boost page shows how much is used and which programs need the most'
        'Seit wann ist es langsam? Neue Programme, Treiber und Windows-Updates der letzten Tage', 'Since when is it slow? New programs, drivers and Windows updates of the last days'
        'Prüft Dienste, Stummschaltung und Ausgabegerät und repariert in Stufen', 'Checks services, mute and output device and repairs step by step'
        'Audiotreiber aktuell?', 'Audio driver up to date?'
        'Ein Scan findet neuere Treiber für Soundkarte und Headset', 'A scan finds newer drivers for sound card and headset'
        'Gerät mit Fehler?', 'Device with an error?'
        'Erkennt Geräte, die Windows mit Fehler meldet, und richtet sie neu ein', 'Finds devices Windows reports with an error and sets them up again'
        'Testet die Verbindung Schritt für Schritt und repariert in Stufen', 'Tests the connection step by step and repairs in stages'
        'Netzwerktreiber aktuell?', 'Network driver up to date?'
        'Ein Scan findet neuere Treiber für WLAN und Netzwerkkarte', 'A scan finds newer drivers for Wi-Fi and network card'
        'WLAN bricht im Standby ab?', 'Wi-Fi drops in standby?'
        'Der Standby-Detektiv zeigt, welche Geräte den PC wecken dürfen', 'The sleep detective shows which devices may wake the PC'
        'Bild unscharf oder falsche Auflösung', 'Blurry picture or wrong resolution'
        'Prüft Grafiktreiber und empfohlene Auflösung', 'Checks graphics driver and recommended resolution'
        'Ein Gerät geht nicht', 'A device doesn''t work'
        'Erkennt fehlerhafte Geräte und richtet sie neu ein', 'Finds faulty devices and sets them up again'
        'PC wacht von selbst auf', 'PC wakes up by itself'
        'Der Standby-Detektiv zeigt, was ihn weckt oder wach hält', 'The sleep detective shows what wakes it or keeps it awake'
        'BIOS veraltet?', 'BIOS outdated?'
        'Version, Alter und die Seite des Herstellers', 'Version, age and the manufacturer''s page'
        'Hilfe holen', 'Get help'
        'Ein Diagnose-Paket fasst alles für die Fehlersuche zusammen und geht per E-Mail an pulsrig.hilfe@gmail.com', 'A diagnostics package bundles everything for troubleshooting and goes by email to pulsrig.hilfe@gmail.com'
        'Erstellen', 'Create'
        'Am besten von oben nach unten: die ersten Punkte finden die häufigsten Ursachen', 'Best from top to bottom: the first items find the most common causes'
        # --- Standby-Detektiv
        'Standby-Detektiv', 'Sleep detective'
        'Warum der PC aufwacht oder wach bleibt', 'Why the PC wakes up or stays awake'
        'Warum der PC aufwacht und was ihn wach hält', 'Why the PC wakes up and what keeps it awake'
        'Aufwachen', 'Waking up'
        'Wach gehalten', 'Kept awake'
        'Geplante Aufgabe weckt den PC', 'A scheduled task wakes the PC'
        'Aufweck-Timer lassen sich in den Energieoptionen abschalten', 'Wake timers can be switched off in the power options'
        'Energieoptionen', 'Power options'
        'Maus oder Tastatur weckt den PC', 'Mouse or keyboard wakes the PC'
        'Schon ein Ruckeln am Tisch reicht. Im Geräte-Manager lässt sich das je Gerät abschalten', 'Even a bump of the desk is enough. Device Manager can switch this off per device'
        'Geräte-Manager', 'Device Manager'
        'Netzwerkkarte weckt den PC', 'Network adapter wakes the PC'
        'Wake-on-LAN oder Netzwerkverkehr. Im Geräte-Manager unter Energieverwaltung abschaltbar', 'Wake-on-LAN or network traffic. Can be switched off in Device Manager under Power Management'
        'Netzschalter', 'Power button'
        'Der PC wurde von Hand aufgeweckt', 'The PC was woken by hand'
        'Ohne erkennbaren Grund aufgewacht', 'Woke up for no visible reason'
        'Windows nennt keine Quelle; oft ein USB-Gerät oder das BIOS', 'Windows names no source; often a USB device or the BIOS'
        'Im Geräte-Manager unter Energieverwaltung abschaltbar', 'Can be switched off in Device Manager under Power Management'
        'Kein Aufwachen aus dem Standby in 14 Tagen', 'No wake-ups from sleep in 14 days'
        'Der PC geht allerdings gar nicht von selbst in den Standby; siehe „Wach gehalten“.', 'However, the PC never goes to sleep on its own; see “Kept awake”.'
        'Der PC hat geschlafen, bis ihn jemand geweckt hat.', 'The PC slept until someone woke it.'
        'Kein Gerät darf den PC wecken', 'No device may wake the PC'
        '1 Gerät darf den PC wecken', '1 device may wake the PC'
        'Nur Netzschalter und geplante Aufgaben können ihn aufwecken.', 'Only the power button and scheduled tasks can wake it.'
        'Aufweck-Timer sind aus', 'Wake timers are off'
        'Geplante Aufgaben können den PC nicht wecken.', 'Scheduled tasks cannot wake the PC.'
        'Aufweck-Timer sind erlaubt', 'Wake timers are allowed'
        'Geplante Aufgaben wie Windows Update dürfen den PC wecken.', 'Scheduled tasks such as Windows Update may wake the PC.'
        'Nur wichtige Aufweck-Timer', 'Important wake timers only'
        'Nur wichtige Aufgaben von Windows dürfen den PC wecken, etwa ein Neustart nach Updates.', 'Only important Windows tasks may wake the PC, such as a restart after updates.'
        'Standby ist ausgeschaltet', 'Sleep is switched off'
        'Im Energieplan steht „Nie“: der PC geht nicht von selbst in den Standby. Das ist der häufigste Grund.', 'The power plan says “Never”: the PC does not go to sleep on its own. That is the most common reason.'
        'Nie', 'Never'
        'So steht es im Energieplan. Geht er trotzdem nicht schlafen, hält ihn etwas wach (siehe unten).', 'That is what the power plan says. If it still does not sleep, something keeps it awake (see below).'
        'Was den PC gerade wach hält, verrät Windows nur mit Adminrechten', 'Windows only reveals what keeps the PC awake with admin rights'
        'PulsRig als Admin starten und hier neu einlesen.', 'Start PulsRig as admin and refresh here.'
        'Gerade hält nichts den PC wach', 'Nothing is keeping the PC awake right now'
        'Kein Programm, Dienst oder Treiber verhindert den Standby.', 'No program, service or driver prevents sleep.'
        'Programm', 'program'
        'Dienst', 'service'
        'Standby aus', 'sleep off'
        'letzte 14 Tage', 'last 14 days'
        'Energieplan und Anfragen von Programmen, Diensten und Treibern', 'Power plan and requests from programs, services and drivers'
        'Das ließ sich nicht öffnen', 'That could not be opened'
        'Im Geräte-Manager: Gerät doppelklicken → Energieverwaltung → „Gerät kann den Computer aus dem Standby aktivieren“', 'In Device Manager: double-click the device → Power Management → “Allow this device to wake the computer”'
        'Energieoptionen: Energiesparen → Zeitgeber zur Aktivierung zulassen', 'Power options: Sleep → Allow wake timers'
        'Verlauf', 'History'
        'Ansehen', 'View'
        'Ein Laufwerk ist auffällig', 'A drive shows problems'
        'Ausblenden, bis sich etwas ändert', 'Hide until something changes'
        'mehr Störungen', 'more faults'
        'langsamer', 'slower'
        'ab heute', 'from today'
        'unverändert', 'unchanged'
        'mitgeschrieben ab heute', 'recorded from today'
        'Temperatur nur mit Adminrechten', 'temperature only with admin rights'
        'Bei jedem Start schreibt PulsRig einen Eintrag pro Tag mit, dazu jede Tempomessung', 'PulsRig records one entry per day at each start, plus every speed test'
        'Scan startet gleich …', 'Scan starts in a moment …'
        'Wichtige Daten sichern und das Laufwerk bald ersetzen.', 'Back up important data and replace the drive soon.'
        'heute', 'today'
        'keine', 'none'
        'in Ordnung', 'OK'
        'auffällig', 'attention'
        'offen', 'open'
        'aktuell', 'up to date'
        'optional', 'optional'
        'installiert', 'installed'
        'vorhanden', 'present'
        'vollständig', 'complete'
        'bereit', 'ready'
        'Bereit', 'Ready'
        'signiert', 'signed'
        'unbedenklich', 'no concern'
        'Ergebnis', 'Result'
        'Ergebnisse', 'Results'
        'Übersicht', 'Overview'
        'Einzelheiten', 'Details'
        'Weitere', 'More'
        'Weitere Werte', 'More values'
        'Name', 'Name'
        'Art', 'Type'
        'Datum', 'Date'
        'ohne Datum', 'no date'
        'vom Hersteller nicht angegeben', 'not given by the vendor'
        'Größe', 'Size'
        'Version', 'Version'
        'Hersteller', 'Vendor'
        'Modell', 'Model'
        'Seriennummer', 'Serial number'
        'Zustand', 'Health'
        'Betriebszustand', 'Operational status'
        'Anschluss', 'Connection'
        'Ordner', 'Folders'
        'Rechte', 'Rights'
        'Quellen', 'Sources'
        'Tipp', 'Tip'
        'Wozu', 'What for'

        # --- Startseite und Scan
        'SCAN', 'SCAN'
        'Treiber prüfen', 'Check drivers'
        'Bereit für einen Scan', 'Ready to scan'
        'Scan läuft …', 'Scanning …'
        'Ein Klick auf SCAN sucht nach neueren Treibern.', 'Click SCAN to look for newer drivers.'
        'Zum Abbrechen noch einmal auf den Knopf klicken.', 'Click the button again to cancel.'
        'Klicken stoppt', 'Click to stop'
        'In dieser Sitzung wurde noch nicht gescannt', 'No scan in this session yet'
        'Gerätetreiber', 'Device drivers'
        'Spielkomponenten', 'Game components'
        'Treiberverlauf', 'Driver history'
        'Noch nicht geprüft', 'Not checked yet'
        'Frühere Aktualisierungen', 'Earlier updates'
        'Alles aktuell', 'All up to date'
        'Nicht geprüft', 'Not checked'
        'Vollständig', 'Complete'
        'Lese Geräte und installierte Treiber …', 'Reading devices and installed drivers …'
        'Frage Windows Update nach neueren Treibern …', 'Asking Windows Update for newer drivers …'
        'Frage NVIDIA nach dem neuesten Grafiktreiber …', 'Asking NVIDIA for the latest graphics driver …'
        'Frage NVIDIA und AMD nach den neuesten Treibern …', 'Asking NVIDIA and AMD for the latest drivers …'
        'Durchsuche den Microsoft-Katalog …', 'Searching the Microsoft catalog …'
        'Prüfe Spielkomponenten …', 'Checking game components …'
        'Prüfe die Komponenten …', 'Checking the components …'
        'Treiber. Boost. Werkzeuge.', 'Drivers. Boost. Tools.'
        'Treiber.', 'Drivers.'
        'Boost.', 'Boost.'
        'Werkzeuge.', 'Tools.'

        # --- Ergebnisse
        'In der Liste suchen', 'Search the list'
        'Ausgewählte aktualisieren', 'Update selected'
        'Nichts ausgewählt', 'Nothing selected'
        'Jetzt aktualisieren', 'Update now'
        'Treiber aktualisieren', 'Update drivers'
        'Windows Update war nicht erreichbar', 'Windows Update could not be reached'
        'Ein neuerer Treiber gefunden', 'One newer driver found'
        'Neuer Chipsatz-Treiber bei AMD', 'New chipset driver at AMD'
        'Ein Gerät meldet einen Fehler', 'One device reports an error'
        'Alle Treiber sind aktuell', 'All drivers are up to date'
        'Geräte mit Fehlern', 'Devices with errors'
        'Hinweise aus dem Microsoft-Katalog (werden nicht automatisch geladen)', 'Notes from the Microsoft catalog (not downloaded automatically)'
        'Hinweise der Hersteller und aus dem Microsoft-Katalog (werden nicht automatisch geladen)', 'Notes from vendors and the Microsoft catalog (not downloaded automatically)'
        'direkt von NVIDIA', 'directly from NVIDIA'
        'direkt bei AMD geprüft', 'checked directly at AMD'
        'Windows Update', 'Windows Update'
        'Firmware', 'Firmware'
        'Systemfirmware', 'system firmware'
        'Ursache', 'Cause'
        'Hinweis', 'Note'
        'Hinweis im Katalog', 'Note in catalog'
        'Treiber erneuern', 'Renew driver'
        'Der Chipsatz-Treiber fehlt', 'The chipset driver is missing'
        'Treiber im Microsoft-Katalog gefunden', 'Driver found in the Microsoft catalog'
        'Treiber suchen', 'Find driver'
        'Im Katalog ansehen', 'View in catalog'
        'Im Microsoft-Katalog suchen', 'Search the Microsoft catalog'
        'Einzelheiten anzeigen', 'Show details'
        'Diesen Treiber sichern', 'Back up this driver'
        'Ignorieren', 'Ignore'
        'Ignoriert', 'Ignored'
        'enthält keinen Treibercode', 'contains no driver code'
        'nicht geprüft', 'not checked'
        'Katalog', 'Catalog'
        'Audio', 'Audio'
        'Netzwerk', 'Network'
        'Display', 'Display'
        'Chipsatz-Treiber', 'Chipset driver'
        'Intel: Chipsatz, Grafik und WLAN', 'Intel: chipset, graphics and Wi-Fi'
        'Das prüft Intels eigener Assistent, nicht PulsRig', 'Checked by Intel''s own assistant, not by PulsRig'
        'Bei Intel prüfen', 'Check at Intel'
        'Geräteklasse', 'Device class'
        'Hardware-ID', 'Hardware ID'
        'Treiberpaket', 'Driver package'
        'Treiberpaket im Treiberspeicher von Windows', 'Driver package in the Windows driver store'
        'Version des installierten Treibers', 'Version of the installed driver'
        'Signiert von', 'Signed by'
        'Geräte mit diesem Treiber', 'Devices using this driver'
        'Treiber von', 'Driver by'
        'GERÄT', 'DEVICE'
        'Gerät', 'Device'
        'TREIBER', 'DRIVER'
        'Treiber', 'Drivers'
        'Geräte', 'Devices'
        'Am installierten Treiber ändert sich nichts.', 'The installed driver is not changed.'
        'Das Treiberpaket wird in einen eigenen Ordner kopiert.', 'The driver package is copied to its own folder.'
        'Punkt und Sicherung', 'Restore point and backup'
        'danach evtl. Neustart', 'restart may follow'
        'Der NVIDIA-Installer öffnet sich als eigenes Fenster.', 'The NVIDIA installer opens in its own window.'
        'Ohne Adminrechte läuft das als Probelauf: Es wird nichts geladen und nichts installiert.', 'Without admin rights this is a dry run: nothing is downloaded or installed.'

        # --- Boost
        'Schafft vor dem Spielen Platz: Energieplan, entbehrliche Dienste und speicherhungrige Programme.', 'Frees resources before gaming: power plan, dispensable services and memory-hungry programs.'
        'Spiel-Beschleunigung', 'Game boost'
        'Derzeit ausgeschaltet', 'Currently off'
        'Derzeit ausgeschaltet. Das fasst der Boost an:', 'Currently off. The boost will touch:'
        'Das fasst der Boost beim Einschalten an:', 'When switched on, the boost touches:'
        'Eingeschaltet', 'Switched on'
        'Einrichten', 'Set up'
        'Einschalten', 'Switch on'
        'Ausschalten', 'Switch off'
        'Arbeitsspeicher', 'Memory'
        'BELEGT', 'USED'
        'FREI', 'FREE'
        'belegt', 'used'
        'GRÖSSTE VERBRAUCHER', 'LARGEST CONSUMERS'
        'Dienste nach Vorgabe', 'Default services'
        'Energieplan', 'Power plan'
        'Spielmodus', 'Game mode'
        'Zwischenablage', 'Clipboard'
        'Energieplan umgestellt', 'Power plan changed'
        'Boost einrichten', 'Set up boost'
        'Auswählen, was die Spiel-Beschleunigung schließt, anhält und umstellt', 'Choose what the game boost closes, stops and changes'
        'Programme', 'Programs'
        'Dienste', 'Services'
        'Laufende Programme, größte zuerst', 'Running programs, largest first'
        'LAUFENDE PROGRAMME, GRÖSSTE ZUERST', 'RUNNING PROGRAMS, LARGEST FIRST'
        'ENTBEHRLICHE WINDOWS-DIENSTE, DIE GERADE LAUFEN', 'DISPENSABLE WINDOWS SERVICES CURRENTLY RUNNING'
        'DIENSTE ANDERER HERSTELLER', 'SERVICES FROM OTHER VENDORS'
        'VORGESCHLAGEN ODER GEMERKT', 'SUGGESTED OR REMEMBERED'
        'Empfohlene Auswahl', 'Recommended selection'
        'Nur speichern', 'Save only'
        'Boost starten', 'Start boost'
        'Lese Programme und Dienste …', 'Reading programs and services …'
        'Energieplan „Höchstleistung“', 'Power plan “Ultimate performance”'
        'Stellt den Energieplan um und nach dem Spielen wieder zurück', 'Switches the power plan and restores it after gaming'
        'Spielmodus von Windows', 'Windows game mode'
        'Schaltet den Spielmodus ein, falls er ausgeschaltet ist', 'Turns game mode on if it is off'
        'Zwischenablage leeren', 'Clear clipboard'
        'Gibt den Speicher frei, den kopierte Inhalte belegen', 'Frees the memory held by copied content'
        'Dienste anhalten', 'Stop services'
        'Energieplan, Spielmodus', 'Power plan, game mode'
        'Energieplan, Dienste und speicherhungrige Programme', 'Power plan, services and memory-hungry programs'
        'DEINE ENTSCHEIDUNG', 'YOUR DECISION'
        'Welche schließen? Nummern mit Komma oder Eingabetaste für keines', 'Which ones to close? Numbers separated by commas, or Enter for none'

        # --- Werkzeuge
        'Jedes Werkzeug prüft zuerst nur und fragt nach, bevor es etwas verändert.', 'Every tool only checks first and asks before it changes anything.'
        'Schnelle Reparaturen', 'Quick repairs'
        'System und Spiele', 'System and games'
        'Tonstörung beheben', 'Fix sound problems'
        'Audiodienste, Stummschaltung und Wiedergabegeräte prüfen', 'Check audio services, mute state and playback devices'
        'Audiodienste, Stummschaltung und Wiedergabegeräte prüfen.', 'Check audio services, mute state and playback devices.'
        'Netzwerkfehler beheben', 'Fix network problems'
        'Verbindung testen und in Stufen reparieren', 'Test the connection and repair it step by step'
        'Bildauflösung beheben', 'Fix screen resolution'
        'Grafiktreiber und empfohlene Auflösung prüfen', 'Check graphics driver and recommended resolution'
        'Gerätefehler beheben', 'Fix device errors'
        'Fehlerhafte Geräte erkennen und neu einrichten', 'Find faulty devices and set them up again'
        'Gerätedaten bereinigen', 'Clean up device data'
        'Einträge nicht mehr angeschlossener Hardware entfernen', 'Remove entries of hardware that is no longer connected'
        'Inkompatible Treiber', 'Incompatible drivers'
        'Treiber finden, die die Kernisolierung blockieren', 'Find drivers that block core isolation'
        'Treiber sichern', 'Back up drivers'
        'Alle Treiber von Drittherstellern exportieren', 'Export all third-party drivers'
        'Treiber wiederherstellen', 'Restore drivers'
        'Eine Sicherung wieder einspielen', 'Restore a backup'
        'Offline-Paket', 'Offline package'
        'Treiberpaket für eine Neuinstallation ohne Internet', 'Driver package for a reinstall without internet'
        'Systeminformationen', 'System information'
        'Hardware und Windows im Überblick', 'Hardware and Windows at a glance'
        'Was Windows Update eingespielt hat und wann', 'What Windows Update installed, and when'
        'Visual C++, DirectX und XNA prüfen und nachinstallieren', 'Check and install Visual C++, DirectX and XNA'
        'liest nur den Zustand', 'reads the state only'
        'was zu tun wäre', 'what would be done'
        'nur mit Adminrechten', 'admin rights only'
        'Ohne Adminrechte läuft das Werkzeug als Probelauf: Es prüft alles und zeigt, was es tun würde.', 'Without admin rights the tool runs as a dry run: it checks everything and shows what it would do.'
        'Werkzeug', 'Tool'
        'Treiberpakete', 'Driver packages'
        'Was Windows Update eingespielt hat und wann Treiberpakete ins System kamen', 'What Windows Update installed and when driver packages entered the system'
        'Lese den Verlauf …', 'Reading the history …'
        'Aus dem Verlauf von Windows Update, neueste zuerst', 'From the Windows Update history, newest first'
        'Spielkomponenten installieren', 'Install game components'
        'Laufzeitbibliotheken, die Spiele voraussetzen', 'Runtime libraries that games require'
        'Komponenten', 'Components'
        'Einzelne Dateien', 'Individual files'
        'Vorhandene ausblenden', 'Hide present ones'
        'Ausgewählte installieren', 'Install selected'
        'Keine Komponente fehlt', 'No component is missing'
        'Alle geprüften Einträge sind vorhanden', 'All checked entries are present'
        'Hier fehlt nichts', 'Nothing is missing here'
        'Nur nötig, wenn ein Spiel danach fragt.', 'Only needed if a game asks for it.'
        'DirectX-Zusatzbibliotheken (9 bis 11)', 'DirectX add-on libraries (9 to 11)'
        'DIRECTX-ZUSATZBIBLIOTHEKEN (9 BIS 11)', 'DIRECTX ADD-ON LIBRARIES (9 TO 11)'
        '• DirectX-Laufzeit', '• DirectX runtime'
        'Hardware und Windows-Version', 'Hardware and Windows version'
        'Lese die Hardware aus …', 'Reading the hardware …'
        'Als Text speichern', 'Save as text'
        'Windows', 'Windows'
        'Prozessor', 'Processor'
        'Speicher', 'Memory'
        'Grafik', 'Graphics'
        'Grafikkarte', 'Graphics card'
        'Bildschirm', 'Display'
        'Datenträger', 'Storage'
        'Mainboard', 'Mainboard'
        'BIOS', 'BIOS'
        'BIOS-Version', 'BIOS version'
        'BIOS-Datum', 'BIOS date'
        'Sockel', 'Socket'
        'Kerne und Threads', 'Cores and threads'
        'Zwischenspeicher', 'Cache'
        'Takt', 'Clock speed'
        'Tastatur', 'Keyboard'
        'Maus', 'Mouse'
        'Laufwerksbuchstaben', 'Drive letters'

        # --- Einstellungen
        'Änderungen gelten sofort', 'Changes apply immediately'
        'Allgemein', 'General'
        'Design', 'Design'
        'Standard wiederherstellen', 'Restore defaults'
        'Animationen', 'Animations'
        'Übergänge, Schweben und Einblenden. Ausschalten spart Rechenzeit auf schwächeren PCs.', 'Transitions, hover effects and fade-ins. Turning them off saves processing time on slower PCs.'
        'Fensterposition merken', 'Remember window position'
        'Das Fenster öffnet sich beim nächsten Start dort, wo es zuletzt stand.', 'The window reopens where it was last time.'
        'Nach neuerer Fassung von PulsRig sehen', 'Check for a newer PulsRig release'
        'Fragt beim Start einmal bei GitHub nach. Geladen und installiert wird nichts von allein.', 'Asks GitHub once at startup. Nothing is downloaded or installed on its own.'
        'Deckkraft des Fensters', 'Window opacity'
        'Unter 100 % scheint durch, was hinter dem Fenster liegt.', 'Below 100 %, whatever is behind the window shows through.'
        'Sprache', 'Language'
        'Deutsch oder Englisch. Ein Wechsel startet das Fenster kurz neu.', 'German or English. Switching restarts the window briefly.'
        'Skin', 'Skin'
        'Komplettes Aussehen: Formen, Schrift, Karten und Bewegungen. Ein Wechsel startet das Fenster kurz neu.', 'The complete look: shapes, font, cards and motion. Switching restarts the window briefly.'
        'Farbdesign', 'Color theme'
        'Färbt das ganze Programm um, der Ring um SCAN bekommt die Gegenfarbe. Die Leiste stellt stufenlos einen eigenen Farbton ein.', 'Recolors the whole program; the ring around SCAN gets the contrasting color. The bar sets a custom hue.'
        'Ring-Animation um den SCAN-Knopf', 'Ring animation around the SCAN button'
        'Standard', 'Standard'
        'Cyberpunk', 'Cyberpunk'
        'Minimal', 'Minimal'
        'Modern', 'Modern'
        'Designer', 'Designer'
        'Animiert', 'Animated'
        'Retro-Terminal', 'Retro terminal'
        'Glas', 'Glass'
        'Gaming', 'Gaming'
        'Pastell', 'Pastel'
        'Kontrast', 'Contrast'
        'Graphit', 'Graphite'
        'Mitternacht', 'Midnight'
        'Neon-Nacht', 'Neon night'
        'Smaragd', 'Emerald'
        'Tiefsee', 'Deep sea'
        'Aurora', 'Aurora'
        'Klassik', 'Classic'
        'Welle', 'Wave'
        'RGB', 'RGB'
        'Komet', 'Comet'
        'Technik', 'Tech'
        'Sechseck', 'Hexagon'
        'Orbit', 'Orbit'
        'Neon', 'Neon'
        'Pac-Man', 'Pac-Man'
        'Beim Start automatisch scannen', 'Scan automatically at startup'
        'Der Scan beginnt, sobald das Fenster offen ist.', 'The scan starts as soon as the window is open.'
        'Hersteller direkt fragen', 'Ask vendors directly'
        'NVIDIA nach dem Grafiktreiber, AMD nach dem Chipsatz-Treiber. Dort erscheinen neue Versionen früher als bei Windows Update.', 'NVIDIA for the graphics driver, AMD for the chipset driver. New versions appear there earlier than on Windows Update.'
        'Microsoft Update-Katalog durchsuchen', 'Search the Microsoft Update catalog'
        'Liefert Hinweise auf neuere Treiber, die Windows Update nicht anbietet. Dieser Teil des Scans dauert am längsten.', 'Gives notes on newer drivers that Windows Update does not offer. This part of the scan takes longest.'
        'Firmware-Updates anzeigen', 'Show firmware updates'
        'Firmware bleibt in der Liste abgewählt, bis du sie ausdrücklich ankreuzt.', 'Firmware stays unselected in the list until you tick it explicitly.'
        'Aktuelle Treiber auflisten', 'List up-to-date drivers'
        'Zeigt unter den Ergebnissen auch alle Treiber, zu denen nichts Neueres gefunden wurde.', 'Also lists all drivers for which nothing newer was found.'
        'Wiederherstellungspunkt vor der Installation', 'Restore point before installing'
        'Windows kann damit zum Stand vor der Aktualisierung zurückkehren.', 'Lets Windows return to the state before the update.'
        'Ersetzte Treiber vorher sichern', 'Back up replaced drivers first'
        'Die bisherigen Treiberpakete landen im Zielordner und lassen sich über „Treiber wiederherstellen“ zurückspielen.', 'The previous driver packages go to the target folder and can be restored with “Restore drivers”.'
        'Zielordner', 'Target folder'
        'Für Downloads, Sicherungen und Berichte:', 'For downloads, backups and reports:'
        'Öffnen', 'Open'
        'Ändern …', 'Change …'

        # --- Menü, Hilfe, Über
        'Verlauf, Ordner, Design und Hilfe', 'History, folder, design and help'
        'SCHNELLZUGRIFF', 'QUICK ACCESS'
        'Zielordner öffnen', 'Open target folder'
        'Design ändern', 'Change design'
        'Kurzanleitung', 'Quick guide'
        'Über PulsRig', 'About PulsRig'
        'Über', 'About'
        'Hilfe', 'Help'
        'PulsRig in Kürze', 'PulsRig in brief'
        'Menü und Design', 'Menu and design'
        'Der große Knopf fragt Windows Update, NVIDIA, AMD und den Microsoft-Katalog nach neueren Treibern. Die Karten darunter führen zu den Ergebnissen.', 'The big button asks Windows Update, NVIDIA, AMD and the Microsoft catalog for newer drivers. The cards below lead to the results.'
        'Angekreuzte Treiber installiert der Knopf oben rechts – vorher entsteht ein Wiederherstellungspunkt. Fehlt einem Gerät der Treiber, hilft „Beheben“.', 'The button at the top right installs the ticked drivers – a restore point is created first. If a device lacks its driver, “Fix” helps.'
        'Schafft vor dem Spielen Platz. Unter „Einrichten“ wählst du Programme und Dienste aus. Ein zweiter Klick stellt alles zurück.', 'Frees resources before gaming. Under “Set up” you choose programs and services. A second click restores everything.'
        'Jedes Werkzeug prüft zuerst nur und fragt nach, bevor es etwas ändert. Ohne Adminrechte laufen die meisten als Probelauf.', 'Every tool only checks first and asks before it changes anything. Without admin rights most run as a dry run.'
        'Sensoren, Stabilitätstest, Laufwerke, Arbeitsspeicher und Prüfbericht. Das Diagnose-Paket sammelt Angaben für die Fehlersuche in einer Datei.', 'Sensors, stability test, drives, memory and test report. The diagnostics package collects details for troubleshooting in one file.'
        'Im Menü: Treiberverlauf, Zielordner und diese Hilfe. Skins, Farbdesigns, ein eigener Farbton und Ring-Animationen stehen in den Einstellungen unter „Design“.', 'In the menu: driver history, target folder and this help. Skins, color themes, a custom hue and ring animations are in Settings under “Design”.'
        'Was es tut', 'What it does'
        'Sucht neuere Treiber, beschleunigt den PC fürs Spielen und bringt Werkzeuge für Treiber, Geräte und Spiele mit. Testversion: Fehler bitte mit dem Diagnose-Paket melden.', 'Finds newer drivers, speeds up the PC for gaming and comes with tools for drivers, devices and games. Test version: please report errors with the diagnostics package.'
        'Windows Update, NVIDIA, die Chipsatz-Seite von AMD und der Microsoft Update-Katalog. Von AMD und aus dem Katalog kommen Hinweise. Fehlt einem Gerät der Treiber, lädt PulsRig ihn auf Nachfrage aus dem Katalog.', 'Windows Update, NVIDIA, AMD''s chipset page and the Microsoft Update catalog. AMD and the catalog provide notes. If a device lacks its driver, PulsRig downloads it from the catalog on request.'
        'Läuft ohne Adminrechte: Scannen geht, Installieren und Reparieren nicht.', 'Running without admin rights: scanning works, installing and repairing do not.'
        'Läuft mit Adminrechten: Installieren und Reparieren ist möglich.', 'Running with admin rights: installing and repairing are possible.'

        # --- Hardware: Seite und Karten
        'Sensoren, Tests und Zustand der Bauteile an einem Ort.', 'Sensors, tests and component health in one place.'
        'Testversion – Fehler bitte mit dem Diagnose-Paket melden', 'Test version – please report errors with the diagnostics package'
        'Vorschau – noch ohne Funktion', 'Preview – not functional yet'
        'In Arbeit', 'In progress'
        'Live', 'Live'
        'Sensoren', 'Sensors'
        'Temperaturen, Lüfter und Auslastung live als Kurven', 'Temperatures, fans and load live as graphs'
        'Grafikkarte: Temperatur und Lüfter', 'Graphics card: temperature and fan'
        'Prozessor: Auslastung und Takt', 'Processor: load and clock speed'
        'Verlauf der letzten 60 Sekunden', 'History of the last 60 seconds'
        'Stabilitätstest', 'Stability test'
        'Prozessor und Grafikkarte unter Volllast prüfen', 'Test processor and graphics card under full load'
        'Prozessor unter Volllast', 'Processor under full load'
        'Grafikkarte unter Volllast', 'Graphics card under full load'
        'Abbruch bei Fehlern oder Hitze', 'Stops on errors or heat'
        'Laufwerke', 'Drives'
        'Zustand, Belegung und Tempo von SSD und Festplatte', 'Health, usage and speed of SSD and hard disk'
        'Zustand und Störungen', 'Health and faults'
        'Betriebsstunden (mit Adminrechten)', 'Power-on hours (with admin rights)'
        'Lese- und Schreibtempo', 'Read and write speed'
        'Riegel, Belegung und Speichertest', 'Modules, usage and memory test'
        'Eingebaute Riegel und Steckplätze', 'Installed modules and slots'
        'Speichertest beim Neustart', 'Memory test at restart'
        'Letztes Ergebnis und Hardwarefehler', 'Last result and hardware errors'
        'Diagnose-Paket', 'Diagnostics package'
        'Angaben zum PC und Fehlerprotokoll für die Fehlersuche', 'PC details and error log for troubleshooting'
        'Fehlerprotokoll und letzter Scan', 'Error log and last scan'
        'Eine Datei zum Verschicken', 'One file to send'
        'Prüfbericht', 'Test report'
        'Ergebnisse aller Prüfungen als Bericht speichern', 'Save the results of all checks as a report'
        'Ergebnisse aller Tests auf einer Seite', 'Results of all tests on one page'
        'Als Datei speichern', 'Save as file'
        'Zum Weitergeben oder Ausdrucken', 'To pass on or print'
        'Noch nicht gelaufen', 'Not run yet'
        'Messung öffnen', 'Open measurement'
        'Test starten', 'Start test'
        'Jetzt prüfen', 'Check now'
        'Paket erstellen', 'Create package'
        'Bericht öffnen', 'Open report'
        'Liegt auf dem Desktop', 'Saved on the desktop'
        'Abgebrochen', 'Stopped'
        'Bestanden', 'Passed'
        'Gestoppt', 'Stopped'
        'Rechenfehler', 'Calculation error'
        'Zu heiß', 'Too hot'
        'PROZESSOR', 'PROCESSOR'
        'Einmal nachgeprellt', 'Bounced once'
        'Die Maus meldet nur, wenn sie sich bewegt: Für eine höhere Rate schneller kreisen oder die DPI erhöhen.', 'The mouse only reports when it moves: for a higher rate circle faster or raise the DPI.'
        'Maus jetzt ein paar Sekunden schnell und ohne Pause im Kreis bewegen', 'Move the mouse quickly in circles for a few seconds without pausing'
        'Controller und Maus', 'Controller and mouse'
        'Controller', 'Controller'
        'Tasten, Stick-Drift, Abfragerate und ungewollte Doppelklicks prüfen', 'Check buttons, stick drift, polling rate and unwanted double clicks'
        'Tasten, Stick-Drift, Abfragerate und Doppelklick-Fehler', 'Buttons, stick drift, polling rate and double-click faults'
        'Linker Stick', 'Left stick'
        'Rechter Stick', 'Right stick'
        'Suche einen Controller …', 'Looking for a controller …'
        'Drift messen', 'Measure drift'
        'Vibrieren', 'Vibrate'
        'Xbox-kompatible Controller (XInput). PlayStation-Controller nur über Steam oder DS4Windows.', 'Xbox-compatible controllers (XInput). PlayStation controllers only via Steam or DS4Windows.'
        'Maus jetzt ein paar Sekunden schnell im Kreis bewegen', 'Move the mouse quickly in circles for a few seconds'
        'Abfragerate', 'Polling rate'
        'Links', 'Left'
        'Rechts', 'Right'
        'Mitte', 'Middle'
        'Seite 1', 'Side 1'
        'Seite 2', 'Side 2'
        'Rad', 'Wheel'
        'Doppelklick-Fehler', 'Double-click fault'
        'Jede Taste 20- bis 30-mal schnell hintereinander klicken. Löst eine kurz nach dem Loslassen von selbst wieder aus, steht es hier.', 'Click every button 20 to 30 times quickly. If one fires again by itself right after release, it shows up here.'
        'Zurücksetzen', 'Reset'
        'Gemessen wird jede einzelne Meldung der Maus, auch außerhalb von PulsRig', 'Every single report of the mouse is measured, also outside PulsRig'
        'Sticks nicht berühren …', 'Do not touch the sticks …'
        'Gemessen wird 3 Sekunden lang, wie weit sie in Ruhe von der Mitte abweichen.', 'For 3 seconds it measures how far they rest from the center.'
        'Kein Controller gefunden', 'No controller found'
        'Controller per Kabel, Funk oder Bluetooth verbinden. Erkannt werden Xbox-kompatible Controller (XInput).', 'Connect a controller by cable, wireless or Bluetooth. Xbox-compatible controllers (XInput) are detected.'
        'leichter Drift', 'slight drift'
        'Drift', 'drift'
        'Beide kehren sauber in die Mitte zurück.', 'Both return cleanly to the center.'
        'Die meisten Spiele gleichen das mit ihrer Totzone aus. Wird es schlimmer: Stick mit Druckluft reinigen.', 'Most games compensate with their dead zone. If it gets worse: clean the stick with compressed air.'
        'Der Stick bewegt die Figur von selbst. Reinigen hilft manchmal; sonst muss das Stick-Modul getauscht werden.', 'The stick moves the character by itself. Cleaning sometimes helps; otherwise the stick module has to be replaced.'
        'Kein Stick-Drift', 'No stick drift'
        'Stick-Drift gemessen', 'Stick drift measured'
        'Ungewollte Doppelklicks', 'Unwanted double clicks'
        'Kein Doppelklick-Fehler', 'No double-click fault'
        'Controller oder Maus spinnt', 'Controller or mouse acting up'
        'Stick-Drift, Tasten, Abfragerate und ungewollte Doppelklicks prüfen', 'Check stick drift, buttons, polling rate and unwanted double clicks'
        'Verschleiß', 'Wear'
        'zu wenig Daten', 'too little data'
        'sammelt noch', 'still collecting'
        'lässt nach', 'declining'
        'über 10 Jahre', 'over 10 years'
        'Zeit zum Entstauben: Lüfter, Kühlrippen und Filter reinigen. Hilft das nicht, kann die Wärmeleitpaste eingetrocknet sein.', 'Time to dust: clean fans, heat sinks and filters. If that does not help, the thermal paste may have dried out.'
        'Die Kühlung hält mit: kein Nachlassen zu sehen.', 'The cooling keeps up: no decline visible.'
        'Die Abnutzung liest Windows nur mit Adminrechten. PulsRig einmal als Admin starten.', 'Windows only reports wear with admin rights. Start PulsRig once as admin.'
        'Seit Beginn der Aufzeichnung unverändert: Für eine Schätzung ist sie noch zu jung oder wird wenig beschrieben.', 'Unchanged since recording began: it is too new or written too little for an estimate.'
        'Lässt die Kühlung nach?', 'Is the cooling declining?'
        'Vergleicht Temperaturen bei gleicher Leistung über Wochen: Wird es wärmer, ist es Zeit zum Entstauben', 'Compares temperatures at the same power over weeks: if it gets warmer, it is time to dust'
        'Nicht aufzeichnen', 'Stop recording it'
        'aufgezeichnet werden die Boost-Spiele und die hier gewählten – „Aufzeichnen“ schaltet keinen Boost ein', 'recorded are the boost games and the ones chosen here – "Record" does not switch on the boost'
        'Der Helfer zeichnet die Spiele auf, die unter „Deine Spiele“ zum Aufzeichnen gewählt sind, und die Boost-Spiele. Noch ist keines gewählt.', 'The helper records the games chosen for recording under "Your games" and the boost games. None is chosen yet.'
        'Läuft ein Boost-Spiel oder eines, das unter „Deine Spiele“ zum Aufzeichnen gewählt ist, schreibt der Helfer alle 5 Sekunden Temperaturen, Last und Takt mit. Ansehen unter Hardware → Sensoren → Spielsitzungen.', 'While a boost game or one chosen for recording under "Your games" runs, the helper records temperatures, load and clock every 5 seconds. View them under Hardware → Sensors → Game sessions.'
        'Deine Spiele', 'Your games'
        'Jedes Spiel einzeln: Laufwerk, Temperaturen beim Spielen und was für alle Spiele gilt', 'Every game on its own: drive, temperatures while gaming and what applies to all games'
        'FÜR ALLE SPIELE', 'FOR ALL GAMES'
        'JEDES SPIEL EINZELN', 'EVERY GAME ON ITS OWN'
        'Läuft der Monitor mit seiner höchsten Hz-Zahl? Sonst wirkt jedes Spiel weniger flüssig', 'Does the monitor run at its highest refresh rate? Otherwise every game feels less smooth'
        'Energieplan, voller Takt des Speichers, Spielmodus und mehr: sieben Einstellungen, die fürs Spielen zählen', 'Power plan, full memory speed, game mode and more: seven settings that matter for gaming'
        'unbekanntes Laufwerk', 'unknown drive'
        'zu warm oder gedrosselt', 'too warm or throttled'
        'kein Drosseln', 'no throttling'
        'wird beim nächsten Spielen aufgezeichnet', 'will be recorded the next time it is played'
        'wird nicht aufgezeichnet', 'not recorded'
        'Aufzeichnen', 'Record'
        'zu warm', 'too warm'
        'ohne Messung', 'not measured yet'
        'letzte Sitzung nicht lesbar', 'last session not readable'
        'Sobald ein Spiel einmal gelaufen ist, steht es hier.', 'As soon as a game has run once, it shows up here.'
        'aufgezeichnet werden die, die unter Boost → Einrichten → Spiele gewählt sind', 'recorded are those selected under Boost → Set up → Games'
        'Gemerkt. Aufgezeichnet wird im Helfer neben der Uhr: unter Optionen → Hintergrund einschalten.', 'Noted. Recording happens in the helper next to the clock: switch it on under Options → Background.'
        'Gemerkt: Beim nächsten Spielen zeichnet der Helfer auf.', 'Noted: the helper records the next time you play.'
        'Das Spiel einzeln prüfen', 'Check the game on its own'
        'Laufwerk, Temperaturen beim letzten Spielen und ob etwas gedrosselt hat', 'Drive, temperatures the last time it was played and whether anything throttled'
        'Spielsitzungen', 'Game sessions'
        'Temperaturen, Lüfter und Auslastung im Sekundentakt – und beim Spielen aufgezeichnet', 'Temperatures, fans and load every second – and recorded while gaming'
        'Noch keine Spielsitzung', 'No game session yet'
        'Was aufgezeichnet wird', 'What is recorded'
        'Alle 5 Sekunden Temperatur, Last und Takt von Prozessor und Grafikkarte, dazu Leistung und Lüfter der Grafikkarte. Es bleiben die letzten 30 Sitzungen.', 'Every 5 seconds temperature, load and clock of processor and graphics card, plus power and fan of the graphics card. The last 30 sessions are kept.'
        'Aufzeichnungen: keine', 'Recordings: none'
        'Aufgezeichnet wird im Helfer neben der Uhr. Den gibt es nur im installierten Programm.', 'Recording happens in the helper next to the clock. It only exists in the installed program.'
        'Aufgezeichnet wird im Helfer neben der Uhr. Er ist ausgeschaltet.', 'Recording happens in the helper next to the clock. It is switched off.'
        'Die Aufzeichnung beim Spielen ist ausgeschaltet.', 'Recording while gaming is switched off.'
        'Der Helfer zeichnet die Spiele auf, die unter Boost → Einrichten → Spiele gewählt sind. Noch ist keines gewählt.', 'The helper records the games selected under Boost → Set up → Games. None is selected yet.'
        'Helfer einschalten', 'Switch helper on'
        'Spiele wählen', 'Choose games'
        'Die Sitzung ließ sich nicht lesen', 'The session could not be read'
        'Zusammenfassung', 'Summary'
        'Zu warm oder gedrosselt', 'Too warm or throttled'
        'Die Temperatur des Prozessors fehlt: Sensoren → Freischalten, oder Core Temp laufen lassen.', 'The processor temperature is missing: Sensors → Unlock, or keep Core Temp running.'
        'Kein Drosseln zu sehen: Die Kühlung kommt mit dem Spiel zurecht.', 'No throttling visible: the cooling copes with the game.'
        'Spiele aufzeichnen', 'Record games'
        'Läuft eines dieser Spiele, schreibt der Helfer alle 5 Sekunden Temperaturen, Last und Takt mit. Ansehen unter Hardware → Sensoren → Spielsitzungen.', 'While one of these games runs, the helper records temperatures, load and clock every 5 seconds. View them under Hardware → Sensors → Game sessions.'
        'Wie warm wird es beim Spielen?', 'How warm does it get while gaming?'
        'Der Helfer neben der Uhr zeichnet jede Spielsitzung auf: Temperaturen, Takt und ob etwas drosselt', 'The helper next to the clock records every game session: temperatures, clock and whether anything throttles'
        'Der Prozessor lief an seiner Temperaturgrenze. Viele Prozessoren takten unter Volllast absichtlich so weit hoch, wie die Kühlung es zulässt: Bei normalen Punkten ist das kein Fehler. Werden die Punkte mit der Zeit weniger, Kühler und Staub prüfen.', 'The processor ran at its temperature limit. Many processors deliberately boost under full load as far as the cooling allows: with normal scores this is not a fault. If the scores drop over time, check the cooler and dust.'
        'Der Prozessor lief an seiner Temperaturgrenze: Viele takten unter Volllast absichtlich so weit hoch, wie die Kühlung es zulässt.', 'The processor ran at its temperature limit: many deliberately boost under full load as far as the cooling allows.'
        'nicht gemessen', 'not measured'
        'Benchmark', 'Benchmark'
        'Benchmark starten', 'Start benchmark'
        'Prozessor, Arbeitsspeicher, Grafikkarte und Laufwerk mit Punkten – und der Vergleich mit früher', 'Processor, memory, graphics card and drive with scores – compared with earlier runs'
        'Punkte', 'points'
        'Dauert rund eine Minute. Ein Fenster für die Grafikkarte geht kurz auf, auf das Windows-Laufwerk wird 1 GB geschrieben und gleich wieder gelöscht. Andere Programme vorher schließen, sonst sinken die Punkte.', 'Takes about a minute. A window for the graphics card opens briefly, and 1 GB is written to the Windows drive and deleted right away. Close other programs first, otherwise the scores drop.'
        'Am besten vergleichbar: gleiche Uhrzeit, gleiche Programme offen, PC nicht gerade erst gestartet', 'Best comparable: same time of day, same programs open, PC not just started'
        'Prozessor, ein Kern', 'Processor, one core'
        'Prozessor, alle Kerne', 'Processor, all cores'
        'Grafikkarte (eigenes Fenster)', 'Graphics card (own window)'
        'Nicht fertig geworden', 'Not finished'
        'Abgebrochen.', 'Cancelled.'
        'Erst den Stabilitätstest beenden', 'Finish the stability test first'
        'Fertig – die Grafikkarte ließ sich nicht messen', 'Done – the graphics card could not be measured'
        'Noch kein Lauf', 'No run yet'
        'Der erste Benchmark ist der Vergleich für alle späteren: nach einem Treiber-Update, mit XMP oder mit Boost.', 'The first benchmark is the reference for all later ones: after a driver update, with XMP or with Boost.'
        'erster Lauf', 'first run'
        'besser', 'better'
        'schlechter', 'worse'
        'gleich', 'same'
        'nicht messbar', 'not measurable'
        'Speichertakt', 'memory clock'
        'seit dem Lauf davor', 'since the previous run'
        'Erster Lauf: Er ist ab jetzt der Vergleich für die nächsten.', 'First run: from now on it is the reference for the next ones.'
        'Seitdem hat sich an Treiber, Speichertakt, Energieplan und Windows nichts geändert: andere Programme im Hintergrund oder Wärme sind wahrscheinlicher.', 'Since then nothing changed in drivers, memory clock, power plan or Windows: background programs or heat are more likely.'
        'Wirklich langsamer als früher?', 'Really slower than before?'
        'Der Benchmark misst Prozessor, Speicher, Grafikkarte und Laufwerk und vergleicht mit früheren Läufen', 'The benchmark measures processor, memory, graphics card and drive and compares with earlier runs'
        'Prozessor · Temperatur', 'Processor · temperature'
        'Prozessor · Leistung', 'Processor · power'
        'Freischalten', 'Unlock'
        'Windows gibt die Temperatur des Prozessors nicht heraus. PulsRig kann sie mit dem freien Treiber PawnIO lesen; „Freischalten“ installiert ihn über sein offizielles Setup (braucht Adminrechte). Hinweis: Das Anti-Cheat von FACEIT hat PawnIO schon blockiert.', 'Windows does not provide the processor temperature. PulsRig can read it with the free driver PawnIO; "Unlock" installs it through its official setup (needs admin rights). Note: the FACEIT anti-cheat has blocked PawnIO before.'
        'Der Treiber PawnIO ist installiert. Lesen darf PulsRig die Temperatur des Prozessors aber nur mit Adminrechten.', 'The PawnIO driver is installed, but PulsRig may only read the processor temperature with admin rights.'
        'PawnIO ist installiert, aber dieser Prozessor meldet keine Temperatur. Läuft Core Temp, übernimmt PulsRig dessen Werte.', 'PawnIO is installed, but this processor reports no temperature. If Core Temp is running, PulsRig uses its values.'
        'Die Temperatur des Prozessors gibt Windows nicht heraus, und der Baustein dafür fehlt in diesem Ordner.', 'Windows does not provide the processor temperature, and the component for it is missing from this folder.'
        'Im Probelauf wird PawnIO nicht installiert', 'PawnIO is not installed in a dry run'
        'Lade das Setup von PawnIO …', 'Downloading the PawnIO setup …'
        'Das Laden hat nicht geklappt. Später noch einmal versuchen.', 'The download failed. Try again later.'
        'Die geladene Datei passt nicht zur geprüften Fassung von PawnIO. Sie wurde gelöscht und nicht gestartet.', 'The downloaded file does not match the checked version of PawnIO. It was deleted and not started.'
        'Das Setup wurde nicht gestartet – die Abfrage von Windows wurde abgelehnt.', 'The setup was not started – the Windows prompt was declined.'
        'Das Setup von PawnIO läuft …', 'The PawnIO setup is running …'
        'PawnIO ist nicht installiert worden. Das Setup wurde wohl abgebrochen.', 'PawnIO was not installed. The setup was probably cancelled.'
        'Freigeschaltet: Die Temperatur des Prozessors wird jetzt gemessen.', 'Unlocked: the processor temperature is now measured.'
        'PawnIO ist installiert. Lesen darf PulsRig die Temperatur nur mit Adminrechten: einmal als Admin neu starten.', 'PawnIO is installed. PulsRig may only read the temperature with admin rights: restart once as admin.'
        'PawnIO ist installiert, aber der Prozessor meldet noch keine Temperatur. PulsRig einmal neu starten.', 'PawnIO is installed, but the processor reports no temperature yet. Restart PulsRig once.'
        'Der Test endet von selbst: bei Rechenfehlern, bei 90 °C an der Grafikkarte, 98 °C am Prozessor oder wenn der Prozessor seinen Takt drosselt. Laut und warm ist dabei normal.', 'The test ends on its own: on calculation errors, at 90 °C on the graphics card, 98 °C on the processor or when the processor throttles its clock. Loud and warm is normal.'
        'Prozessor drosselt', 'Processor throttles'
        'Überwachung ausgefallen', 'Monitoring lost'
        'Grafiklast nicht möglich', 'Graphics load not possible'
        'Ohne Fehler durchgelaufen', 'Completed without errors'
        'Dual-Channel', 'Dual channel'
        'Single-Channel', 'Single channel'
        'Riegel unbekannt', 'Modules unknown'
        'keine Angaben', 'no data'
        'falsch gesteckt', 'wrong slots'
        'Hardwarefehler', 'Hardware errors'
        'Speicherfehler', 'Memory errors'
        'Fehler gefunden', 'Errors found'
        'alles bestanden', 'all passed'

        # --- Hardware: Sensoren und Stabilitätstest
        'Temperaturen, Lüfter und Auslastung im Sekundentakt', 'Temperatures, fans and load, every second'
        'Grafikkarte · Temperatur', 'Graphics card · temperature'
        'Temperatur', 'temperature'
        'Auslastung', 'load'
        'Lüfter', 'fan'
        'Leistung', 'power'
        'Grafikspeicher belegt', 'Graphics memory used'
        'Arbeitsspeicher belegt', 'Memory used'
        'nicht verfügbar', 'not available'
        'Was hier fehlt', 'What is missing here'
        'Die Temperatur des Prozessors und die Lüfter des Mainboards gibt Windows auf diesem PC nicht heraus. Dafür wäre ein Zusatzbaustein nötig, der mit Adminrechten direkt auf die Sensoren zugreift.', 'Windows does not provide the processor temperature or the mainboard fans on this PC. That would need an add-on component that accesses the sensors directly with admin rights.'
        'letzte 60 Sekunden', 'last 60 seconds'
        'Keine NVIDIA-Grafikkarte gefunden', 'No NVIDIA graphics card found'
        'Kurven: letzte 60 Sekunden', 'Graphs: last 60 seconds'
        'Was belasten?', 'What to load?'
        'Beides zusammen fordert auch das Netzteil am stärksten.', 'Both together also put the most strain on the power supply.'
        'Beides', 'Both'
        'Wie lange?', 'How long?'
        'Eine Minute zeigt grobe Fehler, 15 Minuten auch Hitzeprobleme.', 'One minute shows gross errors, 15 minutes also heat problems.'
        'Der Test endet von selbst: bei Rechenfehlern, bei 90 °C an der Grafikkarte oder wenn der Prozessor seinen Takt drosselt. Laut und warm ist dabei normal.', 'The test ends on its own: on calculation errors, at 90 °C on the graphics card or when the processor throttles. Loud and warm is normal.'
        'Vorher speichern, was offen ist: Ein instabiler PC kann beim Test abstürzen', 'Save your open work first: an unstable PC can crash during the test'
        'Stoppen', 'Stop'
        'Läuft …', 'Running …'
        'Die Last fährt hoch.', 'The load is ramping up.'
        'Grafiklast läuft', 'Graphics load running'
        'Grafiklast startet', 'Graphics load starting'
        'Temperatur nicht messbar: kein Abbruch bei Hitze', 'Temperature not measurable: no stop on heat'
        'Grafiklast ohne Abbruch, Temperatur nicht messbar', 'Graphics load without a stop, temperature not measurable'
        'Grafiklast ohne Abbruch, Temperatur nicht messbar.', 'Graphics load without a stop, temperature not measurable.'
        'Das Fenster der Grafiklast wurde geschlossen.', 'The graphics load window was closed.'
        'Die Temperatur der Grafikkarte kam nicht mehr an. Ohne Überwachung läuft der Test nicht weiter.', 'The graphics card temperature stopped arriving. Without monitoring the test does not continue.'
        'Prozessor und Grafikkarte', 'Processor and graphics card'

        # --- Hardware: Laufwerke
        'Zustand und Belegung der eingebauten Laufwerke', 'Health and usage of the installed drives'
        'Tempo', 'Speed'
        'Lese die Laufwerke …', 'Reading the drives …'
        'LAUFWERKE', 'DRIVES'
        'BELEGUNG', 'USAGE'
        'alle in Ordnung', 'all OK'
        'fast voll', 'almost full'
        'Temperatur und Betriebsstunden zeigt Windows nur mit Adminrechten', 'Windows shows temperature and power-on hours only with admin rights'
        'Temperatur, Betriebsstunden und Abnutzung nur mit Adminrechten', 'Temperature, power-on hours and wear only with admin rights'
        'Störungen (30 Tage)', 'Faults (30 days)'
        'Störungen der letzten 30 Tage sind nicht lesbar', 'Faults of the last 30 days cannot be read'
        'Windows gibt das Ereignisprotokoll auf diesem PC nicht heraus. Der Zustand oben stammt vom Laufwerk selbst.', 'Windows does not release the event log on this PC. The health above comes from the drive itself.'
        'Windows hat kein Laufwerk gemeldet', 'Windows reported no drive'
        'Das kommt in virtuellen Maschinen vor oder wenn die Laufwerksverwaltung von Windows nicht antwortet.', 'This happens in virtual machines or when Windows storage management does not respond.'
        'nicht lesbar', 'not readable'
        'Laufwerk', 'Drive'
        'SSD', 'SSD'
        'Festplatte', 'Hard disk'
        'Tempotest', 'Speed test'
        'prüfen', 'check'
        'So langsam ist kein gesundes Laufwerk. Kabel und Anschluss prüfen; siehe auch „Übersicht“.', 'No healthy drive is this slow. Check cable and port; see also “Overview”.'
        'Tempo messen', 'Measure speed'
        'Erneut messen', 'Measure again'
        'Noch nicht gemessen. Die Messung schreibt eine Testdatei von bis zu 1 GB und löscht sie wieder.', 'Not measured yet. The measurement writes a test file of up to 1 GB and deletes it again.'
        'Kein Laufwerk mit Laufwerksbuchstaben gefunden', 'No drive with a drive letter found'
        'Richtwerte am Stück: Festplatte 80–200', 'Sequential reference values: hard disk 80–200'
        'SATA-SSD 400–550', 'SATA SSD 400–550'
        'NVMe-SSD ab 1.500 MB/s', 'NVMe SSD from 1,500 MB/s'
        'Windows meldet alle als gesund', 'Windows reports all as healthy'
        'Windows meldet es als gesund', 'Windows reports it as healthy'

        # --- Hardware: Arbeitsspeicher
        'Eingebaute Riegel, Belegung und Speichertest', 'Installed modules, usage and memory test'
        'Test', 'Test'
        'Lese den Arbeitsspeicher …', 'Reading the memory …'
        'STECKPLÄTZE', 'SLOTS'
        'Steckplatz', 'Slot'
        'frei', 'free'
        'richtig gesteckt', 'correct slots'
        'voller Takt', 'full speed'
        'Aufbau prüfen', 'Check the setup'
        'Die Riegel laufen so schnell, wie sie gebaut sind. Am Speicherprofil im BIOS (XMP, DOCP oder EXPO) ist nichts zu tun.', 'The modules run as fast as they are built to. Nothing to do about the memory profile in the BIOS (XMP, DOCP or EXPO).'
        'Die gelb markierten Riegel stecken im ersten Steckplatz ihres Kanals. Fast alle Mainboards wollen zuerst den zweiten (meist A2 und B2), sonst scheitert oft XMP. PC ausschalten und wie markiert umstecken; im Zweifel gilt das Handbuch.', 'The modules marked yellow sit in the first slot of their channel. Almost all mainboards want the second one first (usually A2 and B2), otherwise XMP often fails. Switch the PC off and move them as marked; when in doubt, the manual applies.'
        'Ein einzelner Riegel läuft im Single-Channel. Ein zweiter gleicher im anderen Kanal macht den Speicher deutlich schneller.', 'A single module runs in single channel. A second identical one in the other channel makes the memory noticeably faster.'
        'SPEICHERTEST VON WINDOWS', 'WINDOWS MEMORY TEST'
        'Speichertest von Windows', 'Windows memory test'
        'Test beim Neustart', 'Test at restart'
        'Windows prüft den Speicher vor dem Hochfahren. Das dauert je nach Größe 15 bis 40 Minuten.', 'Windows tests the memory before booting. Depending on size this takes 15 to 40 minutes.'
        'Test einplanen', 'Schedule test'
        'Letztes Ergebnis', 'Last result'
        'keine Fehler gefunden', 'no errors found'
        'Windows hat Speicherfehler gefunden', 'Windows found memory errors'
        'Im Protokoll von Windows steht noch kein Speichertest', 'The Windows log contains no memory test yet'
        'Nicht lesbar: Windows gibt das Ereignisprotokoll auf diesem PC nicht heraus', 'Not readable: Windows does not release the event log on this PC'
        'IM LAUFENDEN BETRIEB', 'DURING OPERATION'
        'Keine Hardwarefehler in 90 Tagen', 'No hardware errors in 90 days'
        'Prozessor, Speicher und Mainboard haben Windows nichts gemeldet', 'Processor, memory and mainboard reported nothing to Windows'
        'Hardwarefehler sind nicht lesbar', 'Hardware errors cannot be read'
        'Windows gibt das Ereignisprotokoll auf diesem PC nicht heraus', 'Windows does not release the event log on this PC'
        'GRÜNDLICHER TEST VOM USB-STICK', 'THOROUGH TEST FROM A USB STICK'
        'Startet vom USB-Stick und prüft länger und strenger als der Test von Windows. Kostenlos.', 'Boots from a USB stick and tests longer and more strictly than the Windows test. Free.'
        'Seite öffnen', 'Open page'
        'Bei Abstürzen oder Bluescreens zuerst den Test von Windows, bei Verdacht danach den vom USB-Stick', 'After crashes or bluescreens run the Windows test first, then the USB stick test if in doubt'
        'Windows nennt auf diesem PC keine Riegel', 'Windows lists no modules on this PC'
        'Kanal A', 'Channel A'
        'Kanal B', 'Channel B'

        # --- Hardware: Diagnose-Paket und Prüfbericht
        'Angaben für die Fehlersuche in einer Datei', 'Details for troubleshooting in one file'
        'Läuft etwas nicht, wie es soll, hilft diese Datei bei der Suche nach dem Grund. Sie landet auf dem Desktop – verschickt wird nichts von allein.', 'If something does not work as it should, this file helps find the reason. It is saved to the desktop – nothing is sent on its own.'
        'Angaben zum PC', 'PC details'
        'Windows-Version, Prozessor, Mainboard, Grafikkarte samt Treiber, Riegel und Namen der Steckplätze, Laufwerke, Virenschutz.', 'Windows version, processor, mainboard, graphics card with driver, modules and slot names, drives, antivirus.'
        'Aus PulsRig', 'From PulsRig'
        'Version, Einstellungen, Testergebnisse, das Fehlerprotokoll, der letzte Scan und die Ausgabe der Werkzeuge dieser Sitzung.', 'Version, settings, test results, the error log, the last scan and this session''s tool output.'
        'Nicht enthalten', 'Not included'
        'Seriennummern, dein Benutzername und der Name des PCs. Wo sie in Pfaden stehen, werden sie durch Platzhalter ersetzt.', 'Serial numbers, your user name and the PC name. Where they appear in paths they are replaced by placeholders.'
        'Vorher einmal scannen und den Fehler noch einmal auslösen, ohne PulsRig dazwischen zu schließen – dann steht beides im Paket.', 'Scan once and trigger the error again first, without closing PulsRig in between – then both are in the package.'
        'Im Ordner zeigen', 'Show in folder'
        'Noch kein Paket erstellt', 'No package created yet'
        'Erst ein Paket erstellen', 'Create a package first'
        'Ergebnisse aller Prüfungen auf einer Seite', 'Results of all checks on one page'
        'Stelle den Bericht zusammen …', 'Compiling the report …'
        'Zustand der Laufwerke', 'Drive health'
        'Tempo der Laufwerke', 'Drive speed'
        'Noch kein Laufwerk gemessen.', 'No drive measured yet.'
        'Steckplätze des Arbeitsspeichers', 'Memory slots'
        'Gemeldete Hardwarefehler', 'Reported hardware errors'
        'Höchsttemperatur unter Last', 'Peak temperature under load'
        'Prozessor, Speicher und Mainboard haben Windows in 90 Tagen nichts gemeldet.', 'Processor, memory and mainboard reported nothing to Windows in 90 days.'
        'Im Protokoll von Windows steht noch kein Speichertest.', 'The Windows log contains no memory test yet.'
        'Nicht lesbar: Windows gibt das Ereignisprotokoll auf diesem PC nicht heraus.', 'Not readable: Windows does not release the event log on this PC.'
        'Windows hat keine Angaben geliefert.', 'Windows provided no data.'
        'Richtig gesteckt', 'Correct slots'
        'Falsch gesteckt', 'Wrong slots'
        'ein zweiter Kanal wäre schneller', 'a second channel would be faster'
        'Zu den Laufwerken', 'Go to drives'
        'Zum Speichertest', 'Go to memory test'
        'Zum Arbeitsspeicher', 'Go to memory'
        'zum Drucken im Browser Strg+P', 'to print, press Ctrl+P in the browser'
        'Computer', 'Computer'

        # --- Neue Fassung
        'Neue Fassung verfügbar', 'New release available'
        'Neue Fassung', 'New release'
        'Laden und installieren', 'Download and install'
        'Seite im Browser öffnen', 'Open page in browser'
        'Was passiert', 'What happens'
        'Was bleibt', 'What stays'
        'Einstellungen, Ergebnisse und gesicherte Treiber bleiben erhalten.', 'Settings, results and backed-up drivers are kept.'
        'Prüfung', 'Verification'
        'Gestartet wird die Datei nur, wenn Größe und Prüfsumme zu den veröffentlichten Angaben passen.', 'The file is only started if its size and checksum match the published values.'
        'Windows fragt nach', 'Windows will ask'
        'PulsRig läuft mit Adminrechten: Die Installation beginnt ohne weitere Rückfrage.', 'PulsRig runs with admin rights: the installation starts without another prompt.'
        'Die Installation braucht Adminrechte. Windows fragt danach, mit dem Hinweis „Unbekannter Herausgeber“.', 'The installation needs admin rights. Windows will ask for them, noting “Unknown publisher”.'
        'Noch nichts geladen', 'Nothing downloaded yet'
        'Lade die Setup-Datei …', 'Downloading the setup file …'
        'Das Laden hat nicht geklappt. Später noch einmal versuchen oder die Seite im Browser öffnen.', 'The download failed. Try again later or open the page in the browser.'
        'Die geladene Datei passt nicht zu den veröffentlichten Angaben. Sie wurde gelöscht und nicht gestartet.', 'The downloaded file does not match the published values. It was deleted and not started.'
        'Geladen und geprüft – im Probelauf wird nicht installiert', 'Downloaded and verified – not installed in a dry run'
        'Die Installation wurde nicht gestartet – die Abfrage von Windows wurde abgelehnt oder die Datei ließ sich nicht öffnen.', 'The installation was not started – the Windows prompt was declined or the file could not be opened.'
        'Geprüft. Die Installation läuft, PulsRig schließt sich …', 'Verified. The installation is running, PulsRig is closing …'

        # --- Dialog der Werkzeuge: Rahmen, Rückfragen, häufige Zeilen
        'Abbrechen', 'Cancel'
        'Überspringen', 'Skip'
        'Fertig', 'Done'
        'Mit Fehler beendet', 'Ended with an error'
        'Fertig, aber nicht alle Schritte haben geklappt', 'Done, but not every step worked'
        'Probelauf beendet – nichts verändert', 'Dry run finished – nothing changed'
        'Einen Moment, der Arbeitsbereich ist noch beschäftigt …', 'One moment, the worker is still busy …'
        'Wartet auf deine Antwort', 'Waiting for your answer'
        'Wartet, bis der Scan fertig ist …', 'Waiting for the scan to finish …'
        'DEINE EINGABE', 'YOUR INPUT'
        'Die Eingabetaste bestätigt. Das Werkzeug wartet so lange.', 'Enter confirms. The tool waits until then.'
        'Erst mit „Ja“ wird etwas verändert. Das Werkzeug wartet so lange.', 'Nothing is changed until you say “Yes”. The tool waits until then.'
        'Neustart nötig', 'restart required'
        'Aktualisierung abgeschlossen - für den neuen Stand erneut scannen', 'Update finished - scan again to see the new state'
        'nur Probelauf', 'dry run only'
        'nur nach deinem Ja', 'only after your Yes'
        'vor jeder Änderung', 'before every change'
        'Probelauf: Es wird nur geprüft und angezeigt, nichts verändert.', 'Dry run: things are only checked and shown, nothing is changed.'
        'Prüfe die Verbindung ...', 'Checking the connection ...'
        'Netzwerkadapter verbunden', 'Network adapter connected'
        'IP-Adresse und Gateway', 'IP address and gateway'
        'Internet erreichbar', 'Internet reachable'
        'Namensauflösung (DNS)', 'Name resolution (DNS)'
        'Webseiten abrufbar', 'Web pages reachable'
        'DNS-Zwischenspeicher leeren', 'Flush the DNS cache'
        'IP-Adresse freigeben und neu anfordern', 'Release and renew the IP address'
        'Letzte Stufe: Netzwerkeinstellungen von Windows zurücksetzen (Winsock und TCP/IP).', 'Last step: reset the Windows network settings (Winsock and TCP/IP).'
        'Dabei gehen fest eingetragene IP-Adressen verloren, und der PC muss neu gestartet werden.', 'Manually configured IP addresses are lost, and the PC must be restarted.'
        'Nicht zurückgesetzt. Hilft auch das nicht, liegt es meist am Router, am Anbieter oder am Treiber.', 'Not reset. If that does not help either, the cause is usually the router, the provider or the driver.'
        'Verbindung testen und in Stufen reparieren.', 'Test the connection and repair it step by step.'
        'Hardware und Windows im Überblick.', 'Hardware and Windows at a glance.'
        'Audiogeräte ohne Fehler', 'Audio devices without errors'
        'Standardgerät nicht stumm', 'Default device not muted'
        'Dienst "Windows-Audio" jetzt starten?', 'Start the "Windows Audio" service now?'
        'Keine Ursache gefunden. Prüfe, ob in Windows das richtige Wiedergabegerät gewählt ist (Klick auf das Lautsprechersymbol).', 'No cause found. Check that the right playback device is selected in Windows (click the speaker icon).'
        'Diese Programme werden geschlossen (dort vorher alles Ungespeicherte sichern):', 'These programs will be closed (save any unsaved work there first):'
        'Fehlende Bibliotheken sind kein Fehler: Sie werden nur gebraucht, wenn ein Spiel sie verlangt,', 'Missing libraries are not an error: they are only needed if a game requires them,'
        'und die meisten Spiele bringen sie selbst mit.', 'and most games bring them along.'
        'Die Installer kommen direkt von Microsoft und öffnen sich nacheinander - dort jeweils selbst bestätigen.', 'The installers come directly from Microsoft and open one after another - confirm each one yourself.'
        'Eine Komponente ist ausgewählt.', 'One component is selected.'
        'Diese Version ignorieren', 'Ignore this version'
        'Vorhandene einblenden', 'Show present ones'
        'Treiberpakete von Drittherstellern, neueste zuerst', 'Third-party driver packages, newest first'
        'Auf Standard zurückgesetzt (Design, Boost-Auswahl und Ignoriertes bleiben)', 'Reset to defaults (design, boost selection and ignored items are kept)'
        'PROZESSOR-AUSLASTUNG', 'PROCESSOR LOAD'
        'ARBEITSSPEICHER BELEGT', 'MEMORY USED'
        'DATENTRÄGER', 'STORAGE'
        'Warte auf die ersten Messwerte …', 'Waiting for the first readings …'
        'falscher Steckplatz', 'wrong slot'
        'frei – hierhin umstecken', 'free – move a module here'
        'Werkstatt (nicht aus einem Paket)', 'Workshop (not from a package)'
        'Der Update-Server wurde nicht gefunden (Internetverbindung prüfen).', 'The update server was not found (check the internet connection).'
        'Keine Verbindung zu Windows Update (Internet, Proxy oder DNS prüfen).', 'No connection to Windows Update (check internet, proxy or DNS).'
        'Keine Verbindung zum Update-Server (Firewall oder Proxy prüfen).', 'No connection to the update server (check firewall or proxy).'
        'Zeitüberschreitung bei der Verbindung zum Update-Server.', 'Timed out connecting to the update server.'
        'Der Windows-Update-Dienst wurde während des Vorgangs beendet.', 'The Windows Update service was stopped during the operation.'
        'Der Dienst "Windows Update" ist deaktiviert.', 'The "Windows Update" service is disabled.'
        'Für diesen Schritt sind Adminrechte nötig.', 'This step needs admin rights.'
        'Windows Update ist auf diesem PC per Richtlinie gesperrt.', 'Windows Update is blocked by policy on this PC.'
        'Zugriff verweigert.', 'Access denied.'
        'Ein Klick auf SCAN prüft Windows Update.', 'Click SCAN to check Windows Update.'

        # --- Ausgaben der Werkzeuge (Treiber-Scan.ps1, Treiber-Werkzeuge.ps1)
        'ok', 'ok'
        'Geplante Schritte:', 'Planned steps:'
        'Jetzt ausführen?', 'Run now?'
        'Alle Bildschirme laufen in ihrer empfohlenen Auflösung.', 'All displays run at their recommended resolution.'
        'Alle Geräte arbeiten wieder.', 'All devices are working again.'
        'Alles aktuell - nichts zu tun.', 'All up to date - nothing to do.'
        'Anzeigeeinstellungen von Windows öffnen?', 'Open the Windows display settings?'
        'Audiodienste neu starten', 'Restart the audio services'
        'Audiodienste trotzdem neu starten (hilft bei hängendem Ton)?', 'Restart the audio services anyway (helps when sound hangs)?'
        'Ausschalten und alles zurückstellen?', 'Switch off and restore everything?'
        'Bitte den PC jetzt neu starten.', 'Please restart the PC now.'
        'Bitte den PC neu starten, um die Installation abzuschließen.', 'Please restart the PC to finish the installation.'
        'Bitte den PC neu starten, um die Wiederherstellung abzuschließen.', 'Please restart the PC to finish the restore.'
        'Bitte eine Nummer aus der Liste eingeben.', 'Please enter a number from the list.'
        'Dafür den Treiber beim Hersteller suchen (die Hardware-ID hilft bei der Suche) oder den PC neu starten.', 'For these, look for the driver at the vendor (the hardware ID helps with the search) or restart the PC.'
        'Das Paket enthält alle installierten Treiber von Drittherstellern samt Startdatei zum Einspielen -', 'The package contains all installed third-party drivers plus a start file to restore them -'
        'gedacht für diesen PC nach einer Neuinstallation von Windows, auch ohne Internet.', 'meant for this PC after reinstalling Windows, even without internet.'
        'Das Paket nennt dieses Gerät nicht und wurde verworfen.', 'The package does not list this device and was discarded.'
        'Deaktivierte Geräte wieder aktivieren?', 'Enable the disabled devices again?'
        'Der Katalog lieferte keine auswertbaren Treffer - vermutlich wurde die Webseite umgebaut.', 'The catalog returned no usable results - the website was probably changed.'
        'Der Katalog nennt zu diesem Treiber keine Datei.', 'The catalog lists no file for this driver.'
        'Die Seite von AMD nennt keine Version - vermutlich wurde sie umgebaut.', 'AMD''s page lists no version - it was probably changed.'
        'Die Verbindung funktioniert wieder.', 'The connection works again.'
        'Die Verbindung funktioniert.', 'The connection works.'
        'Die geladene Datei ist nicht die, die der Katalog nennt (Prüfsumme weicht ab).', 'The downloaded file is not the one the catalog lists (checksum differs).'
        'Die geladene Datei trägt keine gültige NVIDIA-Signatur und wurde verworfen.', 'The downloaded file has no valid NVIDIA signature and was discarded.'
        'Die geladene Datei trägt keine gültige Signatur des Herstellers und wurde verworfen.', 'The downloaded file has no valid vendor signature and was discarded.'
        'Die geladene Datei trägt keine gültige Signatur von Microsoft und wurde verworfen.', 'The downloaded file has no valid Microsoft signature and was discarded.'
        'Dort erscheinen neue Versionen oft früher als bei Windows Update (manuell prüfen):', 'New versions often appear there earlier than on Windows Update (check manually):'
        'Durchsuche den Microsoft-Katalog ...', 'Searching the Microsoft catalog ...'
        'Es gibt nichts zu beschleunigen - das System ist bereits so eingestellt.', 'There is nothing to boost - the system is already set up this way.'
        'Exportiere Treiber (kann einige Minuten dauern) ...', 'Exporting drivers (may take a few minutes) ...'
        'Exportiere alle Treiber von Drittherstellern (kann einige Minuten dauern) ...', 'Exporting all third-party drivers (may take a few minutes) ...'
        'Frage Windows Update ab (dauert bis zu einer Minute) ...', 'Querying Windows Update (takes up to a minute) ...'
        'Geräte mit Problemen:', 'Devices with problems:'
        'Gewählte Programme werden geschlossen; reagiert eines nach 8 Sekunden nicht, wird es beendet.', 'Selected programs are closed; if one does not respond after 8 seconds it is terminated.'
        'Grafiktreiber jetzt suchen und installieren?', 'Search for and install the graphics driver now?'
        'Hardware neu erkennen', 'Rescan hardware'
        'Im Arbeitsordner liegt etwas, das nicht von PulsRig stammt - abgebrochen.', 'The working folder contains something that is not from PulsRig - aborted.'
        'Installiere Treiber (der Bildschirm kann kurz flackern, Geräte können sich kurz abmelden) ...', 'Installing drivers (the screen may flicker, devices may disconnect briefly) ...'
        'Kein Adapter ist verbunden - zuerst Kabel bzw. WLAN prüfen.', 'No adapter is connected - check the cable or Wi-Fi first.'
        'Kein Gerät meldet einen Fehler.', 'No device reports an error.'
        'Kein neuer Wiederherstellungspunkt: Windows hat in den letzten 24 Stunden bereits einen erstellt.', 'No new restore point: Windows already created one in the last 24 hours.'
        'Keine Geräte mit Treiberproblemen gefunden.', 'No devices with driver problems found.'
        'Keine inkompatiblen Treiber gefunden.', 'No incompatible drivers found.'
        'Lautstärke auf 30 % stellen', 'Set the volume to 30 %'
        'Lege Verknüpfung an', 'Creating shortcut'
        'Microsoft-Katalog: keine neueren Versionen gefunden.', 'Microsoft catalog: no newer versions found.'
        'NVIDIA hat keinen passenden Treiber gemeldet.', 'NVIDIA reported no matching driver.'
        'Nach dem Spielen dieses Werkzeug noch einmal starten - dann wird alles zurückgestellt.', 'Start this tool again after gaming - everything is then restored.'
        'Netzwerkeinstellungen zurücksetzen?', 'Reset the network settings?'
        'Nichts zu bereinigen.', 'Nothing to clean up.'
        'Nichts zu installieren.', 'Nothing to install.'
        'Nichts zu laden. Die Hinweise aus dem Microsoft-Katalog stehen oben.', 'Nothing to download. The notes from the Microsoft catalog are listed above.'
        'Nummer der Sicherung (Eingabetaste = neueste)', 'Number of the backup (Enter = newest)'
        'Programme mit dem größten Speicherverbrauch:', 'Programs using the most memory:'
        'Prüfe alle Treiberdateien gegen die Regeln der Kernisolierung ...', 'Checking all driver files against the core isolation rules ...'
        'Reparatur starten (die Verbindung bricht dabei kurz ab)?', 'Start the repair (the connection drops briefly)?'
        'Reparatur trotzdem versuchen?', 'Try the repair anyway?'
        'Solange solche Treiber installiert sind, lässt sich die Speicher-Integrität in Windows-Sicherheit nicht einschalten.', 'While such drivers are installed, memory integrity cannot be turned on in Windows Security.'
        'Spiel-Beschleunigung ausgeschaltet.', 'Game boost switched off.'
        'Spiel-Beschleunigung einschalten?', 'Switch on the game boost?'
        'Spiele Treiber ein (kann einige Minuten dauern)', 'Restoring drivers (may take a few minutes)'
        'Spielmodus von Windows einschalten', 'Turn on Windows game mode'
        'Starte den NVIDIA-Installer - bitte dem Assistenten folgen ...', 'Starting the NVIDIA installer - please follow the wizard ...'
        'Stummschaltung des Standardgeräts aufheben', 'Unmute the default device'
        'TCP/IP zurücksetzen', 'Reset TCP/IP'
        'Winsock zurücksetzen', 'Reset Winsock'
        'Treiber aus dieser Sicherung einspielen?', 'Restore the drivers from this backup?'
        'Trotzdem DNS-Zwischenspeicher leeren und die Adresse erneuern?', 'Flush the DNS cache and renew the address anyway?'
        'Unbenutzte Pakete lassen sich entfernen. Wird das zugehörige Gerät später wieder angeschlossen,', 'Unused packages can be removed. If the device is connected again later,'
        'braucht es dann einen neuen (aktuelleren) Treiber.', 'it will then need a new (more recent) driver.'
        'Unerwartete Kennung im Katalog.', 'Unexpected identifier in the catalog.'
        'Ursache: Der Grafikkarte fehlt ihr Treiber - ohne ihn bietet Windows nur niedrige Auflösungen an.', 'Cause: the graphics card lacks its driver - without it Windows only offers low resolutions.'
        'Vermutlich ist der Computerschutz für Laufwerk C: abgeschaltet. Die Installation läuft trotzdem weiter.', 'System protection for drive C: is probably turned off. The installation continues anyway.'
        'Vorher dort alles Ungespeicherte sichern.', 'Save any unsaved work there first.'
        'Wiederherstellungspunkt erstellt.', 'Restore point created.'
        'Wiederherstellungspunkt erstellen', 'Create a restore point'
        'Windows Update: alle Treiber sind aktuell.', 'Windows Update: all drivers are up to date.'
        'Windows übernimmt daraus nur Treiber, die besser passen als die installierten. Ein neuerer Treiber', 'Windows only takes drivers from it that fit better than the installed ones. A newer driver'
        'wird so nicht ersetzt - um ein Update zurückzunehmen, den Wiederherstellungspunkt verwenden.', 'is not replaced this way - to undo an update, use the restore point.'
        'Wirkt das Bild trotzdem unscharf oder zu groß, liegt es meist an der Skalierung.', 'If the picture still looks blurry or too large, scaling is usually the reason.'
        'noch offen - das Programm wartet vermutlich auf eine Antwort (Speichern?). Es wurde nicht beendet.', 'still open - the program is probably waiting for an answer (save?). It was not terminated.'
        'Suche im Microsoft-Katalog nach Treibern für Geräte ohne Treiber ...', 'Searching the Microsoft catalog for drivers for devices without one ...'
        'Suche passende Treiber bei Windows Update ...', 'Searching Windows Update for matching drivers ...'
        'Vor einer Installation prüfen, ob der Eintrag zu Gerät und Windows-Version passt.', 'Before installing, check that the entry matches the device and the Windows version.'
        'Windows Update hat für diese Geräte keinen Treiber.', 'Windows Update has no driver for these devices.'
        'Treibersuche mit Installation starten', 'Start the driver search with installation'
        'Kein eigenes Treiberpaket - gehört zu Windows oder zu einem installierten Programm.', 'No driver package of its own - belongs to Windows or to an installed program.'
        'Wird gerade verwendet - beim Hersteller nach einer neueren Version suchen.', 'Currently in use - look for a newer version at the vendor.'
        'Enthält keinen Treibercode - ein Update ändert voraussichtlich nur den Eintrag im Geräte-Manager.', 'Contains no driver code - an update will probably only change the entry in Device Manager.'
        '(liegt nur im Windows-Update-Cache, die Kopie in den Zielordner ist fehlgeschlagen)', '(only in the Windows Update cache, copying to the target folder failed)'
        'Achtung: Von einem früheren Update steht noch ein Neustart aus.', 'Note: a restart from an earlier update is still pending.'
        'eingeschaltet', 'on'
        'ausgeschaltet', 'off'

        # --- Sprache und Prüfbericht als Datei
        'Deutsch', 'Deutsch'
        'English', 'English'
        'Prüfungen', 'Checks'
        'Dieser PC', 'This PC'
        'Jede Prüfung des Berichts ist gelaufen.', 'Every check in this report has been run.'
        'Der Bericht gibt wieder, was Windows und die Tests von PulsRig zum genannten Zeitpunkt gemeldet haben. Er ist kein Gutachten und keine Garantie: Fehler, die nur selten oder erst nach Stunden auftreten, kann eine kurze Prüfung übersehen.', 'This report reflects what Windows and the PulsRig tests reported at the stated time. It is neither an expert opinion nor a guarantee: a short check can miss errors that occur only rarely or after hours.'
        '1 Fehler gefunden', '1 error found'
        '1 Auffälligkeit', '1 finding'
        'Bisher keine Auffälligkeiten', 'No findings so far'
        'Alle Prüfungen bestanden', 'All checks passed'
        '1 Prüfung steht noch aus', '1 check is still open'
        '1 Prüfung steht noch aus.', '1 check is still open.'
        'Fehler', 'Error'
        'Windows meldet alle als gesund.', 'Windows reports all as healthy.'
        'Windows meldet es als gesund.', 'Windows reports it as healthy.'
        'Störungen im Ereignisprotokoll nicht lesbar', 'faults in the event log not readable'
        'Störungen im Ereignisprotokoll nicht lesbar.', 'faults in the event log not readable.'
        'Das ist unbedenklich.', 'That is no concern.'
        'Das ist viel: Lüfter, Staub und die Luft im Gehäuse prüfen.', 'That is high: check fans, dust and airflow in the case.'
        'Zu heiß: Kühlung, Lüfter und Staub prüfen.', 'Too hot: check cooling, fans and dust.'
        'zu heiß', 'too hot'
        'kaum Speicher freigemacht', 'hardly any memory freed'
        # --- Hintergrund und Helfer
        'Hintergrund', 'Background'
        'Helfer neben der Uhr', 'Helper next to the clock'
        'Startet mit Windows und bleibt klein neben der Uhr: Boost per Rechtsklick, Meldung bei neuen Treibern.', 'Starts with Windows and stays small next to the clock: boost via right-click, a message when new drivers appear.'
        'Einmal pro Woche nach Treibern sehen', 'Check for drivers once a week'
        'Der Helfer fragt im Hintergrund nach und meldet sich nur, wenn es neuere gibt.', 'The helper checks in the background and only speaks up when there are newer ones.'
        'Boost automatisch bei Spielen', 'Automatic boost for games'
        'Startet eines der Spiele aus Boost → Einrichten → Spiele, schaltet der Helfer den Boost ein und danach wieder aus. Programme schließt er dabei nicht.', 'When one of the games from Boost → Set up → Games starts, the helper switches the boost on and off again afterwards. It does not close programs.'
        'Zustand', 'Status'
        'Den Helfer gibt es nur im installierten Programm.', 'The helper is only available in the installed program.'
        'Ausgeschaltet.', 'Off.'
        'Läuft und startet mit Windows - mit Adminrechten, Boost automatisch ist möglich.', 'Running and starts with Windows - with admin rights, automatic boost is possible.'
        'Startet mit Windows - mit Adminrechten, Boost automatisch ist möglich.', 'Starts with Windows - with admin rights, automatic boost is possible.'
        'Läuft ohne Adminrechte: Boost automatisch ist so nicht möglich. PulsRig einmal als Admin starten und den Helfer neu einschalten.', 'Running without admin rights: automatic boost is not possible this way. Start PulsRig as admin once and switch the helper on again.'
        'Startet mit Windows, ohne Adminrechte: Boost automatisch ist so nicht möglich.', 'Starts with Windows, without admin rights: automatic boost is not possible this way.'
        'Spiele', 'Games'
        'SPIELE, DIE WINDOWS KENNT', 'GAMES WINDOWS KNOWS'
        'Boost automatisch ist ausgeschaltet', 'Automatic boost is off'
        'Einschalten unter Einstellungen → Hintergrund. Die Auswahl hier gilt dann sofort.', 'Turn it on under Settings → Background. The selection here then applies right away.'
        'läuft gerade', 'running now'
        'gemerkt, Windows kennt es nicht mehr', 'remembered, Windows no longer knows it'
        'Windows kennt auf diesem PC noch keine Spiele', 'Windows does not know any games on this PC yet'
        'Ein Spiel erscheint hier, sobald Windows es einmal als Spiel erkannt hat.', 'A game appears here once Windows has recognized it as a game.'
        '1 Spiel', '1 game'

        # --- Autostart und Speicherplatz
        'Autostart', 'Startup apps'
        'Programme, die mit Windows starten', 'Programs that start with Windows'
        'Programme, die mit Windows starten.', 'Programs that start with Windows.'
        'Programme, die beim Anmelden mit Windows starten', 'Programs that start when you sign in to Windows'
        'Lese den Autostart …', 'Reading startup apps …'
        'STARTET BEIM ANMELDEN', 'STARTS AT SIGN-IN'
        'Beim Anmelden startet kein Programm von selbst', 'No program starts on its own at sign-in'
        'Ein Haken heißt: startet mit Windows. Wirkt ab der nächsten Anmeldung.', 'A tick means: starts with Windows. Takes effect at the next sign-in.'
        'Einträge für alle Benutzer lassen sich nur mit Adminrechten umschalten', 'Entries for all users can only be switched with admin rights'
        'Benutzer', 'This user'
        'Alle Benutzer', 'All users'
        'Programmdatei fehlt', 'program file missing'
        'an', 'on'
        'aus', 'off'
        '1 Eintrag', '1 entry'
        'Speicherplatz freigeben', 'Free up disk space'
        'Temporäre Dateien, Shader-Cache und alte Treiberpakete löschen', 'Delete temporary files, shader cache and old driver packages'
        'Temporäre Dateien, Shader-Cache und alte Treiberpakete löschen.', 'Delete temporary files, shader cache and old driver packages.'
        'Shader-Cache von Grafiktreibern und Steam', 'Shader cache of graphics drivers and Steam'
        'Lese den Treiberspeicher von Windows ...', 'Reading the Windows driver store ...'
        'Alte Treiberpakete', 'Old driver packages'
        'Alte Treiberpakete (nur mit Adminrechten)', 'Old driver packages (admin rights only)'
        'Nicht angefasst werden: Papierkorb, gesicherte Treiber, Speicherabbilder nach Bluescreens und je Treiber die zwei neuesten Fassungen.', 'Not touched: recycle bin, backed-up drivers, memory dumps after bluescreens and the two newest versions of each driver.'
        'Shader-Cache: Spiele ruckeln danach beim ersten Start kurz, während sie ihre Shader neu übersetzen. Lohnt sich vor allem nach einem neuen Grafiktreiber.', 'Shader cache: games stutter briefly on their first start afterwards while they recompile their shaders. Mostly worth it after a new graphics driver.'
        'Lösche: Shader-Cache', 'Deleting: shader cache'
        'Alte Treiberpakete (die zwei neuesten Fassungen jedes Treibers bleiben):', 'Old driver packages (the two newest versions of each driver stay):'
        'Grafik', 'Graphics'
        'Netzwerk', 'Network'
        'Eingabegerät', 'Input device'
        'Softwarekomponente', 'Software component'
        'Erweiterung', 'Extension'
        'Temporäre Dateien und alte Downloads löschen', 'Delete temporary files and old downloads'
        'Temporäre Dateien und alte Downloads löschen.', 'Delete temporary files and old downloads.'
        'Temporäre Dateien', 'Temporary files'
        'Dienste, Stummschaltung und Ausgabe prüfen', 'Check services, mute state and output'
        'Dienste, Stummschaltung und Ausgabe prüfen.', 'Check services, mute state and output.'
        'Temporäre Dateien von Windows', 'Windows temporary files'
        'Alte Downloads von Windows Update', 'Old Windows Update downloads'
        'Fehlerberichte von Windows', 'Windows error reports'
        'Von PulsRig geladene Installer', 'Installers downloaded by PulsRig'
        'Suche, was sich gefahrlos löschen lässt ...', 'Looking for what can be deleted safely ...'
        'Nicht angefasst werden: Papierkorb, gesicherte Treiber und Speicherabbilder nach Bluescreens.', 'Not touched: recycle bin, backed-up drivers and memory dumps after bluescreens.'
        'Einträge nicht mehr angeschlossener Hardware entfernen.', 'Remove entries of hardware that is no longer connected.'
        '1 Programm geschlossen', '1 program closed'
        '1 Dienst angehalten', '1 service stopped'
        'viel – Kühlung prüfen', 'high – check cooling'

        # --- Monate (Überschriften im Treiberverlauf)
        'JANUAR', 'JANUARY'
        'FEBRUAR', 'FEBRUARY'
        'MÄRZ', 'MARCH'
        'APRIL', 'APRIL'
        'MAI', 'MAY'
        'JUNI', 'JUNE'
        'JULI', 'JULY'
        'AUGUST', 'AUGUST'
        'SEPTEMBER', 'SEPTEMBER'
        'OKTOBER', 'OCTOBER'
        'NOVEMBER', 'NOVEMBER'
        'DEZEMBER', 'DECEMBER'
    )
    Patterns = @(
        # --- Ping-Test
        @{ R = '^Internet (.+)$'; F = 'Internet {T:1}' }
        @{ R = '^Router (.+ ms)$'; F = 'Router {T:1}' }
        @{ R = '^(\d+) ms$'; F = '$1 ms' }
        @{ R = '^(.+) \(Internet\)$'; F = '$1 (internet)' }
        @{ R = '^Keine Antwort von (.+)$'; F = 'No answer from $1' }
        @{ R = '^Schnitt (\d+) ms · schnellste (\d+) · langsamste (\d+) · Schwankung (\d+) ms · (\d+) % verloren$'; F = 'Average $1 ms · fastest $2 · slowest $3 · jitter $4 ms · $5 % lost' }
        @{ R = '^Zu Hause stabil, ins Internet (\d+) ms ohne nennenswerte Schwankung\. Das reicht auch für schnelle Shooter\.$'; F = 'Stable at home, $1 ms to the internet without notable jitter. Good enough even for fast shooters.' }
        # --- Monitor-Test
        @{ R = '^(\d+) von (\d+): (.+)$'; F = '$1 of $2: {T:3}' }
        @{ R = '^(\d+)\. (.+)$'; F = '$1. {T:2}' }
        @{ R = '^(\d+) × (\d+) mit (\d+) Hz – er kann aber (\d+) Hz\. In den Anzeigeeinstellungen umstellen\.$'; F = '$1 × $2 at $3 Hz – but it can do $4 Hz. Change it in the display settings.' }
        @{ R = '^(\d+) × (\d+) mit (\d+) Hz, der höchsten Rate bei dieser Auflösung$'; F = '$1 × $2 at $3 Hz, the highest rate at this resolution' }
        @{ R = '^(.+) \(Hauptbildschirm\)$'; F = '$1 (main display)' }
        # --- Akku-Bericht
        @{ R = '^Akku (\d+) %$'; F = 'Battery $1 %' }
        @{ R = '^Zustand (\d+) %$'; F = 'Health $1 %' }
        @{ R = '^(\d+) Ladezyklen$'; F = '$1 charge cycles' }
        @{ R = '^Fasst noch (\d+) % von neu$'; F = 'Holds $1 % of new' }
        @{ R = '^Der Akku ist gut in Schuss\. Heute (.+) mWh, neu waren es (.+) mWh\.$'; F = 'The battery is in good shape. Today $1 mWh, new it was $2 mWh.' }
        @{ R = '^Der Akku hat merklich nachgelassen; das ist nach einigen Jahren normal\. Heute (.+) mWh, neu waren es (.+) mWh\.$'; F = 'The battery has noticeably declined; that is normal after a few years. Today $1 mWh, new it was $2 mWh.' }
        @{ R = '^Der Akku fasst nur noch wenig\. Ein Tausch lohnt sich, wenn das Notebook oft ohne Netzteil laufen soll\. Heute (.+) mWh, neu waren es (.+) mWh\.$'; F = 'The battery holds little anymore. A replacement is worth it if the laptop often runs without the adapter. Today $1 mWh, new it was $2 mWh.' }
        @{ R = '^Gerade (\d+) % geladen$'; F = 'Charged $1 % right now' }
        @{ R = '^Hält etwa (\d+) Std\. (\d+) Min\.$'; F = 'Lasts about $1 h $2 min' }
        @{ R = '^Hält etwa (\d+) Min\.$'; F = 'Lasts about $1 min' }
        @{ R = '^Schätzung von Windows bei voller Ladung und üblicher Nutzung\. Neu wären es etwa (\d+) Std\. (\d+) Min\. gewesen\.$'; F = 'Windows estimate at full charge and typical use. New it would have been about $1 h $2 min.' }
        @{ R = '^Akku-Zustand: (.+)$'; F = 'Battery health: $1' }
        # --- Was ist los?
        @{ R = '^(\d+) von 100$'; F = '$1 of 100' }
        @{ R = '^(\d+) offen$'; F = '$1 open' }
        @{ R = '^C: (\d+) % belegt$'; F = 'C: $1 % used' }
        @{ R = '^Liegt auf (.+), einer Festplatte \(HDD\)\. Auf eine SSD verschoben lädt es schneller und ruckelt weniger beim Nachladen\.$'; F = 'On $1, a hard disk (HDD). Moved to an SSD it loads faster and stutters less while streaming in.' }
        @{ R = '^Liegt auf (.+), einer schnellen NVMe-SSD$'; F = 'On $1, a fast NVMe SSD' }
        @{ R = '^Liegt auf (.+), einer SSD$'; F = 'On $1, an SSD' }
        @{ R = '^Liegt auf unbekanntes Laufwerk$'; F = 'On an unknown drive' }
        @{ R = '^Liegt auf (.+)$'; F = 'On $1' }
        # --- Aussehen Nacht Puls
        @{ R = '^(\d+) Tipps$'; F = '$1 tips' }
        @{ R = '^(\d+) von (\d+) gut$'; F = '$1 of $2 good' }
        # --- Zahlen mit Wort
        @{ R = '^1 Programm$'; F = '1 program' }
        @{ R = '^(\d+) Programme$'; F = '$1 programs' }
        @{ R = '^1 Dienst$'; F = '1 service' }
        @{ R = '^(\d+) Dienste$'; F = '$1 services' }
        @{ R = '^(\d+) weitere$'; F = '$1 more' }
        @{ R = '^1 Laufwerk$'; F = '1 drive' }
        @{ R = '^(\d+) Laufwerke$'; F = '$1 drives' }
        @{ R = '^1 Riegel$'; F = '1 module' }
        @{ R = '^(\d+) Riegel$'; F = '$1 modules' }
        @{ R = '^(\d+) GB · (\d+) Riegel$'; F = '$1 GB · $2 modules' }
        @{ R = '^1 Hinweis$'; F = '1 note' }
        @{ R = '^(\d+) Hinweise$'; F = '$1 notes' }
        @{ R = '^1 Gerätefehler$'; F = '1 device error' }
        @{ R = '^(\d+) Gerätefehler$'; F = '$1 device errors' }
        @{ R = '^1 neuerer Treiber$'; F = '1 newer driver' }
        @{ R = '^(\d+) neuere Treiber$'; F = '$1 newer drivers' }
        @{ R = '^(\d+) neuere Treiber gefunden$'; F = '$1 newer drivers found' }
        @{ R = '^(\d+) neuere$'; F = '$1 newer' }
        @{ R = '^(\d+) aktuell$'; F = '$1 up to date' }
        @{ R = '^(\d+) nicht geprüft$'; F = '$1 not checked' }
        @{ R = '^(\d+) installiert$'; F = '$1 installed' }
        @{ R = '^(\d+) ausgewählt$'; F = '$1 selected' }
        @{ R = '^(\d+) ausgewählte aktualisieren$'; F = 'Update $1 selected' }
        @{ R = '^(\d+) Treiber$'; F = '$1 drivers' }
        @{ R = '^(\d+) Treiberpakete$'; F = '$1 driver packages' }
        @{ R = '^(\d+) Hersteller$'; F = '$1 vendors' }
        @{ R = '^(\d+) Treiber werden heruntergeladen und installiert\.$'; F = '$1 drivers will be downloaded and installed.' }
        @{ R = '^(\d+) Komponenten sind ausgewählt\.$'; F = '$1 components are selected.' }
        @{ R = '^1 Komponente fehlt$'; F = '1 component missing' }
        @{ R = '^(\d+) Komponenten fehlen$'; F = '$1 components missing' }
        @{ R = '^(\d+) Dateien vorhanden$'; F = '$1 files present' }
        @{ R = '^1 Minute$'; F = '1 minute' }
        @{ R = '^(\d+) Minuten$'; F = '$1 minutes' }
        @{ R = '^1 EINTRAG$'; F = '1 ENTRY' }
        @{ R = '^(\d+) EINTRÄGE$'; F = '$1 ENTRIES' }
        @{ R = '^1 auffällig$'; F = '1 flagged' }
        @{ R = '^(\d+) auffällig$'; F = '$1 flagged' }
        @{ R = '^(\d+) offen$'; F = '$1 open' }
        @{ R = '^(\d+) gut$'; F = '$1 good' }
        @{ R = '^(\d+) in Ordnung$'; F = '$1 OK' }
        @{ R = '^(\d+) Kerne, (\d+) Threads$'; F = '$1 cores, $2 threads' }
        @{ R = '^(\d+) % belegt$'; F = '$1 % used' }
        @{ R = '^([\d.,]+ [KMGT]B) belegt von ([\d.,]+ [KMGT]B)$'; F = '$1 used of $2' }
        @{ R = '^([\d.,]+ [KMGT]B) frei von ([\d.,]+ [KMGT]B)$'; F = '$1 free of $2' }
        @{ R = '^([\d.,]+ [KMGT]B) frei$'; F = '$1 free' }
        @{ R = '^([\d.,]+ [KMGT]B) verbaut$'; F = '$1 installed' }
        @{ R = '^(\d+) GB laut Windows$'; F = '$1 GB according to Windows' }
        @{ R = '^(\d+) von (\d+) belegt$'; F = '$1 of $2 used' }
        @{ R = '^(\d+) von (\d+) Steckplätzen belegt$'; F = '$1 of $2 slots used' }
        @{ R = '^Ausbau bis (\d+) GB$'; F = 'expandable to $1 GB' }
        @{ R = '^bis ([\d,]+) GHz$'; F = 'up to $1 GHz' }
        @{ R = '^min (.+)$'; F = 'min $1' }

        # --- Ergebnisse
        @{ R = '^Aktuell \((\d+)\) – kein neuerer Treiber gefunden$'; F = 'Up to date ($1) – no newer driver found' }
        @{ R = '^Installiert \((\d+)\) – nicht geprüft$'; F = 'Installed ($1) – not checked' }
        @{ R = '^Neuere Treiber \((\d+)\)$'; F = 'Newer drivers ($1)' }
        @{ R = '^(\d+) Geräte geprüft$'; F = '$1 devices checked' }
        @{ R = '^ohne Antwort: (.+)$'; F = 'no answer: $1' }
        @{ R = '^Letzter Scan: heute um (\S+) Uhr$'; F = 'Last scan: today at $1' }
        @{ R = '^Betrifft 1 Gerät$'; F = 'Affects 1 device' }
        @{ R = '^Betrifft (\d+) Geräte$'; F = 'Affects $1 devices' }
        @{ R = '^(\d+) Geräte melden Fehler$'; F = '$1 devices report errors' }
        @{ R = '^Gerät hat einen Fehler gemeldet \(Code (\d+)\)$'; F = 'Device reported an error (code $1)' }
        @{ R = '^kein Treiber installiert \(Code (\d+)\)$'; F = 'no driver installed (code $1)' }
        @{ R = '^im Microsoft-Katalog: (.+)$'; F = 'in the Microsoft catalog: $1' }
        @{ R = '^installiert (\S+) vom (\S+)  →  neu vom (\S+)$'; F = 'installed $1 from $2  →  new from $3' }
        @{ R = '^installiert (\S+)  →  neu vom (\S+)$'; F = 'installed $1  →  new from $2' }
        @{ R = '^installiert (\S+)  →  neu (\S+) vom (\S+)$'; F = 'installed $1  →  new $2 from $3' }
        @{ R = '^installiert (\S+) vom (\S+)$'; F = 'installed $1 from $2' }
        @{ R = '^installiert (\S+)$'; F = 'installed $1' }
        @{ R = '^neu vom (\S+)$'; F = 'new from $1' }
        @{ R = '^für (.+) und (\d+) weitere$'; F = 'for $1 and $2 more' }
        @{ R = '^für (.+)$'; F = 'for {T:1}' }
        @{ R = '^• und (\d+) weitere$'; F = '• and $1 more' }
        @{ R = '^Treiber (\S+) vom (\S+)$'; F = 'Driver $1 from $2' }
        @{ R = '^Version (\S+)$'; F = 'Version $1' }
        @{ R = '^seit (\S+)$'; F = 'since $1' }
        @{ R = '^vom (\d\d\.\d\d\.\d{4})$'; F = 'from $1' }
        @{ R = '^(.+) – ALLE (\d+) VORHANDEN$'; F = '{T:1} – ALL $2 PRESENT' }
        @{ R = '^(JANUAR|FEBRUAR|MÄRZ|APRIL|MAI|JUNI|JULI|AUGUST|SEPTEMBER|OKTOBER|NOVEMBER|DEZEMBER) (\d{4})$'; F = '{T:1} $2' }
        @{ R = '^Programm: (.+)$'; F = 'Program: $1' }
        @{ R = '^Ziel: (.+)$'; F = 'Target: $1' }
        @{ R = '^Zielordner: (.+)$'; F = 'Target folder: $1' }

        # --- Hardware
        @{ R = '^erstellt um (\S+) Uhr$'; F = 'created at $1' }
        @{ R = '^Stand: (.+) Uhr$'; F = 'As of $1' }
        @{ R = '^(\d\d\.\d\d\.\d{4} \d\d:\d\d) Uhr$'; F = '$1' }
        @{ R = '^Gespeichert als (.+)$'; F = 'Saved as $1' }
        @{ R = '^Gespeichert auf dem Desktop: (.+)$'; F = 'Saved to the desktop: $1' }
        @{ R = '^Gespeichert: (.+)$'; F = 'Saved: $1' }
        @{ R = '^Prozessor höchstens (\d+) °C(\.?)$'; F = 'Processor max. $1 °C$2' }
        @{ R = '^CPU (\d+) · GPU (\d+) °C$'; F = 'CPU $1 · GPU $2 °C' }
        @{ R = '^Grafikkarte höchstens (\d+) °C im Stabilitätstest\. (.+) Die Temperatur des Prozessors gibt Windows nicht heraus\.$'; F = 'Graphics card max. $1 °C in the stability test. {T:2} Windows does not provide the processor temperature.' }
        @{ R = '^Grafikkarte höchstens (\d+) °C im Stabilitätstest\. (.+)$'; F = 'Graphics card max. $1 °C in the stability test. {T:2}' }
        @{ R = '^Prozessor höchstens (\d+) °C im Stabilitätstest\. (.+)$'; F = 'Processor max. $1 °C in the stability test. {T:2}' }
        @{ R = '^Der Prozessor hat (\d+) °C erreicht\. Kühler, Wärmeleitpaste und Lüfter prüfen\.$'; F = 'The processor reached $1 °C. Check the cooler, thermal paste and fans.' }
        @{ R = '^Benchmark: (\S+) Punkte$'; F = 'Benchmark: $1 points' }
        @{ R = '^(\S+) Punkte$'; F = '$1 points' }
        @{ R = '^1 Kern: (\S+) Punkte$'; F = '1 core: $1 points' }
        @{ R = '^Füllrate (\S+) Gpx/s$'; F = 'Fill rate $1 Gpx/s' }
        @{ R = '^Wartezeit (\S+) ns$'; F = 'Latency $1 ns' }
        @{ R = '^(\w): lesen$'; F = '$1: read' }
        @{ R = '^schreiben (\S+) MB/s$'; F = 'write $1 MB/s' }
        @{ R = '^wie um (\d\d:\d\d) Uhr$'; F = 'same as at $1' }
        @{ R = '^(\S+) % besser als um (\d\d:\d\d) Uhr$'; F = '$1 % better than at $2' }
        @{ R = '^(\S+) % schlechter als um (\d\d:\d\d) Uhr$'; F = '$1 % worse than at $2' }
        @{ R = '^Besser als um (\d\d:\d\d) Uhr: (.+)$'; F = 'Better than at $1: $2' }
        @{ R = '^Schlechter als um (\d\d:\d\d) Uhr: (.+)$'; F = 'Worse than at $1: $2' }
        @{ R = '^Alles wie um (\d\d:\d\d) Uhr\.$'; F = 'Everything as at $1.' }
        @{ R = '^wie am (.+)$'; F = 'same as on $1' }
        @{ R = '^(\S+) % besser als am (.+)$'; F = '$1 % better than on $2' }
        @{ R = '^(\S+) % schlechter als am (.+)$'; F = '$1 % worse than on $2' }
        @{ R = '^Letzter Lauf: (.+) Uhr$'; F = 'Last run: $1' }
        @{ R = '^Läuft – (\d+) %$'; F = 'Running – $1 %' }
        @{ R = '^Laufwerk (\w): schreiben und lesen$'; F = 'Drive $1: writing and reading' }
        @{ R = '^Besser als am ([^:]+): (.+)$'; F = 'Better than on $1: $2' }
        @{ R = '^Schlechter als am ([^:]+): (.+)$'; F = 'Worse than on $1: $2' }
        @{ R = '^Alles wie am (.+)\.$'; F = 'Everything as on $1.' }
        @{ R = '^Seitdem: (.+)$'; F = 'Since then: $1' }
        @{ R = '^Prozessor bis (\d+) °C$'; F = 'Processor up to $1 °C' }
        @{ R = '^Grafikkarte bis (\d+) °C(\.?)$'; F = 'Graphics card up to $1 °C$2' }
        @{ R = '^Der Prozessor wurde (\d+) °C wärmer als damals\.$'; F = 'The processor got $1 °C warmer than back then.' }
        @{ R = '^Die Grafikkarte wurde (\d+) °C wärmer als damals\.$'; F = 'The graphics card got $1 °C warmer than back then.' }
        @{ R = '^(\d+) von höchstens 30 Läufen gespeichert$'; F = '$1 of at most 30 runs saved' }
        @{ R = '^Prozessor (\S+) \(1 Kern (\S+)\)$'; F = 'Processor $1 (1 core $2)' }
        @{ R = '^Grafik (\S+)$'; F = 'Graphics $1' }
        @{ R = '^Speicher (\S+) GB/s, (\S+) ns$'; F = 'Memory $1 GB/s, $2 ns' }
        @{ R = '^Prozessor im Schnitt (\d+) °C, höchstens (\d+) °C$'; F = 'Processor $1 °C on average, at most $2 °C' }
        @{ R = '^Grafikkarte im Schnitt (\d+) °C, höchstens (\d+) °C(\.?)$'; F = 'Graphics card $1 °C on average, at most $2 °C$3' }
        @{ R = '^(\d+) Minuten lief der Prozessor an seiner Temperaturgrenze\.$'; F = 'For $1 minutes the processor ran at its temperature limit.' }
        @{ R = '^(\d+) Minuten war die Grafikkarte über 83 °C – dort beginnen viele zu drosseln\.$'; F = 'For $1 minutes the graphics card was above 83 °C – many start throttling there.' }
        @{ R = '^Die Grafikkarte hat unter Last in (\d+) % der Zeit deutlich weniger Takt gehabt als sonst: Sie drosselt, meist wegen Hitze oder Strombegrenzung\.$'; F = 'Under load the graphics card ran at a clearly lower clock than usual $1 % of the time: it throttles, mostly because of heat or its power limit.' }
        @{ R = '^Der Prozessor hat unter Last in (\d+) % der Zeit deutlich weniger Takt gehabt als sonst\.$'; F = 'Under load the processor ran at a clearly lower clock than usual $1 % of the time.' }
        @{ R = '^(\d+):(\d\d) Std\.$'; F = '$1:$2 h' }
        @{ R = '^(\d+) Min\.$'; F = '$1 min' }
        @{ R = '^(\d+) von höchstens 30 Sitzungen gespeichert$'; F = '$1 of at most 30 sessions saved' }
        @{ R = '^diese läuft gerade$'; F = 'this one is running right now' }
        @{ R = '^Sobald eines der gewählten Spiele läuft \((.+)\), schreibt der Helfer alle 5 Sekunden mit\. Für alles andere: Rechtsklick auf das Symbol neben der Uhr → Temperaturen aufzeichnen\.$'; F = 'As soon as one of the selected games runs ($1), the helper records every 5 seconds. For anything else: right-click the icon next to the clock → Record temperatures.' }
        @{ R = '^(\w): Festplatte \(HDD\): lädt langsamer, beim Nachladen sind Ruckler möglich$'; F = '$1: hard disk (HDD): loads slower, stutters possible while streaming' }
        @{ R = '^(\w): NVMe-SSD$'; F = '$1: NVMe SSD' }
        @{ R = '^(\w): SSD$'; F = '$1: SSD' }
        @{ R = '^zuletzt gespielt (\S+) \((.+)\)$'; F = 'last played on $1 ($2)' }
        @{ R = '^(\d+) Spiele$'; F = '$1 games' }
        @{ R = '^Alle (\d+) Spiele einzeln prüfen$'; F = 'Check all $1 games one by one' }
        @{ R = '^Grafikkarte: (.+)$'; F = 'Graphics card: {T:1}' }
        @{ R = '^Prozessor: (.+)$'; F = 'Processor: {T:1}' }
        @{ R = '^Erst (\d+) Messpunkte\. Der Vergleich beginnt ab vier, aus Spielsitzungen ab 15 Minuten oder Stabilitätstests ab 5 Minuten\.$'; F = 'Only $1 data points. The comparison starts at four, from game sessions of 15 minutes or more or stability tests of 5 minutes or more.' }
        @{ R = '^(\d+) Messpunkte seit dem (\S+)\. Verglichen wird ab drei Wochen Abstand, ab dem (\S+)\.$'; F = '$1 data points since $2. Comparison starts after three weeks, from $3.' }
        @{ R = '^An der Temperaturgrenze hält er jetzt im Schnitt (\S+) MHz, anfangs \((\S+)\) (\S+) MHz\.$'; F = 'At its temperature limit it now holds $1 MHz on average, at first ($2) $3 MHz.' }
        @{ R = '^Das sind (\d+) % weniger: Die Kühlung schafft weniger als früher\.$'; F = 'That is $1 % less: the cooling manages less than before.' }
        @{ R = '^Unter Last jetzt im Schnitt (\d+) °C bei (\S+) W, anfangs \((\S+)\) (\d+) °C bei (\S+) W\.$'; F = 'Under load now $1 °C on average at $2 W, at first ($3) $4 °C at $5 W.' }
        @{ R = '^Bei gleicher Leistung (\d+) °C wärmer als damals\.$'; F = 'At the same power $1 °C warmer than back then.' }
        @{ R = '^Die Lüfter drehen (\d+) % schneller als damals \((\d+) statt (\d+) %\)\.$'; F = 'The fans spin $1 % faster than back then ($2 instead of $3 %).' }
        @{ R = '^Abnutzung (\d+) %, seit dem (\S+) um (\d+) Punkte gestiegen: rund (\S+) Punkte im Jahr\. Bei diesem Tempo hält sie noch etwa (\S+) Jahre\.$'; F = 'Wear $1 %, up $3 points since $2: about $4 points a year. At this rate it lasts about $5 more years.' }
        @{ R = '^Abnutzung (\d+) %\. Für eine Schätzung braucht es einen Monat Verlauf \(bisher (\d+) Tage\)\.$'; F = 'Wear $1 %. An estimate needs a month of history (so far $2 days).' }
        @{ R = '^Abnutzung (\d+) %\. (.+)$'; F = 'Wear $1 %. {T:2}' }
        @{ R = '^~(\d+) Jahre$'; F = '~$1 years' }
        @{ R = '^(\d+) Messpunkte aus Spielsitzungen und Stabilitätstests$'; F = '$1 data points from game sessions and stability tests' }
        @{ R = '^es zählen nur deutliche Unterschiede$'; F = 'only clear differences count' }
        @{ R = '^Linker Stick in Ruhe (\d+) % aus der Mitte \((.+)\), rechter (\d+) % \((.+)\)\.$'; F = 'Left stick rests $1 % off center ({T:2}), right $3 % ({T:4}).' }
        @{ R = '^(\d+) von (\d+) Tasten getestet\.$'; F = '$1 of $2 buttons tested.' }
        @{ R = '^Controller (\d) verbunden$'; F = 'Controller $1 connected' }
        @{ R = '^Jede Taste einmal drücken: getestete werden grün umrandet \((\d+) von (\d+)\)\. Für den Drift die Sticks loslassen und „Drift messen“ wählen\.$'; F = 'Press every button once: tested ones get a green outline ($1 of $2). For drift, let go of the sticks and choose "Measure drift".' }
        @{ R = '^Abfragerate$'; F = 'Polling rate' }
        @{ R = '^aus (\d+) Meldungen$'; F = 'from $1 reports' }
        @{ R = '^(\d+) Mäuse gefunden$'; F = '$1 mice found' }
        @{ R = '^Kurz nach dem Loslassen wieder ausgelöst: (.+)\. Das ist meist ein verschlissener Schalter; tritt es öfter auf, hilft nur ein neuer Schalter oder eine neue Maus\.$'; F = 'Fired again right after release: $1. This is usually a worn switch; if it happens often, only a new switch or a new mouse helps.' }
        @{ R = '^(\d+) Klicks, keiner hat von selbst doppelt ausgelöst\.$'; F = '$1 clicks, none fired twice by itself.' }
        @{ R = '^Maus mit (\S+) Hz$'; F = 'mouse at $1 Hz' }
        @{ R = '^Maus (\S+) Hz$'; F = 'mouse $1 Hz' }
        @{ R = '^Drift (\d+) / (\d+) %$'; F = 'drift $1 / $2 %' }
        @{ R = '^kein ungewollter Doppelklick bei (\d+) Klicks$'; F = 'no unwanted double click in $1 clicks' }
        @{ R = '^ungewollte Doppelklicks: (.+) \(bei (\d+) Klicks\)$'; F = 'unwanted double clicks: {T:1} (in $2 clicks)' }
        @{ R = '^Sticks in Ruhe (\d+) % und (\d+) % aus der Mitte$'; F = 'sticks rest $1 % and $2 % off center' }
        @{ R = '^(\d+) von (\d+) Tasten getestet$'; F = '$1 of $2 buttons tested' }
        @{ R = '^getestet am (\S+)$'; F = 'tested on $1' }
        @{ R = '^(Links|Rechts|Mitte|Seite 1|Seite 2) (\d+)×$'; F = '{T:1} $2×' }
        @{ R = '^mindestens (\S+) Hz$'; F = 'at least $1 Hz' }
        @{ R = '^Maus mit mindestens (\S+) Hz$'; F = 'mouse at least $1 Hz' }
        @{ R = '^Maus ≥ (\S+) Hz$'; F = 'mouse ≥ $1 Hz' }
        @{ R = '^Bei (\d+) Klicks hat diese Taste einmal kurz nach dem Loslassen nachgeprellt: (.+)\. Das kann einmal vorkommen, etwa beim Mausrad; passiert es öfter, ist der Schalter verschlissen\.$'; F = 'In $1 clicks this button bounced once right after release: $2. That can happen once, e.g. with the wheel; if it happens more often, the switch is worn.' }
        @{ R = '^einmal nachgeprellt: (.+) \(bei (\d+) Klicks\)$'; F = 'bounced once: {T:1} (in $2 clicks)' }
        @{ R = '^Höchstens (\d+) °C$'; F = 'Max. $1 °C' }
        @{ R = '^Grafikkarte höchstens (\d+) °C(\.?)$'; F = 'Graphics card max. $1 °C$2' }
        @{ R = '^Takt bis ([\d,]+) GHz(\.?)$'; F = 'Clock up to $1 GHz$2' }
        @{ R = '^([\d.]+) Rechenproben ohne Fehler$'; F = '$1 calculations without errors' }
        @{ R = '^Läuft – (\S+) von (\S+)$'; F = 'Running – $1 of $2' }
        @{ R = '^(.+) – (Prozessor und Grafikkarte|Prozessor|Grafikkarte), (\S+) Minuten$'; F = '{T:1} – {T:2}, $3 minutes' }
        @{ R = '^Der Prozessor hat sich (\d+)-mal verrechnet\. Das deutet auf Übertaktung, zu wenig Spannung, Hitze oder defekten Arbeitsspeicher\.$'; F = 'The processor miscalculated $1 time(s). This points to overclocking, too little voltage, heat or faulty memory.' }
        @{ R = '^Der Takt ist von ([\d,]+) auf ([\d,]+) GHz eingebrochen\. .+$'; F = 'The clock speed dropped from $1 to $2 GHz. This is how the processor protects itself from overheating: check the cooler and thermal paste. On notebooks this is often normal under sustained load.' }
        @{ R = '^Die Grafikkarte hat (\d+) °C erreicht\. Kühlung, Lüfter und Staub prüfen\.$'; F = 'The graphics card reached $1 °C. Check cooling, fans and dust.' }
        @{ R = '^Die Grafikkarte ließ sich nicht belasten: (.+)$'; F = 'The graphics card could not be loaded: $1' }
        @{ R = '^Laufwerk (\d+)$'; F = 'Drive $1' }
        @{ R = '^1 Störung in 30 Tagen$'; F = '1 fault in 30 days' }
        @{ R = '^(\d+) Störungen in 30 Tagen$'; F = '$1 faults in 30 days' }
        @{ R = '^(.+): (\d+) Störungen in 30 Tagen$'; F = '$1: $2 faults in 30 days' }
        @{ R = '^(\d+) im Ereignisprotokoll von Windows, zuletzt (.+)$'; F = '$1 in the Windows event log, last on $2' }
        @{ R = '^(\d+)-mal Verbindung neu aufgebaut(\.?)$'; F = 'connection re-established $1 time(s)$2' }
        @{ R = '^Windows musste (\d+)-mal die Verbindung zu einem Laufwerk neu aufbauen$'; F = 'Windows had to re-establish the connection to a drive $1 time(s)' }
        @{ R = '^In den letzten 30 Tagen, zuletzt (.+)\. Häufige Ursachen: Kabel, Anschluss oder ein schwächelndes Laufwerk\.$'; F = 'In the last 30 days, last on $1. Common causes: cable, port or a failing drive.' }
        @{ R = '^nicht gesund laut Windows: (.+)$'; F = 'not healthy according to Windows: $1' }
        @{ R = '^Läuft etwas nicht, wie es soll, hilft diese Datei bei der Suche nach dem Grund\. Sie landet auf dem Desktop; verschickt wird nichts von allein\. Schick sie mit ein paar Worten zum Fehler an (\S+)\.$'; F = 'If something does not work as it should, this file helps find the reason. It is saved to the desktop; nothing is sent on its own. Send it with a few words about the problem to $1.' }
        @{ R = '^Mail an (\S+) geöffnet – die ZIP-Datei aus dem Ordner anhängen$'; F = 'Email to $1 opened – attach the ZIP file from the folder' }
        @{ R = '^Kein Mailprogramm gefunden\. Die Adresse (\S+) ist kopiert – im Browser eine Mail schreiben und die ZIP-Datei anhängen$'; F = 'No mail program found. The address $1 is copied – write an email in your browser and attach the ZIP file' }
        @{ R = '^1-mal aufgewacht$'; F = 'woke up once' }
        @{ R = '^(\d+)-mal aufgewacht$'; F = 'woke up $1 times' }
        @{ R = '^1-mal nachts$'; F = 'once at night' }
        @{ R = '^(\d+)-mal nachts$'; F = '$1 times at night' }
        @{ R = '^1-mal in 14 Tagen, zuletzt (.+) Uhr$'; F = 'once in 14 days, last on $1' }
        @{ R = '^(\d+)-mal in 14 Tagen, zuletzt (.+) Uhr$'; F = '$1 times in 14 days, last on $2' }
        @{ R = '^(\d+) Geräte dürfen den PC wecken$'; F = '$1 devices may wake the PC' }
        @{ R = '^Standby nach (\d+) Minuten ohne Bedienung$'; F = 'Sleep after $1 minutes of inactivity' }
        @{ R = '^Standby nach (\d+) Stunden ohne Bedienung$'; F = 'Sleep after $1 hours of inactivity' }
        @{ R = '^(.+) hält den Bildschirm an$'; F = '$1 keeps the display on' }
        @{ R = '^(.+) verhindert den Standby$'; F = '$1 prevents sleep' }
        @{ R = '^(.+) hält den Abwesenheitsmodus$'; F = '$1 holds away mode' }
        @{ R = '^(.+) arbeitet im Hintergrund weiter$'; F = '$1 keeps working in the background' }
        @{ R = '^(.+) hält den PC wach$'; F = '$1 keeps the PC awake' }
        @{ R = '^(.+) weckt den PC$'; F = '$1 wakes the PC' }
        @{ R = '^(.+) läuft mit (\d+) statt (\d+) Hz: unter „Erweiterte Anzeige“ umstellen\.$'; F = '$1 runs at $2 instead of $3 Hz: change it under “Advanced display”.' }
        @{ R = '^(.+) läuft mit der höchsten Rate, die er bei dieser Auflösung kann\.$'; F = '$1 runs at the highest rate it supports at this resolution.' }
        @{ R = '^Die Grafikkarte erreicht ihren ganzen Speicher auf einmal \((\d+) GB\)\. Das bringt in vielen neuen Spielen ein paar Prozent\.$'; F = 'The graphics card can reach all of its memory at once ($1 GB). That gains a few percent in many new games.' }
        @{ R = '^Läuft mit ([\d.,]+) statt ([\d.,]+) MHz: im BIOS XMP, DOCP oder EXPO einschalten\.$'; F = 'Runs at $1 instead of $2 MHz: enable XMP, DOCP or EXPO in the BIOS.' }
        @{ R = '^(\d+) von 100$'; F = '$1 of 100' }
        @{ R = '^Gaming-Check: (\d+) von 100$'; F = 'Gaming check: $1 of 100' }
        @{ R = '^(\d+) grün$'; F = '$1 green' }
        @{ R = '^(\d+) zu prüfen$'; F = '$1 to check' }
        @{ R = '^(\d+) Hz$'; F = '$1 Hz' }
        @{ R = '^Stand (.+) → (.+)$'; F = 'build $1 → $2' }
        @{ R = '^Grafiktreiber geändert: (.+)$'; F = 'Graphics driver changed: $1' }
        @{ R = '^Netzwerktreiber geändert: (.+)$'; F = 'Network driver changed: $1' }
        @{ R = '^Audiotreiber geändert: (.+)$'; F = 'Audio driver changed: $1' }
        @{ R = '^Speichertreiber geändert: (.+)$'; F = 'Storage driver changed: $1' }
        @{ R = '^(\S+) geändert: (.+)$'; F = '{T:1} changed: $2' }
        @{ R = '^Version (.+) → (.+)$'; F = 'version $1 → $2' }
        @{ R = '^von PulsRig am (\S+)$'; F = 'by PulsRig on $1' }
        @{ R = '^von Windows Update oder von Hand am (\S+)$'; F = 'by Windows Update or by hand on $1' }
        @{ R = '^(\d+) weitere Treiber geändert$'; F = '$1 more drivers changed' }
        @{ R = '^Neues Programm: (.+)$'; F = 'New program: $1' }
        @{ R = '^(\d+) neue Programme$'; F = '$1 new programs' }
        @{ R = '^Version (\S+)$'; F = 'version $1' }
        @{ R = '^Entfernt: (.+)$'; F = 'Removed: $1' }
        @{ R = '^(\d+) Programme entfernt$'; F = '$1 programs removed' }
        @{ R = '^Aktualisiert: (.+)$'; F = 'Updated: $1' }
        @{ R = '^(\d+) Programme aktualisiert$'; F = '$1 programs updated' }
        @{ R = '^Startet jetzt mit Windows: (.+)$'; F = 'Now starts with Windows: $1' }
        @{ R = '^(\d+) Programme starten jetzt mit Windows$'; F = '$1 programs now start with Windows' }
        @{ R = '^Startet nicht mehr mit Windows: (.+)$'; F = 'No longer starts with Windows: $1' }
        @{ R = '^(\d+) Programme starten nicht mehr mit Windows$'; F = '$1 programs no longer start with Windows' }
        @{ R = '^Abstürze seit (\S+)$'; F = 'Crashes since $1' }
        @{ R = '^1 Aussetzer oder Ausschalten$'; F = '1 dropout or shutdown' }
        @{ R = '^(\d+) Aussetzer oder Ausschalten$'; F = '$1 dropouts or shutdowns' }
        @{ R = '^(.+) und (\d+) weitere$'; F = '$1 and $2 more' }
        @{ R = '^Nichts geändert seit (\S+)$'; F = 'Nothing changed since $1' }
        @{ R = '^(\d+) weitere Änderungen$'; F = '$1 more changes' }
        @{ R = '^(\d+) Änderungen$'; F = '$1 changes' }
        @{ R = '^(\d+) Änderungen in 7 Tagen$'; F = '$1 changes in 7 days' }
        @{ R = '^Seit (\S+) merkt sich PulsRig einmal am Tag Windows-Stand, Programme, Autostart, wichtige Treiber und Energieplan\. Ab morgen steht hier, was sich seitdem geändert hat\.$'; F = 'Since $1 PulsRig records once a day the Windows build, programs, startup apps, important drivers and power plan. From tomorrow this shows what has changed since.' }
        @{ R = '^Verglichen mit dem (\S+)$'; F = 'Compared with $1' }
        @{ R = '^mitgeschrieben seit (\S+)$'; F = 'recorded since $1' }
        @{ R = '^Mitgeschrieben erst seit (\S+): verglichen mit diesem Tag$'; F = 'Recorded only since $1: compared with that day' }
        @{ R = '^Seit dem neuen (\S+) (\d+) Abstürze oder Aussetzer$'; F = 'Since the new {T:1}: $2 crashes or dropouts' }
        @{ R = '^(.+), neu seit (\S+) \(Version (\S+), vorher (\S+)\)\. In den (\d+) Tagen davor: keine\. Die vorige Fassung zurückholen\?$'; F = '$1, new since $2 (version $3, before $4). In the $5 days before: none. Restore the previous version?' }
        @{ R = '^(.+), neu seit (\S+) \(Version (\S+), vorher (\S+)\)\. In den (\d+) Tagen davor: (\d+)\. Die vorige Fassung zurückholen\?$'; F = '$1, new since $2 (version $3, before $4). In the $5 days before: $6. Restore the previous version?' }
        @{ R = '^Treiber (\S+) seit (\S+), vorher (\S+)$'; F = 'driver $1 since $2, before $3' }
        @{ R = '^Tag (\d+) von (\d+)$'; F = 'day $1 of $2' }
        @{ R = '^seitdem (\d+) Abstürze oder Aussetzer$'; F = '$1 crashes or dropouts since' }
        @{ R = '^davor (\d+) in (\d+) Tagen$'; F = 'before: $1 in $2 days' }
        @{ R = '^Probezeit: (.+)$'; F = 'Trial period: $1' }
        @{ R = '^Bluescreen: (.+)$'; F = 'Blue screen: {T:1}' }
        @{ R = '^1-mal, zuletzt (.+) Uhr$'; F = 'once, last on $1' }
        @{ R = '^(\d+)-mal, zuletzt (.+) Uhr$'; F = '$1 times, last on $2' }
        @{ R = '^Code (0x[0-9A-F]+)$'; F = 'code $1' }
        @{ R = '^zuletzt (.+) Uhr$'; F = 'last on $1' }
        @{ R = '^Zuletzt (.+) Uhr$'; F = 'Last on $1' }
        @{ R = '^Programme im Grafiktreiber abgestürzt: (.+)$'; F = 'programs crashed in the graphics driver: $1' }
        @{ R = '^Treiber (\S+) vom (\S+)$'; F = 'driver $1 from $2' }
        @{ R = '^Treiber (\S+)$'; F = 'driver $1' }
        @{ R = '^Grafiktreiber ist 1-mal ausgesetzt$'; F = 'Graphics driver dropped out once' }
        @{ R = '^Grafiktreiber ist (\d+)-mal ausgesetzt$'; F = 'Graphics driver dropped out $1 times' }
        @{ R = '^1-mal im Grafiktreiber abgestürzt$'; F = 'Crashed in the graphics driver once' }
        @{ R = '^(\d+)-mal im Grafiktreiber abgestürzt$'; F = 'Crashed in the graphics driver $1 times' }
        @{ R = '^1-mal am Ausschalter ausgemacht, der PC hing also vorher$'; F = 'switched off at the power button once, so the PC had hung' }
        @{ R = '^(\d+)-mal am Ausschalter ausgemacht, der PC hing also vorher$'; F = 'switched off at the power button $1 times, so the PC had hung' }
        @{ R = '^1-mal beim Standby$'; F = 'once during sleep' }
        @{ R = '^(\d+)-mal beim Standby$'; F = '$1 times during sleep' }
        @{ R = '^1 Hardwarefehler gemeldet$'; F = '1 hardware error reported' }
        @{ R = '^(\d+) Hardwarefehler gemeldet$'; F = '$1 hardware errors reported' }
        @{ R = '^1 Bluescreen$'; F = '1 blue screen' }
        @{ R = '^(\d+) Bluescreens$'; F = '$1 blue screens' }
        @{ R = '^1-mal ausgegangen$'; F = 'switched off once' }
        @{ R = '^(\d+)-mal ausgegangen$'; F = 'switched off $1 times' }
        @{ R = '^Grafik 1-mal ausgesetzt$'; F = 'graphics dropped out once' }
        @{ R = '^Grafik (\d+)-mal ausgesetzt$'; F = 'graphics dropped out $1 times' }
        @{ R = '^1 Vorfall$'; F = '1 incident' }
        @{ R = '^(\d+) Vorfälle$'; F = '$1 incidents' }
        @{ R = '^Sucht im Browser nach der Download-Seite für (.+)\. Dort steht die neueste Version mit Datum\.$'; F = 'Searches in the browser for the download page for $1. It lists the newest version with its date.' }
        @{ R = '^(\d+) Monate$'; F = '$1 months' }
        @{ R = '^(\d+) Jahre$'; F = '$1 years' }
        @{ R = '^1 Jahr und 1 Monat$'; F = '1 year and 1 month' }
        @{ R = '^1 Jahr und (\d+) Monate$'; F = '1 year and $1 months' }
        @{ R = '^(\d+) Jahre und 1 Monat$'; F = '$1 years and 1 month' }
        @{ R = '^(\d+) Jahre und (\d+) Monate$'; F = '$1 years and $2 months' }
        @{ R = '^(.+) alt$'; F = '{T:1} old' }
        @{ R = '^(\S+) vom (\d+\.\d+\.\d+)$'; F = '$1 from $2' }
        @{ R = '^(\d+) Riegel$'; F = '$1 modules' }
        @{ R = '^erstellt (\d+:\d+)$'; F = 'created $1' }
        @{ R = '^Störungen: keine seit (.+)$'; F = 'Faults: none since $1' }
        @{ R = '^Störungen: (\d+) in 30 Tagen, am (.+) waren es (\d+)$'; F = 'Faults: $1 in 30 days, $3 on $2' }
        @{ R = '^Störungen: (\d+) in 30 Tagen$'; F = 'Faults: $1 in 30 days' }
        @{ R = '^Temperatur: (\d+) °C, höchstens (\d+) °C$'; F = 'Temperature: $1 °C, at most $2 °C' }
        @{ R = '^Abnutzung: (\d+) %, am (.+) waren es (\d+) %$'; F = 'Wear: $1 %, $3 % on $2' }
        @{ R = '^Abnutzung: (\d+) %$'; F = 'Wear: $1 %' }
        @{ R = '^(\w): Lesen ([\d.,]+) MB/s am (.+)$'; F = '$1: read $2 MB/s on $3' }
        @{ R = '^(\w): Lesen ([\d.,]+) MB/s, bestes ([\d.,]+) MB/s$'; F = '$1: read $2 MB/s, best $3 MB/s' }
        @{ R = '^(\d+) Tage mitgeschrieben$'; F = '$1 days recorded' }
        @{ R = '^(.+) meldet einen schlechten Zustand$'; F = '$1 reports a poor health state' }
        @{ R = '^(.+) ist auffällig$'; F = '$1 shows problems' }
        @{ R = '^1 Störung in 30 Tagen, zuletzt (.+)\. Kabel und Anschluss prüfen, wichtige Daten sichern\.$'; F = '1 fault in 30 days, last on $1. Check cable and port, back up important data.' }
        @{ R = '^(\d+) Störungen in 30 Tagen, zuletzt (.+)\. Kabel und Anschluss prüfen, wichtige Daten sichern\.$'; F = '$1 faults in 30 days, last on $2. Check cable and port, back up important data.' }
        @{ R = '^(\w): ist auffällig langsam$'; F = '$1: is noticeably slow' }
        @{ R = '^Lesen ([\d.,]+) MB/s bei der letzten Messung\. Kabel und Anschluss prüfen\.$'; F = 'Read $1 MB/s in the last test. Check cable and port.' }
        @{ R = '^(\w): liest langsamer als früher$'; F = '$1: reads slower than before' }
        @{ R = '^Lesen ([\d.,]+) statt bis zu ([\d.,]+) MB/s\. Ist das Laufwerk fast voll oder läuft nebenher etwas, noch einmal messen\.$'; F = 'Read $1 instead of up to $2 MB/s. If the drive is almost full or something runs alongside, measure again.' }
        @{ R = '^(\d+) Auffälligkeiten bei den Laufwerken$'; F = '$1 drive issues' }
        @{ R = '^Lesen ([\d.,]+)$'; F = 'Read $1' }
        @{ R = '^Schreiben ([\d.,]+)$'; F = 'write $1' }
        @{ R = '^kleine Dateien ([\d.,]+) MB/s$'; F = 'small files $1 MB/s' }
        @{ R = '^am (\d+\.\d+\.) um (\d+:\d+)$'; F = 'on $1 at $2' }
        @{ R = '^heute um (\d+:\d+)$'; F = 'today at $1' }
        @{ R = '^Messung am (\S+) um (\S+) Uhr nicht möglich: (.+)$'; F = 'Measurement on $1 at $2 failed: $3' }
        @{ R = '^Messung um (\S+) Uhr nicht möglich: (.+)$'; F = 'Measurement today at $1 failed: $2' }
        @{ R = '^(\w): auffällig langsam$'; F = '$1: noticeably slow' }
        @{ R = '^Messe das Tempo von (\S+) – meist unter 20 Sekunden, bei einem gestörten Laufwerk auch Minuten …$'; F = 'Measuring the speed of $1 – usually under 20 seconds, minutes on a faulty drive …' }
        @{ R = '^([\d.,]+) MHz – voller Takt der Riegel$'; F = '$1 MHz – full rated speed of the modules' }
        @{ R = '^1 Hardwarefehler in 90 Tagen$'; F = '1 hardware error in 90 days' }
        @{ R = '^(\d+) Hardwarefehler in 90 Tagen$'; F = '$1 hardware errors in 90 days' }
        @{ R = '^Letzter Lauf am (.+) Uhr: keine Fehler gefunden\.$'; F = 'Last run on $1: no errors found.' }
        @{ R = '^Letzter Lauf am (.+) Uhr: Windows hat Speicherfehler gefunden\.$'; F = 'Last run on $1: Windows found memory errors.' }
        @{ R = '^(.+) Uhr$'; F = '$1' }
        @{ R = '^(.+) \((\d+) x (\d+) bei (\d+) Hz\)$'; F = '$1 ($2 x $3 at $4 Hz)' }
        @{ R = '^(P?[\w.]+) vom (\d\d\.\d\d\.\d{4})$'; F = '$1 from $2' }
        @{ R = '^PulsRig lädt die Setup-Datei \(([\d,]+) MB\) von GitHub, prüft sie und startet die Installation\. Das Programm schließt sich dabei und öffnet sich danach wieder\.$'; F = 'PulsRig downloads the setup file ($1 MB) from GitHub, verifies it and starts the installation. The program closes and reopens afterwards.' }
        @{ R = '^Lade die Setup-Datei: ([\d,]+) von ([\d,]+) MB$'; F = 'Downloading the setup file: $1 of $2 MB' }
        @{ R = '^PulsRig (.+), gebaut am (\S+) um (\S+) Uhr$'; F = 'PulsRig $1, built on $2 at $3' }
        # --- Dialog der Werkzeuge
        @{ R = '^\[ ok \] (.+)$'; F = '[ ok ] {T:1}' }
        @{ R = '^\[ !! \] (.+)$'; F = '[ !! ] {T:1}' }
        @{ R = '^\[Probelauf\] (.+)$'; F = '[Dry run] {T:1}' }
        @{ R = '^Dienst "(.+)" - läuft, Starttyp automatisch$'; F = 'Service "$1" - running, startup type automatic' }
        @{ R = '^Dienst "(.+)" - gestoppt$'; F = 'Service "$1" - stopped' }
        @{ R = '^Dienst anhalten: (.+)$'; F = 'Stop service: $1' }
        @{ R = '^Adapter neu starten: (.+)$'; F = 'Restart adapter: $1' }
        @{ R = '^Adapter: (.+) - verbunden, (.+)$'; F = 'Adapter: $1 - connected, $2' }
        @{ R = '^Energieplan - (.+)$'; F = 'Power plan - $1' }
        @{ R = '^Spielmodus von Windows - eingeschaltet$'; F = 'Windows game mode - on' }
        @{ R = '^Lautstärke - (\d+) %$'; F = 'Volume - $1 %' }
        @{ R = '^Ausgewählte Dienste, die gerade laufen: (.+)$'; F = 'Selected services currently running: $1' }
        @{ R = '^Gewählt: (.+)$'; F = 'Selected: {T:1}' }
        @{ R = '^(\d+) weitere$'; F = '$1 more' }
        @{ R = '^Arbeitsspeicher: ([\d,]+) von ([\d,]+) GB frei$'; F = 'Memory: $1 of $2 GB free' }
        @{ R = '^Arbeitsspeicher jetzt: ([\d,]+) GB frei \((.+) GB\)$'; F = 'Memory now: $1 GB free ($2 GB)' }
        @{ R = '^(.+?)\s{2,}vorhanden(\s.*)?$'; F = '$1    present$2' }
        @{ R = '^(.+?)\s{2,}fehlt(\s.*)?$'; F = '$1    missing$2' }
        @{ R = '^Lade und starte (.+)$'; F = 'Download and start $1' }
        @{ R = '^Sichere den Treiber von "(.+)" \((.+)\) \.\.\.$'; F = 'Backing up the driver of "$1" ($2) ...' }
        @{ R = '^Zurückspielen bei Bedarf: (.+)$'; F = 'To restore if needed: $1' }
        @{ R = '^Geräte mit Fehlern: (\d+)$'; F = 'Devices with errors: $1' }
        @{ R = '^(\d+) Geräte mit Treiber, (\d+) davon von Drittherstellern$'; F = '$1 devices with a driver, $2 of them third-party' }
        @{ R = '^Laufwerk (\w): (.+), davon (.+) frei$'; F = 'Drive $1: $2, $3 free' }
        @{ R = '^(.+): (.+), (SSD|Laufwerk) über (\w+), Zustand in Ordnung$'; F = '$1: $2, {T:3} via $4, health OK' }
        @{ R = '^Bildschirm (.+): (\d+x\d+) bei (\d+) Hz( \(Hauptbildschirm\))?$'; F = 'Display $1: $2 at $3 Hz' }
        @{ R = '^Gesamt (\d+) GB$'; F = 'Total $1 GB' }
        @{ R = '^Installiert am (\S+), läuft seit (.+)$'; F = 'Installed on $1, running since $2' }
        @{ R = '^(\d+) Kerne, (\d+) Threads, bis ([\d,]+) GHz$'; F = '$1 cores, $2 threads, up to $3 GHz' }
        @{ R = '^Mainboard:\s+(.+)$'; F = 'Mainboard:  $1' }
        @{ R = '^BIOS:\s+(\S+) vom (\S+)$'; F = 'BIOS:       $1 from $2' }
        @{ R = '^Ebenfalls ohne Antwort: (.+)\.$'; F = 'Also no answer: $1.' }
        @{ R = '^(.+\.) \((0x[0-9A-Fa-f]{8})\)$'; F = '{T:1} ($2)' }
        @{ R = '^Fehler beim Lesen: (.+)$'; F = 'Error while reading: $1' }
        @{ R = '^Fehler: (.+)$'; F = 'Error: $1' }
        @{ R = '^Geladen: (\d+)$'; F = 'Downloaded: $1' }
        @{ R = '^Installiert: (\d+)$'; F = 'Installed: $1' }
        @{ R = '^Fehlgeschlagen: (\d+)$'; F = 'Failed: $1' }
        @{ R = '^Eingeschaltet seit (.+)$'; F = 'On since $1' }
        @{ R = '^(\d+) Dienste angehalten$'; F = '$1 services stopped' }
        @{ R = '^(\d+) Programme geschlossen$'; F = '$1 programs closed' }
        @{ R = '^Ein Klick auf SCAN prüft (.+) und den Microsoft-Katalog\.$'; F = 'Click SCAN to check $1 and the Microsoft catalog.' }
        @{ R = '^Ein Klick auf SCAN prüft (.+) und (.+)\.$'; F = 'Click SCAN to check $1 and $2.' }
        @{ R = '^max (.+)$'; F = 'max $1' }
        @{ R = '^(.+) \.\.\.$'; F = '{T:1} ...' }
        @{ R = '^fehlgeschlagen \((.+)\)$'; F = 'failed ($1)' }
        @{ R = '^=== (.+) ===$'; F = '=== {T:1} ===' }
        @{ R = '^- (.+) \(Code (\d+)\), Hardware-ID: (.+)$'; F = '- $1 (code $2), hardware ID: $3' }
        @{ R = '^Deaktiviert \(im Geräte-Manager wieder einschaltbar\): (.+)$'; F = 'Disabled (can be re-enabled in Device Manager): $1' }
        @{ R = '^Derzeit unbenutzt, Treiberpaket (.+) \((.+)\)\.$'; F = 'Currently unused, driver package $1 ($2).' }
        @{ R = '^(.+): Die Suche im Katalog ist fehlgeschlagen \((.+)\)\.$'; F = '$1: the catalog search failed ($2).' }
        @{ R = '^(.+): im Katalog steht dazu kein eigener Treiber\.$'; F = '$1: the catalog has no driver of its own for it.' }
        @{ R = '^(.+): Der Treiber bietet die empfohlene Auflösung nicht an - Kabel und Anschluss prüfen\.$'; F = '$1: the driver does not offer the recommended resolution - check cable and port.' }
        @{ R = '^Die Bildschirmmodi ließen sich nicht auslesen: (.+)$'; F = 'The display modes could not be read: $1' }
        @{ R = '^Die Treibersuche ist fehlgeschlagen: (.+)$'; F = 'The driver search failed: {T:1}' }
        @{ R = '^Geschlossene Programme bitte selbst wieder starten: (.+)$'; F = 'Please restart the closed programs yourself: $1' }
        @{ R = '^Nicht gesichert \((.+) MB, zu groß für die automatische Sicherung\): (.+)$'; F = 'Not backed up ($1 MB, too large for the automatic backup): $2' }
        @{ R = '^(\d+) Einträge entfernen\??$'; F = 'Remove $1 entries?' }
        @{ R = '^Aus dem Microsoft-Katalog installieren: (.+) \(für (.+)\)$'; F = 'Install from the Microsoft catalog: $1 (for $2)' }
        @{ R = '^Treiber exportieren nach (.+)$'; F = 'Export drivers to $1' }
        @{ R = '^Treiber installieren: (.+)$'; F = 'Install driver: $1' }
        @{ R = '^(.+), die gerade laufen: (.+)$'; F = '{T:1} currently running: $2' }
        @{ R = '^(\d+) Einträge lassen sich gefahrlos entfernen \(Windows legt sie beim erneuten Anschließen neu an\):$'; F = '$1 entries can be removed safely (Windows recreates them when the device is connected again):' }
        @{ R = '^(\d+) Gerät\(e\) sind deaktiviert - das ist meist Absicht\.$'; F = '$1 device(s) are disabled - usually on purpose.' }
        @{ R = '^(.+) auf (\S+) stellen\?$'; F = 'Set $1 to $2?' }
        @{ R = '^(\d+) Gerät\(e\): Die Ursache liegt im BIOS oder an der Hardware - .+$'; F = '$1 device(s): the cause is in the BIOS or the hardware - check BIOS settings, update the BIOS, reseat the device.' }
        @{ R = '^(\d+) Gerät\(e\) brauchen nur einen Neustart des PCs \(bei USB-Geräten: ab- und wieder anstecken\)\.$'; F = '$1 device(s) only need a PC restart (for USB devices: unplug and plug in again).' }
        @{ R = '^(\d+) unbenutzte\(s\) Treiberpaket\(e\) entfernen\?$'; F = 'Remove $1 unused driver package(s)?' }
        @{ R = '^(\d+) Gerät\(e\) melden weiterhin einen Fehler:$'; F = '$1 device(s) still report an error:' }
        @{ R = '^(\d+) Gerät\(e\) melden weiter Fehler\. Aus Windows entfernen und neu erkennen lassen\?$'; F = '$1 device(s) still report errors. Remove them from Windows and let it detect them again?' }
        @{ R = '^(\d+) von (\d+) Einträgen entfernt\.$'; F = '$1 of $2 entries removed.' }
        @{ R = '^(AMD Chipsatz-Treiber|NVIDIA .+?) \((.+)\): installiert (\S+), neueste (\S+) vom (\S+) - (.+)$'; F = '$1 ($2): installed $3, latest $4 from $5 - {T:6}' }
        @{ R = '^Aktiviere (.+)$'; F = 'Enabling $1' }
        @{ R = '^Entferne (.+)$'; F = 'Removing $1' }
        @{ R = '^Schließe (.+)$'; F = 'Closing $1' }
        @{ R = '^Starte Gerät neu: (.+)$'; F = 'Restarting device: $1' }
        @{ R = '^Stelle (.+) auf (\S+)$'; F = 'Setting $1 to $2' }
        @{ R = '^Dienst wieder starten: (.+)$'; F = 'Restart service: $1' }
        @{ R = '^Energieplan auf "(.+)" stellen$'; F = 'Set the power plan to "$1"' }
        @{ R = '^Energieplan zurückstellen auf "(.+)"$'; F = 'Restore the power plan to "$1"' }
        @{ R = '^Bericht gespeichert: (.+)$'; F = 'Report saved: $1' }
        @{ R = '^Bisherige Treiber gesichert \((\d+) Paket\(e\)\): (.+)$'; F = 'Previous drivers backed up ($1 package(s)): $2' }
        @{ R = '^Das Paket ließ sich nicht entpacken \(Code (.+)\)\.$'; F = 'The package could not be unpacked (code $1).' }
        @{ R = '^Der Export ist fehlgeschlagen \(pnputil-Code (.+)\)\.$'; F = 'The export failed (pnputil code $1).' }
        @{ R = '^Die Sicherung ist fehlgeschlagen \(pnputil-Code (.+)\)\.$'; F = 'The backup failed (pnputil code $1).' }
        @{ R = '^Der Katalog antwortet nicht \((.+)\)\.$'; F = 'The catalog does not respond ($1).' }
        @{ R = '^Die Abfrage bei (AMD|NVIDIA) ist fehlgeschlagen: (.+)$'; F = 'The query at $1 failed: $2' }
        @{ R = '^Die Abfrage des Microsoft-Katalogs ist fehlgeschlagen: (.+)$'; F = 'The Microsoft catalog query failed: $1' }
        @{ R = '^Die Datei (.+) trägt keine gültige Signatur des Herstellers und wird nicht gestartet\.$'; F = 'The file $1 has no valid vendor signature and is not started.' }
        @{ R = '^Die Spiel-Beschleunigung ist seit (.+) eingeschaltet\.$'; F = 'The game boost has been on since $1.' }
        @{ R = '^Die Suche bei Windows Update ist fehlgeschlagen: (.+)$'; F = 'The Windows Update search failed: {T:1}' }
        @{ R = '^Die automatische Sicherung ist fehlgeschlagen: (.+)$'; F = 'The automatic backup failed: $1' }
        @{ R = '^Download fehlgeschlagen: (.+)$'; F = 'Download failed: $1' }
        @{ R = '^FEHLER: (.+)$'; F = 'ERROR: $1' }
        @{ R = '^Gefunden: (\d+)\s+Geladen: (\d+)\s+Installiert: (\d+)\s+Fehlgeschlagen: (\d+)$'; F = 'Found: $1   Downloaded: $2   Installed: $3   Failed: $4' }
        @{ R = '^Geladen und Signatur geprüft: (.+)$'; F = 'Downloaded and signature verified: $1' }
        @{ R = '^Geladen: (.+)$'; F = 'Downloaded: $1' }
        @{ R = '^Geräte mit Treiber: (\d+), davon (\d+) mit Treibern von Drittherstellern:$'; F = 'Devices with a driver: $1, $2 of them with third-party drivers:' }
        @{ R = '^Geräteeinträge: (\d+), davon (\d+) zu nicht mehr angeschlossener Hardware\.$'; F = 'Device entries: $1, $2 of them for hardware that is no longer connected.' }
        @{ R = '^In (.+) liegen keine Treiberpakete\.$'; F = 'There are no driver packages in $1.' }
        @{ R = '^Installiere (.+) aus dem Microsoft-Katalog$'; F = 'Installing $1 from the Microsoft catalog' }
        @{ R = '^Kernisolierung \(Speicher-Integrität\): (.+)$'; F = 'Core isolation (memory integrity): {T:1}' }
        @{ R = '^Lade NVIDIA-Treiber (.+) \((.+)\)$'; F = 'Downloading NVIDIA driver $1 ($2)' }
        @{ R = '^Microsoft-Katalog: (\d+) neuere\(s\) Paket\(e\), die Windows Update nicht anbietet \(nur Hinweis, nichts wird geladen\):$'; F = 'Microsoft catalog: $1 newer package(s) that Windows Update does not offer (note only, nothing is downloaded):' }
        @{ R = '^NVIDIA-Download abgelehnt: unerwartete Adresse (.+)$'; F = 'NVIDIA download rejected: unexpected address $1' }
        @{ R = '^NVIDIA-Download fehlgeschlagen: (.+)$'; F = 'NVIDIA download failed: $1' }
        @{ R = '^NVIDIA-Treiber (.+) liegt bereits vor: (.+)$'; F = 'NVIDIA driver $1 is already present: $2' }
        @{ R = '^Nicht installiert \(Firmware/BIOS, nur mit -IncludeFirmware\): (.+)$'; F = 'Not installed (firmware/BIOS): $1' }
        @{ R = '^Ordner nicht gefunden: (.+)$'; F = 'Folder not found: $1' }
        @{ R = '^Ordner:\s+(.+)$'; F = 'Folder: $1' }
        @{ R = '^Paket fertig: (\d+) Treiberpakete, (.+) MB$'; F = 'Package done: $1 driver packages, $2 MB' }
        @{ R = '^Protokoll: (.+)$'; F = 'Log: $1' }
        @{ R = '^Reparatur für (\d+) Gerät\(e\) versuchen \(Treiber suchen, Gerät neu starten\)\?$'; F = 'Try to repair $1 device(s) (find driver, restart device)?' }
        @{ R = '^Sicherung gespeichert: (.+)$'; F = 'Backup saved: $1' }
        @{ R = '^Sicherung: (.+) \((\d+) Treiberpakete\)$'; F = 'Backup: $1 ($2 driver packages)' }
        @{ R = '^Unangetastet bleiben (\d+) Einträge \(Bluetooth, Drucker, Netzwerk und andere, die oft nur ausgeschaltet sind\)\.$'; F = '$1 entries stay untouched (Bluetooth, printers, network and others that are often just switched off).' }
        @{ R = '^Unerwartete Adresse: (.+)$'; F = 'Unexpected address: $1' }
        @{ R = '^Wiederherstellungspunkt konnte nicht erstellt werden: (.+)$'; F = 'The restore point could not be created: $1' }
        @{ R = '^Windows Update: (\d+) neuere\(r\) Treiber gefunden:$'; F = 'Windows Update: $1 newer driver(s) found:' }
        @{ R = '^Windows meldet Code (.+)$'; F = 'Windows reports code $1' }
        @{ R = '^(.+) meldet Code (.+)$'; F = '$1 reports code $2' }
        @{ R = '^Übersprungen \(Lizenzvertrag muss in Windows Update bestätigt werden\): (.+)$'; F = 'Skipped (the license agreement must be accepted in Windows Update): $1' }
        @{ R = '^für: (.+) \(installiert (\S+) vom (\S+)\)$'; F = 'for: $1 (installed $2 from $3)' }
        @{ R = '^installiert: (.+?)\s+\|\s+neu vom: (.+?)\s+\|\s+Größe: (.+)$'; F = 'installed: $1   |   new from: $2   |   size: $3' }
        @{ R = '^Welche installieren\? Nummern mit Komma, (.+)$'; F = 'Which ones to install? Numbers separated by commas, $1' }
        @{ R = '^Verknüpfung "(.+)" auf dem Desktop anlegen \(ein Doppelklick schaltet ein und aus\)\?$'; F = 'Create the shortcut "$1" on the desktop (a double click switches on and off)?' }
        @{ R = '^(.+ Minuten), (\S+ \S+) Uhr\. (.+)$'; F = '{T:1}, $2. {T:3}' }
        @{ R = '^Richtig gesteckt \((\d+) von (\d+) Steckplätzen belegt(\)\.)?$'; F = 'Correct slots ($1 of $2 slots used$3' }
        @{ R = '^Falsch gesteckt \((\d+) von (\d+) Steckplätzen belegt(\)\.)?(.*)$'; F = 'Wrong slots ($1 of $2 slots used$3$4' }
        @{ R = '^(Dual|Single|Quad)-Channel\)\.(.*)$'; F = '$1 channel).$2' }
        @{ R = '^(\d+) Fehler gefunden$'; F = '$1 errors found' }
        @{ R = '^(\d+) Auffälligkeiten$'; F = '$1 findings' }
        @{ R = '^(\d+) Prüfungen stehen noch aus(\.?)$'; F = '$1 checks are still open$2' }
        @{ R = '^(\w): Lesen (\S+), Schreiben (\S+) MB/s( \(.+\))?(\.?)$'; F = '$1: read $2, write $3 MB/s$4$5' }
        @{ R = '^(.+) Auffällig langsam: (.+)\.$'; F = '{T:1} Noticeably slow: $2.' }
        @{ R = '^Richtig gesteckt \((.+)\)\.$'; F = 'Correct slots ({T:1}).' }
        @{ R = '^Falsch gesteckt \((.+)\)\. Umstecken: (.+)\. So läuft der Speicher langsamer, .+$'; F = 'Wrong slots ({T:1}). Move: $2. This makes the memory slower or makes the memory profile (XMP) fail; when in doubt, the mainboard manual applies.' }
        @{ R = '^umstecken: (.+)$'; F = 'move: $1' }
        @{ R = '^(\d+) in 90 Tagen von Prozessor, Speicher oder Mainboard gemeldet, zuletzt (.+) Uhr\.$'; F = '$1 reported by processor, memory or mainboard in 90 days, last on $2.' }
        @{ R = '^(.+): (\d+) Störungen in 30 Tagen\.$'; F = '$1: $2 faults in 30 days.' }
        @{ R = '^(.+), (\d+) GB, Treiber (\S+)$'; F = '$1, $2 GB, driver $3' }
        @{ R = '^AMD Chipsatz-Treiber \(Paket für (.+)\)$'; F = 'AMD chipset driver (package for $1)' }
        @{ R = '^Wiedergabegeräte - (\d+) gefunden: (.+)$'; F = 'Playback devices - $1 found: $2' }
        @{ R = '^Arbeitsspeicher frei: vorher ([\d,]+) GB, danach ([\d,]+) GB$'; F = 'Free memory: $1 GB before, $2 GB after' }
        @{ R = '^([\d,]+) GB freigemacht$'; F = '$1 GB freed' }
        @{ R = '^(\d+) Einträge$'; F = '$1 entries' }
        @{ R = '^(\d+) Spiele$'; F = '$1 games' }
        @{ R = '^Eingeschaltet für (.+) seit (.+)$'; F = 'On for $1 since $2' }
        @{ R = '^(\d+) eingeschaltet$'; F = '$1 enabled' }
        @{ R = '^(.+) startet wieder mit Windows$'; F = '$1 starts with Windows again' }
        @{ R = '^(.+) startet nicht mehr mit Windows$'; F = '$1 no longer starts with Windows' }
        @{ R = '^(.+) - ([\d,]+ [MG]B) \(nur mit Adminrechten\)$'; F = '{T:1} - $2 (admin rights only)' }
        @{ R = '^(.+) - ([\d,]+ [MG]B)$'; F = '{T:1} - $2' }
        @{ R = '^Laufwerk (\w:) hat jetzt ([\d,]+) GB frei\.$'; F = 'Drive $1 now has $2 GB free.' }
        @{ R = '^Laufwerk (\w:) hat ([\d,]+) GB frei\.$'; F = 'Drive $1 has $2 GB free.' }
        @{ R = '^([\d,]+ [MG]B) freigeben\?$'; F = 'Free $1?' }
        @{ R = '^Lösche: (.+)$'; F = 'Deleting: {T:1}' }
        @{ R = '^Freigegeben: ([\d.,]+) MB\. Gesperrte Dateien sind geblieben - sie gehören zu laufenden Programmen\.$'; F = 'Freed: $1 MB. Locked files remain - they belong to running programs.' }
        @{ R = '^Freigegeben: ([\d.,]+ [MG]B)\. Gesperrte Dateien sind geblieben - sie gehören zu laufenden Programmen\.$'; F = 'Freed: $1. Locked files remain - they belong to running programs.' }
        @{ R = '^Temporäre Dateien und alte Downloads: ([\d.,]+ [MG]B) freigeben\?$'; F = 'Temporary files and old downloads: free $1?' }
        @{ R = '^Shader-Cache löschen \(([\d.,]+ [MG]B)\)\?$'; F = 'Delete the shader cache ($1)?' }
        @{ R = '^(\d+) alte Treiberpakete entfernen \(([\d.,]+ [MG]B)\)\?$'; F = 'Remove $1 old driver packages ($2)?' }
        @{ R = '^Entferne (\d+) alte Treiberpakete$'; F = 'Removing $1 old driver packages' }
        @{ R = '^\((\d+) noch in Gebrauch, sie bleiben\)$'; F = '($1 still in use, they stay)' }
        @{ R = '^(.+) · (.+) · Version (.+) - ([\d.,]+ [MG]B)$'; F = '$1 · {T:2} · version $3 - $4' }
        @{ R = '^und (\d+) weitere$'; F = 'and $1 more' }
        @{ R = '^Der Treiberspeicher ließ sich nicht lesen \((.+)\)$'; F = 'The driver store could not be read ($1)' }
        @{ R = '^(.+) verfügbar$'; F = '$1 available' }
        @{ R = '^Bau: (.+)$'; F = 'Build: $1' }
    )
}
