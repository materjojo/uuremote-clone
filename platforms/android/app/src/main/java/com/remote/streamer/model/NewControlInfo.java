// Recovered from the supplied 4.48.1 APK; see analysis/official/android.
package com.remote.streamer.model;


public final class NewControlInfo {
    private final byte[] appData;
    private final String controlId;
    private final String negotiateResult;

    public NewControlInfo(String str, byte[] bArr, String str2) {
        java.util.Objects.requireNonNull(str, "controlId");
        java.util.Objects.requireNonNull(bArr, "appData");
        java.util.Objects.requireNonNull(str2, "negotiateResult");
        this.controlId = str;
        this.appData = bArr;
        this.negotiateResult = str2;
    }

    public final byte[] getAppData() {
        return this.appData;
    }

    public final String getControlId() {
        return this.controlId;
    }

    public final String getNegotiateResult() {
        return this.negotiateResult;
    }
}
