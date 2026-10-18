// PulsRig - Benchmark: kurze, wiederholbare Messungen mit Punktzahl. Wird von PulsRig-Benchmark.ps1 beim ersten Lauf übersetzt.
//
// Prozessor: eine feste Rechenaufgabe (Ganzzahlen, Gleitkomma, Zugriffe im schnellen Zwischenspeicher), erst auf einem
// Kern, dann auf allen; gezählt wird, wie oft sie pro Sekunde fertig wird. Bewusst ohne Prüfsummen von Windows: die
// nutzen auf manchen Prozessoren Spezialbefehle und verzerrten den Vergleich.
// Arbeitsspeicher: Kopieren großer Blöcke (GB/s) und Wartezeit bei zufälligen Zugriffen (ns), beides größer als jeder
// Zwischenspeicher eines Prozessors (auch 96 MB beim Ryzen X3D).
// Grafikkarte: Füllrate - wie viele durchscheinende Bildpunkte sie pro Sekunde zeichnet. Die Flächen liegen vorab auf der
// Karte (Anzeigeliste), damit der Prozessor nicht bremst; gemessen wird nur die Zeit des Zeichnens selbst.
// Alles läuft in eigenen Threads; das Fenster fragt Stage und Percent ab.

using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

public static class PulsRigBench
{
    public static volatile string Stage = "";      // single, multi, memory, gpu, done, stopped
    public static volatile int Percent;
    public static double Single, Multi, Copy, Latency, Fill;
    public static string GpuName = "", GpuError = "";
    static volatile bool cancel;
    static Thread runner;
    static double scale = 1.0;

    public static bool Running { get { return runner != null && runner.IsAlive; } }

    // Scale verkürzt alle Messzeiten (Probelauf); Gpu = false lässt die Grafikkarte aus
    public static void Start(double timeScale, bool gpu)
    {
        if (Running) return;
        cancel = false;
        scale = timeScale;
        Single = Multi = Copy = Latency = Fill = 0;
        GpuName = ""; GpuError = "";
        Stage = "single"; Percent = 0;
        runner = new Thread(delegate ()
        {
            try
            {
                Single = MeasureCpu(1, 4.0 * scale, 0, 20);
                if (cancel) { Stage = "stopped"; return; }
                Stage = "multi";
                Multi = MeasureCpu(Environment.ProcessorCount, 6.0 * scale, 20, 50);
                if (cancel) { Stage = "stopped"; return; }
                Stage = "memory";
                MeasureMemory(50, 70);
                if (cancel) { Stage = "stopped"; return; }
                if (gpu)
                {
                    Stage = "gpu";
                    MeasureGpu(7.0 * scale, 70, 100);
                }
                Percent = 100;
                Stage = cancel ? "stopped" : "done";
            }
            catch (Exception problem) { GpuError = problem.Message; Stage = "done"; }
            finally { GC.Collect(); }
        });
        runner.IsBackground = true;
        runner.Priority = ThreadPriority.BelowNormal;
        runner.Start();
    }

    public static void Stop() { cancel = true; }

    // --- Prozessor ---

    static double Work(ref ulong state, double[] table)
    {
        double sum = 0;
        for (int i = 0; i < 40000; i++)
        {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17;
            int slot = (int)(state & 1023);
            table[slot] = table[slot] * 0.999 + (state & 255) * 0.001;
            sum += Math.Sqrt(table[slot] + i) * 0.5;
        }
        return sum;
    }

    // Ergebnis: Aufgaben pro Sekunde, über alle Threads
    static double MeasureCpu(int threads, double seconds, int from, int to)
    {
        long done = 0;
        double sink = 0;
        var start = new ManualResetEvent(false);
        var workers = new Thread[threads];
        bool[] stop = new bool[1];
        for (int t = 0; t < threads; t++)
        {
            int seed = t;
            workers[t] = new Thread(delegate ()
            {
                ulong state = 88172645463325252UL + (ulong)seed;
                double[] table = new double[1024];
                for (int i = 0; i < table.Length; i++) table[i] = i;
                double local = 0;
                start.WaitOne();
                while (!Volatile.Read(ref stop[0]))
                {
                    local += Work(ref state, table);
                    Interlocked.Increment(ref done);
                }
                lock (workers) sink += local;
            });
            workers[t].IsBackground = true;
            workers[t].Priority = ThreadPriority.BelowNormal;   // das Fenster bleibt bedienbar
            workers[t].Start();
        }
        // kurz anlaufen lassen (Takt hoch), dann erst zählen
        start.Set();
        Thread.Sleep(300);
        long before = Interlocked.Read(ref done);
        var watch = Stopwatch.StartNew();
        while (watch.Elapsed.TotalSeconds < seconds && !cancel)
        {
            Thread.Sleep(100);
            Percent = from + (int)((to - from) * Math.Min(1.0, watch.Elapsed.TotalSeconds / seconds));
        }
        long after = Interlocked.Read(ref done);
        double elapsed = watch.Elapsed.TotalSeconds;
        Volatile.Write(ref stop[0], true);
        foreach (var worker in workers) worker.Join();
        if (double.IsNaN(sink)) return 0;      // hält die Rechnung am Leben, damit nichts wegoptimiert wird
        return (after - before) / elapsed;
    }

    // --- Arbeitsspeicher ---

    static void MeasureMemory(int from, int to)
    {
        const int size = 128 << 20;                // 128 MB je Puffer
        byte[] source = new byte[size], target = new byte[size];
        for (int i = 0; i < size; i += 4096) { source[i] = 1; target[i] = 1; }   // Seiten anlegen
        int parts = Math.Max(1, Math.Min(8, Environment.ProcessorCount / 2));
        int chunk = size / parts;
        long copied = 0;
        var watch = Stopwatch.StartNew();
        double seconds = 2.5 * scale;
        while (watch.Elapsed.TotalSeconds < seconds && !cancel)
        {
            var copiers = new Thread[parts];
            for (int p = 0; p < parts; p++)
            {
                int offset = p * chunk;
                copiers[p] = new Thread(delegate () { Buffer.BlockCopy(source, offset, target, offset, chunk); });
                copiers[p].IsBackground = true;
                copiers[p].Start();
            }
            foreach (var copier in copiers) copier.Join();
            copied += (long)chunk * parts;
            Percent = from + (int)((to - from) * 0.5 * Math.Min(1.0, watch.Elapsed.TotalSeconds / seconds));
        }
        Copy = copied / watch.Elapsed.TotalSeconds / 1e9;
        source = null; target = null;
        GC.Collect();
        if (cancel) return;

        // Wartezeit: ein zufälliger Rundgang durch 128 MB (Sattolo), jeder Schritt hängt vom vorigen ab
        int count = 32 << 20;
        int[] next = new int[count];
        for (int i = 0; i < count; i++) next[i] = i;
        var random = new Random(4711);
        for (int i = count - 1; i > 0; i--) { int j = random.Next(i); int swap = next[i]; next[i] = next[j]; next[j] = swap; }
        Percent = from + (int)((to - from) * 0.7);
        int at = 0;
        for (int i = 0; i < 200000; i++) at = next[at];   // anlaufen
        long steps = (long)(12000000 * scale) + 1000000;
        watch.Restart();
        for (long i = 0; i < steps; i++) at = next[at];
        double elapsed = watch.Elapsed.TotalSeconds;
        Latency = elapsed * 1e9 / steps + (at < 0 ? 1 : 0);
        next = null;
        GC.Collect();
        Percent = to;
    }

    // --- Grafikkarte ---

    [StructLayout(LayoutKind.Sequential)]
    struct PixelFormat
    {
        public ushort size, version; public uint flags; public byte pixelType, colorBits;
        public byte r1, r2, g1, g2, b1, b2, a1, a2, accum, ar, ag, ab, aa, depthBits, stencilBits, aux, layerType, reserved;
        public uint layerMask, visibleMask, damageMask;
    }
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr window, IntPtr dc);
    [DllImport("gdi32.dll")] static extern int ChoosePixelFormat(IntPtr dc, ref PixelFormat format);
    [DllImport("gdi32.dll")] static extern bool SetPixelFormat(IntPtr dc, int index, ref PixelFormat format);
    [DllImport("gdi32.dll")] static extern bool SwapBuffers(IntPtr dc);
    [DllImport("opengl32.dll")] static extern IntPtr wglCreateContext(IntPtr dc);
    [DllImport("opengl32.dll")] static extern bool wglMakeCurrent(IntPtr dc, IntPtr context);
    [DllImport("opengl32.dll")] static extern bool wglDeleteContext(IntPtr context);
    [DllImport("opengl32.dll")] static extern void glViewport(int x, int y, int width, int height);
    [DllImport("opengl32.dll")] static extern void glClearColor(float r, float g, float b, float a);
    [DllImport("opengl32.dll")] static extern void glClear(uint mask);
    [DllImport("opengl32.dll")] static extern void glEnable(uint cap);
    [DllImport("opengl32.dll")] static extern void glBlendFunc(uint source, uint target);
    [DllImport("opengl32.dll")] static extern void glBegin(uint mode);
    [DllImport("opengl32.dll")] static extern void glEnd();
    [DllImport("opengl32.dll")] static extern void glColor4f(float r, float g, float b, float a);
    [DllImport("opengl32.dll")] static extern void glVertex2f(float x, float y);
    [DllImport("opengl32.dll")] static extern void glFinish();
    [DllImport("opengl32.dll")] static extern uint glGenLists(int range);
    [DllImport("opengl32.dll")] static extern void glNewList(uint list, uint mode);
    [DllImport("opengl32.dll")] static extern void glEndList();
    [DllImport("opengl32.dll")] static extern void glCallList(uint list);
    [DllImport("opengl32.dll")] static extern IntPtr glGetString(uint name);

    static void MeasureGpu(double seconds, int from, int to)
    {
        Exception failure = null;
        var thread = new Thread(delegate ()
        {
            Form form = null; IntPtr dc = IntPtr.Zero, context = IntPtr.Zero;
            try
            {
                int width = 1280, height = 720;
                form = new Form();
                form.Text = "PulsRig – Benchmark der Grafikkarte";
                form.ClientSize = new System.Drawing.Size(width, height);
                form.FormBorderStyle = FormBorderStyle.FixedToolWindow;
                form.StartPosition = FormStartPosition.CenterScreen;
                form.ShowInTaskbar = false;
                form.TopMost = true;
                form.FormClosing += delegate { cancel = true; };
                form.Show();
                dc = GetDC(form.Handle);
                PixelFormat format = new PixelFormat();
                format.size = (ushort)Marshal.SizeOf(typeof(PixelFormat));
                format.version = 1;
                format.flags = 0x4 | 0x20 | 0x1;
                format.colorBits = 32;
                int index = ChoosePixelFormat(dc, ref format);
                if (index == 0 || !SetPixelFormat(dc, index, ref format)) throw new InvalidOperationException("Kein passendes Bildformat für die Grafikkarte");
                context = wglCreateContext(dc);
                if (context == IntPtr.Zero || !wglMakeCurrent(dc, context)) throw new InvalidOperationException("Die Grafikkarte stellt keine Zeichenfläche bereit");
                IntPtr name = glGetString(0x1F01);
                if (name != IntPtr.Zero) GpuName = Marshal.PtrToStringAnsi(name);
                glViewport(0, 0, width, height);
                glEnable(0x0BE2);
                glBlendFunc(0x0302, 0x0303);
                // 64 bildschirmfüllende, durchscheinende Flächen als Anzeigeliste: liegt danach auf der Karte
                const int layers = 64;
                uint list = glGenLists(1);
                glNewList(list, 0x1300);
                glBegin(0x0007);
                for (int i = 0; i < layers; i++)
                {
                    glColor4f(0.13f + 0.5f * (i % 3 == 0 ? 1 : 0), 0.4f + 0.4f * (i % 3 == 1 ? 1 : 0), 0.9f, 0.02f);
                    glVertex2f(-1, -1); glVertex2f(1, -1); glVertex2f(1, 1); glVertex2f(-1, 1);
                }
                glEnd();
                glEndList();
                int calls = 4;
                double drawn = 0, busy = 0;
                var total = Stopwatch.StartNew();
                var frame = new Stopwatch();
                while (total.Elapsed.TotalSeconds < seconds + 1.0 && !cancel)
                {
                    glClearColor(0.03f, 0.05f, 0.1f, 1);
                    glClear(0x4000);
                    glFinish();
                    frame.Restart();
                    for (int c = 0; c < calls; c++) glCallList(list);
                    glFinish();
                    double ms = frame.Elapsed.TotalMilliseconds;
                    SwapBuffers(dc);
                    Application.DoEvents();
                    // die erste Sekunde wärmt nur auf; danach zählt jede Fläche
                    if (total.Elapsed.TotalSeconds > 1.0) { drawn += (double)calls * layers * width * height; busy += ms; }
                    // ein Bild soll rund 40 ms dauern: genug Arbeit, aber weit weg von der Zeitgrenze von Windows (2 s)
                    if (ms < 30 && calls < 4096) calls = calls * 2;
                    else if (ms > 60 && calls > 1) calls = Math.Max(1, calls * 3 / 4);
                    Percent = from + (int)((to - from) * Math.Min(1.0, total.Elapsed.TotalSeconds / (seconds + 1.0)));
                }
                if (busy > 0) Fill = drawn / (busy / 1000.0) / 1e9;
            }
            catch (Exception problem) { failure = problem; }
            finally
            {
                try { if (context != IntPtr.Zero) { wglMakeCurrent(IntPtr.Zero, IntPtr.Zero); wglDeleteContext(context); } } catch { }
                try { if (dc != IntPtr.Zero && form != null) ReleaseDC(form.Handle, dc); } catch { }
                try { if (form != null) form.Dispose(); } catch { }
            }
        });
        thread.IsBackground = true;
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure != null) GpuError = failure.Message;
    }
}
