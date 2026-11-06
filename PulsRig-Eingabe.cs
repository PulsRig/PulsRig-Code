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

// PS4- und PS5-Controller über Raw Input (HID): ein unsichtbares Fenster bekommt jede Meldung des Controllers, auch
// wenn PulsRig nicht vorn ist; ausgewertet wird sie in PulsRig.Core.Playstation. Die Abfragerate ist die höchste Zahl
// an Meldungen in einer Sekunde. Steam liest mit, das stört nicht; versteckt DS4Windows/HidHide den Controller, sieht
// PulsRig ihn nur als den Xbox-Controller, den DS4Windows nachbildet. Vibrieren geht nur per Kabel (per Bluetooth
// braucht jede Meldung eine Prüfsumme und schaltet den Controller in einen anderen Modus).
public static class PulsRigPlaystation
{
    [StructLayout(LayoutKind.Sequential)]
    struct Device { public ushort UsagePage, Usage; public uint Flags; public IntPtr Target; }
    [StructLayout(LayoutKind.Sequential)]
    struct HidCaps
    {
        public ushort Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved;
        public ushort A, B, C, D, E, F, G, H, I, J;
    }
    [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterRawInputDevices(Device[] devices, uint count, uint size);
    [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr input, uint command, IntPtr data, ref uint size, uint headerSize);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern uint GetRawInputDeviceInfo(IntPtr device, uint command, IntPtr data, ref uint size);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern Microsoft.Win32.SafeHandles.SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool WriteFile(Microsoft.Win32.SafeHandles.SafeFileHandle file, byte[] data, int size, out int written, IntPtr overlapped);
    [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(Microsoft.Win32.SafeHandles.SafeFileHandle file, out IntPtr data);
    [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr data);
    [DllImport("hid.dll")] static extern int HidP_GetCaps(IntPtr data, out HidCaps caps);

    class Sink : NativeWindow
    {
        public Sink() { CreateHandle(new CreateParams()); }
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x00FF) { try { Take(m.LParam); } catch { } }
            // ein Gerät wurde getrennt (wParam 2): war es unser Controller, gilt er als weg
            if (m.Msg == 0x00FE && m.WParam.ToInt64() == 2) { lock (gate) { known.Remove(m.LParam.ToInt64()); if (m.LParam == current) current = IntPtr.Zero; } }
            base.WndProc(ref m);
        }
    }

    static Sink? sink;
    static readonly object gate = new object();
    static readonly Stopwatch clock = Stopwatch.StartNew();
    // je Gerät: Hersteller und Produkt (0 = kein PlayStation-Controller)
    static readonly Dictionary<long, int> known = new Dictionary<long, int>();
    static IntPtr current;
    static int product;
    static int[] state = new int[8];
    static string link = "";
    static readonly Queue<double> times = new Queue<double>();
    static int bestRate;
    static double lastReport = -1;

    static readonly ushort[] Usages = { 4, 5 };        // Joystick und Gamepad

    public static bool Start()
    {
        if (sink != null) return true;
        sink = new Sink();
        var devices = new Device[Usages.Length];
        for (int i = 0; i < Usages.Length; i++) devices[i] = new Device { UsagePage = 1, Usage = Usages[i], Flags = 0x100 | 0x2000, Target = sink.Handle };   // auch im Hintergrund, mit Trennen-Meldung
        if (!RegisterRawInputDevices(devices, (uint)devices.Length, (uint)Marshal.SizeOf(typeof(Device)))) { sink.DestroyHandle(); sink = null; return false; }
        return true;
    }

    public static void Stop()
    {
        if (sink == null) return;
        var devices = new Device[Usages.Length];
        for (int i = 0; i < Usages.Length; i++) devices[i] = new Device { UsagePage = 1, Usage = Usages[i], Flags = 0x1, Target = IntPtr.Zero };
        RegisterRawInputDevices(devices, (uint)devices.Length, (uint)Marshal.SizeOf(typeof(Device)));
        try { sink.DestroyHandle(); }
        finally { sink = null; lock (gate) { current = IntPtr.Zero; known.Clear(); } }
    }

    public static void ResetRate() { lock (gate) { times.Clear(); bestRate = 0; } }

    static int Product(IntPtr device)
    {
        long key = device.ToInt64();
        if (known.TryGetValue(key, out var p)) return p;
        p = 0;
        uint size = 32;
        IntPtr info = Marshal.AllocHGlobal(32);
        try
        {
            Marshal.WriteInt32(info, 0, 32);
            if (GetRawInputDeviceInfo(device, 0x2000000b, info, ref size) != unchecked((uint)-1) && Marshal.ReadInt32(info, 4) == 2)
            {
                int vendor = Marshal.ReadInt32(info, 8), id = Marshal.ReadInt32(info, 12);
                if (PulsRig.Core.Playstation.Model(vendor, id).Length > 0) p = id;
            }
        }
        finally { Marshal.FreeHGlobal(info); }
        known[key] = p;
        return p;
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
            if (Marshal.ReadInt32(buffer, 0) != 2) return;                     // kein HID-Gerät
            IntPtr device = Marshal.ReadIntPtr(buffer, 8);
            lock (gate)
            {
                int id = Product(device);
                if (id == 0) return;
                int at = (int)headerSize;
                int each = Marshal.ReadInt32(buffer, at), count = Marshal.ReadInt32(buffer, at + 4);
                if (each <= 0 || count <= 0) return;
                var report = new byte[each];
                Marshal.Copy(buffer + at + 8 + (count - 1) * each, report, 0, each);
                var read = PulsRig.Core.Playstation.Read(report, id);
                if (read == null) return;
                // ein zweiter Controller zählt erst, wenn der erste eine Sekunde still war
                double now = clock.Elapsed.TotalMilliseconds;
                if (current != IntPtr.Zero && current != device && now - lastReport < 1000) return;
                if (current != device) { times.Clear(); bestRate = 0; }
                current = device; product = id; state = read; link = PulsRig.Core.Playstation.Link(report, id); lastReport = now;
                for (int i = 0; i < count; i++) times.Enqueue(now);
                while (times.Count > 0 && now - times.Peek() > 1000) times.Dequeue();
                // erst ab einer vollen Sekunde Messung
                if (times.Count > 1 && clock.Elapsed.TotalMilliseconds - times.Peek() >= 950 && times.Count > bestRate) bestRate = times.Count;
            }
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    // wie PulsRigPad.Read; dazu Produktkennung (0 = keiner verbunden)
    public static int[] Read(out int productId)
    {
        lock (gate)
        {
            productId = current == IntPtr.Zero ? 0 : product;
            return current == IntPtr.Zero ? new int[8] : (int[])state.Clone();
        }
    }

    public static string Link { get { lock (gate) return current == IntPtr.Zero ? "" : link; } }
    // gemessene Meldungen je Sekunde (höchster Wert seit dem Verbinden), 0 = noch zu wenig
    public static int Rate { get { lock (gate) return bestRate; } }

    // Vibrieren per Kabel: DualSense Meldung 0x02 (Rumpel-Nachbildung an), DualShock 4 Meldung 0x05
    public static bool Vibrate(bool on)
    {
        IntPtr device; int id; string how;
        lock (gate) { device = current; id = product; how = link; }
        if (device == IntPtr.Zero || how != "Kabel") return false;
        try
        {
            uint size = 0;
            GetRawInputDeviceInfo(device, 0x20000007, IntPtr.Zero, ref size);
            if (size == 0) return false;
            IntPtr text = Marshal.AllocHGlobal((int)size * 2);
            string path;
            try { GetRawInputDeviceInfo(device, 0x20000007, text, ref size); path = Marshal.PtrToStringUni(text) ?? ""; }
            finally { Marshal.FreeHGlobal(text); }
            using (var file = CreateFile(path, 0x40000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero))
            {
                if (file.IsInvalid) return false;
                int length = PulsRig.Core.Playstation.IsDualSense(id) ? 48 : 32;
                IntPtr parsed;
                if (HidD_GetPreparsedData(file, out parsed))
                {
                    try { HidCaps caps; if (HidP_GetCaps(parsed, out caps) == 0x00110000 && caps.OutputReportByteLength > 0) length = caps.OutputReportByteLength; }
                    finally { HidD_FreePreparsedData(parsed); }
                }
                var data = new byte[length];
                byte strength = (byte)(on ? 200 : 0);
                if (PulsRig.Core.Playstation.IsDualSense(id)) { data[0] = 0x02; data[1] = 0x03; data[3] = strength; data[4] = strength; }
                else { data[0] = 0x05; data[1] = 0x01; data[4] = strength; data[5] = strength; }
                int written;
                return WriteFile(file, data, data.Length, out written, IntPtr.Zero);
            }
        }
        catch { return false; }
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

    static Sink? sink;
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
        try { sink.DestroyHandle(); }
        finally { sink = null; }
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
