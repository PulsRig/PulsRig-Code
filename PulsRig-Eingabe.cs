// PulsRig - Controller- und Maus-Test. Wird von PulsRig-Eingabe.ps1 beim ersten Öffnen übersetzt.
//
// Controller: über XInput (alle Xbox-kompatiblen Gamepads; PlayStation-Controller nur über Steam oder DS4Windows).
// Maus: über Raw Input bekommt ein unsichtbares Fenster jede einzelne Meldung der Maus, auch wenn PulsRig nicht vorn
// ist. Die Abfragerate ergibt sich aus der Zahl der Bewegungsmeldungen in der besten halben Sekunde flüssiger Bewegung
// (gezählt in 100-ms-Abschnitten; Abstände einzelner Meldungen taugen nicht, Windows liefert sie in Schüben). Enthält
// fast jede Meldung nur einen Punkt Bewegung, begrenzt die Bewegung selbst: Die Maus meldet nur, wenn sie sich bewegt
// hat - bei 800 DPI braucht es für 8.000 Hz 25 cm pro Sekunde. Dann ist die Zahl ein Mindestwert (SpeedLimited).
// Bei den Tasten zählt, ob eine kurz nach dem Loslassen von selbst wieder auslöst (verschlissener Schalter).

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class PulsRigPad
{
    [StructLayout(LayoutKind.Sequential)]
    struct Gamepad { public ushort Buttons; public byte LeftTrigger, RightTrigger; public short LX, LY, RX, RY; }
    [StructLayout(LayoutKind.Sequential)]
    struct State { public uint Packet; public Gamepad Pad; }
    [StructLayout(LayoutKind.Sequential)]
    struct Vibration { public ushort Left, Right; }
    [DllImport("xinput1_4.dll")] static extern uint XInputGetState(uint index, out State state);
    [DllImport("xinput1_4.dll")] static extern uint XInputSetState(uint index, ref Vibration vibration);

    // verbunden (0/1), Tasten (Bitmaske), LT, RT (0-255), LX, LY, RX, RY (-32768..32767)
    public static int[] Read(int index)
    {
        try
        {
            State state;
            if (XInputGetState((uint)index, out state) != 0) return new int[] { 0, 0, 0, 0, 0, 0, 0, 0 };
            var p = state.Pad;
            return new int[] { 1, p.Buttons, p.LeftTrigger, p.RightTrigger, p.LX, p.LY, p.RX, p.RY };
        }
        catch { return new int[] { 0, 0, 0, 0, 0, 0, 0, 0 }; }
    }

    public static void Vibrate(int index, bool on)
    {
        try { var v = new Vibration { Left = (ushort)(on ? 50000 : 0), Right = (ushort)(on ? 50000 : 0) }; XInputSetState((uint)index, ref v); } catch { }
    }
}

public static class PulsRigMouse
{
    [StructLayout(LayoutKind.Sequential)]
    struct Device { public ushort UsagePage, Usage; public uint Flags; public IntPtr Target; }
    [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterRawInputDevices(Device[] devices, uint count, uint size);
    [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr input, uint command, IntPtr data, ref uint size, uint headerSize);

    class Sink : NativeWindow
    {
        public Sink() { CreateHandle(new CreateParams()); }
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x00FF) { try { Take(m.LParam); } catch { } }
            base.WndProc(ref m);
        }
    }

    static Sink sink;
    static readonly Stopwatch clock = Stopwatch.StartNew();
    // Bewegungsmeldungen und Punkte Bewegung je 100-ms-Abschnitt, die letzten 50 Abschnitte (5 Sekunden)
    static readonly Queue<long[]> buckets = new Queue<long[]>();
    static long bucketId = -1, bucketMoves, bucketCounts;
    static double bestRate;
    static bool bestLimited;
    static readonly double[] lastUp = new double[5], lastDown = new double[5];
    public static readonly int[] Clicks = new int[5];        // links, rechts, Mitte, Seite 1, Seite 2
    public static readonly int[] Bounces = new int[5];       // löste kurz nach dem Loslassen wieder aus
    public static readonly bool[] Down = new bool[5];
    public static int Moves, Wheel;
    static readonly HashSet<long> devices = new HashSet<long>();
    public static int Devices { get { return devices.Count; } }
    // unter dieser Pause nach dem Loslassen gilt ein neuer Druck als Prellen des Schalters
    public static double BounceMs = 35;

    public static bool Start()
    {
        if (sink != null) return true;
        sink = new Sink();
        var device = new[] { new Device { UsagePage = 1, Usage = 2, Flags = 0x100, Target = sink.Handle } };   // Maus, auch im Hintergrund
        if (!RegisterRawInputDevices(device, 1, (uint)Marshal.SizeOf(typeof(Device)))) { sink.DestroyHandle(); sink = null; return false; }
        Reset();
        return true;
    }

    public static void Stop()
    {
        if (sink == null) return;
        var device = new[] { new Device { UsagePage = 1, Usage = 2, Flags = 0x1, Target = IntPtr.Zero } };      // abmelden
        RegisterRawInputDevices(device, 1, (uint)Marshal.SizeOf(typeof(Device)));
        sink.DestroyHandle();
        sink = null;
    }

    public static void Reset()
    {
        lock (buckets) { buckets.Clear(); bucketId = -1; bucketMoves = 0; bucketCounts = 0; bestRate = 0; bestLimited = false; }
        Moves = 0; Wheel = 0; devices.Clear();
        for (int i = 0; i < 5; i++) { Clicks[i] = 0; Bounces[i] = 0; Down[i] = false; lastUp[i] = -1000; lastDown[i] = -1000; }
    }

    static void Take(IntPtr handle)
    {
        uint headerSize = (uint)(8 + 2 * IntPtr.Size);
        uint size = 0;
        GetRawInputData(handle, 0x10000003, IntPtr.Zero, ref size, headerSize);
        if (size == 0) return;
        IntPtr buffer = Marshal.AllocHGlobal((int)size);
        try
        {
            if (GetRawInputData(handle, 0x10000003, buffer, ref size, headerSize) != size) return;
            if (Marshal.ReadInt32(buffer, 0) != 0) return;                     // keine Maus
            devices.Add(Marshal.ReadIntPtr(buffer, 8).ToInt64());
            int at = (int)headerSize;
            int flags = Marshal.ReadInt16(buffer, at + 4) & 0xFFFF;
            int x = Marshal.ReadInt32(buffer, at + 12), y = Marshal.ReadInt32(buffer, at + 16);
            double now = clock.Elapsed.TotalMilliseconds;
            if (x != 0 || y != 0)
            {
                Moves++;
                Count(now, Math.Abs(x) + Math.Abs(y));
            }
            for (int b = 0; b < 5; b++)
            {
                int downFlag = 1 << (2 * b), upFlag = 2 << (2 * b);
                if ((flags & downFlag) != 0)
                {
                    Clicks[b]++;
                    if (now - lastUp[b] < BounceMs) Bounces[b]++;
                    Down[b] = true; lastDown[b] = now;
                }
                if ((flags & upFlag) != 0) { Down[b] = false; lastUp[b] = now; }
            }
            if ((flags & 0x400) != 0) Wheel++;
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    static void Count(double now, long points)
    {
        lock (buckets)
        {
            long id = (long)(now / 100);
            if (id != bucketId)
            {
                if (bucketId >= 0)
                {
                    // Lücken (keine Bewegung) als leere Abschnitte mitzählen, damit nur zusammenhängende Bewegung gilt
                    for (long gap = bucketId + 1; gap < id && gap < bucketId + 50; gap++) buckets.Enqueue(new long[] { 0, 0 });
                    buckets.Enqueue(new long[] { bucketMoves, bucketCounts });
                    while (buckets.Count > 50) buckets.Dequeue();
                    Evaluate();
                }
                bucketId = id; bucketMoves = 0; bucketCounts = 0;
            }
            bucketMoves++; bucketCounts += points;
        }
    }

    // die beste halbe Sekunde (5 Abschnitte, alle mit Bewegung) seit dem letzten Zurücksetzen
    static void Evaluate()
    {
        var list = buckets.ToArray();
        for (int i = 0; i + 5 <= list.Length; i++)
        {
            long moves = 0, points = 0; bool steady = true;
            for (int j = i; j < i + 5; j++) { if (list[j][0] == 0) { steady = false; break; } moves += list[j][0]; points += list[j][1]; }
            if (!steady || moves < 50) continue;
            double rate = moves * 2.0;
            if (rate > bestRate) { bestRate = rate; bestLimited = points < moves * 1.3; }
        }
    }

    // Abfragerate in Hz (0, solange zu wenig gemessen ist)
    public static double Rate() { lock (buckets) return bestRate; }
    // true: fast jede Meldung trug nur einen Punkt Bewegung - die Maus könnte schneller melden, wenn sie schneller bewegt würde
    public static bool SpeedLimited { get { lock (buckets) return bestLimited; } }
    public static int Samples { get { return Moves; } }
}
