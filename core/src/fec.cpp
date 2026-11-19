#include "gvpb.h"

#include <cstring>
#include <vector>

namespace {
struct GF {
    uint8_t exp[512];
    uint8_t log[256];
    GF() {
        std::memset(exp, 0, sizeof(exp));
        std::memset(log, 0, sizeof(log));
        unsigned x = 1;
        for (int i = 0; i < 255; ++i) {
            exp[i] = uint8_t(x);
            log[x] = uint8_t(i);
            x <<= 1;
            if (x & 0x100) x ^= 0x11d;
        }
        for (int i = 255; i < 512; ++i) exp[i] = exp[i - 255];
    }
    uint8_t mul(uint8_t a, uint8_t b) const {
        if (!a || !b) return 0;
        return exp[int(log[a]) + int(log[b])];
    }
    uint8_t div(uint8_t a, uint8_t b) const {
        if (!a || !b) return 0;
        int d = int(log[a]) - int(log[b]) + 255;
        return exp[d % 255];
    }
    uint8_t pow(uint8_t a, int p) const {
        uint8_t r = 1;
        for (int i = 0; i < p; ++i) r = mul(r, a);
        return r;
    }
};
const GF gf;

bool invert(std::vector<std::vector<uint8_t>> &a, std::vector<std::vector<uint8_t>> &inv) {
    int n = int(a.size());
    for (int col = 0; col < n; ++col) {
        int piv = -1;
        for (int r = col; r < n; ++r) if (a[r][col]) { piv = r; break; }
        if (piv < 0) return false;
        if (piv != col) { std::swap(a[piv], a[col]); std::swap(inv[piv], inv[col]); }
        uint8_t pv = a[col][col];
        uint8_t ip = gf.div(1, pv);
        for (int c = 0; c < n; ++c) {
            a[col][c] = gf.mul(a[col][c], ip);
            inv[col][c] = gf.mul(inv[col][c], ip);
        }
        for (int r = 0; r < n; ++r) {
            if (r == col) continue;
            uint8_t f = a[r][col];
            if (!f) continue;
            for (int c = 0; c < n; ++c) {
                a[r][c] ^= gf.mul(a[col][c], f);
                inv[r][c] ^= gf.mul(inv[col][c], f);
            }
        }
    }
    return true;
}
}

int gvpb_rs_encode(const uint8_t *const *shards, int k, int m, int shard_size, uint8_t **parity) {
    if (!shards || k <= 0 || m <= 0 || shard_size < 0 || !parity) return -1;
    for (int p = 0; p < m; ++p) {
        if (!parity[p]) return -1;
        std::memset(parity[p], 0, size_t(shard_size));
        for (int j = 0; j < k; ++j) {
            uint8_t coef = gf.pow(uint8_t(j + 1), p);
            if (!coef) continue;
            for (int i = 0; i < shard_size; ++i) {
                parity[p][i] ^= gf.mul(shards[j][i], coef);
            }
        }
    }
    return 0;
}

int gvpb_rs_decode(uint8_t **shards, const int *present, int k, int m, int shard_size) {
    if (!shards || !present || k <= 0) return -1;
    int have = 0;
    for (int i = 0; i < k + m; ++i) if (present[i]) have++;
    if (have < k) return -1;

    std::vector<int> idx;
    for (int i = 0; i < k + m && int(idx.size()) < k; ++i) if (present[i]) idx.push_back(i);
    if (int(idx.size()) < k) return -1;

    std::vector<std::vector<uint8_t>> rows(k, std::vector<uint8_t>(k, 0));
    for (int r = 0; r < k; ++r) {
        int index = idx[r];
        if (index < k) rows[r][index] = 1;
        else for (int c = 0; c < k; ++c) rows[r][c] = gf.pow(uint8_t(c + 1), index - k);
    }
    std::vector<std::vector<uint8_t>> inv(k, std::vector<uint8_t>(k, 0));
    for (int i = 0; i < k; ++i) inv[i][i] = 1;
    if (!invert(rows, inv)) return -1;

    std::vector<std::vector<uint8_t>> in(k, std::vector<uint8_t>(shard_size, 0));
    for (int r = 0; r < k; ++r) {
        int index = idx[r];
        if (shards[index]) std::memcpy(in[r].data(), shards[index], size_t(shard_size));
    }
    for (int i = 0; i < k; ++i) {
        std::vector<uint8_t> out(shard_size, 0);
        for (int j = 0; j < k; ++j) {
            uint8_t coef = inv[i][j];
            if (!coef) continue;
            for (int x = 0; x < shard_size; ++x) out[x] ^= gf.mul(in[j][x], coef);
        }
        if (shards[i]) std::memcpy(shards[i], out.data(), size_t(shard_size));
    }
    return 0;
}
