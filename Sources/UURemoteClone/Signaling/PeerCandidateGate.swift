import Foundation
import WebRTC

/// Stages outgoing ICE disclosure; local interface gathering still belongs to
/// WebRTC. Withhold SDP candidates too, otherwise they bypass this ordering.
final class PeerCandidateGate {
    var emit: ((RTCIceCandidate) -> Void)?
    var connected: (() -> Bool)?
    private var seen = Set<String>()
    private var queued: [Int: [RTCIceCandidate]] = [:]
    private var scheduled = Set<Int>()
    private var released = Set<Int>()
    private var timers: [DispatchWorkItem] = []
    private var closed = false

    func submit(_ value: RTCIceCandidate) {
        guard !closed, seen.insert("\(value.sdpMid ?? ""):\(value.sdpMLineIndex):\(value.sdp)").inserted else { return }
        let stage = PeerNetwork.candidateStage(value.sdp)
        if stage == 0 { emit?(value); return }
        if released.contains(stage) {
            if connected?() != true { emit?(value) }
            return
        }
        queued[stage, default: []].append(value)
        guard scheduled.insert(stage).inserted else { return }
        let timer = DispatchWorkItem { [weak self] in
            guard let self, !self.closed else { return }
            self.released.insert(stage)
            let values = self.queued.removeValue(forKey: stage) ?? []
            for value in values {
                guard !self.closed, self.connected?() != true else { break }
                self.emit?(value)
            }
        }
        timers.append(timer)
        DispatchQueue.main.asyncAfter(deadline: .now() + (stage == 1 ? 1.2 : 8), execute: timer)
    }

    /// Keep all session/media attributes and trickle each embedded candidate
    /// with its own m-line index and MID. Do not edit the local description.
    func signalSDP(_ sdp: String) -> String {
        let lines = sdp.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var media: Int32 = -1
        var mids: [Int32: String] = [:]
        for line in lines {
            if line.hasPrefix("m=") { media += 1 }
            if line.hasPrefix("a=mid:") { mids[media] = String(line.dropFirst(6)) }
        }
        media = -1
        var output: [String] = []
        for line in lines {
            if line.hasPrefix("m=") { media += 1 }
            if line.hasPrefix("a=candidate:") {
                submit(RTCIceCandidate(sdp: String(line.dropFirst(2)), sdpMLineIndex: max(0, media), sdpMid: mids[media]))
            } else if line != "a=end-of-candidates" { output.append(line) }
        }
        return output.joined(separator: "\r\n") + "\r\n"
    }

    func close() {
        closed = true; timers.forEach { $0.cancel() }; timers.removeAll()
        queued.removeAll(); emit = nil; connected = nil
    }
}
