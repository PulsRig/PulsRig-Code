using PulsRig.Core;

namespace PulsRig.Tests;

public class RueckgaengigTests : IDisposable
{
    readonly string file = Path.Combine(Path.GetTempPath(), "PulsRig-Rueck-" + Guid.NewGuid().ToString("N"), "a.json");
    public void Dispose() { try { Directory.Delete(Path.GetDirectoryName(file)!, true); } catch (Exception) { } }

    [Fact]
    public void StoresAndMarksUndone()
    {
        var a = new Rueckgabe(new DateTime(2026, 11, 9, 12, 0, 0), "Autostart aufräumen", "Discord ausschalten", "autostart", Rueckgaengig.AutostartData(false, "Run", "Discord", true));
        Rueckgaengig.Add(file, a);
        Rueckgaengig.Add(file, new Rueckgabe(DateTime.Now, "Treiber", "Treiber installiert"));
        Assert.Equal(2, Rueckgaengig.Load(file).Count);
        Rueckgaengig.MarkUndone(file, a);
        Assert.True(Rueckgaengig.Load(file)[0].Undone);
        Assert.False(Rueckgaengig.Load(file)[1].Undone);
    }

    [Fact]
    public void CounterStepSettlesOldEntry()
    {
        var off = Rueckgaengig.AutostartData(true, "Run", "Steam", true);
        Assert.Equal("HKLM|Run|Steam|1", off);
        Assert.Equal("HKLM|Run|Steam|0", Rueckgaengig.Flip(off));
        Rueckgaengig.Add(file, new Rueckgabe(DateTime.Now, "A", "Steam ausschalten", "autostart", off));
        Rueckgaengig.Settle(file, "autostart", off);
        Assert.True(Assert.Single(Rueckgaengig.Load(file)).Undone);
    }

    [Fact]
    public void KeepsOnlyNewest()
    {
        for (var i = 0; i < Rueckgaengig.Keep + 5; i++) Rueckgaengig.Add(file, new Rueckgabe(DateTime.Now, "A", "x" + i));
        var list = Rueckgaengig.Load(file);
        Assert.Equal(Rueckgaengig.Keep, list.Count);
        Assert.Equal("x5", list[0].Text);
    }

    [Fact]
    public void BrokenFileStartsEmpty()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllText(file, "{kaputt");
        Assert.Empty(Rueckgaengig.Load(file));
    }
}
