using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace UURemoteClone;

/// <summary>
/// 直调官方 streamer.dll（COM 风格接口工厂，Ghidra 逆向确认，见 docs/09-official-api.md）：
///   ordinal 1 = ExchangeControlledInterface（16 槽回调 → 23 槽 vtable）
///   ordinal 2 = ExchangeControllerInterface（18 槽回调 → 21 槽 vtable）
/// 返回静态函数指针表；各槽签名与官方内部实现一致（细节见反编译记录）。
/// 运行时需将官方 streamer.dll 置于 exe 同目录。
/// </summary>
public sealed class OfficialStreamer : IDisposable
{
    // ---- 回调委托（签名按官方日志/类型编码推断，槽位顺序确定）----
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void CbGeneric(IntPtr a, IntPtr b, IntPtr c, IntPtr d);

    // ControllerCallback：18 槽（macOS ObjC 编码顺序）
    [StructLayout(LayoutKind.Sequential)]
    public struct ControllerCallback
    {
        public IntPtr OnReceiveMediaTrack;
        public IntPtr OnRemoveMediaTrack;
        public IntPtr OnFrameChange;
        public IntPtr OnReceiveControlData;
        public IntPtr OnReceiveTextData;
        public IntPtr OnReceiveFileData;
        public IntPtr OnReceiveBinaryData;
        public IntPtr OnRoomState;
        public IntPtr OnSignalPush;
        public IntPtr OnQosStats;
        public IntPtr OnNatInfo;
        public IntPtr OnPeerConnectionState;
        public IntPtr OnConnectionStateCode;
        public IntPtr OnEventReport;
        public IntPtr OnDualNegotiateCapability;
        public IntPtr OnReceiveDataChannel;
        public IntPtr OnSignalData;
        public IntPtr Reserved;   // 第 18 槽
    }

    // ControlledCallback：16 槽
    [StructLayout(LayoutKind.Sequential)]
    public struct ControlledCallback
    {
        public IntPtr OnReceiveControlData;
        public IntPtr OnReceiveTextData;
        public IntPtr OnReceiveFileData;
        public IntPtr OnReceiveBinaryData;
        public IntPtr OnRoomState;
        public IntPtr OnSignalPush;
        public IntPtr OnQosStats;
        public IntPtr OnCursorChange;
        public IntPtr OnCaptureFailed;
        public IntPtr OnMuMuData;
        public IntPtr OnNewControl;
        public IntPtr OnPeerConnectionState;
        public IntPtr OnConnectionStateCode;
        public IntPtr OnEventReport;
        public IntPtr OnReceiveDataChannel;
        public IntPtr Reserved;
    }

    // ordinal 导出
    [DllImport("streamer.dll", EntryPoint = "#2", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr ExchangeControllerInterface(ref ControllerCallback cb);

    [DllImport("streamer.dll", EntryPoint = "#1", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr ExchangeControlledInterface(ref ControlledCallback cb);

    /// <summary>返回的接口对象：函数指针表（首槽 = 0，其后为方法）</summary>
    private IntPtr _vtable;
    private IntPtr[]? _slots;
    private readonly List<Delegate> _keepAlive = new();

    /// <summary>
    /// 获取控制端接口。callback 实现 18 个回调；返回 vtable 槽位委托数组（index = 槽位）。
    /// </summary>
    public IntPtr[] StartController(ClipboardSync.Sender sender)
    {
        var cb = new ControllerCallback();
        // OnReceiveControlData = 槽 3（顺序表第 4 个）→ 把收到的控制数据回给剪贴板/分发器
        // 官方回调参数风格（data*, len, ctx）需运行时确认；先透传指针长度
        var recvControl = new CbGeneric((a, b, c, d) =>
        {
            try
            {
                int len = (int)(c.ToInt64() & 0xffffff);
                if (len > 0 && len <= 1 << 20)
                {
                    var bytes = new byte[len];
                    Marshal.Copy(b, bytes, 0, len);
                    sender.SendControl(bytes);
                }
            }
            catch { }
        });
        _keepAlive.Add(recvControl);
        cb.OnReceiveControlData = Marshal.GetFunctionPointerForDelegate(recvControl);

        _vtable = ExchangeControllerInterface(ref cb);
        ReadSlots();
        return _slots ?? Array.Empty<IntPtr>();
    }

    /// <summary>获取被控端接口</summary>
    public IntPtr[] StartControlled()
    {
        var cb = new ControlledCallback();
        _vtable = ExchangeControlledInterface(ref cb);
        ReadSlots();
        return _slots ?? Array.Empty<IntPtr>();
    }

    private void ReadSlots()
    {
        _slots = new IntPtr[24];
        for (int i = 0; i < 24; i++)
        {
            IntPtr v = Marshal.ReadIntPtr(_vtable, i * IntPtr.Size);
            if (v == IntPtr.Zero) { Array.Resize(ref _slots, i); break; }
            _slots[i] = v;
        }
    }

    /// <summary>按槽位调用无参方法（示例：slot 表见 docs/09）</summary>
    public void Call(int slot)
    {
        if (_slots == null || slot >= _slots.Length) return;
        var fn = Marshal.GetDelegateForFunctionPointer<CbGeneric>(_slots[slot]);
        fn(IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
    }

    public void Dispose()
    {
        _keepAlive.Clear();  // 委托由 _keepAlive 持有防 GC；COM 对象为静态表无需释放
    }
}
