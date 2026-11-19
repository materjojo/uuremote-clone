// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.model;


public final class IceNetworkConfig {
    public static final int ICE_NETWORK_ALL = 0;
    public static final int ICE_NETWORK_RELAY = 1;
    private final int type;



    public IceNetworkConfig(int i10) {
        this.type = i10;
    }

    public final int getType() {
        return this.type;
    }
}
