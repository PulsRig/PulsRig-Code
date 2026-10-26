using System.Text.Json;
using System.Windows.Threading;

namespace PulsRig.App;

sealed record StressErgebnis(string Title, string Text, string Tone, string Time, double MaxGpuTemp, double MaxCpuTemp, List<double> Temps, bool Ended = true);

// Der Stabilitätstest wie Start-Stress, Update-Stress und Stop-Stress in PulsRig-Hardware.ps1: Last über
// PulsRig-Last.cs, Überwachung zweimal je Sekunde mit den Werten von Live. Der Test endet von selbst bei
// Rechenfehlern, 90 °C an der Grafikkarte, 98 °C am Prozessor, wenn der Prozessor drosselt oder die Zeit um ist.
static class Belastung
{
    public static string What = "both";      // cpu, gpu oder both
    public static int Minutes = 5;
    public static bool Running => timer != null;
    public static StressErgebnis? Last { get; private set; } = Load();
    public static string State { get; private set; } = "";
    public static double Elapsed { get; private set; }
    public static int Seconds { get; private set; }
    // Temperatur je Messpunkt (die höhere von Prozessor und Grafikkarte, soweit belastet) für die Balken
    public static List<double> Temps { get; } = new();
    public static event Action? Changed;

    static DispatcherTimer? timer;
    static DateTime start, seen;
    static object? stamp;
    static double baseClock, maxClock, maxGpu, maxCpu;
    // die letzte Minute für den Messpunkt unter Verschleiß (Verschleissdaten.AddStress)
    static readonly List<(double? GT, double? GW, double? GF, double? CT, double? CC, double? CW)> tail = new();
    static int lowClock, cpuAt;
    static bool hadTemp;

    // Datenordner der neuen Oberfläche, getrennt vom PowerShell-Programm; ohne Installation auf dem Stick
    public static string Folder => System.IO.Path.Combine(Altdaten.Portable is { } stick ? System.IO.Path.Combine(stick, "Treiber") : System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PulsRig"), "Neu");
    static string File => System.IO.Path.Combine(Folder, "Stabilitaetstest.json");

    static StressErgebnis? Load()
    {
        try { return JsonSerializer.Deserialize<StressErgebnis>(System.IO.File.ReadAllText(File)); }
        catch (Exception) { return null; }
    }

    static void Save(StressErgebnis result)
    {
        try
        {
            System.IO.Directory.CreateDirectory(System.IO.Path.GetDirectoryName(File)!);
            System.IO.File.WriteAllText(File, JsonSerializer.Serialize(result));
        }
        catch (Exception) { }
    }

    static bool Cpu => What is "cpu" or "both";
    static bool Gpu => What is "gpu" or "both";

    public static void Start()
    {
        if (Running) return;
        Seconds = 60 * Minutes;
        tail.Clear();
        // vorab als Ausfall vermerkt: endet der Test regulär, überschreibt Stop das. Bleibt es stehen, ist der PC
        // mittendrin ausgefallen - das soll nach dem Neustart dastehen
        Save(new("PC während des Tests ausgefallen",
            "Der letzte Stabilitätstest wurde nicht zu Ende gebracht: Der PC ist abgestürzt oder hat abgeschaltet. Unter Volllast liegt das meist am Netzteil (zu schwach, alt oder überfordert von Lastspitzen der Grafikkarte) oder an einer übertakteten oder fehlerhaften Grafikkarte. Prozessor und Grafikkarte einzeln testen und unter „Abstürze“ nachsehen.",
            "bad", DateTime.Now.ToString("dd.MM.yyyy HH:mm"), 0, 0, new()));
        // bei beidem kommt der Prozessor erst nach 10 Sekunden dazu: Springen beide im selben Moment auf Volllast,
        // schaltet ein schwächeres Netzteil am ehesten ab
        cpuAt = What == "both" ? 10 : 0;
        if (What == "cpu") PulsRigStress.StartCpu(Environment.ProcessorCount);
        if (Gpu) PulsRigStress.StartGpu("PulsRig – Grafiklast (Schließen beendet den Test)");
        start = seen = DateTime.UtcNow;
        stamp = null;
        baseClock = maxClock = maxGpu = maxCpu = 0;
        lowClock = 0;
        hadTemp = false;
        Temps.Clear();
        Elapsed = 0;
        try { PulsRigStress.KeepAwake(true); } catch (Exception) { }
        Live.Use();
        State = "Die Last fährt hoch.";
        timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        timer.Tick += (_, _) => Tick();
        timer.Start();
        Changed?.Invoke();
    }

    public static void Choose(string what)
    {
        if (Running) return;
        What = what;
        Changed?.Invoke();
    }

    public static void Cancel() => Stop("Gestoppt", "warn", "Du hast den Test vorzeitig beendet.");

    static void Tick()
    {
        Elapsed = (DateTime.UtcNow - start).TotalSeconds;
        if (Cpu && Elapsed >= cpuAt && !PulsRigStress.CpuActive) PulsRigStress.StartCpu(Environment.ProcessorCount);
        var cpuTime = Elapsed - cpuAt;
        // den Zähler setzt erst StartCpu zurück: bei "beides" kommt der Prozessor 10 Sekunden später dazu
        if (PulsRigStress.CpuActive && PulsRigStress.Errors > 0)
        {
            Stop("Rechenfehler", "bad", "Der Prozessor hat sich " + PulsRigStress.Errors + "-mal verrechnet. Das deutet auf Übertaktung, zu wenig Spannung, Hitze oder defekten Arbeitsspeicher.");
            return;
        }
        if (Gpu && PulsRigStress.GpuError.Length > 0) { Stop("Grafiklast nicht möglich", "warn", "Die Grafikkarte ließ sich nicht belasten: " + PulsRigStress.GpuError); return; }
        if (Gpu && Elapsed > 6 && !PulsRigStress.GpuActive) { Stop("Gestoppt", "warn", "Das Fenster der Grafiklast wurde geschlossen."); return; }
        var values = Live.Values;
        if (!ReferenceEquals(values, stamp) && values.Count > 0)
        {
            stamp = values;
            seen = DateTime.UtcNow;
            double? gpuTemp = Live.Get("GpuTemp"), cpuTemp = Live.Get("CpuTemp"), clock = Live.Get("CpuClock");
            if (gpuTemp is { } gt)
            {
                hadTemp = true;
                if (Gpu && gt > maxGpu) maxGpu = gt;
                if (Gpu && gt >= 90) { Stop("Zu heiß", "bad", "Die Grafikkarte hat " + Math.Round(gt) + " °C erreicht. Kühlung, Lüfter und Staub prüfen."); return; }
            }
            if (cpuTemp is { } ct)
            {
                if (Cpu && ct > maxCpu) maxCpu = ct;
                // die meisten Prozessoren drosseln zwischen 90 und 100 °C selbst; 98 °C heißt, die Kühlung reicht nicht
                if (Cpu && ct >= 98) { Stop("Zu heiß", "bad", "Der Prozessor hat " + Math.Round(ct) + " °C erreicht. Kühler, Wärmeleitpaste und Lüfter prüfen."); return; }
            }
            tail.Add((gpuTemp, Live.Get("GpuPower"), Live.Get("GpuFan"), cpuTemp, clock, Live.Get("CpuPower")));
            if (tail.Count > 60) tail.RemoveAt(0);
            var shown = Math.Max(Gpu ? gpuTemp ?? 0 : 0, Cpu ? cpuTemp ?? 0 : 0);
            if (shown > 0) Temps.Add(shown);
            if (Cpu && clock is { } c)
            {
                if (c > maxClock) maxClock = c;
                // Vergleichswert ist der Takt zwischen der 8. und 20. Sekunde; fällt er später anhaltend um ein Drittel,
                // bremst sich der Prozessor selbst - das tut er, wenn er zu heiß wird
                if (cpuTime >= 8 && cpuTime < 20 && c > baseClock) baseClock = c;
                if (cpuTime >= 20 && baseClock > 0)
                {
                    lowClock = c < 0.67 * baseClock ? lowClock + 1 : 0;
                    if (lowClock >= 6)
                    {
                        Stop("Prozessor drosselt", "warn", string.Format(Ui.De, "Der Takt ist von {0:N2} auf {1:N2} GHz eingebrochen. So schützt sich der Prozessor vor Überhitzung: Kühler und Wärmeleitpaste prüfen. Bei Notebooks ist das unter Dauerlast oft normal.", baseClock, c));
                        return;
                    }
                }
            }
        }
        // kamen schon Temperaturen und bleiben dann aus, läuft die Grafiklast ohne Hitzeschutz: lieber beenden
        if (Gpu && hadTemp && (DateTime.UtcNow - seen).TotalSeconds > 10)
        {
            Stop("Überwachung ausgefallen", "warn", "Die Temperatur der Grafikkarte kam nicht mehr an. Ohne Überwachung läuft der Test nicht weiter.");
            return;
        }
        var samples = PulsRigStress.Iterations;
        if (Elapsed >= Seconds)
        {
            var parts = new List<string>();
            if (Cpu) parts.Add(samples.ToString("N0", Ui.De) + " Rechenproben ohne Fehler");
            if (Cpu && maxClock > 0) parts.Add("Takt bis " + maxClock.ToString("N2", Ui.De) + " GHz");
            if (maxCpu > 0) parts.Add("Prozessor höchstens " + maxCpu.ToString("N0", Ui.De) + " °C");
            if (maxGpu > 0) parts.Add("Grafikkarte höchstens " + maxGpu.ToString("N0", Ui.De) + " °C");
            else if (Gpu) parts.Add("Grafiklast ohne Abbruch, Temperatur nicht messbar");
            Stop("Bestanden", "good", string.Join(" · ", parts) + ".");
            return;
        }
        var state = new List<string>();
        if (Cpu) state.Add(samples.ToString("N0", Ui.De) + " Rechenproben ohne Fehler");
        if (Gpu) state.Add(PulsRigStress.GpuActive ? "Grafiklast läuft" : "Grafiklast startet");
        // ohne NVIDIA-Karte gibt es keine Temperatur und damit keinen Abbruch bei Hitze - das muss dastehen
        if (Gpu && Elapsed > 5 && !hadTemp) state.Add("Temperatur nicht messbar: kein Abbruch bei Hitze");
        State = string.Join(" · ", state);
        Changed?.Invoke();
    }

    public static string Clock(double seconds) => ((int)seconds / 60) + ":" + ((int)seconds % 60).ToString("00");

    static void Stop(string title, string tone, string text)
    {
        if (timer == null) return;
        timer.Stop();
        timer = null;
        try { PulsRigStress.Stop(); PulsRigStress.KeepAwake(false); } catch (Exception) { }
        Live.Release();
        var what = What == "cpu" ? "Prozessor" : What == "gpu" ? "Grafikkarte" : "Prozessor und Grafikkarte";
        Last = new(title + " – " + what + ", " + Clock(Math.Min(Elapsed, Seconds)) + " Minuten", text, tone, DateTime.Now.ToString("dd.MM.yyyy HH:mm"), maxGpu, maxCpu, Temps.ToList());
        Save(Last);
        var (kind, seconds, minute) = (What, Math.Min(Elapsed, Seconds), tail.ToList());
        Task.Run(() => Verschleissdaten.AddStress(kind, seconds, minute));
        State = "";
        // ein paar Sekunden später, wenn das Grafikfenster zu ist: unbenutzten Arbeitsspeicher an Windows zurückgeben
        var later = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        later.Tick += (_, _) => { later.Stop(); if (!Running) try { PulsRigStress.ReleaseMemory(); } catch (Exception) { } };
        later.Start();
        Changed?.Invoke();
    }

    // beim Schließen des Programms: Last sofort beenden
    public static void Shutdown()
    {
        if (Running) Stop("Gestoppt", "warn", "PulsRig wurde während des Tests geschlossen.");
    }
}
