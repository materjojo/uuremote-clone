#include "gvpb.h"

#include <algorithm>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

static std::vector<uint8_t> kcpAtoB;
static void onA(void *, const uint8_t *d, size_t n) { kcpAtoB.assign(d, d + n); }
static std::vector<uint8_t> kcpBtoA;
static void onB(void *, const uint8_t *d, size_t n) { kcpBtoA.assign(d, d + n); }
static std::vector<uint8_t> received;
static void onRecv(void *, const uint8_t *d, size_t n) { received.assign(d, d + n); }

int main() {
    // 1. protobuf 往返
    gvpb_msg *m = gvpb_new();
    gvpb_set_varint(m, 1, 42);
    gvpb_set_string(m, 9, "mac");
    gvpb_set_bytes(m, 20, "\x01\x02", 2);
    uint8_t buf[256];
    size_t n = gvpb_encode(m, buf, sizeof(buf));
    assert(n > 0);
    gvpb_msg *d = gvpb_decode(buf, n);
    uint64_t v = 0;
    assert(gvpb_varint(d, 1, &v) == 0 && v == 42);
    char s[16] = {0};
    assert(gvpb_string(d, 9, s, sizeof(s)) == 3 && std::strcmp(s, "mac") == 0);
    assert(gvpb_count(d) == 3);
    gvpb_free(m);
    gvpb_free(d);

    // 2. schema（来自官方 descriptor）
    assert(gvpb_schema_message_count() == 179);
    assert(gvpb_schema_number("ScreenResolution", "width") == 1);
    assert(gvpb_schema_number("MumuSetting.MapKeyValueEntry", "value") == 2);
    assert(gvpb_schema_number("Message", "input_event") == 20);
    assert(std::strcmp(gvpb_schema_name("Message", 20), "input_event") == 0);
    assert(gvpb_schema_number("ConnectOptions", "decoder_cap_list") == 4);

    // 3. KCP 往返
    gvpb_kcp *a = gvpb_kcp_new(7);
    gvpb_kcp *b = gvpb_kcp_new(7);
    gvpb_kcp_set_output(a, onA, nullptr);
    gvpb_kcp_set_output(b, onB, nullptr);
    gvpb_kcp_set_callback(b, onRecv, nullptr);
    const char *hello = "hello-kcp";
    gvpb_kcp_send(a, (const uint8_t *)hello, std::strlen(hello));
    assert(!kcpAtoB.empty());
    gvpb_kcp_input(b, kcpAtoB.data(), kcpAtoB.size());
    assert(received.size() == std::strlen(hello));
    assert(std::memcmp(received.data(), hello, received.size()) == 0);
    gvpb_kcp_free(a);
    gvpb_kcp_free(b);

    // 4. RS(4,2) 丢两片恢复
    const int k = 4, mm = 2, sz = 8;
    std::vector<std::vector<uint8_t>> shards(k + mm, std::vector<uint8_t>(sz));
    for (int i = 0; i < k; ++i)
        for (int j = 0; j < sz; ++j) shards[i][j] = uint8_t(i * 16 + j);
    std::vector<uint8_t *> ptrs(k + mm);
    for (int i = 0; i < k + mm; ++i) ptrs[i] = shards[i].data();
    std::vector<uint8_t> parity0(sz), parity1(sz);
    const uint8_t *dataPtrs[4] = {shards[0].data(), shards[1].data(), shards[2].data(), shards[3].data()};
    uint8_t *parity[2] = {parity0.data(), parity1.data()};
    assert(gvpb_rs_encode(dataPtrs, k, mm, sz, parity) == 0);

    std::vector<std::vector<uint8_t>> origin(k, std::vector<uint8_t>(sz));
    for (int i = 0; i < k; ++i) origin[i] = shards[i];
    std::memcpy(ptrs[4], parity0.data(), sz);
    std::memcpy(ptrs[5], parity1.data(), sz);
    // 丢掉 0 和 2
    std::fill(shards[0].begin(), shards[0].end(), 0);
    std::fill(shards[2].begin(), shards[2].end(), 0);
    int present[6] = {0, 1, 0, 1, 1, 1};
    assert(gvpb_rs_decode(ptrs.data(), present, k, mm, sz) == 0);
    for (int i = 0; i < k; ++i) assert(shards[i] == origin[i]);

    std::printf("gvpb core tests passed (messages=%d)\n", gvpb_schema_message_count());
    return 0;
}
