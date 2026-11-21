using System.Text.Json;
using UURemoteClone;

// Runner only. Exercises production bindings in separate native-owner processes.
// Certificate instrumentation is in the test helper, outside application code.
internal static class PairChecks
{
    internal static void Run(string[] input)
    {
        if (!OperatingSystem.IsWindows() || Environment.GetEnvironmentVariable("GITHUB_ACTIONS") != "true")
            throw new InvalidOperationException("Native pair checks require Windows Actions.");
        var role = input[1] switch
        {
            "controller" => OfficialStreamer.Role.Controller,
            "controlled" => OfficialStreamer.Role.Controlled,
            _ => throw new ArgumentException("Unknown role")
        };
        string runtime = Path.GetFullPath(input[2]), workspace = Path.GetFullPath(input[3]);
        string output = Path.GetFullPath(input[4]);
        using var fixture = JsonDocument.Parse(File.ReadAllText(input[5]));
        string Setting(string name) => fixture.RootElement.GetProperty(name).GetString()!;
        bool mediaMode = fixture.RootElement.TryGetProperty("media", out var mediaFlag) && mediaFlag.GetBoolean();
        var server = new Uri(Setting("server_url"));
        if (server.Scheme != "wss" || server.Host != "127.0.0.1")
            throw new ArgumentException("Pair recorder requires TLS loopback.");
        Directory.CreateDirectory(workspace);
        string config = Path.Combine(workspace, "config-配置.json"), dll = Path.Combine(runtime, "streamer.dll");
        File.Copy(Path.Combine(runtime, "streamer-config.json"), config, false);
        var notices = new List<OfficialWindowsEngine.RoomNotification>();
        var controls = new List<OfficialWindowsEngine.NewControlNotification>();
        var binaryData = new List<OfficialWindowsEngine.BinaryDataNotification>();
        var peerStates = new List<OfficialWindowsEngine.PeerStateNotification>();
        byte[] payload = Convert.FromBase64String(Setting("send_payload_base64"));
        byte[] expectedPayload = Convert.FromBase64String(Setting("expected_payload_base64"));
        byte[] appData = Convert.FromBase64String("Y2ktY29udHJvbC1hcHAtZGF0YQD//g==");
        var report = new Dictionary<string, object?>
        {
            ["role"] = input[1], ["phase"] = "initialize", ["passed"] = false,
            ["notifications"] = notices, ["new_controls"] = controls,
            ["binary_data"] = binaryData, ["peer_states"] = peerStates,
            ["send_payload_base64"] = Convert.ToBase64String(payload),
            ["expected_payload_base64"] = Convert.ToBase64String(expectedPayload),
            ["source_commit"] = Environment.GetEnvironmentVariable("GITHUB_SHA"),
            ["scope"] = mediaMode
                ? "Original binary-channel delivery and original capture/encode/decode/render observation with runner-owned windows."
                : "Two original engines with independent local signaling and opaque binary transfer; no capture or media."
        };
        void Save()
        {
            string temporary = output + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, output, true);
        }
        bool HasCode(int handle, int code) => notices.Any(value => value.Handle == handle
            && value.Kind == OfficialWindowsEngine.RoomNotificationKind.ConnectionCode && value.Value == code);
        void MustThrow<T>(Action action) where T : Exception
        {
            try { action(); }
            catch (T) { return; }
            throw new Exception("Expected " + typeof(T).Name);
        }
        Save();
        try
        {
            using var media = mediaMode ? new NativeMediaObservation(input[1], fixture.RootElement) : null;
            if (media is not null) report["media"] = media.Report;
            using var engine = new OfficialWindowsEngine(role, Path.Combine(workspace, "logs"), config,
                "native-pair-" + input[1], dll);
            int handle = engine.OpenRoom("ci-loopback-token", new[] { server });
            report["handle"] = handle;
            media?.Validate(engine, handle);
            MustThrow<ArgumentException>(() => engine.SendBinary(int.MaxValue, new byte[] { 1 }));
            MustThrow<ArgumentOutOfRangeException>(() => engine.SendBinary(handle, Array.Empty<byte>()));
            MustThrow<ArgumentOutOfRangeException>(() => engine.SendBinary(handle, new byte[512 * 1024]));
            bool trusted = false, ready = false, requested = false, stopped = false, binarySent = false;
            DateTime deadline = DateTime.UtcNow.AddSeconds(mediaMode ? 90 : 60);
            while (DateTime.UtcNow < deadline)
            {
                notices.AddRange(engine.DrainRoomNotifications());
                controls.AddRange(engine.DrainNewControls());
                binaryData.AddRange(engine.DrainBinaryData());
                peerStates.AddRange(engine.DrainPeerStates());
                if (!trusted && File.Exists(Setting("baseline_rejection_path")))
                {
                    report["trust_extension"] = RoomChecks.ExtendFixtureTrust(dll, Setting("certificate_pem"));
                    trusted = true;
                }
                if (!ready && HasCode(handle, 9004))
                {
                    if (!trusted) throw new Exception("Unexpected login before explicit fixture trust");
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                    GC.Collect();
                    File.WriteAllText(Setting("ready_path"), "original login 9004");
                    ready = true;
                    report["login_observed"] = true;
                }
                if (role == OfficialStreamer.Role.Controller && ready && !requested && File.Exists(Setting("start_path")))
                {
                    engine.RequestControl(handle, appData, "ci-local-control-01", "Etc/UTC");
                    requested = true;
                    report["control_requested"] = true;
                }
                if (controls.Any(value => value.Handle != handle || value.ControlId != "ci-local-control-01"
                        || !value.AppData.SequenceEqual(appData)))
                    throw new Exception("Actual peer new-control input changed");
                if (!binarySent && File.Exists(Setting("send_path")))
                {
                    report["binary_submission_attempted"] = true;
                    Save();
                    engine.SendBinary(handle, payload);
                    binarySent = true;
                    Array.Fill(payload, (byte)0x5a);
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                    GC.Collect();
                    report["binary_sent"] = true;
                }
                if (binaryData.Any(value => value.Handle != handle || !value.Data.SequenceEqual(expectedPayload)))
                    throw new Exception("Original binary callback did not preserve actual peer bytes");
                bool received = binarySent && binaryData.Count == 1;
                report["peer_binary_received"] = received;
                if (received && !File.Exists(Setting("received_path")))
                    File.WriteAllText(Setting("received_path"), "original binary callback matched peer nonce");
                media?.Tick(engine, handle, Save);
                report["phase"] = ready ? (mediaMode ? "media_observation" : "binary_observation") : "room_login";
                Save();
                if (File.Exists(Setting("stop_path"))) { stopped = true; break; }
                Thread.Sleep(50);
            }
            report["observation_stopped_by_parent"] = stopped;
            report["phase"] = "dispose";
            Save();
            media?.Complete(engine, handle);
            engine.Dispose();
            media?.Dispose();
            MustThrow<ObjectDisposedException>(() => engine.SendBinary(handle, new byte[] { 1 }));
            MustThrow<ObjectDisposedException>(() => engine.DrainBinaryData());
            MustThrow<ObjectDisposedException>(() => engine.DrainPeerStates());
            MustThrow<ObjectDisposedException>(() => engine.DrainMediaTracks());
            MustThrow<ObjectDisposedException>(() => engine.DrainFrameChanges());
            MustThrow<ObjectDisposedException>(() => engine.DrainCaptureFailures());
            report["passed"] = stopped && ready && binarySent && binaryData.Count == 1
                && (role == OfficialStreamer.Role.Controller ? requested : controls.Count == 1);
            report["phase"] = "complete";
            if (!(bool)report["passed"]!) throw new Exception("Original pair observation did not complete");
        }
        catch (Exception error) { report["passed"] = false; report["error"] = error.ToString(); throw; }
        finally { Save(); }
    }
}
