using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using UURemoteClone;

// Runner test instrumentation only. The production room binding has no private
// helper calls or certificate-store writes. Keep this separate from the app.
internal static class RoomChecks
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr ParseCertificate(IntPtr output, ref IntPtr cursor, int size);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int AddCertificate(IntPtr store, IntPtr certificate);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void ReleaseCertificate(IntPtr certificate);

    internal static void Run(string[] input)
    {
        if (!OperatingSystem.IsWindows() || Environment.GetEnvironmentVariable("GITHUB_ACTIONS") != "true")
            throw new InvalidOperationException("Compiled room checks require Windows GitHub Actions.");
        var role = input[1] switch
        {
            "controller" => OfficialStreamer.Role.Controller,
            "controlled" => OfficialStreamer.Role.Controlled,
            _ => throw new ArgumentException("Unknown native role")
        };
        string runtime = Path.GetFullPath(input[2]), workspace = Path.GetFullPath(input[3]);
        string output = Path.GetFullPath(input[4]);
        using var fixture = JsonDocument.Parse(File.ReadAllText(input[5]));
        var server = new Uri(fixture.RootElement.GetProperty("server_url").GetString()!);
        if (server.Scheme != "wss" || server.Host != "127.0.0.1")
            throw new ArgumentException("Native room fixture must be TLS IPv4 loopback.");
        string rejection = fixture.RootElement.GetProperty("baseline_rejection_path").GetString()!;
        string certificatePem = fixture.RootElement.GetProperty("certificate_pem").GetString()!;
        Directory.CreateDirectory(workspace);
        Directory.CreateDirectory(Path.GetDirectoryName(output)!);
        string config = Path.Combine(workspace, "config-配置.json"), logs = Path.Combine(workspace, "logs");
        string dll = Path.Combine(runtime, "streamer.dll");
        File.Copy(Path.Combine(runtime, "streamer-config.json"), config, false);
        var notices = new List<OfficialWindowsEngine.RoomNotification>();
        var report = new Dictionary<string, object?>
        {
            ["role"] = input[1], ["phase"] = "initialize", ["passed"] = false,
            ["source_commit"] = Environment.GetEnvironmentVariable("GITHUB_SHA"),
            ["scope"] = "Production C# room binding with explicitly instrumented child-only fixture trust; no control or media.",
            ["instrumentation"] = "After baseline TLS rejection, add exactly the fixture CA using original DER/store helpers. No production CA override.",
            ["notifications"] = notices
        };
        void Save() => File.WriteAllText(output, JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
        void MustThrow<T>(Action action) where T : Exception
        {
            try { action(); }
            catch (T) { return; }
            throw new Exception("Expected " + typeof(T).Name);
        }
        void WaitFor(Func<bool> condition, string description, OfficialWindowsEngine engine)
        {
            var deadline = DateTime.UtcNow.AddSeconds(10);
            while (DateTime.UtcNow < deadline)
            {
                notices.AddRange(engine.DrainRoomNotifications());
                if (condition()) return;
                Thread.Sleep(20);
            }
            throw new TimeoutException(description);
        }
        bool HasCode(int handle, int code) => notices.Any(value => value.Handle == handle
            && value.Kind == OfficialWindowsEngine.RoomNotificationKind.ConnectionCode && value.Value == code);
        Save();
        try
        {
            using var engine = new OfficialWindowsEngine(role, logs, config, "managed-room-" + input[1], dll);
            MustThrow<ArgumentException>(() => engine.OpenRoom("test", new[] { new Uri("ws://127.0.0.1/test") }));
            MustThrow<ArgumentOutOfRangeException>(() => engine.OpenRoom("test", Array.Empty<Uri>()));
            MustThrow<ArgumentException>(() => engine.OpenRoom("bad\0token", new[] { server }));
            report["phase"] = "open_first_room";
            Save();
            int handle = engine.OpenRoom("ci-loopback-token", new[] { server });
            report["first_handle"] = handle;
            // Asynchronous native callbacks must remain rooted across GC.
            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
            WaitFor(() => File.Exists(rejection), "Expected ordinary native TLS rejection", engine);
            if (HasCode(handle, 9004)) throw new Exception("Fixture room logged in before trust instrumentation");
            using (var baseline = JsonDocument.Parse(File.ReadAllText(rejection)))
                report["baseline_rejection"] = baseline.RootElement.Clone();
            report["phase"] = "fixture_trust_instrumentation";
            Save();
            report["trust_extension"] = ExtendFixtureTrust(dll, certificatePem);
            WaitFor(() => HasCode(handle, 9004), "Expected original room login code 9004", engine);
            if (!notices.Any(value => value.Handle == handle && value.Kind == OfficialWindowsEngine.RoomNotificationKind.RoomState && value.Value == 2))
                throw new Exception("No matching native room-state callback");
            report["first_login_observed"] = true;
            report["phase"] = "close_first_room";
            Save();
            if (!engine.CloseRoom(handle) || engine.CloseRoom(handle))
                throw new Exception("Room close must execute exactly once");
            report["first_close_idempotent"] = true;
            int second = engine.OpenRoom("ci-loopback-token", new[] { server });
            report["second_handle"] = second;
            if (second == handle) throw new Exception("Expected a fresh local room handle");
            WaitFor(() => HasCode(second, 9004), "Expected second native room login", engine);
            report["second_login_observed"] = true;
            report["phase"] = "dispose_with_owned_room";
            Save();
            engine.Dispose();
            engine.Dispose();
            MustThrow<ObjectDisposedException>(() => engine.OpenRoom("test", new[] { server }));
            MustThrow<ObjectDisposedException>(() => engine.CloseRoom(second));
            MustThrow<ObjectDisposedException>(() => engine.DrainRoomNotifications());
            report["dispose_with_owned_room_passed"] = true;
            report["phase"] = "complete";
            report["passed"] = true;
            report["checks"] = new[] { "invalid room inputs rejected before native call", "native callback delegates survive GC",
                "baseline TLS CA rejection", "explicit child-only fixture trust", "native room login callbacks",
                "queued notifications retain handle and domain", "close exactly once", "second room login",
                "Dispose closes owned room", "repeat Dispose", "calls after Dispose rejected" };
            Console.WriteLine("PASS production original room binding: " + input[1]);
        }
        catch (Exception error)
        {
            report["error"] = error.ToString();
            throw;
        }
        finally { Save(); }
    }

    private static object ExtendFixtureTrust(string dll, string certificatePem)
    {
        const string expected = "ac351cf4e1d489e0b6e1a3df5cdf8aed96348876f7e2c7fcf7162fe59e1bb1c4";
        if (Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(dll))).ToLowerInvariant() != expected)
            throw new Exception("Fixture helper RVAs require the original DLL identity");
        IntPtr module = NativeLibrary.Load(dll); // Original engine pins this module; never unload it here.
        IntPtr cachedStore = IntPtr.Add(module, 0x143f880), store = Marshal.ReadIntPtr(cachedStore);
        if (store == IntPtr.Zero) throw new Exception("No cached native trust store after TLS rejection");
        byte[] der = Convert.FromBase64String(certificatePem.Replace("-----BEGIN CERTIFICATE-----", "")
            .Replace("-----END CERTIFICATE-----", ""));
        var parse = Marshal.GetDelegateForFunctionPointer<ParseCertificate>(IntPtr.Add(module, 0xd5d110));
        var add = Marshal.GetDelegateForFunctionPointer<AddCertificate>(IntPtr.Add(module, 0xe105d0));
        var release = Marshal.GetDelegateForFunctionPointer<ReleaseCertificate>(IntPtr.Add(module, 0xd5d040));
        IntPtr bytes = Marshal.AllocHGlobal(der.Length);
        int status;
        try
        {
            Marshal.Copy(der, 0, bytes, der.Length);
            IntPtr cursor = bytes;
            IntPtr certificate = parse(IntPtr.Zero, ref cursor, der.Length);
            if (certificate == IntPtr.Zero) throw new Exception("Original DER parser rejected the fixture CA");
            try
            {
                if (cursor != IntPtr.Add(bytes, der.Length)) throw new Exception("Fixture DER not fully consumed");
                status = add(store, certificate);
                if (status != 1) throw new Exception("Fixture CA insertion failed");
            }
            finally { release(certificate); }
        }
        finally { Marshal.FreeHGlobal(bytes); }
        if (Marshal.ReadIntPtr(cachedStore) != store) throw new Exception("Original cached store pointer changed");
        return new
        {
            add_status = status, certificate_der_sha256 = Convert.ToHexString(SHA256.HashData(der)).ToLowerInvariant(),
            store_pointer_unchanged = true,
            scope = "Explicit test instrumentation of this child native trust store only; no system certificate store or DLL file change."
        };
    }
}
