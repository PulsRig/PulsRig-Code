using PulsRig.Core;

namespace PulsRig.Tests;

public class ScanTextTests
{
    [Fact]
    public void Datum()
    {
        Assert.Equal("03.10.2026", ScanText.FormatDate(new DateTime(2026, 10, 3)));
        Assert.Equal("-", ScanText.FormatDate(new DateTime(1968, 7, 18)));
        Assert.Equal("-", ScanText.FormatDate(null));
        Assert.Equal("1.2 vom 03.10.2026", ScanText.FormatDriverText("1.2", new DateTime(2026, 10, 3)));
        Assert.Equal("1.2", ScanText.FormatDriverText("1.2", null));
    }

    [Fact]
    public void Kuerzen()
    {
        Assert.Equal("abc", ScanText.LimitText("abc", 5));
        Assert.Equal("ab...", ScanText.LimitText("abcdef", 5));
        Assert.Equal("a_b_c_ d", ScanText.SafeName("a/b:c*   d. ", 80));
        Assert.Equal("abc", ScanText.SafeName("abc.def", 4));
    }

    [Fact]
    public void UpdateFehler()
    {
        Assert.Equal("Zugriff verweigert. (0x80070005)", ScanText.UpdateError(unchecked((int)0x80070005), "x"));
        Assert.Equal("Unbekannt (0x80004005)", ScanText.UpdateError(unchecked((int)0x80004005), " Unbekannt "));
    }

    [Theory]
    [InlineData("NVIDIA - Display - 32.0.15.6094", "NVIDIA – Grafik – 32.0.15.6094")]
    [InlineData("Realtek - media - 10/3/2026 12:00:00 AM - 6.0.9", "Realtek – Audio – 6.0.9")]
    [InlineData("Foo - Other hardware - 1.2", "Foo – Gerät – 1.2")]
    [InlineData("A - B", "A - B")]
    public void Updatetitel(string title, string expected) => Assert.Equal(expected, ScanText.FormatUpdateTitle(title));
}

public class ScanGeraeteTests
{
    [Theory]
    [InlineData("SM-Bus-Controller", 28, @"PCI\VEN_1022&DEV_790B&SUBSYS_1", true)]
    [InlineData("PCI-Gerät", 28, @"ACPI\AMDI0030\0", true)]
    [InlineData("SM-Bus-Controller", 10, @"PCI\VEN_1022&DEV_790B", false)]
    [InlineData("Grafik", 28, @"PCI\VEN_1002&DEV_1", false)]
    [InlineData("SM-Bus-Controller", 28, @"PCI\VEN_10DE&DEV_1", false)]
    public void Chipsatz(string name, int code, string id, bool expected) => Assert.Equal(expected, ScanGeraete.IsChipsetDevice(name, code, id));

    [Fact]
    public void Mainboardsuche()
    {
        Assert.Equal("ASUSTeK ROG STRIX B650E-F", ScanGeraete.BoardDriverSearch("To Be Filled By O.E.M.", "x", "ASUSTeK COMPUTER INC.", "ROG STRIX B650E-F")!.Name);
        Assert.Equal("MSI MAG B550", ScanGeraete.BoardDriverSearch("", "", "Micro-Star International Co., Ltd.", "MAG B550")!.Name);
        Assert.Equal("LENOVO 82JW", ScanGeraete.BoardDriverSearch("LENOVO", "82JW", "LENOVO", "LNVNB161216")!.Name);
        Assert.StartsWith("https://www.bing.com/search?q=Dell%20XPS", ScanGeraete.BoardDriverSearch("Dell Inc.", "XPS 15", "", "")!.Url);
        Assert.Null(ScanGeraete.BoardDriverSearch("", "", "Default string", "Default string"));
    }

    [Fact]
    public void Grafikschutz()
    {
        Assert.Equal(@"PCI\VEN_10DE&DEV_2684", ScanGeraete.GpuShieldKey(@"pci\ven_10de&dev_2684&subsys_1"));
        Assert.Equal("", ScanGeraete.GpuShieldKey(@"PCI\VEN_10DE"));
    }
}

public class KatalogTests
{
    [Theory]
    [InlineData(@"PCI\VEN_1022&DEV_790B&SUBSYS_FFFF1849&REV_59", "VEN_1022&DEV_790B")]
    [InlineData(@"ACPI\VEN_AMDI&DEV_0030", "AMDI0030")]
    [InlineData(@"USB\VID_046D&PID_C52B&MI_00", "VID_046D&PID_C52B")]
    [InlineData(@"ROOT\X", null)]
    [InlineData(@"HID\X", null)]
    [InlineData("X", null)]
    public void Suchbegriff(string id, string? expected) => Assert.Equal(expected, Katalog.Query(id));

    [Fact]
    public void Trefferseite()
    {
        const string page = """
            <tr id="55e4c288-1590-4fed-b4c1-248ebd64da45_R1">
              <td id="x_C1_R1"><a>Realtek Driver Update (10.79.50.1003)</a></td>
              <td id="x_C2_R1">Windows 11 Client, version 24H2 and later</td>
              <td id="x_C4_R1">10/2/2025</td>
              <td id="x_C5_R1">10.79.50.1003</td>
              <td id="x_C6_R1"><span class="noDisplay">x</span> 584 KB <span id="y_originalSize">598115</span></td>
            </tr>
            <tr id="11111111-1590-4fed-b4c1-248ebd64da45_R2"><td id="x_C4_R2">10/2/2025</td><td id="x_C5_R2">n/a</td></tr>
            """;
        var rows = Katalog.ParseRows(page);
        var row = Assert.Single(rows);
        Assert.Equal("55e4c288-1590-4fed-b4c1-248ebd64da45", row.Id);
        Assert.Equal("Realtek Driver Update (10.79.50.1003)", row.Title);
        Assert.Equal(new DateTime(2025, 10, 2), row.Date);
        Assert.Equal(new Version(10, 79, 50, 1003), row.Version);
        Assert.Equal(598115, row.Bytes);
    }
}

public class HerstellerTests
{
    [Fact]
    public void Nvidia()
    {
        Assert.Equal("617.42", Hersteller.NvidiaVersion("32.0.16.1742"));
        Assert.Null(Hersteller.NvidiaVersion("1.2"));
    }

    [Theory]
    [InlineData("AMD Radeon RX 7800 XT", "radeon-rx-7000-series/amd-radeon-rx-7800-xt.html")]
    [InlineData("AMD Radeon(TM) RX 7900 XTX", "radeon-rx-7000-series/amd-radeon-rx-7900-xtx.html")]
    [InlineData("Radeon RX Vega 64", "radeon-rx-vega-series/radeon-rx-vega-64.html")]
    [InlineData("AMD Radeon RX 580", null)]
    [InlineData("AMD Radeon(TM) Graphics", null)]
    public void Radeonseite(string name, string? tail)
    {
        string? page = Hersteller.RadeonPage(name);
        if (tail == null) Assert.Null(page);
        else Assert.EndsWith(tail, page);
    }

    [Fact]
    public void AmdSeiten()
    {
        Assert.Equal("26.10.1", Hersteller.RadeonLatest("a adrenalin-edition-26.9.2-win b adrenalin-edition-26.10.1-win11"));
        Assert.Null(Hersteller.RadeonLatest("nichts"));
        Assert.Equal("20.10.2026", Hersteller.ReleaseDate("<strong>Release Date</strong>\n <p> 2026-10-20</p>"));
        const string chipset = "AMD_Chipset_Software_8.09.28.1124.exe <strong>Revision Number</strong><p>8.09.28.1124</p>" +
            "<strong>File Size</strong><p> 79 MB </p><strong>Release Date</strong><p>2026-10-21</p>";
        Assert.Equal("8.09.28.1124", Hersteller.AmdChipsetLatest(chipset));
        Assert.Equal(new[] { "79 MB", "21.10.2026" }, Hersteller.AmdChipsetDetails(chipset, "8.09.28.1124"));
    }

    [Theory]
    [InlineData("B650 AORUS ELITE AX", "AM5", "am5", "B650")]
    [InlineData("ROG STRIX X870E-E", "AM5", "am5", "X870E")]
    [InlineData("AB350 Pro4", "AM4", "am4", "B350")]
    [InlineData("Unbekannt", "AM4", "am4", "B550")]
    [InlineData("Z790", "LGA1700", null, null)]
    public void AmdChipsatz(string board, string socket, string? expectedSocket, string? expectedChipset)
    {
        var found = Hersteller.AmdChipset(board, socket);
        Assert.Equal(expectedSocket, found?.Socket);
        Assert.Equal(expectedChipset, found?.Chipset);
    }
}

public class KatalogAuswahlTests
{
    static KatalogTreffer Row(string id, string title, string products, string version, int day) =>
        new KatalogTreffer { Id = id, Title = title, Products = products, Version = Version.Parse(version), Date = new DateTime(2026, 1, day) };

    [Fact]
    public void Kandidat()
    {
        var rows = new[]
        {
            Row("a", "Realtek Driver Update", "Windows 11 Client", "10.80.1.1", 5),
            Row("b", "Realtek Driver Update", "Windows 11 Client", "11.0.0.1", 9),    // andere Hauptversion
            Row("c", "Intel Driver Update", "Windows 11 Client", "10.90.0.1", 9),     // anderer Hersteller
            Row("d", "Realtek Driver Update", "Windows 10", "10.95.0.1", 9),          // andere Windows-Fassung
        };
        Assert.Equal("a", KatalogAuswahl.Candidate("10.70.0.1", "Realtek Semiconductor", new DateTime(2026, 1, 1), rows, "Windows 11")?.Id);
        Assert.Null(KatalogAuswahl.Candidate("10.70.0.1", "Realtek", new DateTime(2026, 1, 6), rows, "Windows 11"));
        Assert.Null(KatalogAuswahl.Candidate("abc", "Realtek", null, rows, "Windows 11"));
    }

    [Fact]
    public void GeraetOhneTreiber()
    {
        var rows = new[]
        {
            Row("a", "AMD Extension", "Windows 11 Client, version 22H2 and later", "9.0.0.1", 5),
            Row("b", "AMD System", "Windows 11 Client, version 25H2 and later", "3.0.0.1", 5),
            Row("c", "AMD System", "Windows 11 Client, version 22H2 and later", "2.0.0.1", 5),
            Row("d", "AMD Firmware", "Windows 11 Client", "8.0.0.1", 5),
            Row("", "AMD System", "Windows 11 Client", "7.0.0.1", 5),
        };
        Assert.Equal("c", KatalogAuswahl.MissingDriver(rows, "Windows 11", "24H2")?.Id);
        Assert.Equal("b", KatalogAuswahl.MissingDriver(rows, "Windows 11", "25H2")?.Id);
        Assert.Equal("a", KatalogAuswahl.MissingDriver(rows.Take(1), "Windows 11", "24H2")?.Id);
        Assert.Null(KatalogAuswahl.MissingDriver(rows, "Windows 10", "24H2"));
    }
}

public class ZuordnungTests
{
    [Fact]
    public void Geraetename()
    {
        var ids = new List<string[]?> { new[] { @"MONITOR\BNQ78CA" }, new[] { @"USB\VID_04F9&PID_04BB&MI_01&NETSCN" }, null };
        var names = new List<string?> { "Monitor", "Scanner", "Leer" };
        Assert.Equal("Monitor", Zuordnung.DeviceName(@"monitor\bnq78ca", ids, names));
        Assert.Equal("Scanner", Zuordnung.DeviceName("vid_04f9&pid_04bb", ids, names));
        Assert.Equal("", Zuordnung.DeviceName("abc", ids, names));
    }

    [Fact]
    public void InstallierterTreiber()
    {
        var ids = new List<string?> { null, @"PCI\VEN_10EC&DEV_8168&SUBSYS_1", @"pci\ven_10ec&dev_8168" };
        Assert.Equal(2, Zuordnung.InstalledDriver(@"PCI\VEN_10EC&DEV_8168", ids));
        Assert.Equal(1, Zuordnung.InstalledDriver(@"PCI\VEN_10EC", ids));
        Assert.Equal(-1, Zuordnung.InstalledDriver("", ids));
    }

    [Theory]
    [InlineData("NVIDIA - Display - 1.2", "nvidia", true)]
    [InlineData("NVIDIA - Display - 1.2", "Intel*", false)]
    [InlineData("Intel - System - 1.2", "?ntel*", true)]
    [InlineData("Intel - System - 1.2", "[NI]*", true)]
    [InlineData("a*b", "a`*b", true)]
    [InlineData("axb", "a`*b", false)]
    [InlineData("Foo", "", false)]
    public void Ausschluss(string title, string pattern, bool expected) => Assert.Equal(expected, Zuordnung.IsExcluded(title, new[] { pattern }));
}
