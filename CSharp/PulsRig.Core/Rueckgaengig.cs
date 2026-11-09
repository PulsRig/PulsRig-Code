// PulsRig.Core - Rückgängig-Zentrale: Protokoll aller Änderungen, die PulsRig am System macht, mit der Angabe, wie
// sie sich zurücknehmen lassen. Die App führt die Rücknahme aus; hier stehen nur Liste, Laden und Speichern.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
namespace PulsRig.Core;

// Undo: "" = nicht automatisch rücknehmbar, "autostart" (Data = HKLM/HKCU|Ordner|Name|vorher an 1/0),
// "boost" (Spiel-Boost ausschalten), "restorepoint" (Systemwiederherstellung öffnen)
public sealed record Rueckgabe(DateTime Time, string Area, string Text, string Undo = "", string Data = "", bool Undone = false);

public static class Rueckgaengig
{
    public const int Keep = 300;
    static readonly object gate = new();
    static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public static List<Rueckgabe> Load(string file)
    {
        lock (gate)
        {
            try { return File.Exists(file) ? JsonSerializer.Deserialize<List<Rueckgabe>>(File.ReadAllText(file)) ?? new() : new(); }
            catch (Exception) { return new(); }   // kaputte Datei: neu anfangen statt abstürzen
        }
    }

    public static void Add(string file, Rueckgabe a) => Change(file, list => list.Add(a));

    // gleiche Art und gleiche Daten: der neueste noch offene Eintrag gilt als zurückgenommen
    public static void MarkUndone(string file, Rueckgabe a) => Change(file, list =>
    {
        var i = list.FindLastIndex(x => x.Time == a.Time && x.Text == a.Text && !x.Undone);
        if (i >= 0) list[i] = list[i] with { Undone = true };
    });

    // ein neuer Gegenschritt erledigt den alten (Autostart wieder an, Boost aus)
    public static void Settle(string file, string undo, string data) => Change(file, list =>
    {
        for (var i = 0; i < list.Count; i++)
            if (!list[i].Undone && list[i].Undo == undo && list[i].Data == data) list[i] = list[i] with { Undone = true };
    });

    static void Change(string file, Action<List<Rueckgabe>> edit)
    {
        lock (gate)
        {
            var list = Load(file);
            edit(list);
            if (list.Count > Keep) list.RemoveRange(0, list.Count - Keep);
            Directory.CreateDirectory(Path.GetDirectoryName(file)!);
            File.WriteAllText(file, JsonSerializer.Serialize(list, Json), new UTF8Encoding(true));
        }
    }

    // Autostart: Data für die Rücknahme und ihr Gegenstück
    public static string AutostartData(bool machine, string folder, string name, bool wasOn) => (machine ? "HKLM" : "HKCU") + "|" + folder + "|" + name + "|" + (wasOn ? "1" : "0");
    public static string Flip(string data) => data.EndsWith("|1") ? data[..^1] + "0" : data[..^1] + "1";
}
