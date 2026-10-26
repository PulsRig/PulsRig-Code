using System.IO;
using PulsRig.Core;

namespace PulsRig.Tests;

public class BoostTabuTests
{
    static readonly string[] Known = { "WSearch", "SysMain" };
    const string Windir = @"C:\Windows";

    [Fact]
    public void EigeneListe() => Assert.True(Boost.IsAllowed("SysMain", Known, null, Windir));

    // Prioritäten: das Spiel höher, Browser und Cloud niedriger; Windows, Starter, Ton und Sprache bleiben, wie sie sind
    [Fact]
    public void Prioritaeten()
    {
        var running = new[] { (1, "cs2"), (2, "chrome"), (3, "explorer"), (4, "Discord"), (5, "steam"), (6, "NMS"), (7, "OneDrive"), (8, "Spotify") };
        var plan = Boost.PriorityPlan(running, new[] { "NMS.exe" }, "cs2");
        Assert.Equal(new[] { (1, "cs2", true), (2, "chrome", false), (6, "NMS", true), (7, "OneDrive", false) }, plan);
        Assert.Empty(Boost.PriorityPlan(new[] { (3, "explorer"), (5, "steam") }, new[] { "explorer", "steam" }, null));
        Assert.Empty(Boost.PriorityPlan(null, null, null));
    }

    [Fact]
    public void FremderHersteller() => Assert.True(Boost.IsAllowed("Steuer", Known, @"""C:\Program Files\Steuer\steuer.exe""", Windir));

    [Theory]
    [InlineData("WinDefend", @"C:\WINDOWS\System32\svchost.exe -k secsvcs")]   // Windows-Dienst
    [InlineData("Unbekannt", null)]                                           // gibt es nicht
    [InlineData("x' OR Name like '%", @"C:\Program Files\a.exe")]             // unsicherer Name
    [InlineData("", @"C:\Program Files\a.exe")]
    public void Verboten(string name, string? pathName) => Assert.False(Boost.IsAllowed(name, Known, pathName, Windir));
}

public class AufraeumenTabuTests : IDisposable
{
    readonly string root = Path.Combine(Path.GetTempPath(), "PulsRig-CsTest-" + Guid.NewGuid().ToString("N"));
    readonly string outside;

    public AufraeumenTabuTests() { outside = root + "-fremd"; }

    string Old(string relative, string? baseDir = null)
    {
        string file = Path.Combine(baseDir ?? root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllText(file, "x");
        File.SetLastWriteTime(file, DateTime.Now.AddDays(-30));
        return file;
    }

    [Fact]
    public void JunctionWirdNichtBetreten()
    {
        Old("alt.tmp");
        Old("wichtig.txt", outside);
        File.WriteAllText(Path.Combine(root, "neu.tmp"), "x");
        var link = Path.Combine(root, "Sprung");
        // Junction statt symbolischer Verknüpfung: die geht auch ohne Adminrechte
        using (var mklink = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("cmd.exe", $"/c mklink /J \"{link}\" \"{outside}\"") { CreateNoWindow = true, UseShellExecute = false }))
            mklink!.WaitForExit();
        Assert.True(new DirectoryInfo(link).Attributes.HasFlag(FileAttributes.ReparsePoint));
        var names = Aufraeumen.CleanableFiles(root, 7).Select(f => f.Name).ToArray();
        Assert.Equal(new[] { "alt.tmp" }, names);
    }

    [Fact]
    public void GeschuetzteOrdnerBleiben()
    {
        Old("frei.tmp");
        Old(@"$Recycle.Bin\a.txt"); Old(@"Minidump\1.dmp"); Old("MEMORY.DMP");
        Old(@"Backup_2026-10-01\setup.exe"); Old(@"Auto-Sicherung_1\x.inf"); Old(@"DriverStore\y.inf");
        var names = Aufraeumen.CleanableFiles(root, 7).Select(f => f.Name).ToArray();
        Assert.Equal(new[] { "frei.tmp" }, names);
    }

    [Fact]
    public void GeschuetzterStartordnerGibtNichts()
    {
        Old(@"Minidump\1.dmp");
        Assert.Empty(Aufraeumen.CleanableFiles(Path.Combine(root, "Minidump"), 0));
        Assert.Empty(Aufraeumen.CleanableFiles(Path.Combine(root, "gibtsnicht"), 0));
    }

    public void Dispose()
    {
        try { var link = Path.Combine(root, "Sprung"); if (Directory.Exists(link)) Directory.Delete(link); } catch (Exception) { }
        try { Directory.Delete(root, true); } catch (Exception) { }
        try { Directory.Delete(outside, true); } catch (Exception) { }
    }
}
