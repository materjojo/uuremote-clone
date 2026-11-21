using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using UURemoteClone;

// Runner-only observation of original capture/renderer operations. The parent
// chooses the source colors and checks independently sampled controller pixels.
internal sealed class NativeMediaObservation : IDisposable
{
    private readonly bool _source;
    private readonly JsonElement _settings;
    private readonly NativeTestWindow _window;
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly List<OfficialWindowsEngine.MediaTrackNotification> _tracks = new();
    private readonly List<OfficialWindowsEngine.FrameChangeNotification> _frames = new();
    private readonly List<OfficialWindowsEngine.CaptureFailureNotification> _failures = new();
    private readonly List<object> _samples = new();
    private readonly List<OfficialWindowsEngine.ConnectionStatsNotification> _stats = new();
    private bool _started, _phaseChanged;
    private int _trackIndex, _sampleIndex;
    private long _nextSample, _nextStats, _postStatsDeadline;
    private int? _postStatsBefore;
    private bool _postStatsReady;
    private readonly HashSet<int> _snapshots = new();
    public Dictionary<string, object?> Report { get; }

    private string Setting(string name) => _settings.GetProperty(name).GetString()!;

    internal NativeMediaObservation(string role, JsonElement settings)
    {
        _settings = settings;
        _source = role == "controlled";
        uint[][]? patterns = _source ? settings.GetProperty("source_patterns").EnumerateArray()
            .Select(phase => phase.EnumerateArray().Select(color => color.GetUInt32()).ToArray()).ToArray() : null;
        if (_source && (patterns!.Length != 2 || patterns.Any(phase => phase.Length != 4)))
            throw new ArgumentException("Source observation requires two four-color patterns.");
        _window = new NativeTestWindow(_source, patterns);
        Report = new Dictionary<string, object?>
        {
            ["role"] = role, ["window_handle"] = _window.Handle.ToInt64(),
            ["tracks"] = _tracks, ["frame_changes"] = _frames, ["capture_failures"] = _failures,
            ["samples"] = _samples, ["connection_stats"] = _stats, ["started"] = false,
            ["scope"] = _source ? "Runner-owned test window captured by original native engine."
                : "Original native renderer output sampled from a separate visible test window; no source colors are supplied to this child."
        };
    }

    internal void Validate(OfficialWindowsEngine engine, int handle)
    {
        void MustThrow<T>(Action action) where T : Exception
        {
            try { action(); }
            catch (T) { return; }
            throw new Exception("Expected " + typeof(T).Name);
        }
        if (_source)
        {
            MustThrow<InvalidOperationException>(() => engine.StartVideoRender(handle, _window.Handle, 0));
            MustThrow<ArgumentException>(() => engine.StartWindowCapture(int.MaxValue, _window.Handle));
            MustThrow<ArgumentException>(() => engine.StartWindowCapture(handle, IntPtr.Zero));
            MustThrow<ArgumentOutOfRangeException>(() => engine.StartWindowCapture(handle, _window.Handle, 0, 0));
            if (engine.StopVideoCapture(handle)) throw new Exception("Unexpected active capture");
        }
        else
        {
            MustThrow<InvalidOperationException>(() => engine.StartWindowCapture(handle, _window.Handle));
            MustThrow<ArgumentException>(() => engine.StartVideoRender(int.MaxValue, _window.Handle, 0));
            MustThrow<ArgumentException>(() => engine.StartVideoRender(handle, IntPtr.Zero, 0));
            if (engine.StopVideoRender(handle, 0)) throw new Exception("Unexpected active renderer");
        }
        MustThrow<ArgumentException>(() => engine.RequestConnectionStats(int.MaxValue));
        Report["input_rejections_passed"] = true;
    }

    internal void Tick(OfficialWindowsEngine engine, int handle, Action save)
    {
        try
        {
            _tracks.AddRange(engine.DrainMediaTracks());
            _frames.AddRange(engine.DrainFrameChanges());
            _failures.AddRange(engine.DrainCaptureFailures());
            DrainStats(engine, handle);
            if (_tracks.Any(value => value.Handle != handle) || _frames.Any(value => value.Handle != handle))
                throw new Exception("Native media callback changed its local room handle");
            if (_failures.Count != 0) throw new Exception("Original capture reported a failure");
            if (!_started && File.Exists(Setting("media_start_path")))
            {
                if (_source)
                {
                    Report["capture_attempted"] = true;
                    Report["requested_config"] = new { capture_type = 1, video_codec = 1, chroma_sampling = 1,
                        fps = 15, quality = 1, max_scale_width = 1280, max_scale_height = 720, track_index = 0 };
                    save();
                    engine.StartWindowCapture(handle, _window.Handle);
                    _trackIndex = 0;
                    _started = true;
                }
                else
                {
                    int? videoTrack = null;
                    foreach (var track in _tracks)
                    {
                        using var document = JsonDocument.Parse(track.Json);
                        if (document.RootElement.GetProperty("type").GetString() == "video")
                        {
                            videoTrack = document.RootElement.GetProperty("track_index").GetInt32();
                            break;
                        }
                    }
                    if (videoTrack is int index)
                    {
                        _trackIndex = index;
                        Report["renderer_attempted"] = true;
                        Report["render_track_index"] = index;
                        save();
                        engine.StartVideoRender(handle, _window.Handle, index);
                        _started = true;
                    }
                }
                Report["started"] = _started;
                if (_started)
                {
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                    GC.Collect();
                }
            }
            if (_source && !_phaseChanged && File.Exists(Setting("media_phase_path")))
            {
                _window.SetPhase(1);
                _phaseChanged = true;
                Report["source_phase_changed"] = true;
            }
            if (_started)
            {
                if (_postStatsBefore is null && File.Exists(Setting("media_verified_path")))
                {
                    _postStatsBefore = _stats.Count;
                    _postStatsDeadline = _clock.ElapsedMilliseconds + 3000;
                    engine.RequestConnectionStats(handle);
                }
                else if (_postStatsBefore is null && _clock.ElapsedMilliseconds >= _nextStats)
                {
                    _nextStats = _clock.ElapsedMilliseconds + 1000;
                    engine.RequestConnectionStats(handle);
                }
                DrainStats(engine, handle);
                if (!_postStatsReady && _postStatsBefore is int before)
                {
                    if (_stats.Count > before)
                    {
                        var stats = _stats[^1];
                        string hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(stats.Json))).ToLowerInvariant();
                        string path = Setting("stats_ready_path");
                        File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(new { stats.Handle, stats.Json, Sha256 = hash }));
                        File.Move(path + ".tmp", path);
                        _postStatsReady = true;
                        Report["post_render_stats_received"] = true;
                        Report["post_render_stats_sha256"] = hash;
                        GC.Collect();
                        GC.WaitForPendingFinalizers();
                    }
                    else if (_clock.ElapsedMilliseconds > _postStatsDeadline)
                        throw new Exception("Original statistics callback was not observed after the rendered patterns");
                }
                for (int phase = 0; phase < 2; phase++)
                {
                    if (!_snapshots.Contains(phase) && File.Exists(Setting("snapshot_prefix") + phase))
                    {
                        string path = Path.Combine(Setting("sample_directory"),
                            (_source ? "controlled" : "controller") + "-phase-" + phase + ".bmp");
                        _window.SaveBitmap(path);
                        _snapshots.Add(phase);
                    }
                }
                if (!_source && _clock.ElapsedMilliseconds >= _nextSample && _sampleIndex < 180)
                {
                    _nextSample = _clock.ElapsedMilliseconds + 250;
                    var sample = new { index = _sampleIndex++, elapsed_ms = _clock.ElapsedMilliseconds, colors = _window.Sample(),
                        frame_change_count = _frames.Count };
                    _samples.Add(sample);
                    string path = Path.Combine(Setting("sample_directory"), "sample-" + sample.index.ToString("D4") + ".json");
                    File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(sample));
                    File.Move(path + ".tmp", path);
                }
            }
        }
        catch (Exception error) { Report["error"] = error.ToString(); save(); throw; }
    }

    private void DrainStats(OfficialWindowsEngine engine, int handle)
    {
        foreach (var stats in engine.DrainConnectionStats())
        {
            if (stats.Handle != handle) throw new Exception("Original statistics changed the local room handle");
            using var parsed = JsonDocument.Parse(stats.Json);
            _stats.Add(stats);
        }
    }

    internal void Complete(OfficialWindowsEngine engine, int handle)
    {
        if (!_started) throw new Exception("Original media operation did not start");
        if (!File.Exists(Setting("media_verified_path"))) throw new Exception("Parent did not observe both rendered source patterns");
        // Parent waits for both post-render callbacks before stopping either
        // process, so peer disposal cannot race the other statistics request.
        if (!_postStatsReady) throw new Exception("Post-render original statistics are absent");
        bool stopped = _source ? engine.StopVideoCapture(handle, _trackIndex) : engine.StopVideoRender(handle, _trackIndex);
        bool stoppedAgain = _source ? engine.StopVideoCapture(handle, _trackIndex) : engine.StopVideoRender(handle, _trackIndex);
        if (!stopped || stoppedAgain) throw new Exception("Native video stop lifecycle changed");
        _frames.AddRange(engine.DrainFrameChanges());
        _failures.AddRange(engine.DrainCaptureFailures());
        if (_failures.Count != 0 || (!_source && _frames.Count == 0))
            throw new Exception("Native media callbacks did not satisfy the pixel observation");
        Report["explicit_stop_passed"] = true;
        Report["parent_pixels_verified"] = true;
    }

    public void Dispose()
    {
        _window.Dispose();
        Report["window_thread_stopped"] = _window.Stopped;
    }
}
