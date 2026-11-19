#include "gvpb.h"

#include <algorithm>
#include <cstring>
#include <map>
#include <vector>

struct FieldValue {
    int wire = 0;
    uint64_t v = 0;
    std::vector<uint8_t> bytes;
};

struct gvpb_msg {
    std::map<int, std::vector<FieldValue>> fields;
};

static void put_varint(std::vector<uint8_t> &out, uint64_t v) {
    do {
        uint8_t b = uint8_t(v & 0x7f);
        v >>= 7;
        if (v) b |= 0x80;
        out.push_back(b);
    } while (v);
}

static bool get_varint(const uint8_t *d, size_t n, size_t &i, uint64_t &v) {
    v = 0;
    int shift = 0;
    while (i < n) {
        uint8_t b = d[i++];
        v |= uint64_t(b & 0x7f) << shift;
        if (!(b & 0x80)) return true;
        shift += 7;
        if (shift > 63) return false;
    }
    return false;
}

gvpb_msg *gvpb_new(void) { return new gvpb_msg(); }
void gvpb_free(gvpb_msg *m) { delete m; }

int gvpb_set_varint(gvpb_msg *m, int field, uint64_t value) {
    if (!m || field <= 0) return -1;
    m->fields[field].clear();
    m->fields[field].push_back({0, value, {}});
    return 0;
}

int gvpb_set_fixed32(gvpb_msg *m, int field, uint32_t value) {
    if (!m || field <= 0) return -1;
    m->fields[field].clear();
    m->fields[field].push_back({5, value, {}});
    return 0;
}

int gvpb_set_fixed64(gvpb_msg *m, int field, uint64_t value) {
    if (!m || field <= 0) return -1;
    m->fields[field].clear();
    m->fields[field].push_back({1, value, {}});
    return 0;
}

int gvpb_set_bytes(gvpb_msg *m, int field, const void *data, size_t len) {
    if (!m || field <= 0) return -1;
    m->fields[field].clear();
    FieldValue fv;
    fv.wire = 2;
    fv.bytes.assign((const uint8_t *)data, (const uint8_t *)data + len);
    m->fields[field].push_back(std::move(fv));
    return 0;
}

int gvpb_set_string(gvpb_msg *m, int field, const char *s) {
    return gvpb_set_bytes(m, field, s, s ? std::strlen(s) : 0);
}

int gvpb_add_bytes(gvpb_msg *m, int field, const void *data, size_t len) {
    if (!m || field <= 0) return -1;
    FieldValue fv;
    fv.wire = 2;
    fv.bytes.assign((const uint8_t *)data, (const uint8_t *)data + len);
    m->fields[field].push_back(std::move(fv));
    return 0;
}

size_t gvpb_encode(const gvpb_msg *m, uint8_t *out, size_t cap) {
    if (!m) return 0;
    std::vector<uint8_t> buf;
    for (const auto &kv : m->fields) {
        for (const auto &fv : kv.second) {
            put_varint(buf, (uint64_t(kv.first) << 3) | uint64_t(fv.wire));
            switch (fv.wire) {
            case 0: put_varint(buf, fv.v); break;
            case 1:
                for (int i = 0; i < 8; ++i) buf.push_back(uint8_t(fv.v >> (8 * i)));
                break;
            case 5:
                for (int i = 0; i < 4; ++i) buf.push_back(uint8_t(fv.v >> (8 * i)));
                break;
            case 2:
                put_varint(buf, fv.bytes.size());
                buf.insert(buf.end(), fv.bytes.begin(), fv.bytes.end());
                break;
            default: break;
            }
        }
    }
    size_t n = std::min(cap, buf.size());
    if (out && n) std::memcpy(out, buf.data(), n);
    return buf.size();
}

gvpb_msg *gvpb_decode(const uint8_t *data, size_t len) {
    if (!data) return nullptr;
    auto *m = new gvpb_msg();
    size_t i = 0;
    while (i < len) {
        uint64_t key = 0;
        if (!get_varint(data, len, i, key)) break;
        int field = int(key >> 3);
        int wire = int(key & 7);
        if (field <= 0) break;
        FieldValue fv;
        fv.wire = wire;
        if (wire == 0) {
            if (!get_varint(data, len, i, fv.v)) break;
        } else if (wire == 1) {
            if (i + 8 > len) break;
            fv.v = 0;
            for (int b = 0; b < 8; ++b) fv.v |= uint64_t(data[i + b]) << (8 * b);
            i += 8;
        } else if (wire == 5) {
            if (i + 4 > len) break;
            fv.v = 0;
            for (int b = 0; b < 4; ++b) fv.v |= uint64_t(data[i + b]) << (8 * b);
            i += 4;
        } else if (wire == 2) {
            uint64_t n = 0;
            if (!get_varint(data, len, i, n)) break;
            if (i + n > len) break;
            fv.bytes.assign(data + i, data + i + n);
            i += size_t(n);
        } else {
            break;
        }
        m->fields[field].push_back(std::move(fv));
    }
    return m;
}

int gvpb_count(const gvpb_msg *m) {
    if (!m) return 0;
    int n = 0;
    for (const auto &kv : m->fields) n += int(kv.second.size());
    return n;
}

int gvpb_field_at(const gvpb_msg *m, int index, int *field, int *wire) {
    if (!m || index < 0) return -1;
    int i = 0;
    for (const auto &kv : m->fields) {
        for (const auto &fv : kv.second) {
            if (i == index) {
                if (field) *field = kv.first;
                if (wire) *wire = fv.wire;
                return 0;
            }
            ++i;
        }
    }
    return -1;
}

int gvpb_varint(const gvpb_msg *m, int field, uint64_t *out) {
    if (!m) return -1;
    auto it = m->fields.find(field);
    if (it == m->fields.end() || it->second.empty() || it->second[0].wire != 0) return -1;
    if (out) *out = it->second[0].v;
    return 0;
}

int gvpb_float(const gvpb_msg *m, int field, float *out) {
    if (!m) return -1;
    auto it = m->fields.find(field);
    if (it == m->fields.end() || it->second.empty() || it->second[0].wire != 5) return -1;
    uint32_t bits = uint32_t(it->second[0].v);
    if (out) std::memcpy(out, &bits, 4);
    return 0;
}

int gvpb_double(const gvpb_msg *m, int field, double *out) {
    if (!m) return -1;
    auto it = m->fields.find(field);
    if (it == m->fields.end() || it->second.empty() || it->second[0].wire != 1) return -1;
    uint64_t bits = it->second[0].v;
    if (out) std::memcpy(out, &bits, 8);
    return 0;
}

int gvpb_string(const gvpb_msg *m, int field, char *out, size_t cap) {
    if (!m) return -1;
    auto it = m->fields.find(field);
    if (it == m->fields.end() || it->second.empty() || it->second[0].wire != 2) return -1;
    const auto &b = it->second[0].bytes;
    size_t n = std::min(cap ? cap - 1 : 0, b.size());
    if (out && n) std::memcpy(out, b.data(), n);
    if (out && cap) out[n] = 0;
    return int(b.size());
}
