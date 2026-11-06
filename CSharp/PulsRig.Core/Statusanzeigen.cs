using System;
using System.Collections.Generic;
using System.Linq;

namespace PulsRig.Core
{
    public static partial class Spielcheck
    {
        public static bool IsUnknown(string tone) => tone != "good" && tone != "warn" && tone != "bad";
        public static (int Good, int Concern, int Unknown) Counts(IEnumerable<string> tones)
        {
            var list = tones.ToList();
            return (list.Count(t => t == "good"), list.Count(t => t == "warn" || t == "bad"), list.Count(IsUnknown));
        }
        public static string BarDescription(int mib) =>
            "Der Prozessor kann über ein vergrößertes BAR1-Adressfenster auf den Grafikspeicher zugreifen (" +
            (mib / 1024.0).ToString("0.##", System.Globalization.CultureInfo.GetCultureInfo("de-DE")) +
            " GiB Adressbereich). Das ist nicht die Größe des eingebauten Grafikspeichers. Der Nutzen hängt vom Spiel ab.";
    }

    public sealed class Stabilitaetsanzeige
    {
        public string Value { get; private set; } = "–";
        public string Label { get; private set; } = "noch nicht geprüft";
        public bool Known { get; private set; }
        public List<int> Days { get; private set; } = new List<int>();

        public static Stabilitaetsanzeige From(AbsturzDaten? data, DateTime today)
        {
            var result = new Stabilitaetsanzeige();
            if (data == null) return result;
            if (!data.Log) { result.Label = "Protokoll unvollständig"; return result; }
            var events = data.Blue.Concat(data.Off).Concat(data.Tdr).Concat(data.Apps)
                .Where(v => v.When.Date <= today.Date && v.When.Date > today.Date.AddDays(-30)).ToList();
            result.Known = true;
            result.Days = events.Select(v => (today.Date - v.When.Date).Days).Distinct().ToList();
            if (events.Count == 0)
            {
                result.Value = "0";
                result.Label = "Vorfälle / 30 Tage";
            }
            else
            {
                var days = result.Days.Min();
                result.Value = days.ToString();
                result.Label = days == 1 ? "Tag ohne Vorfall" : "Tage ohne Vorfall";
            }
            return result;
        }
    }
}