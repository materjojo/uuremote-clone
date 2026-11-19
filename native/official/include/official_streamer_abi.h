#ifndef UU_OFFICIAL_STREAMER_ABI_H
#define UU_OFFICIAL_STREAMER_ABI_H
#include <stddef.h>

#if defined(_WIN32)
#define UU_ABI_EXPORT __declspec(dllexport)
#else
#define UU_ABI_EXPORT __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif

typedef struct uu_official_library uu_official_library;
enum uu_official_role { UU_CONTROLLER = 0, UU_CONTROLLED = 1 };

/* Inspection only: no Initialize, room, capture, or network operation is run.
 * The private media libraries expose global callback registries. This interface
 * installs empty callbacks and must not be used alongside an active session.
 * absolute_path must identify the supplied 4.48.1 desktop library. */
UU_ABI_EXPORT uu_official_library *uu_official_open(const char *absolute_path,
    int role, char *error, size_t error_capacity);
/* Copies the library-owned UTF-8 version bytes; never frees the original string.
 * Returns 0 on success, negative on a bridge error, or a native error code. */
UU_ABI_EXPORT int uu_official_version(uu_official_library *library,
    char *output, size_t capacity);
UU_ABI_EXPORT void uu_official_close(uu_official_library *library);
#ifdef __cplusplus
}
#endif
#endif
