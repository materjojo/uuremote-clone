// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.model;

import java.util.List;

public final class StreamerRoomConfig {
    private final String appData;
    private final String reportServerAddress;
    private final String reportToken;
    private final String reportUrl;
    private final int signalReconnectDelay;
    private final List<String> signalServers;
    private final List<String> sniRequiredServers;
    private final String streamerConfig;
    private final int timeout;
    private final String token;

    public StreamerRoomConfig(String str, List<String> list, int i10, int i11, String str2, String str3, String str4, String str5, List<String> list2, String str6) {
        java.util.Objects.requireNonNull(str, "token");
        java.util.Objects.requireNonNull(list, "signalServers");
        java.util.Objects.requireNonNull(str2, "reportToken");
        java.util.Objects.requireNonNull(str3, "reportUrl");
        java.util.Objects.requireNonNull(str4, "reportServerAddress");
        java.util.Objects.requireNonNull(str5, "appData");
        java.util.Objects.requireNonNull(list2, "sniRequiredServers");
        java.util.Objects.requireNonNull(str6, "streamerConfig");
        this.token = str;
        this.signalServers = list;
        this.timeout = i10;
        this.signalReconnectDelay = i11;
        this.reportToken = str2;
        this.reportUrl = str3;
        this.reportServerAddress = str4;
        this.appData = str5;
        this.sniRequiredServers = list2;
        this.streamerConfig = str6;
    }

    public final String getAppData() {
        return this.appData;
    }

    public final String getReportServerAddress() {
        return this.reportServerAddress;
    }

    public final String getReportToken() {
        return this.reportToken;
    }

    public final String getReportUrl() {
        return this.reportUrl;
    }

    public final int getSignalReconnectDelay() {
        return this.signalReconnectDelay;
    }

    public final String[] getSignalServers() {
        return (String[]) this.signalServers.toArray(new String[0]);
    }

    public final String[] getSniRequiredServers() {
        return (String[]) this.sniRequiredServers.toArray(new String[0]);
    }

    public final String getStreamerConfig() {
        return this.streamerConfig;
    }

    public final int getTimeout() {
        return this.timeout;
    }

    public final String getToken() {
        return this.token;
    }

    public String toString() {
        return "token:" + this.token + ", signalServers:" + this.signalServers + ",appData:" + this.appData;
    }


}
