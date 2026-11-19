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

    public StreamerRoomConfig(String token, List<String> signalServers, int timeout, int signalReconnectDelay,
                              String reportToken, String reportUrl, String reportServerAddress,
                              String streamerConfig, List<String> sniRequiredServers, String appData) {
        this.token = token; this.signalServers = signalServers; this.timeout = timeout;
        this.signalReconnectDelay = signalReconnectDelay; this.reportToken = reportToken;
        this.reportUrl = reportUrl; this.reportServerAddress = reportServerAddress;
        this.streamerConfig = streamerConfig; this.sniRequiredServers = sniRequiredServers;
        this.appData = appData;
    }
    public String getAppData() { return appData; }
    public String getReportServerAddress() { return reportServerAddress; }
    public String getReportToken() { return reportToken; }
    public String getReportUrl() { return reportUrl; }
    public int getSignalReconnectDelay() { return signalReconnectDelay; }
    public List<String> getSignalServers() { return signalServers; }
    public List<String> getSniRequiredServers() { return sniRequiredServers; }
    public String getStreamerConfig() { return streamerConfig; }
    public int getTimeout() { return timeout; }
    public String getToken() { return token; }
}
