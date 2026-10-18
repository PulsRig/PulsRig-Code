using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

// Last für den Stabilitätstest. Prozessor: jeder Kern rechnet immer wieder dieselbe Aufgabe aus Ganzzahlen,
// Gleitkomma und Wurzeln (wie der Benchmark), deren Ergebnis feststeht - weicht eines ab, hat die Hardware falsch
// gerechnet. Bis Oktober 2026 waren es Prüfsummen (SHA-256): die rechnen viele Prozessoren mit sparsamen
// Spezialbefehlen, der Ryzen 7 5800X3D blieb damit 12 °C kühler als unter echter Volllast.
// Grafikkarte: ein Fenster, in dem so viele durchscheinende Flächen übereinander gezeichnet werden, dass die Karte
// voll ausgelastet ist. Die Flächen liegen als Anzeigeliste auf der Karte (wie im Benchmark): Bis Oktober 2026
// wurde jede Fläche einzeln geschickt, dann bremste der Prozessor und eine RTX 3080 blieb bei 63 °C.
// Kann die Karte Shader, rechnet stattdessen ein kleines Programm für jeden Bildpunkt eine Schleife aus Sinus,
// Kosinus und Multiplikationen: Das lastet die Recheneinheiten aus, nicht nur das Zeichnen (wie FurMark).
// Wie viel gerechnet wird, regelt sich so, dass ein Bild rund 30 ms dauert - auch auf schwacher Onboard-Grafik
// weit weg von der Zeitgrenze von Windows (2 Sekunden je Bild).
public static class PulsRigStress
{
    static volatile bool cpuRun;
    static volatile bool gpuRun;
    static long iterations;
    static long errors;
    static long frames;
    static Thread[] workers;
    static Thread gpuThread;
    static volatile string gpuError = "";
    static volatile bool gpuActive;
    // Zähler der Läufe: ein Lauf, der gerade erst gestoppt wurde, darf nicht weiterarbeiten, wenn sofort ein neuer startet
    static volatile int cpuRound;
    static volatile int gpuRound;

    public static long Iterations { get { return Interlocked.Read(ref iterations); } }
    public static long Errors { get { return Interlocked.Read(ref errors); } }
    public static long Frames { get { return Interlocked.Read(ref frames); } }
    public static string GpuError { get { return gpuError; } }
    public static string GpuMode = "";        // "Shader" oder "Flächen" (ohne Shader)
    public static bool GpuActive { get { return gpuActive; } }
    public static bool CpuActive { get { return cpuRun; } }

    // eine Rechenprobe: fester Startwert, also immer dasselbe Ergebnis (bitgenau)
    static double Probe(double[] table)
    {
        ulong state = 88172645463325252UL;
        for (int i = 0; i < table.Length; i++) table[i] = i;
        double sum = 0;
        for (int i = 0; i < 40000; i++)
        {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17;
            int slot = (int)(state & 1023);
            table[slot] = table[slot] * 0.999 + (state & 255) * 0.001;
            sum += Math.Sqrt(table[slot] + i) * 0.5;
        }
        return sum + state;
    }

    public static void StartCpu(int count)
    {
        if (cpuRun) return;
        Interlocked.Exchange(ref iterations, 0);
        Interlocked.Exchange(ref errors, 0);
        long expected = BitConverter.DoubleToInt64Bits(Probe(new double[1024]));
        int mine = cpuRound + 1;
        cpuRound = mine;
        cpuRun = true;
        workers = new Thread[count];
        for (int t = 0; t < count; t++)
        {
            workers[t] = new Thread(delegate ()
            {
                double[] table = new double[1024];
                while (cpuRun && cpuRound == mine)
                {
                    if (BitConverter.DoubleToInt64Bits(Probe(table)) != expected) Interlocked.Increment(ref errors);
                    Interlocked.Increment(ref iterations);
                }
            });
            workers[t].IsBackground = true;
            workers[t].Priority = ThreadPriority.BelowNormal;   // das Fenster des Programms bleibt bedienbar
            workers[t].Start();
        }
    }

    public static void Stop()
    {
        cpuRun = false;
        gpuRun = false;
    }

    [DllImport("psapi.dll")] static extern bool EmptyWorkingSet(IntPtr process);

    // Gibt nach dem Test den Arbeitsspeicher an Windows zurück, den das Programm gerade nicht braucht. Der Grafiktreiber
    // und die Fensterbibliothek bleiben geladen und hielten sonst rund 50 bis 80 MB belegt; was davon wieder gebraucht
    // wird, holt Windows von selbst zurück. Der zugesagte Speicher ändert sich dadurch nicht.
    public static void ReleaseMemory()
    {
        try
        {
            GC.Collect();
            EmptyWorkingSet(Process.GetCurrentProcess().Handle);
        }
        catch { }
    }

    [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);

    // Hält Windows während des Tests wach: sonst beendet der Energiesparmodus einen langen Lauf mittendrin
    public static void KeepAwake(bool on)
    {
        SetThreadExecutionState(on ? 0x80000003u : 0x80000000u);
    }

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
    [DllImport("opengl32.dll")] static extern IntPtr wglGetProcAddress(string name);

    // Shader-Befehle gibt es nur über wglGetProcAddress (OpenGL 2.0)
    delegate uint CreateShaderFn(uint type);
    delegate void ShaderSourceFn(uint shader, int count, string[] source, int[] length);
    delegate void CompileShaderFn(uint shader);
    delegate void GetShaderivFn(uint shader, uint name, out int value);
    delegate uint CreateProgramFn();
    delegate void AttachShaderFn(uint program, uint shader);
    delegate void LinkProgramFn(uint program);
    delegate void UseProgramFn(uint program);
    delegate int GetUniformLocationFn(uint program, string name);
    delegate void Uniform1fFn(int location, float value);

    static T Gl<T>(string name) where T : class
    {
        IntPtr pointer = wglGetProcAddress(name);
        long value = pointer.ToInt64();
        if (value == 0 || value == 1 || value == 2 || value == 3 || value == -1) return null;
        return Marshal.GetDelegateForFunctionPointer(pointer, typeof(T)) as T;
    }

    // Rechnet je Bildpunkt eine Schleife; "n" (Durchläufe) und "t" (Zeit) kommen von außen
    const string ShaderCode = @"#version 110
uniform float t;
uniform float n;
void main() {
    vec2 p = gl_FragCoord.xy / 400.0;
    float v = t;
    vec3 c = vec3(0.0);
    for (int i = 0; i < 512; i++) {
        if (float(i) >= n) break;
        v = sin(v * 1.31 + p.x * 3.7) * cos(v * 0.97 + p.y * 2.3) + p.x * p.y;
        c += vec3(abs(v), v * v, 0.5 + 0.5 * v) * 0.004;
    }
    gl_FragColor = vec4(c * vec3(0.3, 0.8, 1.0), 0.08);
}";

    // baut das Programm; Ergebnis 0, wenn die Karte oder der Treiber keine Shader kann
    static uint BuildShader(out UseProgramFn use, out Uniform1fFn uniform, out int timeAt, out int countAt)
    {
        use = null; uniform = null; timeAt = -1; countAt = -1;
        try
        {
            var create = Gl<CreateShaderFn>("glCreateShader");
            var source = Gl<ShaderSourceFn>("glShaderSource");
            var compile = Gl<CompileShaderFn>("glCompileShader");
            var status = Gl<GetShaderivFn>("glGetShaderiv");
            var program = Gl<CreateProgramFn>("glCreateProgram");
            var attach = Gl<AttachShaderFn>("glAttachShader");
            var link = Gl<LinkProgramFn>("glLinkProgram");
            var linked = Gl<GetShaderivFn>("glGetProgramiv");
            var location = Gl<GetUniformLocationFn>("glGetUniformLocation");
            use = Gl<UseProgramFn>("glUseProgram");
            uniform = Gl<Uniform1fFn>("glUniform1f");
            if (create == null || source == null || compile == null || status == null || program == null || attach == null ||
                link == null || linked == null || location == null || use == null || uniform == null) return 0;
            uint shader = create(0x8B30);              // Fragment-Shader
            source(shader, 1, new[] { ShaderCode }, null);
            compile(shader);
            int ok;
            status(shader, 0x8B81, out ok);            // kompiliert?
            if (ok == 0) return 0;
            uint id = program();
            attach(id, shader);
            link(id);
            linked(id, 0x8B82, out ok);                // gebunden?
            if (ok == 0) return 0;
            timeAt = location(id, "t");
            countAt = location(id, "n");
            return countAt < 0 ? 0 : id;
        }
        catch { return 0; }
    }

    public static void StartGpu(string title)
    {
        if (gpuRun) return;
        gpuError = "";
        Interlocked.Exchange(ref frames, 0);
        int mine = gpuRound + 1;
        gpuRound = mine;
        gpuActive = false;
        gpuRun = true;
        gpuThread = new Thread(delegate ()
        {
            Form form = null; IntPtr dc = IntPtr.Zero, context = IntPtr.Zero;
            try
            {
                form = new Form();
                form.Text = title;
                form.ClientSize = new System.Drawing.Size(640, 400);
                form.FormBorderStyle = FormBorderStyle.FixedToolWindow;
                form.StartPosition = FormStartPosition.Manual;
                form.Location = new System.Drawing.Point(60, 60);
                form.ShowInTaskbar = false;
                form.TopMost = true;
                form.FormClosing += delegate { if (gpuRound == mine) gpuRun = false; };
                form.Show();
                dc = GetDC(form.Handle);
                PixelFormat format = new PixelFormat();
                format.size = (ushort)Marshal.SizeOf(typeof(PixelFormat));
                format.version = 1;
                format.flags = 0x4 | 0x20 | 0x1;       // ins Fenster zeichnen, OpenGL, doppelt gepuffert
                format.colorBits = 32;
                int index = ChoosePixelFormat(dc, ref format);
                if (index == 0 || !SetPixelFormat(dc, index, ref format)) throw new InvalidOperationException("Kein passendes Bildformat für die Grafikkarte");
                context = wglCreateContext(dc);
                if (context == IntPtr.Zero || !wglMakeCurrent(dc, context)) throw new InvalidOperationException("Die Grafikkarte stellt keine Zeichenfläche bereit");
                glViewport(0, 0, 640, 400);
                glEnable(0x0BE2);                       // Durchscheinen
                glBlendFunc(0x0302, 0x0303);
                gpuActive = true;
                // 64 bildschirmfüllende, durchscheinende Flächen als Anzeigeliste: liegen danach auf der Karte
                const int layers = 64;
                uint list = glGenLists(1);
                glNewList(list, 0x1300);
                glBegin(0x0007);
                for (int i = 0; i < layers; i++)
                {
                    glColor4f(0.13f + 0.5f * (i % 3 == 0 ? 1 : 0), 0.4f + 0.4f * (i % 3 == 1 ? 1 : 0), 0.9f, 0.012f);
                    glVertex2f(-1, -1); glVertex2f(1, -1); glVertex2f(1, 1); glVertex2f(-1, 1);
                }
                glEnd();
                glEndList();
                UseProgramFn use; Uniform1fFn uniform; int timeAt, countAt;
                uint shader = BuildShader(out use, out uniform, out timeAt, out countAt);
                GpuMode = shader != 0 ? "Shader" : "Flächen";
                int calls = shader != 0 ? 1 : 4;
                float loops = 8;                        // Durchläufe der Shader-Schleife: klein anfangen
                float phase = 0;
                Stopwatch watch = new Stopwatch();
                while (gpuRun && gpuRound == mine)
                {
                    watch.Restart();
                    glClearColor(0.03f, 0.05f, 0.1f, 1);
                    glClear(0x4000);
                    if (shader != 0)
                    {
                        use(shader);
                        if (timeAt >= 0) uniform(timeAt, phase);
                        uniform(countAt, loops);
                        for (int c = 0; c < calls; c++)
                        {
                            glBegin(0x0007);
                            glVertex2f(-1, -1); glVertex2f(1, -1); glVertex2f(1, 1); glVertex2f(-1, 1);
                            glEnd();
                        }
                        use(0);
                    }
                    else for (int c = 0; c < calls; c++) glCallList(list);
                    // ein wandernder Streifen obendrauf: zeigt, dass der Test läuft
                    float x = (float)Math.Sin(phase) * 0.8f;
                    glBegin(0x0007);
                    glColor4f(0.4f, 0.9f, 1f, 0.6f);
                    glVertex2f(x - 0.03f, -1); glVertex2f(x + 0.03f, -1); glVertex2f(x + 0.03f, 1); glVertex2f(x - 0.03f, 1);
                    glEnd();
                    glFinish();
                    SwapBuffers(dc);
                    Interlocked.Increment(ref frames);
                    phase += 0.05f;
                    // so viel Arbeit, dass ein Bild rund 30 Millisekunden kostet: dann ist die Karte ausgelastet,
                    // und Windows (Zeitgrenze 2 Sekunden je Bild) bleibt weit weg
                    double ms = watch.Elapsed.TotalMilliseconds;
                    if (shader != 0)
                    {
                        // erst die Schleife länger machen (bis 512), dann mehr Flächen; zu langsam: erst Flächen, dann Schleife
                        if (ms < 24) { if (loops < 512) loops = Math.Min(512, loops * 1.25f + 1); else if (calls < 1000) calls++; }
                        else if (ms > 45) { if (calls > 1) calls--; else if (loops > 4) loops = Math.Max(4, loops * 0.7f); }
                    }
                    else if (ms < 24 && calls < 100000) calls = (int)(calls * 1.25) + 1;
                    else if (ms > 45 && calls > 1) calls = Math.Max(1, (int)(calls * 0.85));
                    Application.DoEvents();
                }
            }
            catch (Exception problem) { if (gpuRound == mine) gpuError = problem.Message; }
            finally
            {
                if (gpuRound == mine) { gpuActive = false; gpuRun = false; }
                try { if (context != IntPtr.Zero) { wglMakeCurrent(IntPtr.Zero, IntPtr.Zero); wglDeleteContext(context); } } catch { }
                try { if (dc != IntPtr.Zero && form != null) ReleaseDC(form.Handle, dc); } catch { }
                try { if (form != null) form.Dispose(); } catch { }
            }
        });
        gpuThread.IsBackground = true;
        gpuThread.SetApartmentState(ApartmentState.STA);
        gpuThread.Start();
    }
}
