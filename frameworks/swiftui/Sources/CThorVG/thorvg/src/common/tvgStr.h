#ifndef _TVG_STR_H_
#define _TVG_STR_H_

#include "tvgCommon.h"

namespace tvg
{

static inline bool equal(const char* a, const char* b)
{
    return !strcmp(a, b) && strlen(a) == strlen(b);
}

char* concat(const char* a, const char* b);
float toFloat(const char *str, char **end);
char* duplicate(const char* str, size_t max = SIZE_MAX, uint32_t* size = nullptr);
char* append(char* lhs, const char* rhs, size_t n);
char* dirname(const char* path);
char* filename(const char* path);
const char* fileext(const char* path);

}
#endif
