using PulsRig.Core;

namespace PulsRig.Tests;

public class GebrauchtkaufTests
{
    [Theory]
    [InlineData("RTX 3060 Ti", "NVIDIA GeForce RTX 3060 Ti", "good")]
    [InlineData("rtx3060ti", "NVIDIA GeForce RTX 3060 Ti", "good")]
    [InlineData("RTX 3060 Ti", "NVIDIA GeForce RTX 3060", "bad")]
    [InlineData("RTX 3060", "NVIDIA GeForce RTX 3060 Ti", "bad")]
    [InlineData("RTX 3080", "NVIDIA GeForce RTX 3060", "bad")]
    [InlineData("i7-12700K", "12th Gen Intel(R) Core(TM) i7-12700K", "good")]
    [InlineData("Ryzen 5 2600", "AMD Ryzen 5 2600X Six-Core Processor", "bad")]
    [InlineData("", "NVIDIA GeForce RTX 3060", "open")]
    [InlineData("RTX 3060", "", "open")]
    public void NamesAreCompared(string stated, string found, string state) =>
        Assert.Equal(state, Gebrauchtkauf.Name("Grafikkarte", stated, found).State);

    [Theory]
    [InlineData("16 GB", 16.0)]
    [InlineData("1 TB", 1000.0)]
    [InlineData("1,5 TB", 1500.0)]
    [InlineData("512", 512.0)]
    public void SizesAreRead(string text, double gb) => Assert.Equal(gb, Gebrauchtkauf.ParseGb(text));

    [Theory]
    [InlineData("1 TB", 980, "good")]
    [InlineData("1 TB", 512, "bad")]
    [InlineData("1 TB", 1000.2, "good")]
    [InlineData("16 GB", 32, "warn")]
    [InlineData("500gb", 1000, "warn")]
    [InlineData("viel", 500, "open")]
    public void SizesAreCompared(string stated, double found, string state) =>
        Assert.Equal(state, Gebrauchtkauf.Size("x", stated, found, 0.05).State);

    [Fact]
    public void VerdictNeverPromisesTooMuch()
    {
        Assert.Equal("bad", Gebrauchtkauf.Verdict(1, 0, 0, 0).Tone);
        Assert.Equal("warn", Gebrauchtkauf.Verdict(0, 0, 0, 1).Tone);
        var clean = Gebrauchtkauf.Verdict(0, 0, 0, 0);
        Assert.Equal("good", clean.Tone);
        Assert.DoesNotContain("echt", clean.Title);
        Assert.DoesNotContain("in Ordnung", clean.Title);
    }

    [Fact]
    public void ReportEscapesInput()
    {
        var html = Gebrauchtkauf.Html(Gebrauchtkauf.Verdict(0, 0, 0, 0), new DateTime(2026, 11, 1),
            new[] { Gebrauchtkauf.Name("Grafikkarte", "<script>", "RTX") }, new[] { ("Akku", "90 %", "good") });
        Assert.DoesNotContain("<script>", html);
        Assert.Contains("keine Garantie", html);
    }
}
