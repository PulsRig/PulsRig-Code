using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace PulsRig.App;

// Daten des PowerShell-Programms, die beide Programme teilen, solange es noch ausgeliefert wird: Einstellungen
// (PulsRig-Einstellungen.json), Zustand des Boosts und Aufzeichnungen. Geschrieben werden nur einzelne Schlüssel,
// alle anderen bleiben, wie das PowerShell-Programm sie gespeichert hat.
static class Altdaten
{
    // Programmordner mit PulsRig.exe, wenn die App wie im Paket in dessen Unterordner App liegt; sonst null (beim Entwickeln)
    public static string? ProgramRoot { get; } = FindProgramRoot();

    static string? FindProgramRoot()
    {
        var app = new DirectoryInfo(AppContext.BaseDirectory.TrimEnd('\\'));
        return app.Name.Equals("App", StringComparison.OrdinalIgnoreCase) && app.Parent is { } p && File.Exists(Path.Combine(p.FullName, "PulsRig.exe")) ? p.FullName : null;
    }

    // wie $script:Installed in PulsRig.ps1: liegt PulsRig nicht unter "Programme" (etwa auf dem Notfall-Stick), bleiben
    // die Daten daneben in Treiber\
    public static string? Portable => ProgramRoot is { } r && !r.StartsWith(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), StringComparison.OrdinalIgnoreCase) ? r : null;

    // installiert %LOCALAPPDATA%\PulsRig, ohne Installation Treiber\ daneben, beim Entwickeln Treiber\ neben Treiber-Scan.ps1
    public static string Folder
    {
        get
        {
            if (Portable is { } stick) return Path.Combine(stick, "Treiber");
            var installed = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PulsRig");
            if (File.Exists(Path.Combine(installed, "PulsRig-Einstellungen.json"))) return installed;
            for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
                if (File.Exists(Path.Combine(dir.FullName, "Treiber-Scan.ps1")) && Directory.Exists(Path.Combine(dir.FullName, "Treiber"))) return Path.Combine(dir.FullName, "Treiber");
            return installed;
        }
    }

    public static string SettingsFile => Path.Combine(Folder, "PulsRig-Einstellungen.json");

    static readonly object Gate = new();

    public static JsonObject Settings()
    {
        lock (Gate)
            try { return File.Exists(SettingsFile) ? JsonNode.Parse(File.ReadAllText(SettingsFile)) as JsonObject ?? new() : new(); }
            catch (Exception) { return new(); }
    }

    // liest, ändert und schreibt in einem Zug
    public static void Change(Action<JsonObject> change)
    {
        lock (Gate)
        {
            var settings = Settings();
            change(settings);
            Directory.CreateDirectory(Folder);
            File.WriteAllText(SettingsFile, settings.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), new UTF8Encoding(false));
        }
    }

    public static List<string> List(JsonNode? node, string name) =>
        node?[name] is JsonArray a ? a.Select(x => x?.ToString() ?? "").Where(x => x.Length > 0).ToList()
        : node?[name] is JsonValue v && v.ToString().Length > 0 ? new() { v.ToString() } : new();

    public static bool Flag(JsonNode? node, string name, bool fallback) =>
        node?[name] is JsonValue v && v.TryGetValue<bool>(out var b) ? b : fallback;

    public static string Text(JsonNode? node, string name, string fallback) =>
        node?[name] is JsonValue v && v.TryGetValue<string>(out var s) ? s : fallback;

    public static JsonArray Array(IEnumerable<string> items) => new(items.Select(x => (JsonNode)x).ToArray());
}

// Ergebnisdatei des PowerShell-Programms (PulsRig-Ergebnisse.json): Verlauf der Benchmarks und Messungen.
// Wie bei den Einstellungen wird nur der eigene Teil geändert, der Rest bleibt.
static class Ergebnisse
{
    public static string File => Path.Combine(Altdaten.Folder, "PulsRig-Ergebnisse.json");

    static readonly object Gate = new();

    public static JsonObject Read()
    {
        lock (Gate)
            try { return System.IO.File.Exists(File) ? JsonNode.Parse(System.IO.File.ReadAllText(File)) as JsonObject ?? new() : new(); }
            catch (Exception) { return new(); }
    }

    // erst daneben schreiben, dann an den Platz (wie Save-TextFile): bricht es ab, bleibt die alte Datei heil
    public static void Change(Action<JsonObject> change)
    {
        lock (Gate)
        {
            var results = Read();
            change(results);
            Directory.CreateDirectory(Altdaten.Folder);
            var draft = File + ".neu";
            System.IO.File.WriteAllText(draft, results.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), new UTF8Encoding(true));
            System.IO.File.Move(draft, File, true);
        }
    }

    public static JsonObject History(JsonObject results) => results["History"] as JsonObject ?? (JsonObject)(results["History"] = new JsonObject());
}
