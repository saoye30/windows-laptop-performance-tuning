// NvDrs.cs - NVIDIA 驱动全局配置（与「NVIDIA 控制面板 → 管理 3D 设置 → 全局设置」相同）的最小读写封装
// 函数 ID、结构体布局取自 NVIDIA 官方 nvapi（github.com/NVIDIA/nvapi：nvapi_interface.h、nvapi.h、NvApiDriverSettings.h）
using System;
using System.Runtime.InteropServices;

public static class NvDrs
{
    [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr QueryInterface(uint id);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FnVoid();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FnOutPtr(out IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FnPtr(IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FnPtrOutPtr(IntPtr s, out IntPtr p);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FnGet(IntPtr s, IntPtr prof, uint id, IntPtr setting);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FnSet(IntPtr s, IntPtr prof, IntPtr setting);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FnRestore(IntPtr s, IntPtr prof, uint id);

    static T F<T>(uint id) where T : class
    {
        IntPtr p = QueryInterface(id);
        if (p == IntPtr.Zero) throw new Exception("nvapi 函数不可用: 0x" + id.ToString("X8"));
        return Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
    }

    // NVDRS_SETTING_V1，#pragma pack(4)
    const int SettingSize = 12320;          // 4 + 2048*2 + 5*4 + 4100 + 4100
    const int OffId = 4100, OffType = 4104, OffLocation = 4108, OffCurrent = 8220;
    const uint SettingVer = SettingSize | (1u << 16);
    public const int NotFound = -160;       // NVAPI_SETTING_NOT_FOUND

    static IntPtr session = IntPtr.Zero, profile = IntPtr.Zero;

    static void Check(int rc, string what) { if (rc != 0) throw new Exception(what + " 失败，NvAPI 返回 " + rc); }

    public static void Open()
    {
        Check(F<FnVoid>(0x0150E828)(), "NvAPI_Initialize");
        Check(F<FnOutPtr>(0x0694D52E)(out session), "DRS_CreateSession");
        Check(F<FnPtr>(0x375DBD6B)(session), "DRS_LoadSettings");
        Check(F<FnPtrOutPtr>(0xDA8466A0)(session, out profile), "DRS_GetBaseProfile");
    }

    // 返回 null 表示全局配置里没有这个值（使用驱动默认值）
    public static uint? Get(uint settingId)
    {
        IntPtr buf = Marshal.AllocHGlobal(SettingSize);
        try
        {
            for (int i = 0; i < SettingSize; i++) Marshal.WriteByte(buf, i, 0);
            Marshal.WriteInt32(buf, 0, (int)SettingVer);
            int rc = F<FnGet>(0x73BF8338)(session, profile, settingId, buf);
            if (rc == NotFound) return null;
            Check(rc, "DRS_GetSetting 0x" + settingId.ToString("X8"));
            return (uint)Marshal.ReadInt32(buf, OffCurrent);
        }
        finally { Marshal.FreeHGlobal(buf); }
    }

    public static void Set(uint settingId, uint value)
    {
        IntPtr buf = Marshal.AllocHGlobal(SettingSize);
        try
        {
            for (int i = 0; i < SettingSize; i++) Marshal.WriteByte(buf, i, 0);
            Marshal.WriteInt32(buf, 0, (int)SettingVer);
            Marshal.WriteInt32(buf, OffId, (int)settingId);
            Marshal.WriteInt32(buf, OffType, 0);       // NVDRS_DWORD_TYPE
            Marshal.WriteInt32(buf, OffCurrent, (int)value);
            Check(F<FnSet>(0x577DD202)(session, profile, buf), "DRS_SetSetting 0x" + settingId.ToString("X8"));
        }
        finally { Marshal.FreeHGlobal(buf); }
    }

    public static void RestoreDefault(uint settingId)
    {
        int rc = F<FnRestore>(0x53F0381E)(session, profile, settingId);
        if (rc != 0 && rc != NotFound) Check(rc, "DRS_RestoreProfileDefaultSetting");
    }

    public static void Save() { Check(F<FnPtr>(0xFCBC7E14)(session), "DRS_SaveSettings"); }

    public static void Close()
    {
        if (session != IntPtr.Zero) { F<FnPtr>(0xDAD9CFF8)(session); session = IntPtr.Zero; }
    }
}
