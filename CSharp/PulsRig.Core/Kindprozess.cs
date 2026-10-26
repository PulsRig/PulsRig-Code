using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace PulsRig.Core
{
    // Hilfsprogramme, die PulsRig dauerhaft laufen lässt (nvidia-smi mit "-l 1"), sollen mit PulsRig enden – auch wenn
    // PulsRig abstürzt oder im Task-Manager beendet wird. Dafür kommen sie in ein Job-Objekt von Windows mit
    // "KILL_ON_JOB_CLOSE": Endet der Prozess, der den Job hält, schließt Windows den Job und beendet alles darin.
    public static class Kindprozess
    {
        const int ExtendedLimitInformation = 9;
        const uint KillOnJobClose = 0x2000;

        [StructLayout(LayoutKind.Sequential)]
        struct BasicLimit
        {
            public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
            public uint LimitFlags;
            public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
            public uint ActiveProcessLimit;
            public UIntPtr Affinity;
            public uint PriorityClass, SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct IoCounters { public ulong A, B, C, D, E, F; }

        [StructLayout(LayoutKind.Sequential)]
        struct ExtendedLimit
        {
            public BasicLimit Basic;
            public IoCounters Io;
            public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        static extern IntPtr CreateJobObject(IntPtr attributes, string? name);

        [DllImport("kernel32.dll")]
        static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref ExtendedLimit info, int length);

        [DllImport("kernel32.dll")]
        static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        static readonly object Gate = new object();
        static IntPtr job;

        // bleibt bis zum Ende von PulsRig offen; erst dann schließt Windows den Job
        static IntPtr Job()
        {
            lock (Gate)
            {
                if (job != IntPtr.Zero) return job;
                var created = CreateJobObject(IntPtr.Zero, null);
                if (created == IntPtr.Zero) return IntPtr.Zero;
                var info = new ExtendedLimit { Basic = new BasicLimit { LimitFlags = KillOnJobClose } };
                if (!SetInformationJobObject(created, ExtendedLimitInformation, ref info, Marshal.SizeOf(typeof(ExtendedLimit)))) return IntPtr.Zero;
                return job = created;
            }
        }

        // false, wenn Windows es ablehnt; dann endet das Programm nur über den normalen Weg (Dispose)
        public static bool Bind(Process? process)
        {
            if (process == null) return false;
            try
            {
                var j = Job();
                return j != IntPtr.Zero && AssignProcessToJobObject(j, process.Handle);
            }
            catch (Exception) { return false; }
        }
    }
}
