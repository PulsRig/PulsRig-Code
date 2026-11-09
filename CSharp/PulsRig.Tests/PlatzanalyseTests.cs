using PulsRig.Core;

namespace PulsRig.Tests;

public class PlatzanalyseTests : IDisposable
{
    readonly string root = Path.Combine(Path.GetTempPath(), "PulsRig-Platz-" + Guid.NewGuid().ToString("N"));

    public PlatzanalyseTests() => Directory.CreateDirectory(root);
    public void Dispose()
    {
        foreach (var d in Directory.GetDirectories(root, "*", SearchOption.AllDirectories).Where(d => new DirectoryInfo(d).LinkTarget != null)) Directory.Delete(d);
        Directory.Delete(root, true);
    }

    void File(string rel, int bytes)
    {
        var p = Path.Combine(root, rel);
        Directory.CreateDirectory(Path.GetDirectoryName(p)!);
        System.IO.File.WriteAllBytes(p, new byte[bytes]);
    }

    [Fact]
    public void SumsFoldersAndSortsBiggestFirst()
    {
        File(@"klein\a.bin", 100);
        File(@"gross\b.bin", 5000);
        File(@"gross\tief\c.bin", 3000);
        File("d.bin", 10);
        var r = Platzanalyse.Run(root);
        Assert.Equal(8110, r.Root.Size);
        Assert.Equal(4, r.Root.Files);
        Assert.Equal("gross", r.Root.Children[0].Name);
        Assert.Equal(8000, r.Root.Children[0].Size);
        Assert.Equal(new long[] { 5000, 3000, 100, 10 }, r.Biggest.Select(x => x.Size));
    }

    [Fact]
    public void DoesNotFollowJunctions()
    {
        File(@"echt\x.bin", 4000);
        var link = Path.Combine(root, "verweis");
        try { Directory.CreateSymbolicLink(link, Path.Combine(root, "echt")); }
        catch (Exception)
        {
            // ohne Entwicklermodus keine Verknüpfung - dann per Junction
            var p = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("cmd.exe", $"/c mklink /J \"{link}\" \"{Path.Combine(root, "echt")}\"") { CreateNoWindow = true, UseShellExecute = false })!;
            p.WaitForExit();
        }
        Assert.True(Directory.Exists(link));
        var r = Platzanalyse.Run(root);
        Assert.Equal(4000, r.Root.Size);
        Assert.Single(r.Biggest);
    }

    [Fact]
    public void KeepsOnlyTopFiles()
    {
        for (var i = 1; i <= Platzanalyse.TopFiles + 30; i++) File($"f{i}.bin", i);
        var r = Platzanalyse.Run(root);
        Assert.Equal(Platzanalyse.TopFiles, r.Biggest.Count);
        Assert.Equal(Platzanalyse.TopFiles + 30, r.Biggest[0].Size);
    }

    [Theory]
    [InlineData(@"C:\Program Files (x86)\Steam\steamapps\common\Forza", Platzart.Spiel)]
    [InlineData(@"D:\SteamLibrary\steamapps", Platzart.Spiel)]
    [InlineData(@"C:\Users\Nutzer\AppData\Local\Google\Play Games", Platzart.Spiel)]
    [InlineData(@"C:\Program Files\Roberts Space Industries", Platzart.Spiel)]
    [InlineData(@"C:\Program Files\Mozilla Firefox", Platzart.Programm)]
    [InlineData(@"C:\Windows\WinSxS", Platzart.System)]
    [InlineData(@"C:\$Recycle.Bin", Platzart.Papierkorb)]
    [InlineData(@"C:\Users\Nutzer\Downloads", Platzart.Eigene)]
    [InlineData(@"E:\Videos", Platzart.Eigene)]
    public void RecognisesAreas(string path, Platzart art) => Assert.Equal(art, Platzanalyse.Art(path));

    [Fact]
    public void GroupsLikeWindowsSettings()
    {
        File(@"Users\Nutzer\Downloads\a.iso", 5000);
        File(@"Users\Nutzer\AppData\Local\Temp\x.tmp", 700);
        File(@"Users\Nutzer\AppData\Local\Firma\cache.bin", 300);
        File(@"Program Files\App\app.dll", 2000);
        File(@"Windows\Temp\y.tmp", 100);
        File(@"Windows\System32\k.dll", 900);
        File(@"Sonstiges\z.bin", 50);
        var k = Platzanalyse.Kategorien(Platzanalyse.Run(root).Root).ToDictionary(x => x.Name, x => x.Size);
        Assert.Equal(5000, k["Downloads"]);
        Assert.Equal(800, k["Temporäre Dateien"]);
        Assert.Equal(2300, k["Apps & Spiele"]);
        Assert.Equal(900, k["Windows"]);
        Assert.Equal(50, k["Andere"]);
    }

    [Fact]
    public void ListsOnlyOwnFiles()
    {
        File(@"steamapps\common\Spiel\daten.pak", 9000);
        File(@"Program Files\App\app.dll", 7000);
        File(@"Videos\film.mp4", 3000);
        var r = Platzanalyse.Run(root);
        Assert.Equal(19000, r.Root.Size);
        Assert.Equal("film.mp4", Path.GetFileName(Assert.Single(r.Biggest).Path));
    }
}
