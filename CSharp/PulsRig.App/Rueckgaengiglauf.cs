using System.Diagnostics;
using Microsoft.Win32;
using PulsRig.Core;

namespace PulsRig.App;

// Rückgängig-Zentrale: schreibt jede Änderung von PulsRig ins Protokoll (Core.Rueckgaengig) und nimmt sie zurück,
// soweit das sicher geht. Was sich nicht automatisch zurücknehmen lässt, steht nur zur Übersicht da.
static class Rueckgaengiglauf
{
    public static string File => System.IO.Path.Combine(Altdaten.Folder, "PulsRig-Aenderungen.json");
    public static event Action? Changed;

    public static string Area(string tool) => WerkzeugePage.NameOf(tool);

    public static void Record(string area, string text, string undo = "", string data = "")
    {
        try
        {
            // ein Gegenschritt (Autostart wieder an) erledigt den offenen alten Eintrag, statt einen zweiten anzulegen
            if (undo == "autostart") Rueckgaengig.Settle(File, undo, Rueckgaengig.Flip(data));
            Rueckgaengig.Add(File, new Rueckgabe(DateTime.Now, area, text, undo, data));
        }
        catch (Exception) { }   // das Protokoll darf nie die eigentliche Änderung stören
        Notify();
    }

    public static void Settle(string undo, string data)
    {
        try { Rueckgaengig.Settle(File, undo, data); } catch (Exception) { }
        Notify();
    }

    static void Notify() => System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => Changed?.Invoke());

    // Knopftext oder leer, wenn sich der Eintrag nicht (mehr) zurücknehmen lässt
    public static string Button(Rueckgabe a) => a.Undone ? "" : a.Undo switch
    {
        "autostart" => a.Data.EndsWith("|1") ? "Wieder einschalten" : "Wieder ausschalten",
        "boost" => Spielboost.State() != null ? "Boost ausschalten" : "",
        "restorepoint" => "Wiederherstellung öffnen",
        _ => "",
    };

    public static string Undo(Rueckgabe a)
    {
        switch (a.Undo)
        {
            case "autostart":
            {
                var part = a.Data.Split('|');
                if (part.Length < 4) return "Eintrag unvollständig.";
                if (part[0] == "HKLM" && !App.IsAdmin) return "Dieser Eintrag gilt für alle Benutzer – dafür muss PulsRig als Administrator laufen.";
                using var key = (part[0] == "HKLM" ? Registry.LocalMachine : Registry.CurrentUser)
                    .CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\" + part[1]);
                key.SetValue(part[2], Core.Autostart.Approved(part[3] == "1", DateTime.Now), RegistryValueKind.Binary);
                Rueckgaengig.MarkUndone(File, a);
                Notify();
                return "";
            }
            case "boost":
                Spielboost.Off();
                return "";
            case "restorepoint":
                // Windows zeigt die Wiederherstellungspunkte; welchen man nimmt, entscheidet man dort selbst
                Process.Start(new ProcessStartInfo("rstrui.exe") { UseShellExecute = true });
                return "";
        }
        return "";
    }
}
