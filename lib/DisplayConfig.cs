using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class DispConfig {
  [StructLayout(LayoutKind.Sequential)]
  public struct LUID { public uint LowPart; public int HighPart; }
  [StructLayout(LayoutKind.Sequential)]
  public struct RATIONAL { public uint Numerator; public uint Denominator; }
  [StructLayout(LayoutKind.Sequential)]
  public struct POINTL { public int x; public int y; }
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int left, top, right, bottom; }
  [StructLayout(LayoutKind.Sequential)]
  public struct REGION2D { public uint cx, cy; }

  [StructLayout(LayoutKind.Sequential)]
  public struct PATH_SOURCE_INFO { public LUID adapterId; public uint id; public uint modeInfoIdx; public uint statusFlags; }
  [StructLayout(LayoutKind.Sequential)]
  public struct PATH_TARGET_INFO {
    public LUID adapterId; public uint id; public uint modeInfoIdx;
    public uint outputTechnology; public uint rotation; public uint scaling;
    public RATIONAL refreshRate; public uint scanLineOrdering; public int targetAvailable; public uint statusFlags;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct PATH_INFO { public PATH_SOURCE_INFO sourceInfo; public PATH_TARGET_INFO targetInfo; public uint flags; }

  [StructLayout(LayoutKind.Sequential)]
  public struct VIDEO_SIGNAL_INFO {
    public ulong pixelRate; public RATIONAL hSyncFreq; public RATIONAL vSyncFreq;
    public REGION2D activeSize; public REGION2D totalSize; public uint videoStandard; public uint scanLineOrdering;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct TARGET_MODE { public VIDEO_SIGNAL_INFO targetVideoSignalInfo; }
  [StructLayout(LayoutKind.Sequential)]
  public struct SOURCE_MODE { public uint width, height, pixelFormat; public POINTL position; }
  [StructLayout(LayoutKind.Sequential)]
  public struct DESKTOP_IMAGE_INFO { public POINTL pathSourceSize; public RECT desktopImageRegion; public RECT desktopImageClip; }
  [StructLayout(LayoutKind.Explicit)]
  public struct MODE_UNION {
    [FieldOffset(0)] public TARGET_MODE targetMode;
    [FieldOffset(0)] public SOURCE_MODE sourceMode;
    [FieldOffset(0)] public DESKTOP_IMAGE_INFO desktopImageInfo;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct MODE_INFO { public uint infoType; public uint id; public LUID adapterId; public MODE_UNION modeInfo; }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct TARGET_DEVICE_NAME {
    public uint type; public uint size; public LUID adapterId; public uint id;
    public uint flags; public uint outputTechnology;
    public ushort edidManufactureId; public ushort edidProductCodeId; public uint connectorInstance;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
  }

  public const uint QDC_ALL_PATHS = 1;
  public const uint QDC_ONLY_ACTIVE_PATHS = 2;

  public const uint SDC_TOPOLOGY_EXTEND = 4;
  public const uint SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x20;
  public const uint SDC_APPLY = 0x80;
  public const uint SDC_SAVE_TO_DATABASE = 0x200;
  public const uint SDC_ALLOW_CHANGES = 0x400;

  public const uint PATH_MODE_IDX_INVALID = 0xFFFFFFFF;

  [DllImport("user32.dll")]
  public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPath, out uint numMode);
  [DllImport("user32.dll")]
  public static extern int QueryDisplayConfig(uint flags, ref uint numPath, [Out] PATH_INFO[] paths, ref uint numMode, [Out] MODE_INFO[] modes, IntPtr currentTopologyId);
  [DllImport("user32.dll")]
  public static extern int SetDisplayConfig(uint numPath, [In] PATH_INFO[] paths, uint numMode, [In] MODE_INFO[] modes, uint flags);
  [DllImport("user32.dll")]
  public static extern int DisplayConfigGetDeviceInfo(ref TARGET_DEVICE_NAME name);

  private static string TargetName(PATH_INFO p) {
    var tn = new TARGET_DEVICE_NAME();
    tn.type = 2;
    tn.size = (uint)Marshal.SizeOf(typeof(TARGET_DEVICE_NAME));
    tn.adapterId = p.targetInfo.adapterId;
    tn.id = p.targetInfo.id;
    if (DisplayConfigGetDeviceInfo(ref tn) == 0 && tn.monitorFriendlyDeviceName != null)
      return tn.monitorFriendlyDeviceName;
    return "";
  }

  private static HashSet<uint> ActiveTargetIds() {
    var set = new HashSet<uint>();
    uint np = 0, nm = 0;
    if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out np, out nm) != 0) return set;
    var paths = new PATH_INFO[np];
    var modes = new MODE_INFO[nm];
    if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref np, paths, ref nm, modes, IntPtr.Zero) != 0) return set;
    for (int i = 0; i < np; i++) set.Add(paths[i].targetInfo.id);
    return set;
  }

  // index|friendly name|tech=..|id=..|active|inactive   (only currently active targets)
  public static string ListTargets() {
    uint np = 0, nm = 0;
    int err = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out np, out nm);
    if (err != 0) return "ERR buf " + err;
    var paths = new PATH_INFO[np];
    var modes = new MODE_INFO[nm];
    err = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref np, paths, ref nm, modes, IntPtr.Zero);
    if (err != 0) return "ERR query " + err;
    var sb = new System.Text.StringBuilder();
    for (int i = 0; i < np; i++) {
      sb.AppendLine(i + "|" + TargetName(paths[i]) + "|tech=" + paths[i].targetInfo.outputTechnology + "|id=" + paths[i].targetInfo.id + "|active");
    }
    return sb.ToString();
  }

  // Every target known to the driver, active or not.
  public static string ListAllTargets() {
    var active = ActiveTargetIds();
    uint np = 0, nm = 0;
    int err = GetDisplayConfigBufferSizes(QDC_ALL_PATHS, out np, out nm);
    if (err != 0) return "ERR buf " + err;
    var paths = new PATH_INFO[np];
    var modes = new MODE_INFO[nm];
    err = QueryDisplayConfig(QDC_ALL_PATHS, ref np, paths, ref nm, modes, IntPtr.Zero);
    if (err != 0) return "ERR query " + err;
    var sb = new System.Text.StringBuilder();
    var seen = new HashSet<uint>();
    for (int i = 0; i < np; i++) {
      uint id = paths[i].targetInfo.id;
      if (!seen.Add(id)) continue;
      string friendly = TargetName(paths[i]);
      if (friendly.Length == 0) continue; // empty port / virtual target, no EDID
      sb.AppendLine(i + "|" + friendly + "|tech=" + paths[i].targetInfo.outputTechnology + "|id=" + id + "|" + (active.Contains(id) ? "active" : "inactive"));
    }
    return sb.ToString();
  }

  // Keep a single target active. The target must already have a valid mode path,
  // so call DisplaySwitch /extend (or ExtendAll) first when it is currently off.
  public static string OnlyTargetById(uint targetId) {
    uint np = 0, nm = 0;
    int err = GetDisplayConfigBufferSizes(QDC_ALL_PATHS, out np, out nm);
    if (err != 0) return "ERR buf " + err;
    var paths = new PATH_INFO[np];
    var modes = new MODE_INFO[nm];
    err = QueryDisplayConfig(QDC_ALL_PATHS, ref np, paths, ref nm, modes, IntPtr.Zero);
    if (err != 0) return "ERR query " + err;
    int found = -1;
    for (int i = 0; i < np; i++) {
      if (paths[i].targetInfo.id == targetId) { found = i; break; }
    }
    if (found < 0) return "ERR target id not found: " + targetId;
    var one = new PATH_INFO[1];
    one[0] = paths[found];
    one[0].sourceInfo.modeInfoIdx = PATH_MODE_IDX_INVALID;
    one[0].targetInfo.modeInfoIdx = PATH_MODE_IDX_INVALID;
    err = SetDisplayConfig(1, one, 0, null, SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_ALLOW_CHANGES | SDC_APPLY | SDC_SAVE_TO_DATABASE);
    return "set=" + err;
  }

  // Kept for reference: plain EXTEND topology. Returns 87 on drivers that
  // refuse a topology change without supplied paths.
  public static string ExtendAll() {
    int err = SetDisplayConfig(0, null, 0, null, SDC_TOPOLOGY_EXTEND | SDC_APPLY | SDC_SAVE_TO_DATABASE);
    return "extend=" + err;
  }
}
