// PulsRig.Core - Speicher-Analyse: was belegt ein Laufwerk (wie WizTree/TreeSize), nur lesend.
// Folgt keinen Junctions oder symbolischen Verknüpfungen (sonst zählt z. B. "Dokumente und Einstellungen" doppelt)
// und überspringt Ordner ohne Leserecht. Gezählt wird die Dateigröße, nicht der belegte Platz auf der Platte.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
namespace PulsRig.Core;

public sealed class Platzordner
{
    public required string Path { get; init; }
    public string Name => System.IO.Path.GetFileName(Path.TrimEnd('\\')) is { Length: > 0 } n ? n : Path;
    public long Size { get; set; }
    public long Files { get; set; }
    public Platzart Art { get; set; }
    // Unterordner nur bis zur Tiefe MaxDepth, tiefere Ebenen stecken in Size
    public List<Platzordner> Children { get; } = new();
}

// Eigene = Dateien des Nutzers, die man selbst löschen darf; alles andere gehört zu Windows, einem Programm oder Spiel
// und wird nur als Ganzes gezeigt (deinstallieren statt einzelne Dateien löschen)
public enum Platzart { Eigene, Spiel, Programm, System, Papierkorb }

public sealed record Platzdatei(string Path, long Size, DateTime Changed);

public sealed record Platzkategorie(string Name, long Size, string Path);

public sealed record Platzergebnis(Platzordner Root, List<Platzdatei> Biggest, int Skipped, TimeSpan Duration);

public static class Platzanalyse
{
    public const int MaxDepth = 6;
    public const int TopFiles = 50;

    static readonly EnumerationOptions Options = new()
    {
        RecurseSubdirectories = false, IgnoreInaccessible = true, ReturnSpecialDirectories = false,
        AttributesToSkip = FileAttributes.ReparsePoint,
    };

    public static Platzergebnis Run(string root, CancellationToken cancel = default, Action<long>? progress = null)
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        var top = new Bestenliste(TopFiles);
        var skipped = 0;
        long seen = 0;
        var node = new Platzordner { Path = root, Art = Platzart.Eigene };
        Walk(node, 0);
        Sort(node);
        return new(node, top.Sorted(), skipped, watch.Elapsed);

        void Walk(Platzordner dir, int depth)
        {
            cancel.ThrowIfCancellationRequested();
            IEnumerable<FileSystemInfo> entries;
            try { entries = new DirectoryInfo(dir.Path).EnumerateFileSystemInfos("*", Options); }
            catch (Exception) { Interlocked.Increment(ref skipped); return; }
            var subs = new List<Platzordner>();
            try
            {
                foreach (var e in entries)
                {
                    if (e is FileInfo f)
                    {
                        long len;
                        try { len = f.Length; } catch (Exception) { continue; }
                        dir.Size += len;
                        dir.Files++;
                        if (dir.Art == Platzart.Eigene && !SystemFile(f.Name, depth)) top.Add(new Platzdatei(f.FullName, len, f.LastWriteTime));
                        if ((Interlocked.Increment(ref seen) & 4095) == 0) progress?.Invoke(seen);
                    }
                    else subs.Add(new Platzordner { Path = e.FullName, Art = Erbe(dir.Art, e.Name, depth == 0) });
                }
            }
            catch (Exception) { Interlocked.Increment(ref skipped); }
            // oberste Ebene parallel, darunter der Reihe nach - die Platte ist ohnehin der Engpass
            if (depth == 0) Parallel.ForEach(subs, new ParallelOptions { MaxDegreeOfParallelism = 4, CancellationToken = cancel }, s => Walk(s, 1));
            else foreach (var s in subs) Walk(s, depth + 1);
            foreach (var s in subs)
            {
                dir.Size += s.Size;
                dir.Files += s.Files;
                if (depth < MaxDepth) dir.Children.Add(s);
            }
        }
    }

    // Windows-Dateien direkt im Hauptverzeichnis (Ruhezustand, Auslagerung)
    static bool SystemFile(string name, int depth) => depth == 0 && name.EndsWith(".sys", StringComparison.OrdinalIgnoreCase);

    static readonly string[] Spiele =
    {
        "steamapps", "steamlibrary", "epic games", "riot games", "gog games", "gog galaxy", "xboxgames", "ea games", "ubisoft game launcher",
        "battle.net", "rockstar games", "roberts space industries", "steam", "beamng", "beamng.drive", "origin games", "amazon games", "play games", "minecraft", ".minecraft", "wargaming.net",
    };
    static readonly string[] Programme = { "program files", "program files (x86)", "programs", "appdata", "packages", "android", ".ollama", ".nuget", "nvidia", "nvidia corporation", "node_modules" };
    static readonly string[] Systemordner = { "windows", "programdata", "system volume information", "recovery", "$windows.~bt", "$windows.~ws", "windows.old", "$winreagent", "perflogs", "config.msi" };

    // Art eines Ordners am Pfad: der erste passende Abschnitt entscheidet, Spiele vor Programmen (Steam liegt in Program Files)
    public static Platzart Art(string path)
    {
        var parts = path.Split('\\',StringSplitOptions.RemoveEmptyEntries);
        var art = Platzart.Eigene;
        for (var k = 1; k < parts.Length; k++) art = Erbe(art, parts[k], k == 1);
        return art;
    }

    // Unterordner erben die Art; nur ein Spiel innerhalb von Programmen (Steam in Program Files) wird zum Spiel
    static Platzart Erbe(Platzart parent, string name, bool top) => parent switch
    {
        Platzart.Eigene => Abschnitt(name, top),
        Platzart.Programm when Abschnitt(name, top) == Platzart.Spiel => Platzart.Spiel,
        _ => parent,
    };

    // ein einzelner Ordnername; top = direkt im Hauptverzeichnis des Laufwerks
    static Platzart Abschnitt(string name, bool top)
    {
        var n = name.ToLowerInvariant();
        if (top && n == "$recycle.bin") return Platzart.Papierkorb;
        if (top && Systemordner.Contains(n)) return Platzart.System;
        if (Spiele.Contains(n)) return Platzart.Spiel;
        // versteckte Ordner wie .android, .cache, .vscode gehören zu Programmen
        if (Programme.Contains(n) || (n.StartsWith(".") && n.Length > 1)) return Platzart.Programm;
        return Platzart.Eigene;
    }

    // Übersicht wie die Windows-Speicherseite: Apps & Spiele, Windows, Temporäre Dateien, Benutzerordner, Andere.
    // Path ist der Ordner zum Hineinschauen (nur bei einem einzelnen Benutzerordner), sonst leer.
    public static List<Platzkategorie> Kategorien(Platzordner root)
    {
        var sums = new Dictionary<string, long>();
        var paths = new Dictionary<string, string>();
        void Add(string k, long v, string path = "")
        {
            if (v <= 0) return;
            sums[k] = sums.GetValueOrDefault(k) + v;
            paths[k] = paths.ContainsKey(k) ? "" : path;
        }
        string Rest(Platzart a) => a switch
        {
            Platzart.Spiel or Platzart.Programm => "Apps & Spiele",
            Platzart.System => "Windows",
            Platzart.Papierkorb => "Papierkorb",
            _ => "Andere",
        };
        var rootDepth = root.Path.Split('\\', StringSplitOptions.RemoveEmptyEntries).Length;
        void Visit(Platzordner n)
        {
            var parts = n.Path.Split('\\', StringSplitOptions.RemoveEmptyEntries);
            var name = parts.Length > 0 ? parts[^1].ToLowerInvariant() : "";
            var parent = parts.Length > 1 ? parts[^2].ToLowerInvariant() : "";
            var depth = parts.Length - rootDepth;
            if (name == "temp" && (parent == "local" || (parent == "windows" && depth == 2))) { Add("Temporäre Dateien", n.Size); return; }
            if (depth == 3 && parts[^3].Equals("users", StringComparison.OrdinalIgnoreCase) && n.Art == Platzart.Eigene && Benutzerordner.TryGetValue(name, out var user))
            {
                Add(user, n.Size, n.Path);
                return;
            }
            // Ordner, in denen noch Temp oder Benutzerordner stecken können, weiter aufteilen
            var split = n == root || n.Art == Platzart.Eigene || name is "appdata" or "local" || (name == "windows" && depth == 1);
            if (!split || n.Children.Count == 0) { Add(Rest(n.Art), n.Size); return; }
            foreach (var c in n.Children) Visit(c);
            // lose Dateien im Hauptverzeichnis sind Auslagerung und Ruhezustand
            Add(n == root ? "Windows" : Rest(n.Art), n.Size - n.Children.Sum(c => c.Size));
        }
        Visit(root);
        return sums.Select(s => new Platzkategorie(s.Key, s.Value, paths[s.Key])).OrderByDescending(k => k.Size).ToList();
    }

    static readonly Dictionary<string, string> Benutzerordner = new()
    {
        ["documents"] = "Dokumente", ["desktop"] = "Desktop", ["downloads"] = "Downloads", ["pictures"] = "Bilder",
        ["videos"] = "Videos", ["music"] = "Musik", ["onedrive"] = "OneDrive",
    };

    static void Sort(Platzordner n)
    {
        n.Children.Sort((a, b) => b.Size.CompareTo(a.Size));
        foreach (var c in n.Children) Sort(c);
    }

    // die größten Dateien, auch wenn mehrere Ordner gleichzeitig zählen
    sealed class Bestenliste(int size)
    {
        readonly object gate = new();
        readonly List<Platzdatei> list = new();
        long floor;

        public void Add(Platzdatei d)
        {
            if (d.Size <= Interlocked.Read(ref floor)) return;
            lock (gate)
            {
                list.Add(d);
                if (list.Count > size * 2)
                {
                    list.Sort((a, b) => b.Size.CompareTo(a.Size));
                    list.RemoveRange(size, list.Count - size);
                    Interlocked.Exchange(ref floor, list[^1].Size);
                }
            }
        }

        public List<Platzdatei> Sorted()
        {
            lock (gate) return list.OrderByDescending(x => x.Size).Take(size).ToList();
        }
    }
}
