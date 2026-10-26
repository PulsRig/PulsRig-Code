using System.IO;
using System.Text;
using PulsRig.Core;

namespace PulsRig.Tests;

public class DownloadsTests
{
    static readonly string[] Hosts = { "*.nvidia.com", "download.microsoft.com" };

    [Theory]
    [InlineData("https://us.download.nvidia.com/a.exe", true)]
    [InlineData("https://download.microsoft.com/x.exe", true)]
    [InlineData("http://us.download.nvidia.com/a.exe", false)]             // kein https
    [InlineData("https://nvidia.com.boese.de/a.exe", false)]               // fremder Rechner mit ähnlichem Namen
    [InlineData("https://download.microsoft.com.boese.de/x.exe", false)]
    [InlineData("kein Link", false)]
    public void NurErlaubteAdressen(string url, bool expected) => Assert.Equal(expected, Downloads.IsAllowed(url, Hosts));

    [Fact]
    public void OhneListeNichts() => Assert.False(Downloads.IsAllowed("https://us.download.nvidia.com/a.exe", null));
}

public class TreiberTests
{
    // kleinste PE-Datei: DOS-Kopf, PE-Kopf, optionaler Kopf mit Ausrichtung, ein Abschnitt
    static string Pe(uint alignment, uint flags)
    {
        var data = new byte[0x400];
        using var writer = new BinaryWriter(new MemoryStream(data));
        writer.Write((ushort)0x5A4D);
        writer.Seek(0x3C, SeekOrigin.Begin); writer.Write(0x80);
        writer.Seek(0x80, SeekOrigin.Begin); writer.Write(0x4550u);
        writer.Seek(0x80 + 6, SeekOrigin.Begin); writer.Write((ushort)1);
        writer.Seek(0x80 + 20, SeekOrigin.Begin); writer.Write((ushort)0xF0);
        writer.Seek(0x80 + 24 + 32, SeekOrigin.Begin); writer.Write(alignment);
        writer.Seek(0x80 + 24 + 0xF0, SeekOrigin.Begin); writer.Write(Encoding.ASCII.GetBytes(".text\0\0\0"));
        writer.Seek(28, SeekOrigin.Current); writer.Write(flags);
        string file = Path.Combine(Path.GetTempPath(), "PulsRig-Pe-" + Guid.NewGuid().ToString("N") + ".sys");
        File.WriteAllBytes(file, data);
        return file;
    }

    static string[] Check(uint alignment, uint flags)
    {
        string file = Pe(alignment, flags);
        try { return Treiber.HvciIssues(file); } finally { File.Delete(file); }
    }

    [Fact]
    public void SaubererTreiber() => Assert.Empty(Check(0x1000, 0x60000020));

    [Fact]
    public void BeschreibbarUndAusfuehrbar() => Assert.Equal(new[] { "Abschnitt .text ist zugleich beschreibbar und ausführbar" }, Check(0x1000, 0xE0000020));

    [Fact]
    public void VerworfenerAbschnittZaehltNicht() => Assert.Empty(Check(0x1000, 0xE2000020));

    [Fact]
    public void Ausrichtung() => Assert.Equal(new[] { "Abschnitte nicht seitenweise ausgerichtet" }, Check(0x200, 0x60000020));

    [Fact]
    public void KeinePeDatei()
    {
        string file = Path.GetTempFileName();
        File.WriteAllText(file, "kein Treiber");
        try { Assert.Empty(Treiber.HvciIssues(file)); } finally { File.Delete(file); }
        Assert.Empty(Treiber.HvciIssues(@"Z:\gibt\es\nicht.sys"));
    }

    [Theory]
    [InlineData(@"\SystemRoot\System32\drivers\a.sys", @"C:\Windows\System32\drivers\a.sys")]
    [InlineData(@"System32\drivers\b.sys", @"C:\Windows\System32\drivers\b.sys")]
    [InlineData(@"\??\C:\Tools\c.sys", @"C:\Tools\c.sys")]
    [InlineData(@"""C:\Program Files\d.sys""", @"C:\Program Files\d.sys")]
    public void DriverPath(string value, string expected) => Assert.Equal(expected, Treiber.ResolveDriverPath(value, @"C:\Windows"));

    [Theory]
    [InlineData(@"""C:\Program Files\A\a.exe"" -run", @"C:\Program Files\A\a.exe")]
    [InlineData(@"C:\Tools\b.EXE /service", @"C:\Tools\b.EXE")]
    [InlineData("seltsam", "seltsam")]
    public void ServicePath(string value, string expected) => Assert.Equal(expected, Treiber.ResolveServicePath(value));
}

public class GeraeteAnzeigeTests
{
    [Theory]
    [InlineData(false, @"USB\VID_046D&PID_C52B\1", "HIDClass", true)]
    [InlineData(true, @"USB\VID_046D&PID_C52B\1", "HIDClass", false)]                  // angeschlossen
    [InlineData(false, @"PCI\VEN_10DE&DEV_2206\1", "Display", false)]                   // fest eingebaut
    [InlineData(false, @"USB\VID_0A12&PID_0001\BTH", "USB", false)]                     // Bluetooth
    [InlineData(false, @"HID\{00001124-0000-1000-8000-00805F9B34FB}\1", "HIDClass", false)]
    [InlineData(false, @"USB\VID_0BDA&PID_8153\1", "Net", false)]                       // Netzwerkadapter
    [InlineData(false, @"SWD\WPDBUSENUM\_??_USBSTOR#1", "WPD", true)]
    public void Bereinigen(bool present, string id, string cls, bool expected) => Assert.Equal(expected, Geraete.IsCleanable(present, id, cls));

    [Theory]
    [InlineData(new[] { 60, 144, 165 }, 144, 144)]
    [InlineData(new[] { 60, 144, 165 }, 75, 60)]
    [InlineData(new[] { 100, 144 }, 0, 144)]
    [InlineData(new int[0], 60, 0)]
    public void Bildwiederholrate(int[] rates, int current, int expected) => Assert.Equal(expected, Anzeige.SelectRefreshRate(rates, current));
}
