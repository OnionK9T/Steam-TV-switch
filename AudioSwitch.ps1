param(
    [string]$Set,
    [switch]$List
)

# AudioSwitch.ps1 — enumerate / switch the Windows default audio output device.
#
#   powershell -File AudioSwitch.ps1 -List
#   powershell -File AudioSwitch.ps1 -Set "TV"
#
# Uses only built-in COM interfaces (MMDeviceEnumerator + the undocumented
# IPolicyConfig), so no third-party executable is required.

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class AudioSwitch
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        int GetDevice(string id, out IMMDevice device);
        int RegisterEndpointNotificationCallback(IntPtr client);
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceCollection
    {
        int GetCount(out int count);
        int Item(int index, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice
    {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, out IntPtr interfacePointer);
        int OpenPropertyStore(int access, out IPropertyStore properties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out int state);
    }

    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        int GetCount(out int count);
        int GetAt(int index, out PROPERTYKEY key);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
        int Commit();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PROPERTYKEY
    {
        public Guid fmtid;
        public int pid;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct PROPVARIANT
    {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr pointerValue;
    }

    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(ref PROPVARIANT pvar);

    [ComImport, Guid("870AF99C-171D-4F9E-AF0D-E63DF40C2BC9")]
    private class CPolicyConfigClient { }

    [ComImport, Guid("F8679F50-850A-41CF-9C72-430F290290C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPolicyConfig
    {
        int GetMixFormat(string pszDeviceName, IntPtr ppFormat);
        int GetDeviceFormat(string pszDeviceName, bool bDefault, IntPtr ppFormat);
        int ResetDeviceFormat(string pszDeviceName);
        int SetDeviceFormat(string pszDeviceName, IntPtr pEndpointFormat, IntPtr MixFormat);
        int GetProcessingPeriod(string pszDeviceName, bool bDefault, IntPtr pmftDefaultPeriod, IntPtr pmftMinimumPeriod);
        int SetProcessingPeriod(string pszDeviceName, IntPtr pmftPeriod);
        int GetShareMode(string pszDeviceName, IntPtr pMode);
        int SetShareMode(string pszDeviceName, IntPtr mode);
        int GetPropertyValue(string pszDeviceName, IntPtr key, IntPtr pv);
        int SetPropertyValue(string pszDeviceName, IntPtr key, IntPtr pv);
        int SetDefaultEndpoint(string pszDeviceName, int role);
        int SetEndpointVisibility(string pszDeviceName, bool bVisible);
    }

    private static string FriendlyName(IMMDevice dev)
    {
        IPropertyStore props;
        dev.OpenPropertyStore(0, out props);

        var pk = new PROPERTYKEY
        {
            fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"),
            pid = 14
        };
        PROPVARIANT pv;
        props.GetValue(ref pk, out pv);

        string name = pv.pointerValue != IntPtr.Zero
            ? Marshal.PtrToStringUni(pv.pointerValue)
            : "";
        if (pv.pointerValue != IntPtr.Zero) PropVariantClear(ref pv);
        return name;
    }

    public static string[] List()
    {
        var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
        IMMDeviceCollection coll;
        int hr = en.EnumAudioEndpoints(0, 1, out coll);
        Marshal.ThrowExceptionForHR(hr);

        int count;
        hr = coll.GetCount(out count);
        Marshal.ThrowExceptionForHR(hr);

        var list = new System.Collections.Generic.List<string>();
        for (int i = 0; i < count; i++)
        {
            IMMDevice dev;
            coll.Item(i, out dev);
            string id;
            dev.GetId(out id);
            list.Add(FriendlyName(dev) + "|" + id);
        }
        return list.ToArray();
    }

    public static string Default()
    {
        var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
        IMMDevice dev;
        int hr = en.GetDefaultAudioEndpoint(0, 0, out dev);
        Marshal.ThrowExceptionForHR(hr);
        string id;
        dev.GetId(out id);
        return FriendlyName(dev) + "|" + id;
    }

    public static int SetDefault(string deviceId, int role)
    {
        var pc = (IPolicyConfig)new CPolicyConfigClient();
        return pc.SetDefaultEndpoint(deviceId, role);
    }
}
"@

if ($List -or -not $Set) {
    try {
        $def = [AudioSwitch]::Default()
        Write-Host ("Current default: " + $def.Split('|')[0]) -ForegroundColor Yellow
    } catch {
        Write-Host ("Could not read default device: " + $_.Exception.Message) -ForegroundColor DarkYellow
    }
    $items = [AudioSwitch]::List()
    $i = 0
    foreach ($item in $items) {
        $i++
        $parts = $item.Split('|')
        "{0}. {1}" -f $i, $parts[0]
    }
    return
}

$match = [AudioSwitch]::List() | Where-Object { $_ -like "*$Set*" } | Select-Object -First 1
if (-not $match) {
    Write-Host "No audio device matched: $Set" -ForegroundColor Red
    exit 1
}

$id = $match.Split('|')[-1]
foreach ($role in 0, 1, 2) {
    [void][AudioSwitch]::SetDefault($id, $role)
}
Write-Host "Default output set to: $($match.Split('|')[0])" -ForegroundColor Green
