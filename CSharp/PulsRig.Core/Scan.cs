// PulsRig.Core - Bausteine des Treiber-Scans, abgelöst aus Treiber-Scan.ps1: Texte für die Anzeige, Erkennung von
// Chipsatz-Geräten, Titel von Windows Update, Seiten von NVIDIA, AMD und dem Microsoft-Katalog. Abfragen (CIM,
// Windows Update, Registry), Downloads und Installation bleiben in PowerShell; hier steht, wie die Antworten gelesen
// werden. Die PowerShell-Vergleiche (-match, -replace, Hashtables) achten nicht auf Groß- und Kleinschreibung - hier
// deshalb überall IgnoreCase, wo das Skript sie benutzt hat.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net;
using System.Text.RegularExpressions;

namespace PulsRig.Core
{
    public static class ScanText
    {
        const RegexOptions I = RegexOptions.IgnoreCase;

        public static string LimitText(string? text, int maxLength)
        {
            text ??= "";
            return text.Length <= maxLength ? text : text.Substring(0, maxLength - 3) + "...";
        }

        // Intel-Chipsatz-INFs tragen absichtlich den 18.07.1968 - solche Platzhalter gelten als kein Datum
        public static string FormatDate(DateTime? value) =>
            value.HasValue && value.Value.Year >= 1990 ? value.Value.ToString("dd.MM.yyyy", CultureInfo.InvariantCulture) : "-";

        public static string FormatDriverText(string? version, DateTime? date)
        {
            string text = FormatDate(date);
            return text == "-" ? version ?? "" : $"{version} vom {text}";
        }

        public static string SafeName(string? text, int maxLength)
        {
            string name = Regex.Replace(Regex.Replace(text ?? "", @"[\\/:*?""<>|\[\]]", "_"), @"\s+", " ");
            if (name.Length > maxLength) name = name.Substring(0, maxLength);
            return name.Trim(' ', '.');
        }

        static readonly Dictionary<string, string> UpdateErrors = new Dictionary<string, string>
        {
            ["0x8024402C"] = "Keine Verbindung zu Windows Update (Internet, Proxy oder DNS prüfen).",
            ["0x80072EE7"] = "Der Update-Server wurde nicht gefunden (Internetverbindung prüfen).",
            ["0x80072EFD"] = "Keine Verbindung zum Update-Server (Firewall oder Proxy prüfen).",
            ["0x80072EE2"] = "Zeitüberschreitung bei der Verbindung zum Update-Server.",
            ["0x8024001E"] = "Der Windows-Update-Dienst wurde während des Vorgangs beendet.",
            ["0x80070422"] = "Der Dienst \"Windows Update\" ist deaktiviert.",
            ["0x80240044"] = "Für diesen Schritt sind Adminrechte nötig.",
            ["0x8024500C"] = "Windows Update ist auf diesem PC per Richtlinie gesperrt.",
            ["0x80070005"] = "Zugriff verweigert.",
        };

        // Fehler von Windows Update (COM) mit Code in Worten
        public static string UpdateError(int hresult, string? message)
        {
            string code = "0x" + hresult.ToString("X8", CultureInfo.InvariantCulture);
            return UpdateErrors.TryGetValue(code, out string? known) ? $"{known} ({code})" : $"{(message ?? "").Trim()} ({code})";
        }

        // Windows Update nennt Treiber "Hersteller - Art - Version" (manchmal mit einem Datum dazwischen), die Art in
        // Kürzeln wie "LCD" oder "MEDIA". Für die Anzeige: Kürzel übersetzt, Datum weggelassen.
        static readonly Dictionary<string, string> Kinds = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["LCD"] = "Monitor", ["Monitor"] = "Monitor", ["Display"] = "Grafik", ["Net"] = "Netzwerk", ["MEDIA"] = "Audio",
            ["AudioProcessingObject"] = "Audio", ["Image"] = "Scanner oder Kamera", ["Camera"] = "Kamera", ["Printer"] = "Drucker",
            ["Keyboard"] = "Tastatur", ["Mouse"] = "Maus", ["HIDClass"] = "Eingabegerät", ["USB"] = "USB", ["Bluetooth"] = "Bluetooth",
            ["System"] = "Systemgerät", ["Firmware"] = "Firmware", ["SoftwareComponent"] = "Zusatzsoftware", ["Extension"] = "Erweiterung",
            ["SCSIAdapter"] = "Laufwerkscontroller", ["HDC"] = "Laufwerkscontroller", ["Ports"] = "Anschluss", ["Biometric"] = "Fingerabdruck",
            ["Battery"] = "Akku", ["Other"] = "Gerät", ["Other hardware"] = "Gerät",
        };

        public static string FormatUpdateTitle(string? title)
        {
            title ??= "";
            var parts = Regex.Split(title, @"\s+-\s+").Select(p => p.Trim()).Where(p => p.Length > 0).ToList();
            if (parts.Count < 3) return title;
            string kind = Kinds.TryGetValue(parts[1], out string? known) ? known : parts[1];
            var rest = parts.Skip(2).Where(p => !Regex.IsMatch(p, @"^\d{1,2}/\d{1,2}/\d{4}(\s.*)?$"));
            return string.Join(" – ", new[] { parts[0], kind }.Concat(rest));
        }
    }

    public sealed class BoardSearch
    {
        public string Name { get; set; } = "";
        public string Url { get; set; } = "";
    }

    public static class ScanGeraete
    {
        const RegexOptions I = RegexOptions.IgnoreCase;

        // Gehört ein Gerät ohne Treiber (Code 28) zum Chipsatz? Erkannt am Hersteller in der Gerätekennung (Intel, AMD)
        // und am allgemeinen Namen - Grafik, Netzwerk und Ton heißen anders.
        public static bool IsChipsetDevice(string? name, int code, string? deviceId)
        {
            if (code != 28) return false;
            if (!Regex.IsMatch(deviceId ?? "", @"(?i)^(PCI\\VEN_(8086|1022|1002)|ACPI\\(AMDI?|INT[C3L]?)[0-9A-F]+)")) return false;
            return Regex.IsMatch(name ?? "", "(?i)SM[- ]?Bus|^PCI[- ](Gerät|Device)$|Kommunikationscontroller|Communications Controller|Basissystemgerät|Base System Device|Verschlüsselungs|Encryption|Datensammlungs|Datenerfassungs|Data Acquisition|Unbekanntes Gerät|Unknown device");
        }

        // Wo es den Chipsatz-Treiber gibt: beim Hersteller des Mainboards, bei Fertig-PCs und Notebooks beim Hersteller
        // des Geräts - verlinkt wird eine Suche nach Modell und Treiber. null, wenn kein Modell bekannt ist.
        public static BoardSearch? BoardDriverSearch(string? systemMaker, string? systemModel, string? boardMaker, string? boardModel)
        {
            const string empty = @"(?i)To Be Filled|System manufacturer|System Product Name|Default string|^\s*$";
            string maker = boardMaker ?? "", model = boardModel ?? "";
            if (!Regex.IsMatch(systemMaker ?? "", empty) && !Regex.IsMatch(systemModel ?? "", empty)) { maker = systemMaker!; model = systemModel!; }
            if (Regex.IsMatch(model, empty)) return null;
            if (Regex.IsMatch(maker, empty)) maker = "";
            // Firmenzusätze kürzen: "ASUSTeK COMPUTER INC." -> "ASUSTeK", "Micro-Star International Co., Ltd." -> "MSI"
            maker = Regex.Replace(maker, "(?i)Micro-Star International.*", "MSI");
            maker = Regex.Replace(maker, "(?i)Gigabyte Technology.*", "Gigabyte");
            maker = Regex.Replace(maker, @"(?i)[, ]+(COMPUTER INC\.?|Co\.,? ?Ltd\.?|Corporation|Corp\.?|Inc\.?)\s*$", "");
            string name = Regex.Replace($"{maker} {model}", @"\s+", " ").Trim();
            return new BoardSearch { Name = name, Url = "https://www.bing.com/search?q=" + Uri.EscapeDataString(name + " Chipsatz Treiber Download") };
        }

        // Schlüssel einer Grafikkarte für den Treiberschutz: "PCI\VEN_xxxx&DEV_xxxx" aus ihrer Geräte-ID
        public static string GpuShieldKey(string? hardwareId)
        {
            var match = Regex.Match(hardwareId ?? "", @"^(PCI\\VEN_[0-9A-Fa-f]{4}&DEV_[0-9A-Fa-f]{4})", I);
            return match.Success ? match.Groups[1].Value.ToUpperInvariant() : "";
        }
    }

    public sealed class KatalogTreffer
    {
        public string Id { get; set; } = "";
        public string Title { get; set; } = "";
        public string Products { get; set; } = "";
        public DateTime Date { get; set; }
        public Version? Version { get; set; }
        public string Size { get; set; } = "";
        public long Bytes { get; set; }
    }

    public static class Katalog
    {
        const RegexOptions I = RegexOptions.IgnoreCase;

        // Suchbegriff aus der Hardware-ID, z.B. PCI\VEN_1022&DEV_790B&SUBSYS_FFFF1849&REV_59 -> VEN_1022&DEV_790B
        public static string? Query(string? hardwareId)
        {
            string[] parts = (hardwareId ?? "").Split(new[] { '\\' }, 2);
            if (parts.Length < 2 || parts[0].Equals("ROOT", StringComparison.OrdinalIgnoreCase) || parts[0].Equals("SWD", StringComparison.OrdinalIgnoreCase)) return null;
            // ACPI-Geräte stehen in Treiberpaketen in der Kurzform, z.B. ACPI\AMDI0030
            if (parts[0].Equals("ACPI", StringComparison.OrdinalIgnoreCase))
            {
                var acpi = Regex.Match(parts[1], @"^VEN_(\w+)&DEV_(\w+)", I);
                if (acpi.Success) return acpi.Groups[1].Value + acpi.Groups[2].Value;
            }
            string query = string.Join("&", parts[1].Split('&').Where(p => !Regex.IsMatch(p, @"^(SUBSYS_|REV_|MI_|FUNC_|Col\d)", I)));
            return query.Length >= 8 ? query : null;
        }

        public static string Url(string query) =>
            "https://www.catalog.update.microsoft.com/Search.aspx?q=" + Uri.EscapeDataString(query) + "&scol=DateComputed&sdir=desc";

        // Liest die Trefferseite des Katalogs; Einträge ohne lesbare Version oder ohne Datum fallen weg
        public static KatalogTreffer[] ParseRows(string? content)
        {
            var result = new List<KatalogTreffer>();
            foreach (Match row in Regex.Matches(content ?? "", @"(?s)<tr id=""([0-9a-f\-]{36})_R\d+"".*?</tr>"))
            {
                var cells = new Dictionary<string, string>();
                foreach (Match cell in Regex.Matches(row.Value, @"(?s)<td[^>]*id=""[^""]*_C(\d)_R\d+""[^>]*>(.*?)</td>"))
                {
                    string text = Regex.Replace(cell.Groups[2].Value, @"(?s)<span class=""noDisplay"".*?</span>", "", I);
                    text = Regex.Replace(text, "<[^>]+>", "");
                    cells[cell.Groups[1].Value] = Regex.Replace(WebUtility.HtmlDecode(text), @"\s+", " ").Trim();
                }
                Version? version = null;
                if (cells.TryGetValue("5", out string? versionText) && !Version.TryParse(versionText, out version)) continue;   // alte Einträge ohne Versionsspalte
                if (!cells.TryGetValue("4", out string? dateText) || !DateTime.TryParseExact(dateText, new[] { "M/d/yyyy", "d.M.yyyy" },
                        CultureInfo.InvariantCulture, DateTimeStyles.None, out DateTime date)) continue;
                var size = Regex.Match(row.Value, @"_originalSize"">\s*(\d+)", I);
                result.Add(new KatalogTreffer
                {
                    Id = row.Groups[1].Value,   // Kennung des Eintrags: mit ihr nennt der Katalog die Datei zum Laden
                    Title = cells.TryGetValue("1", out string? title) ? title : "",
                    Products = cells.TryGetValue("2", out string? products) ? products : "",
                    Date = date,
                    Version = version,
                    Size = cells.TryGetValue("6", out string? sizeText) ? sizeText : "",
                    Bytes = size.Success ? long.Parse(size.Groups[1].Value, CultureInfo.InvariantCulture) : 0,
                });
            }
            return result.ToArray();
        }
    }

    public static class KatalogAuswahl
    {
        // Wählt den Katalogeintrag, der sicher zur selben Treiberlinie gehört und neuer ist - sonst null
        public static KatalogTreffer? Candidate(string? driverVersion, string? provider, DateTime? actualDate, IEnumerable<KatalogTreffer?>? rows, string osName)
        {
            if (!Version.TryParse(driverVersion ?? "", out Version? installed)) return null;
            string vendor = Regex.Split(provider ?? "", @"[\s,]+")[0];
            var list = (rows ?? Enumerable.Empty<KatalogTreffer?>()).Where(row => row != null).Select(row => row!)
                .Where(row => row.Products.IndexOf(osName, StringComparison.OrdinalIgnoreCase) >= 0
                    && row.Title.StartsWith(vendor, StringComparison.OrdinalIgnoreCase)
                    // andere Hauptversion = anderes Treibermodell fürs gleiche Gerät, das wäre kein verlässlicher Vergleich
                    && row.Version != null && row.Version.Major == installed.Major && row.Version > installed
                    && (!actualDate.HasValue || row.Date > actualDate.Value.Date)).ToList();
            return First(list, (a, b) => Compare(b.Version, a.Version) is int v && v != 0 ? v : b.Date.CompareTo(a.Date));
        }

        // Für ein Gerät ohne Treiber der neueste Eintrag, der zu dieser Windows-Fassung passt ($OsVersion z.B. "24H2"):
        // Einträge, die eine neuere Fassung verlangen ("version 24H2 and later" auf 22H2), scheiden aus. Firmware nie;
        // reine Zusätze (Erweiterung, Zusatzsoftware) erst nach den eigentlichen Treibern.
        public static KatalogTreffer? MissingDriver(IEnumerable<KatalogTreffer?>? rows, string osName, string? osVersion)
        {
            bool checkVersion = Regex.IsMatch(osVersion ?? "", @"^\d\dH\d$", RegexOptions.IgnoreCase);
            var list = (rows ?? Enumerable.Empty<KatalogTreffer?>()).Where(row => row != null).Select(row => row!)
                .Where(row => row.Id.Length > 0 && row.Products.IndexOf(osName, StringComparison.OrdinalIgnoreCase) >= 0
                    && !Regex.IsMatch(row.Title, @"(?i)firmware|\bBIOS\b")
                    && !(checkVersion && TooNew(row.Products, osVersion!))).ToList();
            return First(list, (a, b) =>
            {
                int extra = IsAddOn(a).CompareTo(IsAddOn(b));
                if (extra != 0) return extra;
                int version = Compare(b.Version, a.Version);
                return version != 0 ? version : b.Date.CompareTo(a.Date);
            });
        }

        static bool IsAddOn(KatalogTreffer row) => Regex.IsMatch(row.Title, "(?i)Extension|SoftwareComponent");

        static int Compare(Version? a, Version? b) => a == null ? (b == null ? 0 : -1) : a.CompareTo(b);

        // Sortiert wie bisher Sort-Object (List.Sort, nicht stabil): bei gleicher Version und gleichem Datum - die
        // Varianten eines Pakets für verschiedene Windows-Fassungen - gewinnt so derselbe Eintrag wie vorher
        static KatalogTreffer? First(List<KatalogTreffer> list, Comparison<KatalogTreffer> comparison)
        {
            list.Sort(comparison);
            return list.Count > 0 ? list[0] : null;
        }

        static bool TooNew(string products, string osVersion)
        {
            var match = Regex.Match(products, @"version (\d\dH\d) and later", RegexOptions.IgnoreCase);
            return match.Success && string.Compare(match.Groups[1].Value, osVersion, StringComparison.OrdinalIgnoreCase) > 0;
        }
    }

    public static class Zuordnung
    {
        // Name des Geräts zu einer Hardware-Kennung aus Windows Update. Die Kennung dort ist oft nur ein Teil der vollen
        // ("vid_04f9&pid_04bb&netscn"), deshalb zählt auch, wenn eine Kennung des Geräts sie enthält. ids[i] sind die
        // Kennungen des Geräts names[i].
        public static string DeviceName(string? hardwareId, IList<string[]?> ids, IList<string?> names)
        {
            if (hardwareId == null || hardwareId.Length < 6) return "";
            string id = hardwareId.ToUpperInvariant();
            foreach (bool exact in new[] { true, false })
                for (int i = 0; i < ids.Count; i++)
                    foreach (string? known in ids[i] ?? new string[0])
                    {
                        string text = (known ?? "").ToUpperInvariant();
                        if ((exact ? text == id : text.Contains(id)) && !string.IsNullOrEmpty(names[i])) return names[i]!;
                    }
            return "";
        }

        // Welcher installierte Treiber gehört zur Kennung? Index in hardwareIds, sonst -1. WMI nennt nur die genaueste
        // Hardware-ID, Treiber zielen oft auf die allgemeinere ohne SUBSYS/REV.
        public static int InstalledDriver(string? hardwareId, IList<string?> hardwareIds)
        {
            if (string.IsNullOrEmpty(hardwareId)) return -1;
            string id = hardwareId!.ToUpperInvariant();
            for (int i = 0; i < hardwareIds.Count; i++)
                if (!string.IsNullOrEmpty(hardwareIds[i]) && hardwareIds[i]!.ToUpperInvariant() == id) return i;
            for (int i = 0; i < hardwareIds.Count; i++)
                if (!string.IsNullOrEmpty(hardwareIds[i]) && hardwareIds[i]!.ToUpperInvariant().StartsWith(id + "&", StringComparison.Ordinal)) return i;
            return -1;
        }

        // Ausschlüsse aus den Einstellungen: Muster wie bei PowerShell -like (* ? [a-z], ` maskiert), ohne
        // Platzhalter zählt das Muster irgendwo im Titel
        public static bool IsExcluded(string? title, IEnumerable<string?>? patterns)
        {
            foreach (string? pattern in patterns ?? Enumerable.Empty<string?>())
            {
                if (string.IsNullOrEmpty(pattern)) continue;
                string wildcard = Regex.IsMatch(pattern, @"[*?]") ? pattern! : "*" + pattern + "*";
                if (Regex.IsMatch(title ?? "", WildcardToRegex(wildcard), RegexOptions.IgnoreCase | RegexOptions.Singleline)) return true;
            }
            return false;
        }

        static string WildcardToRegex(string pattern)
        {
            var result = new System.Text.StringBuilder("^");
            for (int i = 0; i < pattern.Length; i++)
            {
                char c = pattern[i];
                if (c == '`' && i + 1 < pattern.Length) result.Append(Regex.Escape(pattern[++i].ToString()));
                else if (c == '*') result.Append(".*");
                else if (c == '?') result.Append('.');
                else if (c == '[')
                {
                    int end = pattern.IndexOf(']', i + 1);
                    if (end < 0) throw new ArgumentException("Ungültiges Muster: " + pattern);
                    string set = pattern.Substring(i + 1, end - i - 1);
                    result.Append('[').Append(set.Replace(@"\", @"\\").Replace("^", @"\^").Replace("[", @"\[")).Append(']');
                    i = end;
                }
                else result.Append(Regex.Escape(c.ToString()));
            }
            return result.Append('$').ToString();
        }
    }

    public sealed class AmdChipsatz
    {
        public string Socket { get; set; } = "";
        public string Chipset { get; set; } = "";
        public string Url => $"https://www.amd.com/de/support/downloads/drivers.html/chipsets/{Socket}/{Chipset.ToLowerInvariant()}.html";
    }

    public static class Hersteller
    {
        const RegexOptions I = RegexOptions.IgnoreCase;

        // Windows meldet z.B. 32.0.16.1742, NVIDIA nennt dieselbe Version 617.42 (die letzten fünf Ziffern)
        public static string? NvidiaVersion(string? windowsVersion)
        {
            string digits = new string((windowsVersion ?? "").Where(char.IsDigit).ToArray());
            if (digits.Length < 5) return null;
            string tail = digits.Substring(digits.Length - 5);
            return tail.Substring(0, 3) + "." + tail.Substring(3);
        }

        // Seite der Radeon-Karte bei AMD (RX 5000 bis 9000, Vega); für ältere Karten und Prozessorgrafik null
        public static string? RadeonPage(string? gpuName)
        {
            string name = Regex.Replace(Regex.Replace(gpuName ?? "", @"\((TM|R)\)", "", I), @"\s+", " ").Trim().ToLowerInvariant();
            const string baseUrl = "https://www.amd.com/de/support/downloads/drivers.html/graphics/radeon-rx/";
            var rx = Regex.Match(name, @"radeon rx ([5-9])(\d{3})( xtx| xt| gre)?(?![\w])", I);
            if (rx.Success)
                return $"{baseUrl}radeon-rx-{rx.Groups[1].Value}000-series/amd-radeon-rx-{rx.Groups[1].Value}{rx.Groups[2].Value}{rx.Groups[3].Value.Replace(" ", "-")}.html";
            var vega = Regex.Match(name, "radeon rx vega (56|64)", I);
            return vega.Success ? $"{baseUrl}radeon-rx-vega-series/radeon-rx-vega-{vega.Groups[1].Value}.html" : null;
        }

        public static string GpuName(string? name) => Regex.Replace(Regex.Replace(name ?? "", @"\((TM|R)\)", "", I), @"\s+", " ").Trim();

        // neueste Adrenalin-Fassung auf der Seite der Karte, z.B. aus whql-amd-software-adrenalin-edition-26.10.1-win11-b.exe
        public static string? RadeonLatest(string? content) =>
            Regex.Matches(content ?? "", @"adrenalin-edition-([0-9]+(?:\.[0-9]+){1,3})-", I).Cast<Match>().Select(m => m.Groups[1].Value)
                .OrderByDescending(v => Version.Parse(v)).FirstOrDefault();

        // "Release Date" der Seiten von AMD (2026-10-20) als 20.10.2026, sonst leer
        public static string ReleaseDate(string? content)
        {
            var match = Regex.Match(content ?? "", @"(?s)Release Date</strong>\s*<p>\s*([0-9]{4})-([0-9]{2})-([0-9]{2})", I);
            return match.Success ? $"{match.Groups[3].Value}.{match.Groups[2].Value}.{match.Groups[1].Value}" : "";
        }

        // Chipsatz aus dem Namen des Mainboards (AB350 Pro4, B650 AORUS ELITE, ROG STRIX X570-E ...), sonst nach Sockel
        static readonly (string Socket, string[] Names)[] Sockets =
        {
            ("am5", new[] { "X870E", "X870", "B850", "B840", "X670E", "X670", "B650E", "B650", "A620" }),
            ("am4", new[] { "X570", "B550", "A520", "X470", "B450", "X370", "B350", "A320" }),
        };

        public static AmdChipsatz? AmdChipset(string? boardProduct, string? socketDesignation)
        {
            foreach (var (socket, names) in Sockets)
                foreach (string name in names)
                    if (Regex.IsMatch(boardProduct ?? "", $"(?i)(?<![0-9]){name}(?![0-9])")) return new AmdChipsatz { Socket = socket, Chipset = name };
            // unbekanntes Mainboard: der Sockel genügt, das Paket ist dasselbe
            if (Regex.IsMatch(socketDesignation ?? "", "AM5", I)) return new AmdChipsatz { Socket = "am5", Chipset = "B650" };
            if (Regex.IsMatch(socketDesignation ?? "", "AM4", I)) return new AmdChipsatz { Socket = "am4", Chipset = "B550" };
            return null;
        }

        public static string? AmdChipsetLatest(string? content)
        {
            var match = Regex.Match(content ?? "", @"AMD_Chipset_Software_([0-9]+(?:\.[0-9]+){2,3})\.exe", I);
            return match.Success ? match.Groups[1].Value : null;
        }

        // Größe und Datum stehen im Block hinter der Versionsnummer
        public static string[] AmdChipsetDetails(string? content, string latest)
        {
            var block = Regex.Match(content ?? "", @"(?s)Revision Number</strong>\s*<p>\s*" + Regex.Escape(latest) + ".{0,600}");
            if (!block.Success) return new[] { "", "" };
            var size = Regex.Match(block.Value, @"(?s)File Size</strong>\s*<p>\s*([^<]+?)\s*</p>", I);
            return new[] { size.Success ? size.Groups[1].Value : "", ReleaseDate(block.Value) };
        }
    }
}
