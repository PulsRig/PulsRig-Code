using System.Globalization;
using PulsRig.Core;

namespace PulsRig.Tests;

public class LaufwerkeTests
{
    [Theory]
    [InlineData((ushort)4, "SSD")]
    [InlineData((ushort)3, "HDD")]
    [InlineData((ushort)0, "Unspecified")]
    [InlineData("SSD", "SSD")]          // Modul geladen: Windows liefert schon Wörter
    [InlineData(null, "Unspecified")]
    public void MediaType(object? value, string expected) => Assert.Equal(expected, Laufwerke.MediaType(value));

    [Theory]
    [InlineData((ushort)17, "NVMe")]
    [InlineData((ushort)11, "SATA")]
    [InlineData((ushort)14, "Unknown")]
    public void BusType(object value, string expected) => Assert.Equal(expected, Laufwerke.BusType(value));

    [Fact]
    public void OperationalStatus() => Assert.Equal("OK, 53264", Laufwerke.OperationalStatus(new ushort[] { 2, 53264 }));

    [Theory]
    [InlineData('C', "C")]
    [InlineData('d', "D")]
    [InlineData('\0', "")]
    [InlineData("E", "E")]
    [InlineData(null, "")]
    public void DriveLetter(object? value, string expected) => Assert.Equal(expected, Laufwerke.DriveLetter(value));

    [Fact]
    public void BekannteArtWirdNichtNachgefragt() => Assert.Equal("SSD", Laufwerke.ResolveMedia("SSD", 99));
}

public class NetzwerkTests
{
    [Theory]
    [InlineData((uint)2, (uint)1, "Disabled")]
    [InlineData((uint)1, (uint)1, "Up")]
    [InlineData((uint)1, (uint)2, "Disconnected")]
    [InlineData((uint)1, (uint)0, "Not Present")]
    [InlineData("Up", "Connected", "Up")]
    public void Status(object admin, object media, string expected) => Assert.Equal(expected, Netzwerk.Status(admin, media));

    [Fact]
    public void LinkSpeedDeutsch()
    {
        CultureInfo.CurrentCulture = new CultureInfo("de-DE");
        Assert.Equal("2,5 Gbps", Netzwerk.LinkSpeed(2.5e9));
        Assert.Equal("100 Mbps", Netzwerk.LinkSpeed(1e8));
        Assert.Equal("", Netzwerk.LinkSpeed(0));
    }

    [Theory]
    [InlineData("001122AABBCC", "00-11-22-AA-BB-CC")]
    [InlineData("00:11:22:aa:bb:cc", "00-11-22-AA-BB-CC")]
    [InlineData("0011", "")]
    public void MacAddress(string value, string expected) => Assert.Equal(expected, Netzwerk.MacAddress(value));

    [Theory]
    [InlineData((ushort)2, true)]
    [InlineData((ushort)23, false)]
    [InlineData("IPv4", true)]
    public void IsIPv4(object family, bool expected) => Assert.Equal(expected, Netzwerk.IsIPv4(family));
}
