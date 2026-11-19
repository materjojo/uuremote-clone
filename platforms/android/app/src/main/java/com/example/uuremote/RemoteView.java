package com.example.uuremote;

import android.content.Context;
import android.widget.FrameLayout;

import org.webrtc.EglBase;
import org.webrtc.SurfaceViewRenderer;
import org.webrtc.VideoTrack;

/** 远端画面渲染（SurfaceViewRenderer，GPU 合成） */
public class RemoteView extends FrameLayout {
    private final SurfaceViewRenderer renderer;
    private final EglBase egl;

    public RemoteView(Context context) {
        super(context);
        egl = EglBase.create();
        renderer = new SurfaceViewRenderer(context);
        renderer.init(egl.getEglBaseContext(), null);
        renderer.setMirror(false);
        addView(renderer, new LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
    }

    public void attach(VideoTrack track) {
        if (track != null) track.addSink(renderer);
    }

    public void detach(VideoTrack track) {
        if (track != null) track.removeSink(renderer);
    }

    public void release() {
        renderer.release();
        egl.release();
    }
}
