#ifndef GVPB_H
#define GVPB_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---------- protobuf 动态消息 ---------- */
typedef struct gvpb_msg gvpb_msg;

gvpb_msg *gvpb_new(void);
void gvpb_free(gvpb_msg *m);

int gvpb_set_varint(gvpb_msg *m, int field, uint64_t value);
int gvpb_set_fixed32(gvpb_msg *m, int field, uint32_t value);
int gvpb_set_fixed64(gvpb_msg *m, int field, uint64_t value);
int gvpb_set_bytes(gvpb_msg *m, int field, const void *data, size_t len);
int gvpb_set_string(gvpb_msg *m, int field, const char *s);
int gvpb_add_bytes(gvpb_msg *m, int field, const void *data, size_t len);

size_t gvpb_encode(const gvpb_msg *m, uint8_t *out, size_t cap);
gvpb_msg *gvpb_decode(const uint8_t *data, size_t len);

int gvpb_count(const gvpb_msg *m);
int gvpb_field_at(const gvpb_msg *m, int index, int *field, int *wire);
int gvpb_varint(const gvpb_msg *m, int field, uint64_t *out);
int gvpb_float(const gvpb_msg *m, int field, float *out);
int gvpb_double(const gvpb_msg *m, int field, double *out);
int gvpb_string(const gvpb_msg *m, int field, char *out, size_t cap);

/* ---------- 协议 schema（由官方 FileDescriptorProto 生成） ---------- */
const char *gvpb_schema_name(const char *message, int field);
int gvpb_schema_number(const char *message, const char *name);
int gvpb_schema_message_count(void);

/* ---------- KCP ---------- */
typedef void (*gvpb_output_fn)(void *ctx, const uint8_t *data, size_t len);

typedef struct gvpb_kcp gvpb_kcp;

gvpb_kcp *gvpb_kcp_new(uint32_t conv);
void gvpb_kcp_free(gvpb_kcp *k);
void gvpb_kcp_set_output(gvpb_kcp *k, gvpb_output_fn fn, void *ctx);
void gvpb_kcp_set_callback(gvpb_kcp *k, gvpb_output_fn fn, void *ctx);
int gvpb_kcp_send(gvpb_kcp *k, const uint8_t *data, size_t len);
int gvpb_kcp_input(gvpb_kcp *k, const uint8_t *data, size_t len);
void gvpb_kcp_update(gvpb_kcp *k, uint32_t now_ms);

/* ---------- Reed-Solomon ---------- */
int gvpb_rs_encode(const uint8_t *const *shards, int k, int m, int shard_size, uint8_t **parity);
int gvpb_rs_decode(uint8_t **shards, const int *present, int k, int m, int shard_size);

#ifdef __cplusplus
}
#endif

#endif
