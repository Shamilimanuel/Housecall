<#
    Windows' audio system (Core Audio), reached from PowerShell through a
    little C#: the sound outputs and microphones that are in use, which one
    is the default, mute and volume, and switching the default.

    Compiled on first use only (about a second), so areas other than B never
    pay for it. SetDefault uses IPolicyConfig: undocumented, but it is what
    the sound settings themselves use, and it has been stable since Windows 7.

    Plain ASCII like everything else; the names come from Windows at run time.
    The C# sits in a double-quoted here-string on purpose: a line starting
    with '@ would end the $HcSource here-string that carries all of
    Housecall. So the C# must never contain a dollar sign or a backtick.
#>

$script:HcAudioSource = @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Housecall
{
    [StructLayout(LayoutKind.Sequential)]
    public struct PropertyKey { public Guid Fmtid; public int Pid; }

    [StructLayout(LayoutKind.Explicit)]
    public struct PropVariant
    {
        [FieldOffset(0)] public short Vt;
        [FieldOffset(8)] public IntPtr Pointer;
    }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection
    {
        int GetCount(out int count);
        int Item(int index, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        int OpenPropertyStore(int access, out IPropertyStore store);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out int state);
    }

    [ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        int GetCount(out int count);
        int GetAt(int index, out PropertyKey key);
        int GetValue(ref PropertyKey key, out PropVariant value);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume
    {
        int RegisterControlChangeNotify(IntPtr notify);
        int UnregisterControlChangeNotify(IntPtr notify);
        int GetChannelCount(out int count);
        int SetMasterVolumeLevel(float level, ref Guid context);
        int SetMasterVolumeLevelScalar(float level, ref Guid context);
        int GetMasterVolumeLevel(out float level);
        int GetMasterVolumeLevelScalar(out float level);
        int SetChannelVolumeLevel(int channel, float level, ref Guid context);
        int SetChannelVolumeLevelScalar(int channel, float level, ref Guid context);
        int GetChannelVolumeLevel(int channel, out float level);
        int GetChannelVolumeLevelScalar(int channel, out float level);
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);
        int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    [ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPolicyConfig
    {
        int GetMixFormat(string id, IntPtr format);
        int GetDeviceFormat(string id, int def, IntPtr format);
        int ResetDeviceFormat(string id);
        int SetDeviceFormat(string id, IntPtr endpointFormat, IntPtr mixFormat);
        int GetProcessingPeriod(string id, int def, IntPtr defaultPeriod, IntPtr minimumPeriod);
        int SetProcessingPeriod(string id, IntPtr period);
        int GetShareMode(string id, IntPtr mode);
        int SetShareMode(string id, IntPtr mode);
        int GetPropertyValue(string id, int store, IntPtr key, IntPtr value);
        int SetPropertyValue(string id, int store, IntPtr key, IntPtr value);
        int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role);
        int SetEndpointVisibility(string id, int visible);
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorClass { }
    [ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class PolicyConfigClass { }

    public class AudioDevice
    {
        public string Id;
        public string Name;
        public bool IsDefault;
        public bool Muted;
        public int Volume;
    }

    public static class Audio
    {
        static readonly Guid VolumeIid = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
        static readonly PropertyKey FriendlyName = new PropertyKey { Fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), Pid = 14 };

        static IMMDeviceEnumerator Enumerator() { return (IMMDeviceEnumerator)new MMDeviceEnumeratorClass(); }

        static IAudioEndpointVolume VolumeOf(IMMDevice device)
        {
            Guid iid = VolumeIid;
            object o;
            Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out o));
            return (IAudioEndpointVolume)o;
        }

        static IMMDevice Find(string id)
        {
            foreach (int flow in new[] { 0, 1 })
            {
                IMMDeviceCollection all;
                Marshal.ThrowExceptionForHR(Enumerator().EnumAudioEndpoints(flow, 1, out all));
                int count; all.GetCount(out count);
                for (int i = 0; i < count; i++)
                {
                    IMMDevice d; all.Item(i, out d);
                    string did; d.GetId(out did);
                    if (did == id) return d;
                }
            }
            throw new ArgumentException("No active audio device with id " + id);
        }

        // flow 0 = outputs (speakers), 1 = inputs (microphones). Active devices only.
        public static AudioDevice[] List(int flow)
        {
            var result = new List<AudioDevice>();
            IMMDeviceEnumerator e = Enumerator();
            string defaultId = null;
            IMMDevice def;
            if (e.GetDefaultAudioEndpoint(flow, 0, out def) == 0 && def != null) def.GetId(out defaultId);

            IMMDeviceCollection all;
            Marshal.ThrowExceptionForHR(e.EnumAudioEndpoints(flow, 1, out all));
            int count; all.GetCount(out count);
            for (int i = 0; i < count; i++)
            {
                IMMDevice d; all.Item(i, out d);
                var a = new AudioDevice();
                d.GetId(out a.Id);
                a.IsDefault = (a.Id == defaultId);
                IPropertyStore store;
                if (d.OpenPropertyStore(0, out store) == 0)
                {
                    PropertyKey key = FriendlyName;
                    PropVariant v;
                    if (store.GetValue(ref key, out v) == 0 && v.Vt == 31) a.Name = Marshal.PtrToStringUni(v.Pointer);
                }
                try
                {
                    IAudioEndpointVolume vol = VolumeOf(d);
                    float level; vol.GetMasterVolumeLevelScalar(out level);
                    bool mute; vol.GetMute(out mute);
                    a.Volume = (int)Math.Round(level * 100);
                    a.Muted = mute;
                }
                catch (Exception) { a.Volume = -1; }
                result.Add(a);
            }
            return result.ToArray();
        }

        // All three roles (console, multimedia, communications), like the sound settings do.
        public static void SetDefault(string id)
        {
            var policy = (IPolicyConfig)new PolicyConfigClass();
            for (int role = 0; role < 3; role++) Marshal.ThrowExceptionForHR(policy.SetDefaultEndpoint(id, role));
        }

        public static void SetMute(string id, bool mute)
        {
            Guid context = Guid.Empty;
            Marshal.ThrowExceptionForHR(VolumeOf(Find(id)).SetMute(mute, ref context));
        }

        public static void SetVolume(string id, int percent)
        {
            Guid context = Guid.Empty;
            Marshal.ThrowExceptionForHR(VolumeOf(Find(id)).SetMasterVolumeLevelScalar(Math.Max(0, Math.Min(100, percent)) / 100f, ref context));
        }
    }
}
"@

function Initialize-HcAudio {
    if (-not ('Housecall.Audio' -as [type])) {
        Add-Type -TypeDefinition $script:HcAudioSource -Language CSharp -ErrorAction Stop
    }
}

# Active outputs (flow 0) or microphones (flow 1), or $null when Windows'
# audio system cannot be reached at all (for example the service is down).
function Get-HcAudioDevices {
    param([int]$Flow)
    try {
        Initialize-HcAudio
        return @([Housecall.Audio]::List($Flow) | ForEach-Object {
            [pscustomobject]@{ Id = $_.Id; Name = $_.Name; IsDefault = $_.IsDefault; Muted = $_.Muted; Volume = $_.Volume }
        })
    } catch {
        return $null
    }
}
