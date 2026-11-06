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

    [Fact]
    public void BuildsInSameMinuteAreDistinguished()
    {
        var earlier = "29.10.2026 13:30 · Build 20261029-133001123-1234abcd · Stand b8d4f02";
        var later = "29.10.2026 13:30 · Build 20261029-133001124-abcd1234";
        Assert.Equal("20261029-133001123-1234abcd", Fassung.BuildId(earlier));
        Assert.True(Fassung.IsNewer(earlier, later));
        Assert.False(Fassung.IsNewer(later, earlier));
        Assert.True(Fassung.IsNewer("29.10.2026 13:30", earlier));
    }

    [Fact]
    public void KurzeKennungUndAlteNebeneinander()
    {
        var old = "04.11.2026 16:55 · Build 20261104-165522723-cc4c69a0 · Stand de48301";
        var fresh = "06.11.2026 17:01 · Build 20261106-170117 · Stand 5423388";
        Assert.Equal("20261106-170117", Fassung.BuildId(fresh));
        Assert.True(Fassung.IsNewer(old, fresh));
        Assert.False(Fassung.IsNewer(fresh, old));
        // zwei kurze Kennungen in derselben Minute
        Assert.True(Fassung.IsNewer("06.11.2026 17:01 · Build 20261106-170105", fresh));
        Assert.Empty(Fassung.BuildId("Build 20261106-176117"));
    }

    [Theory]
    [InlineData("Build 20261399-999999999-1234abcd")]
    [InlineData("Build ../setup")]
    [InlineData("29.10.2026 13:30 · Stand b8d4f02")]
    public void InvalidOrOldBuildHasNoId(string text) => Assert.Empty(Fassung.BuildId(text));

    [Fact]
    public void NewPackageNamesPassExistingDownloadValidation()
    {
        const string url = "https://github.com/PulsRig/PulsRig/releases/download/v0.7-beta-20261029-133001123-1234abcd/PulsRig-Setup-0.7-Beta-20261029-133001123-1234abcd.exe";
        Assert.True(Fassung.IsValidSetup(url, new string('a', 64), 56L << 20));
    }
}
