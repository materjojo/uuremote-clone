using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Security.Cryptography;
using UURemoteClone;

if (args.Length == 6 && args[0] == "--engine")
{
    RunEngineChecks(args);
    return;
}

if (args.Length != 2) throw new ArgumentException("Expected bridge directory and official DLL path");
NativeLibrary.SetDllImportResolver(typeof(OfficialStreamer).Assembly, (name, _, _) =>
    name == "gvpb" ? NativeLibrary.Load(Path.GetFullPath(Path.Combine(args[0], "gvpb.dll"))) : IntPtr.Zero);
foreach (var role in new[] { OfficialStreamer.Role.Controller, OfficialStreamer.Role.Controlled })
{
    using var streamer = new OfficialStreamer(args[1], role);
    var version = streamer.Version;
    if (version != "V4.14.2") throw new Exception($"Unexpected native version: {version}");
    Console.WriteLine($"PASS managed P/Invoke: {role} {version}");
}
try
{
    using var invalid = new OfficialStreamer(args[1], (OfficialStreamer.Role)99);
    throw new Exception("Invalid role accepted");
}
catch (InvalidOperationException error) when (error.Message.Contains("Invalid library path or role")) {}

static void RunEngineChecks(string[] input)
{
    if (Environment.GetEnvironmentVariable("GITHUB_ACTIONS") != "true")
        throw new InvalidOperationException("Original engine runtime tests require GitHub Actions.");
    var role = input[1] switch
    {
        "controller" => OfficialStreamer.Role.Controller,
        "controlled" => OfficialStreamer.Role.Controlled,
        _ => throw new ArgumentException("Unknown role")
    };
    string runtime = Path.GetFullPath(input[2]), workspace = Path.GetFullPath(input[3]);
    string output = Path.GetFullPath(input[4]), referencePath = Path.GetFullPath(input[5]);
    Directory.CreateDirectory(workspace);
    Directory.CreateDirectory(Path.GetDirectoryName(output)!);
    string config = Path.Combine(workspace, "config-配置.json");
    File.Copy(Path.Combine(runtime, "streamer-config.json"), config, false);
    string logs = Path.Combine(workspace, "logs"), dll = Path.Combine(runtime, "streamer.dll");
    var report = new Dictionary<string, object?>
    {
        ["source_commit"] = Environment.GetEnvironmentVariable("GITHUB_SHA"),
        ["role"] = input[1], ["phase"] = "initialize", ["passed"] = false,
        ["library_sha256"] = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(dll))).ToLowerInvariant(),
        ["config_sha256"] = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(config))).ToLowerInvariant(),
        ["scope"] = "Production C# engine lifecycle, ownership and capability binding; no media session or GPU validation."
    };
    void Save() => File.WriteAllText(output, JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
    void MustThrow<T>(Action action) where T : Exception
    {
        try { action(); }
        catch (T) { return; }
        throw new Exception("Expected " + typeof(T).Name);
    }
    Save();
    try
    {
        MustThrow<ArgumentException>(() => new OfficialWindowsEngine(role, logs, config, "invalid\\suffix", dll));
        using var engine = new OfficialWindowsEngine(role, logs, config, "managed-" + input[1], dll);
        if (engine.Version != "V4.14.2") throw new Exception("Native version mismatch");
        report["version"] = engine.Version;
        MustThrow<InvalidOperationException>(() => new OfficialWindowsEngine(role, logs, config, "duplicate", dll));
        // Both entry points can otherwise mutate the same native callback table.
        MustThrow<InvalidOperationException>(() => new OfficialStreamer(dll, role));
        report["phase"] = "capability";
        Save();
        string json = engine.GetCodecCapabilitiesJson();
        if (json != engine.GetCodecCapabilitiesJson()) throw new Exception("Capability bytes changed on repeat");
        using var document = JsonDocument.Parse(json);
        report["capability_json"] = document.RootElement.Clone();
        report["capability_sha256"] = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(json))).ToLowerInvariant();
        using var reference = JsonDocument.Parse(File.ReadAllText(referencePath));
        var native = reference.RootElement.GetProperty("observations").EnumerateArray()
            .Single(item => item.GetProperty("role").GetString() == input[1]).GetProperty("native");
        if (native.GetProperty("capability_first").GetProperty("utf8").GetString() != json)
            throw new Exception("C# capability bytes differ from the same runner's direct original DLL invocation");
        report["matches_direct_native_bytes"] = true;
        report["phase"] = "finalize";
        Save();
        engine.Dispose();
        engine.Dispose();
        MustThrow<ObjectDisposedException>(() => _ = engine.Version);
        MustThrow<ObjectDisposedException>(() => engine.GetCodecCapabilitiesJson());
        report["phase"] = "reinitialize";
        Save();
        using (var restarted = new OfficialWindowsEngine(role, logs, config, "managed-restart-" + input[1], dll))
        {
            if (restarted.Version != "V4.14.2" || restarted.GetCodecCapabilitiesJson() != json)
                throw new Exception("Native engine could not be reinitialized after successful disposal");
        }
        report["phase"] = "complete";
        report["passed"] = true;
        report["checks"] = new[] { "UTF-16 config path", "invalid suffix rejected", "exclusive engine owner",
            "version inspector factory blocked", "repeat capabilities", "direct native byte parity",
            "idempotent shutdown", "calls after disposal rejected", "reinitialize after shutdown" };
        Console.WriteLine("PASS original engine lifecycle/capability binding: " + input[1]);
    }
    catch (Exception error)
    {
        report["error"] = error.ToString();
        throw;
    }
    finally { Save(); }
}
