#if NET
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;

namespace PulsRig.Core;

// Neue Vollsicherungen werden erst nach Export, Prüfsummen und ZIP veröffentlicht.
// Arbeitsordner bleiben bei Fehlern zur Diagnose liegen, werden aber nie angeboten.
public static class Sicherungsablage
{
    public const string ManifestName = "PulsRig-Sicherung.json";
    public sealed record Datei(string Name, long Bytes, string Sha256);
    public sealed record Manifest(int Format, DateTime Created, string Kind, Datei[] Files);
    public sealed record Befund(int Packages, bool Verified, string Kind = "legacy");
    public static bool IsKind(string? kind) => kind is "full" or "automatic" or "single";
    static int active;
    public static int ActiveCount => Volatile.Read(ref active);
    sealed class Activity : IDisposable
    {
        public Activity() => Interlocked.Increment(ref active);
        public void Dispose() => Interlocked.Decrement(ref active);
    }

    public static void RequireRestorePoint(int? status)
    {
        if (status != 0) throw new InvalidOperationException("Kein bestätigter Wiederherstellungspunkt (Windows-Code " + (status?.ToString() ?? "unbekannt") + ").");
    }

    static string Hash(string file)
    {
        using var stream = File.OpenRead(file);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    static FileInfo[] Files(string folder)
    {
        var result = new List<FileInfo>();
        void Visit(DirectoryInfo dir)
        {
            if (dir.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException("Die Sicherung enthält einen verknüpften Ordner.");
            foreach (var file in dir.GetFiles())
            {
                if (file.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException("Die Sicherung enthält eine verknüpfte Datei.");
                if (file.Name != ManifestName || dir.FullName != Path.GetFullPath(folder)) result.Add(file);
            }
            foreach (var child in dir.GetDirectories()) Visit(child);
        }
        Visit(new DirectoryInfo(folder));
        return result.ToArray();
    }

    public static string Create(string root, Action<string> export, Action<string, string>? archive = null, string kind = "full",
        Action<string>? progress = null, CancellationToken cancellationToken = default)
    {
        using var activity = new Activity();
        cancellationToken.ThrowIfCancellationRequested();
        if (!IsKind(kind)) throw new ArgumentException("Unbekannte Sicherungsart.", nameof(kind));
        Directory.CreateDirectory(root);
        var prefix = kind switch { "automatic" => "Auto-Sicherung_", "single" => "Einzeltreiber_", _ => "Backup_" };
        var name = prefix + DateTime.Now.ToString("yyyy-MM-dd_HHmmss_fff") + "_" + Guid.NewGuid().ToString("N");
        var target = Path.Combine(root, name);
        var work = Path.Combine(root, ".PulsRig-Arbeit_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        progress?.Invoke("Treiber werden exportiert …");
        export(work);
        cancellationToken.ThrowIfCancellationRequested();
        progress?.Invoke("Dateien werden geprüft …");
        var files = Files(work);
        if (!files.Any(f => f.Extension.Equals(".inf", StringComparison.OrdinalIgnoreCase)))
            throw new InvalidDataException("Es wurden keine Treiberpakete exportiert. Die Sicherung wurde nicht abgeschlossen.");
        var manifest = new Manifest(1, DateTime.Now, kind, files.Select(f =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            return new Datei(Path.GetRelativePath(work, f.FullName), f.Length, Hash(f.FullName));
        }).ToArray());
        File.WriteAllText(Path.Combine(work, ManifestName), JsonSerializer.Serialize(manifest));
        var pending = work + ".zip.partial";
        cancellationToken.ThrowIfCancellationRequested();
        progress?.Invoke("Archiv wird erstellt …");
        (archive ?? ((source, zip) => ZipFile.CreateFromDirectory(source, zip, CompressionLevel.Optimal, false)))(work, pending);
        cancellationToken.ThrowIfCancellationRequested();
        progress?.Invoke("Archiv wird geprüft …");
        // Eine defekte oder unvollständige Archivdatei darf keine gültige Sicherung ergeben.
        using (var zip = ZipFile.OpenRead(pending))
        {
            if (zip.Entries.Count(e => !e.FullName.EndsWith('/')) != manifest.Files.Length + 1) throw new InvalidDataException("Das Sicherungsarchiv ist unvollständig.");
            foreach (var file in manifest.Files)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var entry = zip.GetEntry(file.Name.Replace('\\', '/')) ?? zip.GetEntry(file.Name);
                if (entry == null || entry.Length != file.Bytes) throw new InvalidDataException("Das Sicherungsarchiv ist unvollständig.");
                using var stream = entry.Open();
                if (Convert.ToHexString(SHA256.HashData(stream)) != file.Sha256) throw new InvalidDataException("Die Archivprüfung ist fehlgeschlagen.");
            }
            using var saved = (zip.GetEntry(ManifestName) ?? throw new InvalidDataException("Die Sicherungsbeschreibung fehlt im Archiv.")).Open();
            using var reader = new StreamReader(saved);
            if (reader.ReadToEnd() != File.ReadAllText(Path.Combine(work, ManifestName))) throw new InvalidDataException("Die Archivprüfung ist fehlgeschlagen.");
        }
        // Move überschreibt keine vorhandenen Dateien. Ein Abbruch lässt höchstens ein einzelnes Archiv zurück.
        cancellationToken.ThrowIfCancellationRequested();
        File.Move(pending, target + ".zip");
        Directory.Move(work, target);
        return target;
    }

    public static Befund Inspect(string folder, bool verify = false)
    {
        if (!Directory.Exists(folder)) throw new InvalidDataException("Der Sicherungsordner ist nicht mehr vorhanden.");
        if (!Sicherung.IsBackupFolder(Path.GetFileName(folder.TrimEnd(Path.DirectorySeparatorChar))))
            throw new InvalidDataException("Diese Sicherung wurde nicht abgeschlossen.");
        var files = Files(folder);
        var count = files.Count(f => f.Extension.Equals(".inf", StringComparison.OrdinalIgnoreCase));
        if (count == 0) throw new InvalidDataException("In dieser Sicherung liegen keine Treiberpakete.");
        var path = Path.Combine(folder, ManifestName);
        if (!File.Exists(path)) return new(count, false); // ältere und automatische Teilsicherungen
        if (new FileInfo(path).Length > 16 * 1024 * 1024) throw new InvalidDataException("Die Sicherungsbeschreibung ist zu groß.");
        Manifest? manifest;
        try { manifest = JsonSerializer.Deserialize<Manifest>(File.ReadAllText(path)); }
        catch (JsonException) { throw new InvalidDataException("Die Sicherungsbeschreibung ist beschädigt."); }
        if (manifest == null || manifest.Format != 1 || !IsKind(manifest.Kind) || manifest.Files == null || manifest.Files.Length != files.Length)
            throw new InvalidDataException("Die Sicherung ist unvollständig oder hat ein unbekanntes Format.");
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var actual = files.ToDictionary(f => Path.GetRelativePath(folder, f.FullName), StringComparer.OrdinalIgnoreCase);
        foreach (var item in manifest.Files)
        {
            if (item == null || string.IsNullOrEmpty(item.Name) || !names.Add(item.Name) || !actual.TryGetValue(item.Name, out var file) || file.Length != item.Bytes)
                throw new InvalidDataException("Die Sicherung ist unvollständig oder wurde verändert.");
            if (verify && Hash(file.FullName) != item.Sha256) throw new InvalidDataException("Die Prüfsumme einer Sicherungsdatei stimmt nicht.");
        }
        return new(count, verify, manifest.Kind);
    }

    public static string Import(string archive, string root, Action<string>? progress = null, CancellationToken cancellationToken = default)
    {
        using var activity = new Activity();
        cancellationToken.ThrowIfCancellationRequested();
        progress?.Invoke("Archiv wird geprüft …");
        using var zip = ZipFile.OpenRead(archive);
        if (zip.Entries.Count > 100000) throw new InvalidDataException("Das Archiv enthält zu viele Dateien.");
        long bytes = 0;
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in zip.Entries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var name = entry.FullName.Replace('\\', '/').TrimEnd('/');
            var parts = name.Split('/');
            if (name.Length == 0 || !names.Add(name) || parts.Any(p => p.Length == 0 || p is "." or ".." || p.EndsWith(' ') || p.EndsWith('.')
                || p.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0
                || System.Text.RegularExpressions.Regex.IsMatch(p, @"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)", System.Text.RegularExpressions.RegexOptions.IgnoreCase))
                || (entry.ExternalAttributes >> 16 & 0xF000) == 0xA000 || (entry.ExternalAttributes & (int)FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Das Archiv enthält einen unsicheren oder doppelten Dateipfad.");
            bytes = checked(bytes + entry.Length);
            if (bytes > 32L * 1024 * 1024 * 1024) throw new InvalidDataException("Das entpackte Archiv ist größer als 32 GB.");
        }
        Directory.CreateDirectory(root);
        var drive = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(root))!);
        if (drive.AvailableFreeSpace < bytes + 512L * 1024 * 1024) throw new IOException("Zum Entpacken ist nicht genug freier Speicherplatz vorhanden.");
        var work = Path.Combine(root, ".PulsRig-Import_" + Guid.NewGuid().ToString("N"));
        var stage = Path.Combine(work, "Backup_Import");
        Directory.CreateDirectory(stage);
        progress?.Invoke("Archiv wird entpackt …");
        foreach (var entry in zip.Entries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var destination = Path.GetFullPath(Path.Combine(stage, entry.FullName.Replace('/', Path.DirectorySeparatorChar)));
            if (!destination.StartsWith(stage + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Ungültiger Archivpfad.");
            if (entry.FullName.EndsWith('/') || entry.FullName.EndsWith('\\')) { Directory.CreateDirectory(destination); continue; }
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            using var input = entry.Open();
            using var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            var buffer = new byte[1024 * 1024];
            long written = 0;
            int read;
            while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
            {
                cancellationToken.ThrowIfCancellationRequested();
                written += read;
                if (written > entry.Length) throw new InvalidDataException("Die entpackte Dateigröße stimmt nicht.");
                output.Write(buffer, 0, read);
            }
            if (written != entry.Length) throw new InvalidDataException("Die entpackte Dateigröße stimmt nicht.");
        }
        // ZIPs der bisherigen Vollsicherung enthalten die Dateien direkt, ohne zusätzlichen äußeren Ordner.
        cancellationToken.ThrowIfCancellationRequested();
        progress?.Invoke("Dateien werden geprüft …");
        var check = Inspect(stage, verify: true);
        var prefix = check.Kind switch { "automatic" => "Auto-Sicherung_", "single" => "Einzeltreiber_", _ => "Backup_" };
        var target = Path.Combine(root, prefix + "Import_" + DateTime.Now.ToString("yyyy-MM-dd_HHmmss") + "_" + Guid.NewGuid().ToString("N"));
        cancellationToken.ThrowIfCancellationRequested();
        Directory.Move(stage, target);
        Directory.Delete(work); // leer, ausschließlich für diesen Import angelegt
        return target;
    }

    public static List<DirectoryInfo> Find(params string[] roots)
    {
        var result = new Dictionary<string, DirectoryInfo>(StringComparer.OrdinalIgnoreCase);
        foreach (var root in roots.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                foreach (var dir in new DirectoryInfo(root).GetDirectories().Where(d => Sicherung.IsBackupFolder(d.Name)))
                    try { Inspect(dir.FullName); result[dir.FullName] = dir; } catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or ArgumentException) { }
            }
            catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or ArgumentException) { }
        }
        return result.Values.OrderByDescending(d => d.LastWriteTimeUtc).ToList();
    }
}
#endif
