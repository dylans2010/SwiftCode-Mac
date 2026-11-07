#include "config.h"
#include <cmath>
#include "tvgCommon.h"
#include "tvgMath.h"
#include "tvgStr.h"

static inline bool _floatExact(float a, float b)
{
    return memcmp(&a, &b, sizeof(float)) == 0;
}

namespace tvg {

float toFloat(const char *str, char **end)
{
    if (end) *end = (char *) (str);
    if (!str) return 0.0f;

    auto a = str;
    auto iter = str;
    auto val = 0.0f;
    unsigned long long integerPart = 0;
    int minus = 1;

    while (isspace(*iter)) iter++;

    if (*iter == '-') {
        minus = -1;
        iter++;
    } else if (*iter == '+') {
        iter++;
    }

    if (tolower(*iter) == 'i') {
        if ((tolower(*(iter + 1)) == 'n') && (tolower(*(iter + 2)) == 'f')) iter += 3;
        else goto error;

        if (tolower(*(iter)) == 'i') {
            if ((tolower(*(iter + 1)) == 'n') && (tolower(*(iter + 2)) == 'i') && (tolower(*(iter + 3)) == 't') &&
                (tolower(*(iter + 4)) == 'y'))
                iter += 5;
            else goto error;
        }
        if (end) *end = (char *) (iter);
        return (minus == -1) ? -INFINITY : INFINITY;
    }

    if (tolower(*iter) == 'n') {
        if ((tolower(*(iter + 1)) == 'a') && (tolower(*(iter + 2)) == 'n')) iter += 3;
        else goto error;

        if (end) *end = (char *) (iter);
        return (minus == -1) ? -NAN : NAN;
    }

    if (isdigit(*iter)) {
        for (; isdigit(*iter); iter++) {
            integerPart = integerPart * 10ULL + (unsigned long long) (*iter - '0');
        }
        a = iter;
    } else if (*iter != '.') {
        goto success;
    }

    val = static_cast<float>(integerPart);

    if (*iter == '.') {
        unsigned long long decimalPart = 0;
        unsigned long long pow10 = 1;
        int count = 0;

        iter++;

        if (isdigit(*iter)) {
            for (; isdigit(*iter); iter++, count++) {
                if (count < 19) {
                    decimalPart = decimalPart * 10ULL + +static_cast<unsigned long long>(*iter - '0');
                    pow10 *= 10ULL;
                }
            }
        } else if (isspace(*iter)) {
            a = iter;
            goto success;
        }

        val += static_cast<float>(decimalPart) / static_cast<float>(pow10);
        a = iter;
    }

    if (*iter == 'e' || *iter == 'E') {
        ++iter;

        if ((*iter == 'm') || (*iter == 'M')) {
            a = iter + 1;
            goto success;
        }

        int minus_e = 1;

        if (*iter == '-') {
            minus_e = -1;
            ++iter;
        } else if (*iter == '+') {
            iter++;
        }

        unsigned int exponentPart = 0;

        if (isdigit(*iter)) {
            while (*iter == '0') iter++;
            for (; isdigit(*iter); iter++) {
                exponentPart = exponentPart * 10U + static_cast<unsigned int>(*iter - '0');
            }
        } else if (!isdigit(*(a - 1))) {
            a = str;
            goto success;
        } else if (*iter == 0) {
            goto success;
        }

        if ((_floatExact(val, 1.175494351f)) && ((minus_e * static_cast<int>(exponentPart)) <= -38)) {
            val *= 1.0e-38f;
            a = iter;
            goto success;
        }

        a = iter;
        auto scale = 1.0f;

        while (exponentPart >= 8U) {
            scale *= 1E8f;
            exponentPart -= 8U;
        }
        while (exponentPart > 0U) {
            scale *= 10.0f;
            exponentPart--;
        }
        val = (minus_e == -1) ? (val / scale) : (val * scale);
    } else if ((iter > str) && !isdigit(*(iter - 1))) {
        a = str;
        goto success;
    }

success:
    if (end) *end = (char *)a;
    if (!std::isfinite(val)) return 0.0f;

    return minus * val;

error:
    if (end) *end = (char *)str;
    return 0.0f;
}

char* duplicate(const char* str, size_t max, uint32_t* size)
{
    if (!str) {
        if (size) *size = 0;
        return nullptr;
    }

    auto len = strlen(str);
    if (len < max) max = len;

    auto ret = tvg::malloc<char>(max + 1);
    ret[max] = '\0';

    if (size) *size = max;

    return (char*)memcpy(ret, str, max);
}

char* append(char* lhs, const char* rhs, size_t n)
{
    if (!rhs) return lhs;
    if (!lhs) return duplicate(rhs, n);
    lhs = tvg::realloc<char>(lhs, strlen(lhs) + n + 1);
    return strncat(lhs, rhs, n);
}

char* dirname(const char* path)
{
    auto ptr = strrchr(path, '/');
#ifdef _WIN32
    auto ptr2 = strrchr(ptr ? ptr : path, '\\');
    if (ptr2) ptr = ptr2;
#endif
    auto len = ptr ? size_t(ptr - path + 1) : SIZE_MAX;
    return duplicate(path, len);
}

char* filename(const char* path)
{
    const char* ptr = strrchr(path, '/');
#ifdef _WIN32
    auto ptr2 = strrchr(ptr ? ptr : path, '\\');
    if (ptr2) ptr = ptr2;
#endif
    if (ptr) ++ptr;
    else ptr = path;
    auto dot = fileext(ptr);
    auto len = (dot > ptr) ? (size_t)(dot - ptr - 1) : strlen(ptr);
    return duplicate(ptr, len);
}

const char* fileext(const char* path)
{
    auto ext = path;
    while (ext) {
        auto p = strchr(ext, '.');
        if (!p) break;
        ext = p + 1;
    }
    return ext;
}

char* concat(const char* a, const char* b)
{
    auto len = strlen(a) + strlen(b) + 1;
    auto ret = tvg::malloc<char>(len * sizeof(char));
    strcpy(ret, a);
    strcat(ret, b);
    return ret;
}

}
