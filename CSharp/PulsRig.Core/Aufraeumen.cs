// PulsRig.Core - welche Dateien "Speicherplatz freigeben" löschen darf, abgelöst aus Get-CleanableFiles in
// Treiber-Werkzeuge.ps1. Das Löschen selbst bleibt in PowerShell.
//
// Tabu: Verknüpfungen auf andere Ordner (Junctions, symbolische Links) werden nie betreten, und Papierkorb,
// Treibersicherungen und Speicherabbilder sind nie dabei - auch nicht, wenn ein Zielordner sie einmal enthalten sollte.
using System;
using System.Collections.Generic;
using System.IO;

namespace PulsRig.Core
{
    public static class Aufraeumen
    {
        // Ordner und Dateien, die nie gelöscht werden, gleich wo sie liegen
        public static bool IsProtected(FileSystemInfo entry)
        {
            string name = entry.Name;
            if (entry is DirectoryInfo)
            {
                return name.Equals("$Recycle.Bin", StringComparison.OrdinalIgnoreCase)
                    || name.Equals("Minidump", StringComparison.OrdinalIgnoreCase)
                    || name.Equals("LiveKernelReports", StringComparison.OrdinalIgnoreCase)
                    || name.Equals("DriverStore", StringComparison.OrdinalIgnoreCase)
                    || name.StartsWith("Backup_", StringComparison.OrdinalIgnoreCase)
                    || name.StartsWith("Auto-Sicherung_", StringComparison.OrdinalIgnoreCase);
            }
            return name.Equals("MEMORY.DMP", StringComparison.OrdinalIgnoreCase);
        }

        // alle Dateien eines Ordners, die älter als days Tage sind; Ordner ohne Zugriff werden ausgelassen
        public static FileInfo[] CleanableFiles(string? path, int days)
        {
            var result = new List<FileInfo>();
            if (string.IsNullOrEmpty(path) || !Directory.Exists(path)) return result.ToArray();
            var root = new DirectoryInfo(path);
            if ((root.Attributes & FileAttributes.ReparsePoint) != 0 || IsProtected(root)) return result.ToArray();
            DateTime limit = DateTime.Now.AddDays(-days);
            var stack = new Stack<DirectoryInfo>();
            stack.Push(root);
            while (stack.Count > 0)
            {
                FileSystemInfo[] entries;
                try { entries = stack.Pop().GetFileSystemInfos(); }
                catch (Exception) { continue; }
                foreach (var entry in entries)
                {
                    if ((entry.Attributes & FileAttributes.ReparsePoint) != 0 || IsProtected(entry)) continue;
                    if (entry is DirectoryInfo folder) stack.Push(folder);
                    else if (entry.LastWriteTime < limit) result.Add((FileInfo)entry);
                }
            }
            return result.ToArray();
        }
    }
}
