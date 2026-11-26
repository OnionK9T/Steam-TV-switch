using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class DispInfo {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DISPLAY_DEVICE {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
    public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
  }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int dmFields;
    public int dmPositionX, dmPositionY;
    public int dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
    public short dmLogPixels;
    public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }

  public const uint CDS_UPDATEREGISTRY = 0x00000001;
  public const uint CDS_NORESET = 0x10000000;
  public const int DM_POSITION = 0x20;

  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE d, uint flags);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)]
  public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="ChangeDisplaySettingsExW")]
  public static extern int ChangeDisplaySettingsExD(string dev, ref DEVMODE dm, IntPtr hwnd, uint flags, IntPtr param);
  [DllImport("user32.dll", CharSet=CharSet.Unicode, EntryPoint="ChangeDisplaySettingsExW")]
  public static extern int ChangeDisplaySettingsExN(string dev, IntPtr dm, IntPtr hwnd, uint flags, IntPtr param);

  public static string[] GetDevices() {
    var list = new List<string>();
    for (uint i = 0; i < 16; i++) {
      var d = new DISPLAY_DEVICE();
      d.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
      if (!EnumDisplayDevices(null, i, ref d, 0)) break;
      var mon = new DISPLAY_DEVICE();
      mon.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
      string monName = "";
      string monId = "";
      if (EnumDisplayDevices(d.DeviceName, 0, ref mon, 0)) { monName = mon.DeviceString; monId = mon.DeviceID; }
      string mode = GetMode(d.DeviceName);
      list.Add(d.DeviceName + "|" + monName + "|" + monId + "|" + d.StateFlags + "|" + mode);
    }
    return list.ToArray();
  }

  public static string GetMode(string dev) {
    DEVMODE dm;
    if (!GetDevMode(dev, out dm)) return "";
    return dm.dmPositionX + "," + dm.dmPositionY + "|" +
           dm.dmPelsWidth + "x" + dm.dmPelsHeight + "|" +
           dm.dmDisplayFrequency;
  }

  static bool GetDevMode(string dev, out DEVMODE dm) {
    dm = new DEVMODE();
    dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    return EnumDisplaySettings(dev, -1, ref dm);
  }

  // Swap the logical position of two outputs. Note: this reorders the desktop,
  // it does not disable an output.
  public static string SetPositions(string dev1, int x1, string dev2, int x2) {
    DEVMODE d1, d2;
    if (!GetDevMode(dev1, out d1)) return "ERR: read " + dev1;
    if (!GetDevMode(dev2, out d2)) return "ERR: read " + dev2;
    d1.dmPositionX = x1; d1.dmPositionY = 0; d1.dmFields |= DM_POSITION;
    d2.dmPositionX = x2; d2.dmPositionY = 0; d2.dmFields |= DM_POSITION;
    int r1 = ChangeDisplaySettingsExD(dev1, ref d1, IntPtr.Zero, CDS_UPDATEREGISTRY | CDS_NORESET, IntPtr.Zero);
    int r2 = ChangeDisplaySettingsExD(dev2, ref d2, IntPtr.Zero, CDS_UPDATEREGISTRY | CDS_NORESET, IntPtr.Zero);
    int r3 = ChangeDisplaySettingsExN(null, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
    return "r=" + r1 + "," + r2 + "," + r3;
  }

  // Historical attempt: ChangeDisplaySettingsEx with a NULL DEVMODE does NOT
  // disable an output, it only resets it to its default position. Kept to show
  // why SetDisplayConfig is the right tool.
  public static string OnlyMonitor(string devOn, string devOff) {
    DEVMODE dm;
    if (!GetDevMode(devOn, out dm)) return "ERR: read " + devOn;
    dm.dmPositionX = 0; dm.dmPositionY = 0; dm.dmFields |= DM_POSITION;
    int r1 = ChangeDisplaySettingsExD(devOn, ref dm, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
    int r2 = ChangeDisplaySettingsExN(devOff, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
    return "r=" + r1 + "," + r2;
  }
}
