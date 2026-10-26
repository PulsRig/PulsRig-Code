using PulsRig.Core;

namespace PulsRig.Tests;

public class FassungTests
{
    [Fact]
    public void NeuerNurMitBeidenDaten()
    {
        Assert.True(Fassung.IsNewer("13.10.2026 18:45 · Stand abc1234", "14.10.2026 09:00"));
        Assert.False(Fassung.IsNewer("14.10.2026 09:00", "13.10.2026 18:45"));
        Assert.False(Fassung.IsNewer("", "14.10.2026 09:00"));   // Werkstatt: kein Baudatum, kein Hinweis
    }

    [Theory]
    [InlineData("https://github.com/PulsRig/PulsRig/releases/download/v0.8/PulsRig-Setup-0.8-Beta.exe", true)]
    [InlineData("https://github.com/Fremd/PulsRig/releases/download/v0.8/PulsRig-Setup-0.8-Beta.exe", false)]
    [InlineData("http://github.com/PulsRig/PulsRig/releases/download/v0.8/PulsRig-Setup-0.8-Beta.exe", false)]
    [InlineData("https://github.com/PulsRig/PulsRig/releases/download/v0.8/boese.exe", false)]
    public void NurEigeneSetupDatei(string url, bool ok) => Assert.Equal(ok, Fassung.IsValidSetup(url, new string('a', 64), 50L << 20));

    [Fact]
    public void GroesseUndPruefsumme()
    {
        const string url = "https://github.com/PulsRig/PulsRig/releases/download/v0.8/PulsRig-Setup-0.8-Beta.exe";
        Assert.False(Fassung.IsValidSetup(url, "abc", 50L << 20));
        Assert.False(Fassung.IsValidSetup(url, new string('a', 64), 100));
        Assert.False(Fassung.IsValidSetup(url, new string('a', 64), 80L << 20));
    }
}
