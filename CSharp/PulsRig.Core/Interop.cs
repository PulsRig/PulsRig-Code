// PulsRig.Core - Lautstärke und Bildschirmmodi über die Windows-API, abgelöst aus Initialize-Interop in
// Treiber-Werkzeuge.ps1 (dort wurde der Code bei jedem Start per Add-Type neu übersetzt). Übernommener Code,
// darum ohne Null-Prüfungen des Compilers.
#nullable disable
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace PulsRig.Core
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object instance);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioEndpointVolume
    {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int GetChannelCount(out uint count);
        [PreserveSig] int SetMasterVolumeLevel(float levelDb, ref Guid context);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level, ref Guid context);
        [PreserveSig] int GetMasterVolumeLevel(out float levelDb);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(uint channel, float levelDb, ref Guid context);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid context);
        [PreserveSig] int GetChannelVolumeLevel(uint channel, out float levelDb);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    // Standard-Wiedergabegerät: Stummschaltung und Lautstärke (0..1)
    public static class Audio
    {
        private static IAudioEndpointVolume Endpoint()
        {
            IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice device;
            Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out device));
            Guid iid = typeof(IAudioEndpointVolume).GUID;
            object instance;
            Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out instance));
            return (IAudioEndpointVolume)instance;
        }

        public static bool GetMute()
        {
            bool mute;
            Marshal.ThrowExceptionForHR(Endpoint().GetMute(out mute));
            return mute;
        }

        public static void SetMute(bool mute)
        {
            Guid context = Guid.Empty;
            Marshal.ThrowExceptionForHR(Endpoint().SetMute(mute, ref context));
        }

        public static float GetVolume()
        {
            float level;
            Marshal.ThrowExceptionForHR(Endpoint().GetMasterVolumeLevelScalar(out level));
            return level;
        }

        public static void SetVolume(float level)
        {
            Guid context = Guid.Empty;
            Marshal.ThrowExceptionForHR(Endpoint().SetMasterVolumeLevelScalar(level, ref context));
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct DisplayDevice
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct DevMode
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    public class DisplayMode
    {
        public int Width;
        public int Height;
        public int Frequency;
    }

    public class DisplayInfo
    {
        public string Device;
        public string Adapter;
        public string MonitorId;
        public bool Primary;
        public DisplayMode Current;
        public List<DisplayMode> Modes = new List<DisplayMode>();
    }

    public static class Display
    {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern bool EnumDisplayDevices(string device, uint index, ref DisplayDevice info, uint flags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern bool EnumDisplaySettings(string device, int mode, ref DevMode devMode);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int ChangeDisplaySettingsEx(string device, ref DevMode devMode, IntPtr hwnd, uint flags, IntPtr param);

        private static DevMode NewMode()
        {
            DevMode mode = new DevMode();
            mode.dmSize = (short)Marshal.SizeOf(typeof(DevMode));
            return mode;
        }

        private static DisplayMode Convert(DevMode mode)
        {
            DisplayMode result = new DisplayMode();
            result.Width = mode.dmPelsWidth;
            result.Height = mode.dmPelsHeight;
            result.Frequency = mode.dmDisplayFrequency;
            return result;
        }

        // Alle Bildschirme, die zum Desktop gehören, mit aktuellem Modus und Modusliste des Treibers
        public static List<DisplayInfo> GetDisplays()
        {
            List<DisplayInfo> result = new List<DisplayInfo>();
            for (uint i = 0; ; i++)
            {
                DisplayDevice adapter = new DisplayDevice();
                adapter.cb = Marshal.SizeOf(typeof(DisplayDevice));
                if (!EnumDisplayDevices(null, i, ref adapter, 0)) break;
                if ((adapter.StateFlags & 1) == 0) continue;

                DisplayInfo info = new DisplayInfo();
                info.Device = adapter.DeviceName;
                info.Adapter = adapter.DeviceString;
                info.Primary = (adapter.StateFlags & 4) != 0;

                DisplayDevice monitor = new DisplayDevice();
                monitor.cb = Marshal.SizeOf(typeof(DisplayDevice));
                if (EnumDisplayDevices(adapter.DeviceName, 0, ref monitor, 0)) info.MonitorId = monitor.DeviceID;

                DevMode current = NewMode();
                if (EnumDisplaySettings(adapter.DeviceName, -1, ref current)) info.Current = Convert(current);

                for (int n = 0; ; n++)
                {
                    DevMode mode = NewMode();
                    if (!EnumDisplaySettings(adapter.DeviceName, n, ref mode)) break;
                    if (mode.dmBitsPerPel == 32) info.Modes.Add(Convert(mode));
                }
                result.Add(info);
            }
            return result;
        }

        // Stellt einen Modus aus der Liste des Treibers ein. testOnly prüft nur, ob er angenommen würde.
        // Rückgabe: 0 = in Ordnung, -100 = Modus steht nicht in der Liste, sonst Fehlercode von Windows
        public static int SetMode(string device, int width, int height, int frequency, bool testOnly)
        {
            for (int n = 0; ; n++)
            {
                DevMode mode = NewMode();
                if (!EnumDisplaySettings(device, n, ref mode)) return -100;
                if (mode.dmBitsPerPel == 32 && mode.dmPelsWidth == width && mode.dmPelsHeight == height && mode.dmDisplayFrequency == frequency)
                {
                    return ChangeDisplaySettingsEx(device, ref mode, IntPtr.Zero, testOnly ? 2u : 1u, IntPtr.Zero);
                }
            }
        }
    }
}
