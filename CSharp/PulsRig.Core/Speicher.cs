// PulsRig.Core - Arbeitsspeicher: Steckplätze aus dem BIOS, Kanäle, richtige Steckplätze und Takt, abgelöst aus
// PulsRig-Hardware.ps1. Die CIM-Abfragen bleiben beim Aufrufer (PowerShell oder die neue Oberfläche).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace PulsRig.Core
{
    public sealed class SpeicherRiegel
    {
        public string Slot { get; set; } = "";
        public string Bank { get; set; } = "";
        public string Maker { get; set; } = "";
        public string Part { get; set; } = "";
        public double Bytes { get; set; }
        public int Speed { get; set; }
        public int Rated { get; set; }
        public int Voltage { get; set; }
        public string Type { get; set; } = "";
        public bool Laptop { get; set; }
    }

    // ein Steckplatz in der Reihenfolge des Mainboards; Module = Stelle des Riegels oder -1 für leer
    public sealed class Steckplatz
    {
        public string Slot { get; set; } = "";
        public string Bank { get; set; } = "";
        public int Module { get; set; } = -1;
    }

    public sealed class SpeicherKanaele
    {
        public string Name { get; set; } = "";
        public string Hint { get; set; } = "";
    }

    // State: good/bad, leer = kein Urteil; Wrong und Better sind Stellen in der Reihenfolge der Steckplätze
    public sealed class Steckordnung
    {
        public string State { get; set; } = "";
        public List<int> Wrong { get; } = new List<int>();
        public List<int> Better { get; } = new List<int>();
        public string Hint { get; set; } = "";
    }

    public sealed class SpeicherTakt
    {
        public int Speed { get; set; }
        public bool Known { get; set; }
    }

    public sealed class SpeicherProfil
    {
        public string Tone { get; set; } = "";
        public string Badge { get; set; } = "";
        public int Now { get; set; }
        public int Rated { get; set; }
        public string Title { get; set; } = "";
        public string Text { get; set; } = "";
    }

    public static class Speicher
    {
        static readonly Dictionary<int, string> Types = new Dictionary<int, string> { [20] = "DDR", [21] = "DDR2", [24] = "DDR3", [26] = "DDR4", [34] = "DDR5" };

        // Bauart aus SMBIOSMemoryType von Win32_PhysicalMemory
        public static string TypeName(int smbiosType) => Types.TryGetValue(smbiosType, out string? name) ? name : "";

        // "Unknown", "Undefined" und Nullen sind kein Hersteller
        public static string Maker(string? manufacturer)
        {
            string maker = (manufacturer ?? "").Trim();
            return Regex.IsMatch(maker, "^(Unknown|Undefined|0+)$", RegexOptions.IgnoreCase) ? "" : maker;
        }

        // Reihenfolge der Steckplätze samt der leeren: steht nur in der Rohtabelle des BIOS (SMBIOS, Einträge der Art 17).
        // Passt die Zahl der belegten Plätze nicht zu den Riegeln von Windows, ist der Tabelle nicht zu trauen (leere Liste).
        public static List<Steckplatz> ParseSmbios(byte[]? raw, int moduleCount)
        {
            var layout = new List<Steckplatz>();
            if (raw == null) return layout;
            int at = 0, filled = 0;
            while (at < raw.Length - 4)
            {
                int kind = raw[at], length = raw[at + 1];
                if (length < 4) break;
                // hinter dem festen Teil stehen die Texte des Eintrags, jeder mit einer Null beendet, am Ende zwei Nullen
                int next = at + length;
                var strings = new List<string>();
                while (next < raw.Length - 1 && !(raw[next] == 0 && raw[next + 1] == 0))
                {
                    int end = next;
                    while (end < raw.Length && raw[end] != 0) end++;
                    strings.Add(Encoding.ASCII.GetString(raw, next, end - next));
                    next = end;
                    if (next < raw.Length - 1 && raw[next + 1] != 0) next++;
                }
                if (kind == 17 && length >= 0x12)
                {
                    int size = BitConverter.ToUInt16(raw, at + 0x0C);
                    string Name(int offset)
                    {
                        int index = raw[at + offset];
                        return index >= 1 && index <= strings.Count ? strings[index - 1].Trim() : "";
                    }
                    var place = new Steckplatz { Slot = Name(0x10), Bank = Name(0x11) };
                    if (size != 0 && size != 0xFFFF) { place.Module = filled; filled++; }
                    layout.Add(place);
                }
                if (kind == 127) break;
                at = next + 2;
            }
            if (filled != moduleCount) layout.Clear();
            return layout;
        }

        // Reihenfolge der Steckplätze: aus dem BIOS, sonst die Riegel und dahinter die freien Plätze
        public static List<Steckplatz> Layout(IList<SpeicherRiegel> modules, IList<Steckplatz>? smbios, int slots)
        {
            if (smbios != null && smbios.Count > 0) return smbios.ToList();
            var layout = new List<Steckplatz>();
            for (int i = 0; i < modules.Count; i++) layout.Add(new Steckplatz { Slot = modules[i].Slot, Bank = modules[i].Bank, Module = i });
            for (int i = modules.Count; i < slots; i++) layout.Add(new Steckplatz { Slot = "Steckplatz", Bank = "", Module = -1 });
            return layout;
        }

        // Der Kanal eines Steckplatzes steht in seinem Namen ("CHANNEL A", "ChannelB-DIMM0", "DIMM_A1"); fehlt er, gibt
        // es kein Urteil (leere Antwort). Intel-Boards ab der 12. Generation nennen beide Kanäle "ChannelA" und
        // unterscheiden sie nur über den Speicher-Controller davor ("Controller0-ChannelA-DIMM1", "Controller1-…").
        public static string ChannelKey(string? text)
        {
            text ??= "";
            var m = Regex.Match(text, @"controller\s*(\d+)\s*-?\s*channel\s*-?\s*([A-H])(?![A-Za-z])", RegexOptions.IgnoreCase);
            if (m.Success) return m.Groups[1].Value + m.Groups[2].Value.ToUpperInvariant();
            m = Regex.Match(text, @"channel\s*-?\s*([A-H])(?![A-Za-z])", RegexOptions.IgnoreCase);
            if (!m.Success) m = Regex.Match(text, @"DIMM[_ ]?([A-H])[0-9]", RegexOptions.IgnoreCase);
            return m.Success ? m.Groups[1].Value.ToUpperInvariant() : "";
        }

        static string Key(string bank, string slot) => ChannelKey(bank + " " + slot);

        // In wie vielen Kanälen die Riegel stecken: auf zwei Kanäle verteilt (Dual-Channel) ist der Speicher deutlich schneller
        public static SpeicherKanaele? Channels(IList<SpeicherRiegel> modules, int slots)
        {
            var channels = new List<string>();
            foreach (var module in modules)
            {
                string channel = Key(module.Bank, module.Slot);
                if (channel.Length == 0) return null;
                channels.Add(channel);
            }
            int count = channels.Distinct(StringComparer.OrdinalIgnoreCase).Count();
            if (count == 0) return null;
            string name = count switch { 1 => "Single-Channel", 2 => "Dual-Channel", 3 => "Triple-Channel", 4 => "Quad-Channel", _ => count + " Kanäle" };
            string hint = "";
            if (count == 1 && modules.Count > 1) hint = "Alle Riegel stecken im selben Kanal. Auf beide Kanäle verteilt (siehe Handbuch des Mainboards) wird der Speicher deutlich schneller.";
            else if (count == 1 && slots > 1) hint = "Ein einzelner Riegel läuft im Single-Channel. Ein zweiter gleicher im anderen Kanal macht den Speicher deutlich schneller.";
            return new SpeicherKanaele { Name = name, Hint = hint };
        }

        // Stecken die Riegel in den richtigen Steckplätzen? Bei zwei Steckplätzen je Kanal verlangen fast alle Mainboards
        // zuerst den zweiten (meist A2 und B2). Im ersten läuft der PC zwar, aber das Speicherprofil (XMP) scheitert oft.
        public static Steckordnung Placement(IList<Steckplatz> places)
        {
            var result = new Steckordnung();
            var order = new List<string>();
            var groups = new Dictionary<string, List<int>>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < places.Count; i++)
            {
                string channel = Key(places[i].Bank, places[i].Slot);
                if (channel.Length == 0) return result;
                if (!groups.ContainsKey(channel)) { groups[channel] = new List<int>(); order.Add(channel); }
                groups[channel].Add(i);
            }
            // ein Urteil gibt es nur für den üblichen Aufbau: mindestens zwei Kanäle mit je zwei Steckplätzen
            if (groups.Count < 2 || order.Any(c => groups[c].Count != 2)) return result;
            var filled = order.ToDictionary(c => c, c => groups[c].Where(i => places[i].Module >= 0).ToList(), StringComparer.OrdinalIgnoreCase);
            if (filled.Values.All(f => f.Count == 0)) return result;
            bool first = false, crowded = false;
            var empty = order.Where(c => filled[c].Count == 0).ToList();
            foreach (string channel in order)
            {
                var slots = groups[channel];
                var used = filled[channel];
                if (used.Count == 1 && used[0] == slots[0])
                {
                    // ein Riegel im Kanal, aber im ersten Steckplatz statt im zweiten
                    result.Wrong.Add(slots[0]); result.Better.Add(slots[1]); first = true;
                }
                else if (used.Count == 2 && empty.Count > 0)
                {
                    // zwei Riegel in einem Kanal, während ein anderer leer ist: einer gehört hinüber
                    string target = empty[0];
                    empty.RemoveAt(0);
                    result.Wrong.Add(slots[0]); result.Better.Add(groups[target][1]); crowded = true;
                }
            }
            if (result.Wrong.Count == 0) { result.State = "good"; return result; }
            result.State = "bad";
            var hints = new List<string>();
            if (first) hints.Add("Die gelb markierten Riegel stecken im ersten Steckplatz ihres Kanals. Fast alle Mainboards wollen zuerst den zweiten (meist A2 und B2), sonst scheitert oft XMP.");
            if (crowded) hints.Add("Zwei Riegel teilen sich einen Kanal, ein anderer ist leer: so läuft der Speicher nur im Single-Channel.");
            result.Hint = string.Join(" ", hints) + " PC ausschalten und wie markiert umstecken; im Zweifel gilt das Handbuch.";
            return result;
        }

        // Der Takt, für den ein Riegel gebaut ist. Windows meldet oft nur den laufenden Takt; der volle steht bei den
        // meisten Herstellern in der Typenbezeichnung (F4-3000C16, CMK16GX4M2B3200C16, KF432C16 ...).
        public static SpeicherTakt Rated(SpeicherRiegel module)
        {
            int found = 0;
            string part = module.Part ?? "";
            Match m;
            if ((m = Regex.Match(part, "(?<![0-9])([1-9][0-9]{3})H?CL?[0-9]{2}", RegexOptions.IgnoreCase)).Success) found = int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
            else if ((m = Regex.Match(part, "^(?:KF|HX)[45]([0-9]{2})C[0-9]{2}", RegexOptions.IgnoreCase)).Success) found = 100 * int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
            else if ((m = Regex.Match(part, "^BL[0-9]+G([0-9]{2})C[0-9]{2}", RegexOptions.IgnoreCase)).Success) found = 100 * int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
            if (found < 1600 || found > 10000) found = 0;
            return new SpeicherTakt { Speed = Math.Max(module.Rated, found), Known = found > 0 || module.Rated > module.Speed };
        }

        // Urteil über den Takt: laufen die Riegel so schnell, wie sie können? Wenn nicht, fehlt meist das Speicherprofil im BIOS.
        public static SpeicherProfil? Profile(IList<SpeicherRiegel> modules)
        {
            var running = modules.Where(m => m.Speed > 0).ToList();
            if (running.Count == 0) return null;
            int now = running.Min(m => m.Speed);
            var known = running.Select(Rated).Where(r => r.Known).ToList();
            int rated = known.Count > 0 ? known.Min(r => r.Speed) : 0;
            if (rated >= now + 100)
                return new SpeicherProfil { Tone = "Warn", Badge = "Profil prüfen", Now = now, Rated = rated,
                    Title = string.Format("{0:N0} MHz – die Riegel können {1:N0} MHz", now, rated),
                    Text = "Im BIOS ist das Speicherprofil (XMP, bei AMD auch DOCP oder EXPO) nicht aktiv, oder der Takt ist dort von Hand niedriger gestellt. Nicht jedes Mainboard schafft den vollen Takt." };
            if (rated > 0)
                return new SpeicherProfil { Tone = "Good", Badge = "voller Takt", Now = now, Rated = rated,
                    Title = string.Format("{0:N0} MHz – voller Takt der Riegel", now),
                    Text = "Die Riegel laufen so schnell, wie sie gebaut sind. Am Speicherprofil im BIOS (XMP, DOCP oder EXPO) ist nichts zu tun." };
            return new SpeicherProfil { Tone = "TextDim", Badge = "aktuell", Now = now, Rated = 0,
                Title = string.Format("{0:N0} MHz", now),
                Text = "Für welchen Takt die Riegel gebaut sind, verrät Windows bei diesem Modell nicht. Steht auf ihrem Aufkleber mehr, im BIOS das Speicherprofil (XMP, DOCP oder EXPO) einschalten." };
        }
    }
}
