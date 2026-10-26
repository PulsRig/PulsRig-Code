using System.Text;
using PulsRig.Core;

namespace PulsRig.Tests;

public class SpeicherTests
{
    static List<Steckplatz> Board(params int[] filled)
    {
        // vier Steckplätze wie bei AMD: DIMM 0/1 in Kanal A und B
        var names = new[] { ("DIMM 0", "P0 CHANNEL A"), ("DIMM 1", "P0 CHANNEL A"), ("DIMM 0", "P0 CHANNEL B"), ("DIMM 1", "P0 CHANNEL B") };
        var module = 0;
        return names.Select((n, i) => new Steckplatz { Slot = n.Item1, Bank = n.Item2, Module = filled.Contains(i) ? module++ : -1 }).ToList();
    }

    [Theory]
    [InlineData("F4-3000C16-16GISB", 2800, 0, 3000, true)]
    [InlineData("CMK16GX4M2B3200C16", 2133, 0, 3200, true)]
    [InlineData("KF432C16BB/8", 2400, 0, 3200, true)]
    [InlineData("kf432c16bb/8", 2400, 0, 3200, true)]
    [InlineData("BL16G36C16U4B.M16FE1", 2666, 0, 3600, true)]
    [InlineData("M378A1K43CB2-CTD", 2666, 0, 0, false)]
    [InlineData("", 2133, 3600, 3600, true)]
    [InlineData("X-1200C16", 2133, 0, 0, false)]
    public void Takt(string part, int speed, int rated, int expected, bool known)
    {
        var r = Speicher.Rated(new SpeicherRiegel { Part = part, Speed = speed, Rated = rated });
        Assert.Equal(expected, r.Speed);
        Assert.Equal(known, r.Known);
    }

    [Fact]
    public void ProfilFehlt()
    {
        var p = Speicher.Profile(new[] { new SpeicherRiegel { Part = "F4-3000C16-16GISB", Speed = 2800 } })!;
        Assert.Equal("Warn", p.Tone);
        Assert.Equal(3000, p.Rated);
        Assert.Null(Speicher.Profile(new[] { new SpeicherRiegel() }));
    }

    [Fact]
    public void ProfilVollOderUnbekannt()
    {
        Assert.Equal("voller Takt", Speicher.Profile(new[] { new SpeicherRiegel { Part = "F4-3000C16-16GISB", Speed = 3000 } })!.Badge);
        Assert.Equal("TextDim", Speicher.Profile(new[] { new SpeicherRiegel { Part = "M378A1K43CB2-CTD", Speed = 2666 } })!.Tone);
    }

    [Theory]
    [InlineData("P0 CHANNEL A DIMM 0", "A")]
    [InlineData("BANK 0 Controller1-ChannelA-DIMM1", "1A")]
    [InlineData("BANK 1 DIMM_B2", "B")]
    [InlineData("ChannelAB", "")]
    [InlineData("BANK 0 Slot 1", "")]
    public void Kanal(string text, string expected) => Assert.Equal(expected, Speicher.ChannelKey(text));

    [Fact]
    public void Kanaele()
    {
        var dual = new[] { new SpeicherRiegel { Bank = "P0 CHANNEL A", Slot = "DIMM 1" }, new SpeicherRiegel { Bank = "P0 CHANNEL B", Slot = "DIMM 1" } };
        Assert.Equal("Dual-Channel", Speicher.Channels(dual, 4)!.Name);
        var single = new[] { new SpeicherRiegel { Bank = "P0 CHANNEL A", Slot = "DIMM 0" }, new SpeicherRiegel { Bank = "P0 CHANNEL A", Slot = "DIMM 1" } };
        Assert.NotEqual("", Speicher.Channels(single, 4)!.Hint);
        Assert.Null(Speicher.Channels(new[] { new SpeicherRiegel { Slot = "Slot 1" } }, 2));
    }

    [Fact]
    public void Steckplaetze()
    {
        Assert.Equal("good", Speicher.Placement(Board(1, 3)).State);
        Assert.Equal("good", Speicher.Placement(Board(0, 1, 2, 3)).State);
        var first = Speicher.Placement(Board(0, 2));
        Assert.Equal("bad", first.State);
        Assert.Equal(new[] { 0, 2 }, first.Wrong);
        Assert.Equal(new[] { 1, 3 }, first.Better);
        var crowded = Speicher.Placement(Board(0, 1));
        Assert.Equal(new[] { 0 }, crowded.Wrong);
        Assert.Equal(new[] { 3 }, crowded.Better);
        Assert.Equal("", Speicher.Placement(Board()).State);
    }

    [Fact]
    public void ReihenfolgeOhneBios()
    {
        var modules = new[] { new SpeicherRiegel { Slot = "DIMM 1", Bank = "A" }, new SpeicherRiegel { Slot = "DIMM 1", Bank = "B" } };
        var layout = Speicher.Layout(modules, new List<Steckplatz>(), 4);
        Assert.Equal(4, layout.Count);
        Assert.Equal(new[] { 0, 1, -1, -1 }, layout.Select(p => p.Module));
    }

    // Tabelle mit einem fremden Eintrag, zwei Steckplätzen der Art 17 und dem Endeintrag
    static byte[] Table(params (ushort Size, string Slot, string Bank)[] slots)
    {
        var bytes = new List<byte> { 0, 6, 0, 0, 1, 2 };
        bytes.AddRange(Encoding.ASCII.GetBytes("Hersteller"));
        bytes.AddRange(new byte[] { 0, 0 });
        foreach (var (size, slot, bank) in slots)
        {
            var e = new byte[0x15];
            e[0] = 17; e[1] = 0x15;
            BitConverter.GetBytes(size).CopyTo(e, 0x0C);
            e[0x10] = 1; e[0x11] = 2;
            bytes.AddRange(e);
            bytes.AddRange(Encoding.ASCII.GetBytes(slot)); bytes.Add(0);
            bytes.AddRange(Encoding.ASCII.GetBytes(bank)); bytes.Add(0);
            bytes.Add(0);
        }
        bytes.AddRange(new byte[] { 127, 4, 0, 0, 0, 0 });
        return bytes.ToArray();
    }

    [Fact]
    public void BiosTabelle()
    {
        var raw = Table((0, "DIMM 0", "P0 CHANNEL A"), (16384, "DIMM 1", "P0 CHANNEL A "), (0xFFFF, "DIMM 0", "P0 CHANNEL B"));
        var layout = Speicher.ParseSmbios(raw, 1);
        Assert.Equal(new[] { "DIMM 0", "DIMM 1", "DIMM 0" }, layout.Select(p => p.Slot));
        Assert.Equal("P0 CHANNEL A", layout[1].Bank);
        Assert.Equal(new[] { -1, 0, -1 }, layout.Select(p => p.Module));
        // passt nicht zu den Riegeln von Windows: kein Vertrauen in die Tabelle
        Assert.Empty(Speicher.ParseSmbios(raw, 2));
        Assert.Empty(Speicher.ParseSmbios(null, 0));
    }

    [Theory]
    [InlineData("Unknown", "")]
    [InlineData("0000", "")]
    [InlineData(" Corsair ", "Corsair")]
    [InlineData("00AB", "00AB")]
    public void Hersteller(string raw, string expected) => Assert.Equal(expected, Speicher.Maker(raw));
}
