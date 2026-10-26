using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Xml;

namespace PulsRig.Core
{
    // Akku-Bericht wie PulsRig-Akku.ps1: Kapazität heute im Vergleich zu neu, Ladezyklen, Laufzeit laut Windows und der
    // Verlauf der Kapazität je Monat. Die Zahlen kommen aus "powercfg /batteryreport /xml"; Seriennummern bleiben draußen.
    public sealed class AkkuZelle
    {
        public string Name { get; set; } = "";
        public string Maker { get; set; } = "";
        public string Chemistry { get; set; } = "";
        public double Design { get; set; }
        public double Full { get; set; }
        public int Cycles { get; set; }
    }

    public sealed class AkkuMonat
    {
        public string Month { get; set; } = "";
        public double Full { get; set; }
        public double Design { get; set; }
    }

    public sealed class AkkuBericht
    {
        public List<AkkuZelle> Batteries { get; } = new List<AkkuZelle>();
        public string Runtime { get; set; } = "";
        public string RuntimeNew { get; set; } = "";
        public List<AkkuMonat> History { get; } = new List<AkkuMonat>();
    }

    public static class Akku
    {
        static double Number(string text) => double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : 0;

        static string Child(XmlNode? node, string name)
        {
            if (node == null) return "";
            foreach (XmlNode c in node.ChildNodes) if (c.LocalName == name) return c.InnerText.Trim();
            return "";
        }

        static XmlNode? Node(XmlNode? node, string name)
        {
            if (node == null) return null;
            foreach (XmlNode c in node.ChildNodes) if (c.LocalName == name) return c;
            return null;
        }

        // XML von "powercfg /batteryreport /xml"; Verlauf: der erste Eintrag jedes Monats
        public static AkkuBericht Parse(string xml)
        {
            var r = new AkkuBericht();
            var doc = new XmlDocument();
            doc.LoadXml(xml);
            var report = doc.DocumentElement;
            var batteries = Node(report, "Batteries");
            if (batteries != null)
                foreach (XmlNode b in batteries.ChildNodes)
                {
                    if (b.LocalName != "Battery") continue;
                    r.Batteries.Add(new AkkuZelle { Name = Child(b, "Id"), Maker = Child(b, "Manufacturer"), Chemistry = Child(b, "Chemistry"),
                        Design = Number(Child(b, "DesignCapacity")), Full = Number(Child(b, "FullChargeCapacity")), Cycles = (int)Number(Child(b, "CycleCount")) });
                }
            var estimates = Node(report, "RuntimeEstimates");
            r.Runtime = Child(Node(estimates, "FullChargeCapacity"), "ActiveRuntime");
            r.RuntimeNew = Child(Node(estimates, "DesignCapacity"), "ActiveRuntime");
            var months = new SortedDictionary<string, AkkuMonat>(StringComparer.Ordinal);
            var history = Node(report, "History");
            if (history != null)
                foreach (XmlNode e in history.ChildNodes)
                {
                    if (e.LocalName != "HistoryEntry") continue;
                    var day = Child(e, "LocalStartDate");
                    if (day.Length == 0) day = Child(e, "StartDate");
                    if (day.Length < 7) continue;
                    var month = day.Substring(0, 7);
                    if (!months.ContainsKey(month)) months[month] = new AkkuMonat { Month = month, Full = Number(Child(e, "FullChargeCapacity")), Design = Number(Child(e, "DesignCapacity")) };
                }
            r.History.AddRange(months.Values);
            return r;
        }

        // "PT3H4M5S" (so schreibt Windows Zeitspannen) → "3 Std. 4 Min."; leer unter einer Minute
        public static string Time(string text)
        {
            if (string.IsNullOrEmpty(text)) return "";
            TimeSpan span;
            try { span = XmlConvert.ToTimeSpan(text); } catch (Exception) { return ""; }
            if (span.TotalMinutes < 1) return "";
            return span.TotalHours >= 1 ? (int)Math.Floor(span.TotalHours) + " Std. " + span.Minutes + " Min." : span.Minutes + " Min.";
        }

        // Zustand: volle Ladekapazität im Verhältnis zur ursprünglichen; null ohne Werte
        public static (int Percent, string Tone)? Health(double design, double full)
        {
            if (design <= 0 || full <= 0) return null;
            var percent = Math.Min(100, (int)Math.Round(100.0 * full / design, MidpointRounding.AwayFromZero));
            return (percent, Tone(percent));
        }

        public static string Tone(int percent) => percent >= 80 ? "good" : percent >= 60 ? "warn" : "bad";

        public static string Verdict(string tone) => tone switch
        {
            "good" => "Der Akku ist gut in Schuss.",
            "warn" => "Der Akku hat merklich nachgelassen; das ist nach einigen Jahren normal.",
            _ => "Der Akku fasst nur noch wenig. Ein Tausch lohnt sich, wenn das Notebook oft ohne Netzteil laufen soll.",
        };

        public static string Chemistry(string code) => code switch
        {
            "LION" or "Li-I" => "Lithium-Ionen",
            "LiP" => "Lithium-Polymer",
            _ => code,
        };

        // bis sechs Monate alle, sonst der erste und die letzten fünf
        public static List<AkkuMonat> Pick(IEnumerable<AkkuMonat> history)
        {
            var list = history.Where(m => m.Full > 0 && m.Design > 0).ToList();
            if (list.Count < 2) return new List<AkkuMonat>();
            if (list.Count <= 6) return list;
            return new[] { list[0] }.Concat(list.Skip(list.Count - 5)).ToList();
        }
    }
}
