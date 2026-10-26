using PulsRig.Core;

namespace PulsRig.Tests;

public class SysteminfoTests
{
    [Theory]
    [InlineData("To Be Filled By O.E.M.", true)]
    [InlineData("System manufacturer", true)]
    [InlineData("LENOVO", false)]
    [InlineData(null, false)]
    public void Platzhalter(string? value, bool expected) => Assert.Equal(expected, Systeminfo.IsPlaceholder(value));

    [Fact]
    public void Woerter()
    {
        Assert.Equal("Festplatte", Systeminfo.DiskType("HDD", "Laufwerk"));
        Assert.Equal("Laufwerk", Systeminfo.DiskType("Unspecified", "Laufwerk"));
        Assert.Equal("unbekannt", Systeminfo.DiskType("", "unbekannt"));
        Assert.Equal("in Ordnung", Systeminfo.Health("Healthy"));
        Assert.Equal("Warning", Systeminfo.Health("Warning"));
        Assert.True(Systeminfo.IsThirdParty("NVIDIA"));
        Assert.False(Systeminfo.IsThirdParty("Microsoft Corporation"));
        Assert.False(Systeminfo.IsThirdParty(""));
    }

    [Fact]
    public void Grafikspeicher()
    {
        Assert.Equal(10737418240L, Systeminfo.GpuMemory(10737418240L, 4293918720L));
        Assert.Equal(4293918720L, Systeminfo.GpuMemory(0, 4293918720L));
    }

    [Fact]
    public void Treiberdatum()
    {
        Assert.Equal(new DateTime(2026, 10, 3), Systeminfo.DriverDate("10-3-2026"));
        Assert.Null(Systeminfo.DriverDate("2026-10-03"));
    }
}

public class OfflinePaketTests
{
    [Fact]
    public void NamenAusPnputil()
    {
        var lines = new[]
        {
            "Veröffentlichter Name:     oem12.inf",
            "Originalname:              nv_dispi.inf",
            "Original Name:             rt640x64.inf",
            "Originalname:              nv_dispi.inf",
            "Anbietername:              NVIDIA",
        };
        Assert.Equal(new[] { "nv_dispi.inf", "rt640x64.inf" }, OfflinePaket.OriginalNames(lines));
    }

    [Fact]
    public void StartdateiNurAscii() => Assert.All(OfflinePaket.Starter(), line => Assert.True(line.All(c => c < 128), line));

    [Fact]
    public void Meldungen()
    {
        Assert.Contains("kein Platz", OfflinePaket.ExportError(112));
        Assert.Equal("Der Export ist fehlgeschlagen (pnputil-Code 5).", OfflinePaket.ExportError(5));
        Assert.Equal("Offline-Treiberpaket vom 25.10.2026 09:15", OfflinePaket.Readme(new DateTime(2026, 10, 25, 9, 15, 0))[0]);
    }
}

public class VerlaufTests
{
    [Theory]
    [InlineData("NVIDIA - Display - 32.0.15.6094", true)]
    [InlineData("Intel Corporation - Extension - 10.1.19.6", true)]
    [InlineData("Realtek Audio Treiber", true)]
    [InlineData("2026-10 Kumulatives Update für Windows 11", false)]
    [InlineData("Security Intelligence-Update für Microsoft Defender - KB2267602 (Version 1.421.150.0)", false)]
    public void Treiberupdate(string title, bool expected) => Assert.Equal(expected, Verlauf.IsDriverUpdate(title));

    [Fact]
    public void Ergebnis()
    {
        Assert.Equal("installiert", Verlauf.Result(2));
        Assert.Equal("unvollständig", Verlauf.Result(1));
    }

    [Fact]
    public void Geraete()
    {
        Assert.Equal("A, B", Verlauf.Devices(new[] { "A", "B" }));
        Assert.Equal("A, B und 2 weitere", Verlauf.Devices(new[] { "A", "B", "C", "D" }));
        Assert.Equal("", Verlauf.Devices(new string[0]));
    }
}
