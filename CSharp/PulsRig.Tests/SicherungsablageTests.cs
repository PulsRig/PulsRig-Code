using System.IO.Compression;
using System.Text.Json;
using PulsRig.Core;

namespace PulsRig.Tests;

public sealed class SicherungsablageTests : IDisposable
{
    readonly string root = Path.Combine(Path.GetTempPath(), "PulsRig-Sicherungstest-" + Guid.NewGuid().ToString("N"));
    static void Export(string folder)
    {
        var dir = Directory.CreateDirectory(Path.Combine(folder, "driver"));
        File.WriteAllText(Path.Combine(dir.FullName, "test.inf"), "test INF");
        File.WriteAllText(Path.Combine(dir.FullName, "test.sys"), "test driver");
    }
    public void Dispose() { if (Directory.Exists(root)) Directory.Delete(root, true); }

    [Fact]
    public void CompletedBackupHasMatchingArchiveAndHashes()
    {
        var path = Sicherungsablage.Create(root, Export);
        Assert.Equal(new Sicherungsablage.Befund(1, true, "full"), Sicherungsablage.Inspect(path, true));
        using var zip = ZipFile.OpenRead(path + ".zip");
        Assert.Equal(3, zip.Entries.Count);
        Assert.Single(Sicherungsablage.Find(root));
    }

    [Fact]
    public void RepeatedBackupNeverReusesOrDeletesExistingArchive()
    {
        var first = Sicherungsablage.Create(root, Export);
        var bytes = File.ReadAllBytes(first + ".zip");
        var second = Sicherungsablage.Create(root, Export);
        Assert.NotEqual(first, second);
        Assert.Equal(bytes, File.ReadAllBytes(first + ".zip"));
        Assert.Equal(2, Sicherungsablage.Find(root).Count);
    }

    [Fact]
    public void ExportFailureRemainsHiddenAndPreservesPreviousBackup()
    {
        var first = Sicherungsablage.Create(root, Export);
        Assert.Throws<IOException>(() => Sicherungsablage.Create(root, p => { Export(p); throw new IOException("export interrupted"); }));
        Assert.Equal(first, Assert.Single(Sicherungsablage.Find(root)).FullName);
        Assert.True(Sicherungsablage.Inspect(first, true).Verified);
    }

    [Fact]
    public void ArchiveFailureRemainsHiddenAndPreservesPreviousArchive()
    {
        var first = Sicherungsablage.Create(root, Export);
        var bytes = File.ReadAllBytes(first + ".zip");
        Assert.Throws<IOException>(() => Sicherungsablage.Create(root, Export, (_, zip) => { File.WriteAllText(zip, "partial"); throw new IOException("disk full"); }));
        Assert.Single(Sicherungsablage.Find(root));
        Assert.Equal(bytes, File.ReadAllBytes(first + ".zip"));
    }

    [Fact]
    public void EmptyExportAndCorruptArchiveAreNeverPublished()
    {
        Assert.Throws<InvalidDataException>(() => Sicherungsablage.Create(root, _ => { }));
        Assert.Throws<InvalidDataException>(() => Sicherungsablage.Create(root, Export, (_, zip) => File.WriteAllText(zip, "bad ZIP")));
        Assert.Empty(Sicherungsablage.Find(root));
    }

    [Fact]
    public void ChangedBytesMissingFilesAndExtraFilesAreRejected()
    {
        var path = Sicherungsablage.Create(root, Export);
        var file = Path.Combine(path, "driver", "test.sys");
        File.WriteAllText(file, "xxxx driver"); // same length, only checksum catches it
        Assert.Throws<InvalidDataException>(() => Sicherungsablage.Inspect(path, true));
        File.Delete(file);
        Assert.Throws<InvalidDataException>(() => Sicherungsablage.Inspect(path, true));
        Assert.Empty(Sicherungsablage.Find(root));
        var next = Sicherungsablage.Create(root, Export);
        File.WriteAllText(Path.Combine(next, "extra.sys"), "extra");
        Assert.Throws<InvalidDataException>(() => Sicherungsablage.Inspect(next, true));
    }

    [Fact]
    public void LegacyBackupsAreFoundAcrossRootsButEmptyFoldersAreExcluded()
    {
        var legacy = Path.Combine(root, "old");
        var folder = Path.Combine(legacy, "Auto-Sicherung_2026-10-01_1200");
        Directory.CreateDirectory(folder);
        Export(folder);
        Directory.CreateDirectory(Path.Combine(root, "Backup_empty"));
        Assert.False(Sicherungsablage.Inspect(folder, true).Verified);
        Assert.Equal(folder, Assert.Single(Sicherungsablage.Find(root, legacy, legacy)).FullName);
    }

    [Fact]
    public void DuplicateManifestEntriesCannotHideMissingFiles()
    {
        var path = Sicherungsablage.Create(root, Export);
        var file = Path.Combine(path, Sicherungsablage.ManifestName);
        var data = JsonSerializer.Deserialize<Sicherungsablage.Manifest>(File.ReadAllText(file))!;
        File.WriteAllText(file, JsonSerializer.Serialize(data with { Files = new[] { data.Files[0], data.Files[0] } }));
        Assert.Throws<InvalidDataException>(() => Sicherungsablage.Inspect(path, true));
    }

    [Theory]
    [InlineData(null)]
    [InlineData(5)]
    [InlineData(-1)]
    public void RestorePointErrorsCannotBecomeSuccess(int? status) =>
        Assert.Throws<InvalidOperationException>(() => Sicherungsablage.RequireRestorePoint(status));

    [Fact]
    public void RestorePointSuccessIsAccepted() => Sicherungsablage.RequireRestorePoint(0);

    [Fact]
    public void ConcurrentBackupsDoNotShareTargets()
    {
        var targets = new System.Collections.Concurrent.ConcurrentBag<string>();
        Parallel.For(0, 4, _ => targets.Add(Sicherungsablage.Create(root, Export)));
        Assert.Equal(4, targets.Distinct().Count());
        Assert.Equal(4, Sicherungsablage.Find(root).Count);
        Assert.All(targets, p => Assert.True(Sicherungsablage.Inspect(p, true).Verified));
    }

    [Theory]
    [InlineData("automatic", "Auto-Sicherung_")]
    [InlineData("single", "Einzeltreiber_")]
    public void PartialBackupsUseTheSameVerifiedPublication(string kind, string prefix)
    {
        var path = Sicherungsablage.Create(root, Export, kind: kind);
        Assert.StartsWith(prefix, Path.GetFileName(path));
        Assert.Equal(kind, Sicherungsablage.Inspect(path, true).Kind);
        Assert.True(File.Exists(path + ".zip"));
        Assert.Throws<IOException>(() => Sicherungsablage.Create(root, p => { Export(p); throw new IOException(); }, kind: kind));
        Assert.Single(Sicherungsablage.Find(root));
    }

    [Fact]
    public void ImportVerifiesNewArchiveAndDoesNotOverwriteExistingBackup()
    {
        var path = Sicherungsablage.Create(root, Export, kind: "single");
        var first = Sicherungsablage.Import(path + ".zip", root);
        var second = Sicherungsablage.Import(path + ".zip", root);
        Assert.NotEqual(first, second);
        Assert.Equal("single", Sicherungsablage.Inspect(first, true).Kind);
        Assert.Equal(3, Sicherungsablage.Find(root).Count);
    }

    [Theory]
    [InlineData("../escape.inf")]
    [InlineData("/root.inf")]
    [InlineData("C:/escape.inf")]
    [InlineData("driver.sys:stream")]
    [InlineData("NUL.inf")]
    public void ImportRejectsUnsafePaths(string name)
    {
        Directory.CreateDirectory(root);
        var path = Path.Combine(root, "bad.zip");
        using (var zip = ZipFile.Open(path, ZipArchiveMode.Create)) { using var writer = new StreamWriter(zip.CreateEntry(name).Open()); writer.Write("bad"); }
        Assert.Throws<InvalidDataException>(() => Sicherungsablage.Import(path, root));
        Assert.Empty(Sicherungsablage.Find(root));
    }

    [Fact]
    public void ImportRejectsChangedArchiveBeforePublication()
    {
        var path = Sicherungsablage.Create(root, Export);
        using (var zip = ZipFile.Open(path + ".zip", ZipArchiveMode.Update))
        {
            zip.GetEntry("driver/test.sys")?.Delete();
            zip.GetEntry("driver\\test.sys")?.Delete();
            using var writer = new StreamWriter(zip.CreateEntry("driver/test.sys").Open());
            writer.Write("xxxx driver");
        }
        Assert.Throws<InvalidDataException>(() => Sicherungsablage.Import(path + ".zip", root));
        Assert.Single(Sicherungsablage.Find(root));
    }

    [Theory]
    [InlineData("Treiber werden exportiert …")]
    [InlineData("Dateien werden geprüft …")]
    [InlineData("Archiv wird erstellt …")]
    [InlineData("Archiv wird geprüft …")]
    public void CancelBeforePublicationNeverOffersPartialBackup(string phase)
    {
        using var source = new CancellationTokenSource();
        Assert.Throws<OperationCanceledException>(() => Sicherungsablage.Create(root, Export,
            progress: p => { if (p == phase) source.Cancel(); }, cancellationToken: source.Token));
        Assert.Empty(Sicherungsablage.Find(root));
        Assert.Equal(0, Sicherungsablage.ActiveCount);
    }

    [Fact]
    public void CancelledImportDoesNotPublishOrChangeSourceArchive()
    {
        var path = Sicherungsablage.Create(root, Export);
        var before = File.ReadAllBytes(path + ".zip");
        using var source = new CancellationTokenSource();
        Assert.Throws<OperationCanceledException>(() => Sicherungsablage.Import(path + ".zip", root,
            progress: p => { if (p == "Archiv wird entpackt …") source.Cancel(); }, cancellationToken: source.Token));
        Assert.Single(Sicherungsablage.Find(root));
        Assert.Equal(before, File.ReadAllBytes(path + ".zip"));
        Assert.Equal(0, Sicherungsablage.ActiveCount);
    }

    [Fact]
    public void ImportKeepsLegacyBackupsExplicitlyUnverified()
    {
        var legacy = Directory.CreateDirectory(Path.Combine(root, "legacy")).FullName;
        Export(legacy);
        var archive = Path.Combine(root, "legacy.zip");
        ZipFile.CreateFromDirectory(legacy, archive);
        var imported = Sicherungsablage.Import(archive, root);
        Assert.False(Sicherungsablage.Inspect(imported, true).Verified);
        Assert.Equal("legacy", Sicherungsablage.Inspect(imported).Kind);
    }

    [Fact]
    public void ImportRejectsCaseInsensitiveDuplicates()
    {
        Directory.CreateDirectory(root);
        var archive = Path.Combine(root, "duplicates.zip");
        using (var zip = ZipFile.Open(archive, ZipArchiveMode.Create))
        {
            zip.CreateEntry("test.inf");
            zip.CreateEntry("TEST.INF");
        }
        Assert.Throws<InvalidDataException>(() => Sicherungsablage.Import(archive, root));
        Assert.Empty(Sicherungsablage.Find(root));
    }

    [Fact]
    public void ImportRejectsSymbolicLinks()
    {
        Directory.CreateDirectory(root);
        var archive = Path.Combine(root, "link.zip");
        using (var zip = ZipFile.Open(archive, ZipArchiveMode.Create))
            zip.CreateEntry("test.inf").ExternalAttributes = unchecked((int)0xA1FF0000);
        Assert.Throws<InvalidDataException>(() => Sicherungsablage.Import(archive, root));
    }
}
