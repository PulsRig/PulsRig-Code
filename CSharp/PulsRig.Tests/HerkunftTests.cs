using PulsRig.Core;

namespace PulsRig.Tests;

public class HerkunftTests
{
    [Fact]
    public void ErkenntQuelleUndSignatur()
    {
        var updates = new[] { "Realtek - Net - 10.68.1001.2023", "2026-10 Kumulatives Update für Windows 11" };
        Assert.Equal(("über Windows Update · von Microsoft geprüft", false), Herkunft.Of(true, Herkunft.Whql, "Realtek", "10.68.1001.2023", updates));
        Assert.Equal(("vom Hersteller oder von Hand installiert · signiert von NVIDIA", false), Herkunft.Of(true, "NVIDIA", "NVIDIA", "32.0.15.8157", updates));
        Assert.True(Herkunft.Of(false, "", "Generic", "1.0", updates).Warn);
        Assert.False(Herkunft.FromWindowsUpdate("Intel", "10.68.1001.2023", updates));
    }
}
