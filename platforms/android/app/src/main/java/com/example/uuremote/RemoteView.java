package com.example.uuremote;

import android.content.Context;
import android.widget.FrameLayout;
import org.webrtc.*;

public class RemoteView extends FrameLayout {
    private final SurfaceViewRenderer renderer;
    private final EglBase owned;
    private VideoTrack track;
    private int videoWidth, videoHeight;
    public RemoteView(Context context) { this(context, null); }
    public RemoteView(Context context, EglBase.Context shared) {
        super(context);
        owned = shared == null ? EglBase.create() : null;
        renderer = new SurfaceViewRenderer(context);
        renderer.init(shared != null ? shared : owned.getEglBaseContext(), new RendererCommon.RendererEvents() {
            @Override public void onFirstFrameRendered() { }
            @Override public void onFrameResolutionChanged(int width, int height, int rotation) {
                post(() -> { videoWidth = rotation % 180 == 0 ? width : height; videoHeight = rotation % 180 == 0 ? height : width; });
            }
        });
        renderer.setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FIT);
        renderer.setMirror(false);
        addView(renderer, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
    }
    public void attach(VideoTrack next) {
        if (track == next) return;
        if (track != null) track.removeSink(renderer);
        track = next; if (next != null) next.addSink(renderer);
    }
    public void detach(VideoTrack value) { if (value == track) attach(null); }
    /** Reject taps in the letterbox; map input to actual displayed pixels. */
    public float[] normalize(float x, float y) {
        if (videoWidth <= 0 || videoHeight <= 0 || getWidth() <= 0 || getHeight() <= 0) return null;
        float scale = Math.min((float)getWidth() / videoWidth, (float)getHeight() / videoHeight);
        float width = videoWidth * scale, height = videoHeight * scale;
        float nx = (x - (getWidth() - width) / 2) / width, ny = (y - (getHeight() - height) / 2) / height;
        return nx < 0 || ny < 0 || nx > 1 || ny > 1 ? null : new float[]{nx, ny};
    }
    public void release() { attach(null); renderer.release(); if (owned != null) owned.release(); }
}
