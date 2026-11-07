#ifndef _TVG_COMMON_H_
#define _TVG_COMMON_H_

#ifdef _WIN32
    #if defined(WINAPI_ENTRY)
        #if (WINAPI_FAMILY == WINAPI_FAMILY_DESKTOP_APP)
            #include <windows.h>
        #endif
    #elif !defined(APIENTRY) && !defined(__CYGWIN__) && !defined(__SCITECH_SNAP__)
        #include <windows.h>
    #endif
#endif
#include <string>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include "config.h"
#include "thorvg.h"

using namespace std;
using namespace tvg;

#ifdef _MSC_VER
    #define TVG_UNUSED
    #define strncasecmp _strnicmp
    #define strcasecmp _stricmp
    #define strtok_r strtok_s
#else
    #define TVG_UNUSED __attribute__ ((__unused__))
#endif

#if __has_cpp_attribute(fallthrough)
    #ifdef _MSC_VER
        #define TVG_FALLTHROUGH [[fallthrough]];
    #else
        #define TVG_FALLTHROUGH __attribute__ ((fallthrough));
    #endif
#else
    #define TVG_FALLTHROUGH
#endif

void* operator new(std::size_t size);
void operator delete(void* ptr) noexcept;

namespace tvg
{
    enum class FileType
    {
        Svg = 0,
        Lot,
        Sfnt,
        Png,
        Jpg,
        Webp,
        Media,
        Raw,
        Gif,
        Unknown
    };

    #ifdef THORVG_LOG_ENABLED
        constexpr auto ErrorColor = "\033[31m";
        constexpr auto ErrorBgColor = "\033[41m";
        constexpr auto LogColor = "\033[32m";
        constexpr auto LogBgColor = "\033[42m";
        constexpr auto GreyColor = "\033[90m";
        constexpr auto ResetColors = "\033[0m";
        #define TVGERR(tag, fmt, ...) fprintf(stderr, "%s[E]%s %s" tag "%s (%s %d): %s" fmt "\n", ErrorBgColor, ResetColors, ErrorColor, GreyColor, __FILE__, __LINE__, ResetColors, ##__VA_ARGS__)
        #define TVGLOG(tag, fmt, ...) fprintf(stdout, "%s[L]%s %s" tag "%s (%s %d): %s" fmt "\n", LogBgColor, ResetColors, LogColor, GreyColor, __FILE__, __LINE__, ResetColors, ##__VA_ARGS__)
    #else
        #define TVGERR(...) do {} while(0)
        #define TVGLOG(...) do {} while(0)
    #endif

    template<typename T>
    static inline T* to(const Paint* p)
    {
        return static_cast<T*>(const_cast<Paint*>(p));
    }

    uint16_t THORVG_VERSION_NUMBER();

    extern int engineInit;
}

#include "tvgAllocator.h"

#endif
