using PulsRig.Core;
using Xunit;

namespace PulsRig.Tests;

public class PlaystationTests
{
    // Meldung mit Sticks in der Mitte, Steuerkreuz "keine Richtung" (8)
    static byte[] Report(int length, byte id, int sticks, int buttons, int l2, int r2)
    {
        var r = new byte[length];
        r[0] = id;
        for (var i = 0; i < 4; i++) r[sticks + i] = 128;
        r[buttons] = 0x08;
        return r;
    }

    [Fact]
    public void Modelle()
    {
        Assert.Equal("DualSense", Playstation.Model(0x054C, 0x0CE6));
        Assert.Equal("DualSense Edge", Playstation.Model(0x054C, 0x0DF2));
        Assert.Equal("DualShock 4", Playstation.Model(0x054C, 0x09CC));
        Assert.Equal("", Playstation.Model(0x045E, 0x0B13));     // Xbox-Controller läuft über XInput
    }

    [Fact]
    public void DualSensePerKabel()
    {
        var r = Report(64, 0x01, 1, 8, 5, 6);
        r[8] = 0x20 | 0x02;          // Kreuz, Steuerkreuz rechts
        r[9] = 0x01 | 0x20;          // L1, Options
        r[5] = 255;                  // L2 ganz durch
        r[1] = 255; r[2] = 0;        // linker Stick rechts oben
        var s = Playstation.Read(r, 0x0CE6)!;
        Assert.Equal(1, s[0]);
        Assert.Equal(Playstation.A | Playstation.Right | Playstation.LB | Playstation.Start, s[1]);
        Assert.Equal((255, 0), (s[2], s[3]));
        Assert.Equal((32767, 32767), (s[4], s[5]));
        Assert.Equal((0, 0), (s[6], s[7]));
        Assert.Equal("Kabel", Playstation.Link(r, 0x0CE6));
    }

    [Fact]
    public void DualSensePerBluetooth()
    {
        var r = Report(78, 0x31, 2, 9, 6, 7);
        r[9] = 0x80 | 0x08;          // Dreieck, kein Steuerkreuz
        r[10] = 0x10;                // Create
        r[7] = 100;                  // R2
        var s = Playstation.Read(r, 0x0CE6)!;
        Assert.Equal(Playstation.Y | Playstation.Back, s[1]);
        Assert.Equal(100, s[3]);
        Assert.Equal("Bluetooth", Playstation.Link(r, 0x0CE6));
    }

    [Fact]
    public void DualShock4UndEinfacherModus()
    {
        var usb = Report(64, 0x01, 1, 5, 8, 9);
        usb[5] = 0x10 | 0x05;        // Quadrat, Steuerkreuz unten links
        usb[6] = 0x40 | 0x80;        // L3, R3
        Assert.Equal(Playstation.X | Playstation.Down | Playstation.Left | Playstation.LS | Playstation.RS, Playstation.Read(usb, 0x09CC)![1]);

        var bt = Report(78, 0x11, 3, 7, 10, 11);
        bt[7] = 0x40 | 0x08;         // Kreis
        bt[3] = 0;                   // linker Stick ganz links
        var s = Playstation.Read(bt, 0x05C4)!;
        Assert.Equal(Playstation.B, s[1]);
        Assert.Equal(-32768, s[4]);

        // DualSense per Bluetooth ohne Treiber: kurze Meldung wie beim DualShock 4
        var simple = Report(10, 0x01, 1, 5, 8, 9);
        simple[5] = 0x20 | 0x08;
        Assert.Equal(Playstation.A, Playstation.Read(simple, 0x0CE6)![1]);
        Assert.Equal("Bluetooth (einfach)", Playstation.Link(simple, 0x0CE6));
    }

    [Fact]
    public void UnbekannteMeldungen()
    {
        Assert.Null(Playstation.Read(new byte[5], 0x0CE6));
        Assert.Null(Playstation.Read(new byte[64] { 0x05, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, 0x0CE6));
    }

    [Theory]
    [InlineData(128, 0)]
    [InlineData(255, 32767)]
    [InlineData(0, -32768)]
    public void Achsen(byte raw, int value) => Assert.Equal(value, Playstation.Axis(raw));

    [Theory]
    [InlineData(248, 250)]
    [InlineData(990, 1000)]
    [InlineData(180, 180)]
    [InlineData(0, 0)]
    public void AbfragerateAufStufe(int perSecond, int hz) => Assert.Equal(hz, Playstation.Rate(perSecond));

    [Fact]
    public void Tastennamen()
    {
        Assert.Equal("✕", Playstation.ButtonName("A", 0x0CE6));
        Assert.Equal("Create", Playstation.ButtonName("Back", 0x0CE6));
        Assert.Equal("Share", Playstation.ButtonName("Back", 0x09CC));
        Assert.Equal("L2", Playstation.ButtonName("LT", 0x09CC));
    }
}
