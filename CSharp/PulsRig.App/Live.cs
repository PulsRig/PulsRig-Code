using System.Collections;
using System.Windows;
using PulsRig.Core;

namespace PulsRig.App;

// Eine Messung für alle Seiten (nvidia-smi und Leistungszähler über PulsRig.Core.Messung). Sie läuft nur, solange
// eine Seite sie braucht (Use/Release), und endet sofort, wenn keine mehr zuschaut.
static class Live
{
    public const int Keep = 60;
    static readonly object Gate = new();
    static int users;
    static CancellationTokenSource? stop;
    static Messung? messung;

    public static Hashtable Values { get; private set; } = new();
    public static List<double> GpuTemp { get; } = new();
    public static List<double> CpuLoad { get; } = new();
    public static List<double> CpuTemp { get; } = new();
    // warum es keine Temperatur des Prozessors gibt: nolib, nodriver, noadmin, none (leer = gibt es)
    public static string CpuTempStatus { get; private set; } = "";

    // kommt auf dem Oberflächen-Thread, einmal je Sekunde
    public static event Action? Updated;
    // zählt die Takte, damit Verläufe erkennen, ob ein neuer Wert dazukam
    public static long Tick { get; private set; }

    public static void Use()
    {
        lock (Gate)
        {
            if (users++ > 0) return;
            stop = new CancellationTokenSource();
            var token = stop.Token;
            Task.Run(() => Run(token), token);
        }
    }

    public static void Release()
    {
        lock (Gate)
        {
            if (users == 0 || --users > 0) return;
            stop?.Cancel();
            Interlocked.Exchange(ref messung, null)?.Dispose();
        }
    }

    // beim Schließen des Programms: nvidia-smi sofort beenden, egal wer die Messung noch hält
    public static void Shutdown()
    {
        lock (Gate)
        {
            users = 0;
            stop?.Cancel();
            Interlocked.Exchange(ref messung, null)?.Dispose();
            try { PulsRigCpuTemp.Close(); } catch (Exception) { }
        }
    }

    static void Run(CancellationToken token)
    {
        var cpu = Abfragen.Cpu();
        var m = new Messung(Abfragen.NvidiaSmi(), (cpu?.MaxGhz ?? 0) * 1000);
        var sensors = SensorFolder();
        if (sensors != null) try { PulsRigCpuTemp.Init(sensors); } catch (Exception) { sensors = null; }
        messung = m;
        if (token.IsCancellationRequested) { Interlocked.Exchange(ref messung, null)?.Dispose(); return; }
        while (!token.IsCancellationRequested)
        {
            var values = m.Next();
            if (token.IsCancellationRequested) break;
            // Temperatur des Prozessors (PulsRig-Temperatur.cs): LibreHardwareMonitor mit PawnIO oder Core Temp
            var status = "nolib";
            if (sensors != null)
                try
                {
                    var temp = PulsRigCpuTemp.Read();
                    if (!double.IsNaN(temp)) values["CpuTemp"] = temp;
                    if (!double.IsNaN(PulsRigCpuTemp.Power)) values["CpuPower"] = PulsRigCpuTemp.Power;
                    status = double.IsNaN(temp) ? PulsRigCpuTemp.Status : "";
                }
                catch (Exception) { }
            Application.Current?.Dispatcher.BeginInvoke(() =>
            {
                Values = values;
                Add(GpuTemp, values["GpuTemp"]);
                Add(CpuLoad, values["CpuLoad"]);
                Add(CpuTemp, values["CpuTemp"]);
                CpuTempStatus = status;
                Tick++;
                Updated?.Invoke();
            });
        }
        m.Dispose();
    }

    static void Add(List<double> list, object? value)
    {
        if (value is not double d) return;
        list.Add(d);
        if (list.Count > Keep) list.RemoveAt(0);
    }

    public static double? Get(string key) => Values[key] as double?;

    // Ordner Sensoren neben dem Programm, beim Entwickeln weiter oben im Werkstattordner
    static string? SensorFolder()
    {
        for (var dir = new System.IO.DirectoryInfo(AppContext.BaseDirectory); dir != null; dir = dir.Parent)
        {
            var folder = System.IO.Path.Combine(dir.FullName, "Sensoren");
            if (System.IO.File.Exists(System.IO.Path.Combine(folder, "LibreHardwareMonitorLib.dll"))) return folder;
        }
        return null;
    }
}
