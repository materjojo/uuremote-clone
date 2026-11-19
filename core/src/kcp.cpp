#include "gvpb.h"

#include <algorithm>
#include <cstring>
#include <deque>
#include <map>
#include <vector>

struct Seg {
    uint8_t cmd = 81;
    uint8_t frg = 0;
    uint32_t sn = 0;
    uint32_t ts = 0;
    uint32_t una = 0;
    std::vector<uint8_t> data;
};

struct gvpb_kcp {
    uint32_t conv = 0;
    uint32_t snd_una = 0;
    uint32_t snd_nxt = 0;
    uint32_t rcv_nxt = 0;
    uint32_t mtu = 1200;
    uint32_t rto = 200;
    std::deque<Seg> queue;
    std::map<uint32_t, Seg> snd_buf;
    std::map<uint32_t, uint32_t> sent_at;
    std::map<uint32_t, std::vector<uint8_t>> rcv_buf;
    std::vector<uint32_t> acks;
    uint32_t last_ack_ms = 0;
    gvpb_output_fn out = nullptr;
    void *out_ctx = nullptr;
    gvpb_output_fn cb = nullptr;
    void *cb_ctx = nullptr;
};

static void put_varint(std::vector<uint8_t> &o, uint64_t v) {
    do {
        uint8_t b = uint8_t(v & 0x7f);
        v >>= 7;
        if (v) b |= 0x80;
        o.push_back(b);
    } while (v);
}

static bool get_varint(const uint8_t *d, size_t n, size_t &i, uint64_t &v) {
    v = 0;
    int s = 0;
    while (i < n) {
        uint8_t b = d[i++];
        v |= uint64_t(b & 0x7f) << s;
        if (!(b & 0x80)) return true;
        s += 7;
        if (s > 63) return false;
    }
    return false;
}

static void put32(std::vector<uint8_t> &o, uint32_t v) {
    for (int i = 0; i < 4; ++i) o.push_back(uint8_t(v >> (8 * i)));
}

static uint32_t get32(const uint8_t *d) {
    return uint32_t(d[0]) | uint32_t(d[1]) << 8 | uint32_t(d[2]) << 16 | uint32_t(d[3]) << 24;
}

static std::vector<uint8_t> encode(const gvpb_kcp *k, const Seg &s) {
    std::vector<uint8_t> o;
    o.reserve(24 + s.data.size());
    put32(o, k->conv);
    o.push_back(s.cmd);
    o.push_back(s.frg);
    o.push_back(0xff);
    o.push_back(0xff);
    put32(o, s.ts);
    put32(o, s.sn);
    put32(o, s.una);
    put32(o, uint32_t(s.data.size()));
    o.insert(o.end(), s.data.begin(), s.data.end());
    return o;
}

static void emit(gvpb_kcp *k, const Seg &s) {
    if (!k->out) return;
    auto pkt = encode(k, s);
    k->out(k->out_ctx, pkt.data(), pkt.size());
}

static void flush_acks(gvpb_kcp *k, uint32_t now) {
    if (k->acks.empty()) return;
    Seg s;
    s.cmd = 82;
    s.sn = k->rcv_nxt;
    s.ts = now;
    s.una = k->rcv_nxt;
    for (uint32_t a : k->acks) {
        put32(s.data, a);
    }
    k->acks.clear();
    k->last_ack_ms = now;
    emit(k, s);
}

gvpb_kcp *gvpb_kcp_new(uint32_t conv) {
    auto *k = new gvpb_kcp();
    k->conv = conv;
    return k;
}

void gvpb_kcp_free(gvpb_kcp *k) { delete k; }

void gvpb_kcp_set_output(gvpb_kcp *k, gvpb_output_fn fn, void *ctx) {
    if (!k) return;
    k->out = fn;
    k->out_ctx = ctx;
}

void gvpb_kcp_set_callback(gvpb_kcp *k, gvpb_output_fn fn, void *ctx) {
    if (!k) return;
    k->cb = fn;
    k->cb_ctx = ctx;
}

int gvpb_kcp_send(gvpb_kcp *k, const uint8_t *data, size_t len) {
    if (!k) return -1;
    size_t chunk = k->mtu - 24;
    size_t offset = 0;
    if (len == 0) {
        Seg s;
        k->queue.push_back(s);
    }
    while (offset < len) {
        size_t n = std::min(chunk, len - offset);
        Seg s;
        s.data.assign(data + offset, data + offset + n);
        s.frg = (offset + n >= len) ? 0 : 1;
        k->queue.push_back(std::move(s));
        offset += n;
    }
    // 立即发送
    uint32_t now = 0;
    (void)now;
    for (auto &s : k->queue) {
        s.sn = k->snd_nxt++;
        s.una = k->rcv_nxt;
        k->snd_buf[s.sn] = s;
        k->sent_at[s.sn] = 0;
        emit(k, s);
    }
    k->queue.clear();
    return 0;
}

int gvpb_kcp_input(gvpb_kcp *k, const uint8_t *data, size_t len) {
    if (!k || !data || len < 24) return -1;
    if (get32(data) != k->conv) return -1;
    uint8_t cmd = data[4];
    uint32_t sn = get32(data + 12);
    uint32_t una = get32(data + 16);
    uint32_t n = get32(data + 20);
    if (len < 24 + n) return -1;

    if (una > k->snd_una) {
        for (uint32_t s = k->snd_una; s < una; ++s) {
            k->snd_buf.erase(s);
            k->sent_at.erase(s);
        }
        k->snd_una = una;
    }

    if (cmd == 81) {
        std::vector<uint8_t> body(data + 24, data + 24 + n);
        if (sn == k->rcv_nxt) {
            if (!body.empty() && k->cb) k->cb(k->cb_ctx, body.data(), body.size());
            k->rcv_nxt++;
            while (true) {
                auto it = k->rcv_buf.find(k->rcv_nxt);
                if (it == k->rcv_buf.end()) break;
                if (!it->second.empty() && k->cb) k->cb(k->cb_ctx, it->second.data(), it->second.size());
                k->rcv_buf.erase(it);
                k->rcv_nxt++;
            }
        } else if (sn > k->rcv_nxt && k->rcv_buf.size() < 512) {
            k->rcv_buf[sn] = std::move(body);
        }
        k->acks.push_back(sn);
    } else if (cmd == 82) {
        for (uint32_t i = 0; i + 4 <= n; i += 4) {
            uint32_t a = get32(data + 24 + i);
            if (a >= k->snd_una) k->snd_buf.erase(a);
        }
    }
    return 0;
}

void gvpb_kcp_update(gvpb_kcp *k, uint32_t now_ms) {
    if (!k) return;
    for (auto &kv : k->snd_buf) {
        auto &t = k->sent_at[kv.first];
        if (t == 0) { t = now_ms; continue; }
        if (now_ms - t > k->rto) {
            Seg s = kv.second;
            s.ts = now_ms;
            s.una = k->rcv_nxt;
            t = now_ms;
            emit(k, s);
            k->rto = std::min<uint32_t>(k->rto * 2, 3000);
        }
    }
    if (!k->acks.empty() && now_ms - k->last_ack_ms > 20) {
        flush_acks(k, now_ms);
    }
}
