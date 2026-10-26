using PulsRig.Core;

namespace PulsRig.Tests;

public class SicherungTests
{
    [Theory]
    [InlineData("Backup_2026-10-03_1200", true)]
    [InlineData("Offline-Paket_2026-10-03", true)]
    [InlineData("Auto-Sicherung_2026-10-03_1200", true)]
    [InlineData("Einzeltreiber_oem12_2026-10-26_1430", true)]
    [InlineData("Downloads", false)]
    [InlineData(null, false)]
    public void Sicherungsordner(string? name, bool expected) => Assert.Equal(expected, Sicherung.IsBackupFolder(name));

    [Theory]
    [InlineData("", 3, 0)]
    [InlineData(" 2 ", 3, 1)]
    [InlineData("4", 3, 0)]
    [InlineData("0", 3, 0)]
    [InlineData("zwei", 3, 0)]
    [InlineData("99999999999", 3, 0)]
    public void Auswahl(string answer, int count, int expected) => Assert.Equal(expected, Sicherung.PickIndex(answer, count));

    [Fact]
    public void Namen()
    {
        Assert.Equal("Auto-Sicherung_2026-10-25_0905", Sicherung.AutoFolderName(new DateTime(2026, 10, 25, 9, 5, 0)));
        Assert.Equal("nv_dispi", Sicherung.FolderName("nv_dispi.inf"));
        Assert.Equal("Einzeltreiber_oem12_2026-10-26_1430", Sicherung.SingleFolderName("oem12.inf", new DateTime(2026, 10, 26, 14, 30, 0)));
        Assert.Equal(new[] { "oem12.inf", "oem3.inf" },
            Sicherung.PackagesToBackup(new[] { "OEM3.inf", "machine.inf", null, "oem12.inf", "oem3.inf", "" }));
    }

    [Fact]
    public void PaketeAusPnputil()
    {
        var lines = new[]
        {
            "Microsoft-PnP-Dienstprogramm",
            "",
            "Veröffentlichter Name:     oem12.inf",
            "Originalname:              nv_dispi.inf",
            "Anbietername:              NVIDIA",
            "Klassenname:               Grafikkarten",
            "",
            "Veröffentlichter Name:     machine.inf",
            "Originalname:              machine.inf",
            "Anbietername:              Microsoft",
            "",
            "Published Name:     oem3.inf",
            "Original Name:      rt640x64.inf",
            "Provider Name:      Realtek",
        };
        var packages = Sicherung.ParsePackages(lines);
        Assert.Equal(2, packages.Length);
        Assert.Equal(("oem12.inf", "nv_dispi.inf", "NVIDIA"), (packages[0].Published, packages[0].Original, packages[0].Provider));
        Assert.Equal("rt640x64.inf", packages[1].Original);
    }
}

public class GeraetefehlerTests
{
    [Fact]
    public void Codes()
    {
        Assert.Equal(("kein Treiber installiert", "Driver", "Treiber erneuern"),
            (Geraetefehler.Get(28).Text, Geraetefehler.Get(28).Fix, Geraetefehler.Get(28).Advice));
        Assert.Equal("Disabled", Geraetefehler.Get(22).Fix);
        Assert.Equal("-", Geraetefehler.Get(45).Advice);
        Assert.Equal("unbekannter Fehler", Geraetefehler.Get(99).Text);
        Assert.Equal("Driver", Geraetefehler.Get(0).Fix);
    }
}
