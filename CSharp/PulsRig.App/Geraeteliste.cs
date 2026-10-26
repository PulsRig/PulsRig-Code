using System.Runtime.InteropServices;
using System.Text;

namespace PulsRig.App;

// Alle Geräteeinträge mit "angeschlossen ja/nein" wie Get-PnpDevice (Present). WMI kennt nur angeschlossene Geräte,
// deshalb über die SetupAPI: ein Eintrag ohne Knoten im Gerätebaum (CM_Get_DevNode_Status schlägt fehl) ist abgesteckt.
static class Geraeteliste
{
    public sealed record Eintrag(string InstanceId, string Class, string Name, bool Present);

    [StructLayout(LayoutKind.Sequential)]
    struct SpDevInfoData { public int Size; public Guid ClassGuid; public int DevInst; public IntPtr Reserved; }

    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr SetupDiGetClassDevs(IntPtr classGuid, string? enumerator, IntPtr parent, int flags);
    [DllImport("setupapi.dll", SetLastError = true)]
    static extern bool SetupDiEnumDeviceInfo(IntPtr set, int index, ref SpDevInfoData data);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool SetupDiGetDeviceInstanceId(IntPtr set, ref SpDevInfoData data, StringBuilder id, int size, out int required);
    [DllImport("setupapi.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool SetupDiGetDeviceRegistryProperty(IntPtr set, ref SpDevInfoData data, int property, out int type, byte[]? buffer, int size, out int required);
    [DllImport("setupapi.dll")]
    static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
    [DllImport("cfgmgr32.dll")]
    static extern int CM_Get_DevNode_Status(out int status, out int problem, int devInst, int flags);

    const int DigcfAllClasses = 0x4, SpdrpDeviceDesc = 0, SpdrpClass = 7, SpdrpFriendlyName = 12;

    static string Property(IntPtr set, ref SpDevInfoData data, int property)
    {
        var buffer = new byte[1024];
        return SetupDiGetDeviceRegistryProperty(set, ref data, property, out _, buffer, buffer.Length, out var used) && used > 2
            ? Encoding.Unicode.GetString(buffer, 0, used).TrimEnd('\0') : "";
    }

    public static List<Eintrag> All()
    {
        var list = new List<Eintrag>();
        var set = SetupDiGetClassDevs(IntPtr.Zero, null, IntPtr.Zero, DigcfAllClasses);
        if (set == new IntPtr(-1)) return list;
        try
        {
            var data = new SpDevInfoData { Size = Marshal.SizeOf<SpDevInfoData>() };
            for (var i = 0; SetupDiEnumDeviceInfo(set, i, ref data); i++)
            {
                var id = new StringBuilder(512);
                if (!SetupDiGetDeviceInstanceId(set, ref data, id, id.Capacity, out _)) continue;
                var present = CM_Get_DevNode_Status(out _, out _, data.DevInst, 0) == 0;
                var name = Property(set, ref data, SpdrpFriendlyName);
                if (name.Length == 0) name = Property(set, ref data, SpdrpDeviceDesc);
                list.Add(new(id.ToString(), Property(set, ref data, SpdrpClass), name, present));
            }
        }
        finally { SetupDiDestroyDeviceInfoList(set); }
        return list;
    }
}
