#ifndef YDL_FORMAT_H
#define YDL_FORMAT_H

#include <stddef.h>
#include <stdint.h>

#include "yc_macho.h"

uint64_t ydl_uleb(const uint8_t **p, const uint8_t *end, int *bad);
int64_t ydl_sleb(const uint8_t **p, const uint8_t *end, int *bad);

struct ydl_export {
    uint64_t flags;
    uint64_t value;
    uint64_t resolver;
    uint64_t reexport_ordinal;
    const char *import_name;
};

int ydl_trie_find(const uint8_t *trie, size_t size, const char *name, struct ydl_export *out);

struct ydl_import {
    int32_t ordinal;
    int weak;
    const char *name;
    int64_t addend;
};

int64_t ydl_chained_import_count(const uint8_t *blob, size_t size);
int ydl_chained_import(const uint8_t *blob, size_t size, uint32_t index, struct ydl_import *out);

int64_t ydl_chained_apply(const uint8_t *blob, size_t size, uint8_t *load_address, uint64_t preferred_base,
                          const uint64_t *targets, uint32_t ntargets, const char **why);

struct ydl_classic_bind {
    int32_t ordinal;
    int weak;
    const char *name;
    int64_t addend;
    uint64_t *location;
};
typedef int (*ydl_bind_fn)(void *context, const struct ydl_classic_bind *bind);

int64_t ydl_rebase_apply(const uint8_t *opcodes, size_t size, const uint64_t *segment_addresses,
                         const uint64_t *segment_sizes, uint32_t nsegments, uint64_t slide, const char **why);
int64_t ydl_bind_walk(const uint8_t *opcodes, size_t size, const uint64_t *segment_addresses,
                      const uint64_t *segment_sizes, uint32_t nsegments, int lazy, ydl_bind_fn fn, void *context,
                      const char **why);

int ydl_strcmp(const char *a, const char *b);
size_t ydl_strlen(const char *s);

#endif
