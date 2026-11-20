using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;

namespace UURemoteClone;

public record PeerInvitation(int V, string Server, string Id, string Key, string Name, string Platform)
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public string Code => "uur1." + Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(this, Json))
        .TrimEnd('=').Replace('+', '-').Replace('/', '_');
    public static PeerInvitation Parse(string code)
    {
        code = code.Trim();
        if (!code.StartsWith("uur1.") || code.Length > 8192) throw new ArgumentException("请粘贴对端生成的配对码");
        var raw = code[5..].Replace('-', '+').Replace('_', '/');
        raw = raw.PadRight((raw.Length + 3) / 4 * 4, '=');
        var value = JsonSerializer.Deserialize<PeerInvitation>(Convert.FromBase64String(raw), Json)
            ?? throw new ArgumentException("配对码损坏");
        _ = PeerAPI.Endpoint(value.Server);
        if (value.V != 1 || value.Id.Length is < 16 or > 64 || value.Key.Length is < 32 or > 128 ||
            string.IsNullOrWhiteSpace(value.Name) || !new[] { "mac", "windows", "android" }.Contains(value.Platform))
            throw new ArgumentException("配对码版本或设备信息不正确");
        return value;
    }
}

public sealed class PeerSettings
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string OwnerKey { get; set; } = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    public string PairKey { get; set; } = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    public string Server { get; set; } = "";
    public List<PeerInvitation> Devices { get; set; } = new();
    private static string FileName => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "UURemoteClone", "peers.dat");
    public static PeerSettings Load()
    {
        if (!File.Exists(FileName)) { var settings = new PeerSettings(); settings.Save(); return settings; }
        // DPAPI binds saved pairing keys to this OS account.
        var raw = ProtectedData.Unprotect(File.ReadAllBytes(FileName), null, DataProtectionScope.CurrentUser);
        return JsonSerializer.Deserialize<PeerSettings>(raw, PeerInvitation.Json) ?? throw new IOException("设备配置损坏");
    }
    public void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FileName)!);
        var raw = JsonSerializer.SerializeToUtf8Bytes(this, PeerInvitation.Json);
        File.WriteAllBytes(FileName + ".tmp", ProtectedData.Protect(raw, null, DataProtectionScope.CurrentUser));
        File.Move(FileName + ".tmp", FileName, true);
    }
}

public sealed class PeerAPI : IDisposable
{
    private readonly HttpClient _http;
    public static Uri Endpoint(string input)
    {
        if (!Uri.TryCreate(input.Trim(), UriKind.Absolute, out var value) ||
            (value.Scheme != "https" && value.Scheme != "http") || value.Host.Length == 0 ||
            value.UserInfo.Length != 0 || value.Query.Length != 0 || value.Fragment.Length != 0 || value.AbsolutePath != "/")
            throw new ArgumentException("请输入自建信令服务根地址，例如 https://signal.example.org 或 http://局域网地址:8080");
        return value;
    }
    public PeerAPI(string server)
    {
        _http = new HttpClient { BaseAddress = Endpoint(server), Timeout = TimeSpan.FromSeconds(18) };
    }
    public async Task<JsonElement> RequestAsync(string path, string? token = null, object? body = null, CancellationToken ct = default)
    {
        using var request = new HttpRequestMessage(body == null ? HttpMethod.Get : HttpMethod.Post, path);
        if (token != null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (body != null) request.Content = new StringContent(JsonSerializer.Serialize(body, PeerInvitation.Json), Encoding.UTF8, "application/json");
        using var response = await _http.SendAsync(request, ct);
        var content = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode) throw new IOException($"信令服务 {(int)response.StatusCode}：{content[..Math.Min(160, content.Length)]}");
        using var doc = JsonDocument.Parse(content);
        return doc.RootElement.Clone();
    }
    public void Dispose() => _http.Dispose();
}

public sealed class PeerMailbox : IDisposable
{
    private readonly PeerAPI _api;
    private readonly string _id, _token;
    private readonly CancellationTokenSource _stop = new();
    private readonly Channel<(string type, object data, string id)> _outbox =
        Channel.CreateBounded<(string, object, string)>(new BoundedChannelOptions(256) { SingleReader = true });
    public event Func<string, JsonElement, Task>? Signal;
    public event Action<string>? Error;
    public PeerMailbox(PeerAPI api, string id, string token) { _api = api; _id = id; _token = token; }
    public void Start() { _ = Poll(); _ = SendLoop(); }
    public void Send(string type, object? data = null)
    {
        if (!_outbox.Writer.TryWrite((type, data ?? new { }, Guid.NewGuid().ToString())))
            Error?.Invoke("信令队列已满或已关闭");
    }
    private async Task SendLoop()
    {
        try {
            await foreach (var item in _outbox.Reader.ReadAllAsync(_stop.Token)) {
                for (int retry = 0; ; retry++) {
                    try {
                        await _api.RequestAsync($"/v1/sessions/{_id}/signals", _token,
                            new { type = item.type, data = item.data, message_id = item.id }, _stop.Token);
                        break;
                    } catch (OperationCanceledException) when (_stop.IsCancellationRequested) { return; }
                    catch when (retry < 2) { await Task.Delay(500, _stop.Token); }
                }
            }
        } catch (OperationCanceledException) { }
        catch (Exception ex) { Error?.Invoke(ex.Message); }
    }
    private async Task Poll()
    {
        int cursor = 0, failures = 0;
        try {
            while (!_stop.IsCancellationRequested) {
                JsonElement response;
                try {
                    response = await _api.RequestAsync($"/v1/sessions/{_id}/signals?after={cursor}", _token, ct: _stop.Token);
                    failures = 0;
                } catch (OperationCanceledException) when (_stop.IsCancellationRequested) { return; }
                catch when (++failures < 3) { await Task.Delay(1000, _stop.Token); continue; }
                foreach (var item in response.GetProperty("events").EnumerateArray()) {
                    int seq = item.GetProperty("seq").GetInt32();
                    if (seq <= cursor) continue;
                    if (Signal != null) await Signal(item.GetProperty("type").GetString()!, item.GetProperty("data"));
                    cursor = seq;
                }
                if (response.GetProperty("closed").GetBoolean()) return;
            }
        } catch (OperationCanceledException) { }
        catch (Exception ex) { Error?.Invoke(ex.Message); }
    }
    public void Dispose() { _stop.Cancel(); _outbox.Writer.TryComplete(); }
}
