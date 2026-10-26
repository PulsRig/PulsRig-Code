using System.IO;

namespace PulsRig.App;

// Arbeit ohne Fenster für den Helfer neben der Uhr, wie PulsRig-Hintergrund.ps1. PulsRig.exe reicht sie an die App weiter:
//   -Boost Ein [-Spiel Name]   Boost einschalten (Spielmodus, Energieplan, Dienste – Programme schließt er nie)
//   -Boost Aus                 Boost ausschalten und alles zurückstellen
//   -Wochenscan                nach neueren Treibern sehen
// Es gibt nichts aus und fragt nichts; was es tut, steht in PulsRig-Hintergrund.log neben den Einstellungen.
// Das Ergebnis ist eine Zahl: beim Wochenscan die Zahl neuer Treiber (-1 fehlgeschlagen), sonst 0.
static class Hintergrund
{
    static string LogFile => Path.Combine(Altdaten.Folder, "PulsRig-Hintergrund.log");

    static void Log(string text)
    {
        try { File.AppendAllText(LogFile, DateTime.Now.ToString("dd.MM. HH:mm:ss") + "  " + text + "\r\n"); } catch (Exception) { }
    }

    // null: keine Arbeit ohne Fenster, die App öffnet ihr Fenster
    public static int? Run(string[] args)
    {
        string? Arg(string name)
        {
            var at = Array.FindIndex(args, a => a.Equals(name, StringComparison.OrdinalIgnoreCase));
            return at < 0 ? null : at + 1 < args.Length ? args[at + 1] : "";
        }
        var boost = Arg("-Boost");
        var weekly = Arg("-Wochenscan") != null;
        if (boost == null && !weekly) return null;
        try
        {
            Directory.CreateDirectory(Altdaten.Folder);
            if (new FileInfo(LogFile) is { Exists: true, Length: > 256 * 1024 }) File.Delete(LogFile);
        }
        catch (Exception) { }
        var game = Arg("-Spiel");
        // nur Namen von Programmdateien, wie sie der Helfer übergibt
        if (game != null && (game.Length == 0 || game.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)) game = null;
        Log("=== " + (weekly ? "Wochenscan" : "Boost " + boost + (game != null ? " " + game : "")) + " (neue Oberfläche) ===");
        try
        {
            if (weekly) return Treiberscan.Weekly(Log);
            if (boost!.Equals("Aus", StringComparison.OrdinalIgnoreCase))
            {
                Spielboost.OffQuietly();
                Log("Boost ist " + (Spielboost.IsOn ? "noch an" : "aus"));
            }
            else Log(Spielboost.OnQuietly(game) ? "Boost ist an" : "Nichts umzustellen");
            return 0;
        }
        catch (Exception e)
        {
            Log("Fehler: " + e.Message);
            return weekly ? -1 : 0;
        }
    }
}
