using System.Collections;
using PulsRig.Core;

namespace PulsRig.Tests;

public class MessungTests
{
    [Fact]
    public void NvidiaZeile()
    {
        var values = new Hashtable();
        Messung.ParseNvidiaLine("NVIDIA GeForce RTX 3070, 54, 38, 97, 6120, 8192, 211.43", values);
        Assert.Equal("NVIDIA GeForce RTX 3070", values["GpuName"]);
        Assert.Equal(54.0, values["GpuTemp"]);
        Assert.Equal(97.0, values["GpuLoad"]);
        Assert.Equal(211.43, values["GpuPower"]);
    }

    [Fact]
    public void NvidiaOhneLuefter()
    {
        var values = new Hashtable();
        Messung.ParseNvidiaLine("Laptop GPU, 61, [N/A], 40, 900, 4096, [N/A]", values);
        Assert.Null(values["GpuFan"]);
        Assert.Equal(40.0, values["GpuLoad"]);
    }

    [Fact]
    public void KaputteZeileBleibtLeer()
    {
        var values = new Hashtable();
        Messung.ParseNvidiaLine("Fehler", values);
        Assert.Empty(values);
    }

    [Fact]
    public void EchterTakt()
    {
        using var messung = new Messung("", 3800);
        var values = messung.Next();
        Assert.InRange((double)values["CpuLoad"]!, 0.0, 100.0);
        Assert.InRange((double)values["Ram"]!, 0.1, 100.0);
    }
}
