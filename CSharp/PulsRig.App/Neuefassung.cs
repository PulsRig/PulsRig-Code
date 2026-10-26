using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json.Nodes;
using PulsRig.Core;

namespace PulsRig.App;

// Neue Fassung wie Start-VersionCheck und Open-UpdateSheet: beim Start einmal version.json bei GitHub lesen (nur im
// gebauten Programm, das sein Baudatum kennt, und nur mit der Einstellung UpdateCheck). Geladen wird nur auf Knopfdruck
// und gestartet nur, wenn Größe und SHA-256 zu den veröffentlichten Angaben passen. Mit Adminrechten im installierten
// Programm landet die Datei im Programmordner (Update), wo sie niemand ohne Adminrechte austauschen kann.
static class Neuefassung
{
    public sealed record Hinweis(string Version, string Built, string Setup, string Sha256, long Bytes);

    public static Hinweis? Found { get; private set; }
    public static string State { get; private set; } = "";

    // Baudatum aus PulsRig-Bau.txt, das PulsRig-Paket.ps1 neben die App legt
    public static string Build
    {
        get
        {
            try { var file = Path.Combine(AppContext.BaseDirectory, "PulsRig-Bau.txt"); return File.Exists(file) ? File.ReadAllText(file).Trim() : ""; }
            catch (Exception) { return ""; }
        }
    }

    static HttpClient Client()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("PulsRig");
        return client;
    }

    public static async Task<Hinweis?> Check()
    {
        if (Fassung.BuildTime(Build) == null || !Altdaten.Flag(Altdaten.Settings(), "UpdateCheck", true)) return null;
        try
        {
            using var client = Client();
            var json = await client.GetStringAsync("https://raw.githubusercontent.com/" + Fassung.Repo + "/main/version.json");
            // alles Unerwartete (zu lang, kein JSON, seltsame Zeichen) zählt als "keine Angabe"
            if (json.Length > 4000 || JsonNode.Parse(json) is not JsonObject note) { State = "Antwort nicht lesbar"; return null; }
            var version = Altdaten.Text(note, "Version", "");
            var built = Altdaten.Text(note, "Gebaut", "");
            if (!Fassung.IsValidVersion(version) || Fassung.BuildTime(built) == null) { State = "Antwort nicht lesbar"; return null; }
            if (!Fassung.IsNewer(Build, built)) { State = "aktuell"; return null; }
            var setup = Altdaten.Text(note, "Setup", "");
            var sha = Altdaten.Text(note, "Sha256", "");
            var bytes = note["Bytes"] is JsonValue b && b.TryGetValue<long>(out var n) ? n : 0;
            Found = Fassung.IsValidSetup(setup, sha, bytes) ? new(version, built, setup, sha.ToUpperInvariant(), bytes) : new(version, built, "", "", 0);
            State = "neuere Fassung: " + version + ", gebaut " + built;
            return Found;
        }
        catch (Exception) { State = "nicht erreichbar"; return null; }   // kein Netz ist kein Fehler
    }

    static string Folder => App.IsAdmin && Helfer.Exe is { } exe ? Path.Combine(Path.GetDirectoryName(exe)!, "Update") : Path.Combine(Path.GetTempPath(), "PulsRig-Update");

    // lädt, prüft und startet das Setup still; report bekommt den Fortschritt
    public static async Task<string> Install(Hinweis note, Action<string> report)
    {
        var folder = Folder;
        if (Directory.Exists(folder)) Directory.Delete(folder, true);
        Directory.CreateDirectory(folder);
        var file = Path.Combine(folder, "PulsRig-Setup.exe");
        using (var client = Client())
        {
            client.Timeout = TimeSpan.FromMinutes(5);
            using var response = await client.GetAsync(note.Setup, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();
            await using var input = await response.Content.ReadAsStreamAsync();
            await using var output = File.Create(file);
            var buffer = new byte[81920];
            long have = 0;
            for (int read; (read = await input.ReadAsync(buffer)) > 0;)
            {
                // nie mehr annehmen, als angekündigt ist
                if ((have += read) > note.Bytes) throw new InvalidOperationException("Die Datei ist größer als angekündigt.");
                await output.WriteAsync(buffer.AsMemory(0, read));
                report("Lade die Setup-Datei: " + (have / 1048576.0).ToString("N1", Ui.De) + " von " + (note.Bytes / 1048576.0).ToString("N1", Ui.De) + " MB");
            }
        }
        string hash;
        await using (var check = File.OpenRead(file)) hash = Convert.ToHexString(await SHA256.HashDataAsync(check));
        if (new FileInfo(file).Length != note.Bytes || hash != note.Sha256)
        {
            try { File.Delete(file); } catch (Exception) { }
            return "Die geladene Datei passt nicht zu den veröffentlichten Angaben. Sie wurde gelöscht und nicht gestartet.";
        }
        try { Process.Start(new ProcessStartInfo(file, "/SILENT /PULSRIGUPDATE=1") { UseShellExecute = true }); }
        catch (Exception) { return "Die Installation wurde nicht gestartet – die Abfrage von Windows wurde abgelehnt oder die Datei ließ sich nicht öffnen."; }
        return "";
    }
}
