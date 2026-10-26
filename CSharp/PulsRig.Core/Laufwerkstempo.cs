// PulsRig.Core - Tempo eines Laufwerks, abgelöst aus PulsRig-Hardware.ps1 (vorher PulsRigDiskTest per Add-Type):
// eine Testdatei von bis zu 1 GB, am Windows-Zwischenspeicher vorbei geschrieben und gelesen, beim Schließen gelöscht.
// Sonst käme beim Lesen nur das Tempo des Arbeitsspeichers heraus.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace PulsRig.Core
{
    public static class Laufwerkstempo
    {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool WriteFile(SafeFileHandle handle, IntPtr buffer, uint count, out uint done, IntPtr overlapped);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool ReadFile(SafeFileHandle handle, IntPtr buffer, uint count, out uint done, IntPtr overlapped);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetFilePointerEx(SafeFileHandle handle, long distance, out long position, uint method);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr VirtualAlloc(IntPtr address, UIntPtr size, uint type, uint protect);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool VirtualFree(IntPtr address, UIntPtr size, uint type);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool DeviceIoControl(SafeFileHandle handle, uint code, ref ushort input, uint inputSize, IntPtr output, uint outputSize, out uint returned, IntPtr overlapped);

        // Ergebnis: Schreiben am Stück, Lesen am Stück, kleine zufällige Lesezugriffe (alles MB/s), Größe der Testdatei in MB.
        // Fehlercode 5 (Zugriff verweigert) kommt als negative Zahl im ersten Feld zurück, damit der Aufrufer einen anderen Ordner probiert.
        public static double[] Run(string path, long maxBytes, double seconds)
        {
            const int block = 1 << 20;
            IntPtr buffer = VirtualAlloc(IntPtr.Zero, (UIntPtr)(uint)block, 0x3000, 0x04);
            if (buffer == IntPtr.Zero) throw new IOException("Kein Speicher für die Messung");
            try
            {
                // Zufallsdaten: manche Laufwerke stauchen gleichförmige Daten und wirken dann schneller, als sie sind
                byte[] noise = new byte[block];
                new Random(12345).NextBytes(noise);
                Marshal.Copy(noise, 0, buffer, block);
                // Lesen und Schreiben, immer neu anlegen; ohne Zwischenspeicher, direkt durchschreiben, beim Schließen löschen
                using (SafeFileHandle handle = CreateFile(path, 0xC0000000, 0, IntPtr.Zero, 2, 0xA4000000u, IntPtr.Zero))
                {
                    if (handle.IsInvalid)
                    {
                        int code = Marshal.GetLastWin32Error();
                        if (code == 5) return new double[] { -5, 0, 0, 0 };
                        throw new IOException("Die Testdatei lässt sich nicht anlegen (Windows-Fehler " + code + ")");
                    }
                    uint done;
                    long position;
                    // liegt die Datei in einem komprimierten Ordner, erbt sie die Komprimierung: dann schreibt Windows langsam und
                    // liest immer über den Zwischenspeicher - gemessen würde der Prozessor statt des Laufwerks. Also abschalten.
                    ushort plain = 0;
                    DeviceIoControl(handle, 0x9C040, ref plain, 2, IntPtr.Zero, 0, out done, IntPtr.Zero);
                    long written = 0;
                    Stopwatch watch = Stopwatch.StartNew();
                    while (written < maxBytes && watch.Elapsed.TotalSeconds < seconds)
                    {
                        if (!WriteFile(handle, buffer, block, out done, IntPtr.Zero)) throw new IOException("Schreiben fehlgeschlagen (Windows-Fehler " + Marshal.GetLastWin32Error() + ")");
                        written += done;
                    }
                    double write = written / 1048576.0 / watch.Elapsed.TotalSeconds;

                    SetFilePointerEx(handle, 0, out position, 0);
                    long read = 0;
                    watch.Restart();
                    while (read < written && watch.Elapsed.TotalSeconds < seconds)
                    {
                        if (!ReadFile(handle, buffer, block, out done, IntPtr.Zero)) throw new IOException("Lesen fehlgeschlagen (Windows-Fehler " + Marshal.GetLastWin32Error() + ")");
                        if (done == 0) break;
                        read += done;
                    }
                    double readSpeed = read / 1048576.0 / watch.Elapsed.TotalSeconds;

                    // kleine Zugriffe: 4 KB an zufälligen Stellen, einer nach dem anderen
                    Random random = new Random(7);
                    long blocks = written / 4096;
                    long count = 0;
                    double smallSeconds = Math.Min(seconds, 3.0);
                    watch.Restart();
                    while (blocks > 0 && watch.Elapsed.TotalSeconds < smallSeconds)
                    {
                        SetFilePointerEx(handle, (long)(random.NextDouble() * blocks) * 4096, out position, 0);
                        if (!ReadFile(handle, buffer, 4096, out done, IntPtr.Zero)) break;
                        count++;
                    }
                    double small = count * 4096 / 1048576.0 / watch.Elapsed.TotalSeconds;
                    return new double[] { write, readSpeed, small, written / 1048576.0 };
                }
            }
            finally { VirtualFree(buffer, UIntPtr.Zero, 0x8000); }
        }

        // weit unter dem, was selbst eine alte Festplatte schafft: das deutet auf eine Störung, nicht auf ein langsames Modell
        public static bool Slow(double read, double write) => read < 25 || write < 15;

        // Balkenlänge: die Wurzel staucht die Spanne, sonst wäre neben einer NVMe-SSD jede Festplatte unsichtbar
        public static double Bar(double value, double top) => value <= 0 ? 0 : Math.Min(1.0, Math.Sqrt(value / top));
    }
}
