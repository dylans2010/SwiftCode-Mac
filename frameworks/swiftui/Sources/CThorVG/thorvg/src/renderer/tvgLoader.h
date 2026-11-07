#ifndef _TVG_LOADER_H_
#define _TVG_LOADER_H_

#include <atomic>
#include "tvgCommon.h"
#include "tvgRender.h"
#include "tvgInlist.h"
#include "tvgStr.h"
#include "tvgAccessor.h"

namespace tvg
{

struct AssetResolver
{
    std::function<bool(Paint* paint, const char* src, void* data)> func;
    void* data;
};

enum struct Ownership : uint8_t
{
    Borrow,
    Copy,
    Transfer
};

struct LoaderOps
{
    Type caller;
    Ownership owner;
};

struct PictureOps : LoaderOps
{
    AssetResolver* resolver;
    const char* rpath;
    bool accessible;

    PictureOps(Ownership owner, AssetResolver* resolver, const char* rpath, bool accessible) :
        LoaderOps{Type::Picture, owner}, resolver(resolver), rpath(rpath), accessible(accessible) {}
};

struct Loader
{
    INLIST_ITEM(Loader);

    uintptr_t hashkey = 0;
    char* hashpath = nullptr;

    FileType type;
    atomic<uint16_t> sharing{};
    Ownership owner = Ownership::Borrow;
    bool readied = false;
    bool cached = false;

    Loader(FileType type) : type(type) {}

    virtual ~Loader()
    {
        tvg::free(hashpath);
    }

    bool allowCache()
    {
        if (type == FileType::Lot) return false;
        if (type == FileType::Gif) return false;
        if (type == FileType::Media) return false;

        return true;
    }

    bool cache(uintptr_t data)
    {
        if (!allowCache()) return false;
        hashkey = data;
        cached = true;
        return true;
    }

    bool cache(const char* path)
    {
        if (!allowCache()) return false;

        hashpath = tvg::duplicate(path);
        cached = true;
        return true;
    }

    virtual Result open(const char* path, const LoaderOps& ops) { return Result::NonSupport; }
    virtual Result open(const char* data, uint32_t size, const LoaderOps& ops) { return Result::NonSupport; }
    virtual bool resize(Paint* paint, float w, float h) { return false; }
    virtual bool sync() { return false; };

    virtual bool read()
    {
        if (readied) return false;
        readied = true;
        return true;
    }

    virtual bool close()
    {
        if (sharing == 0) return true;
        --sharing;
        return false;
    }

    char* open(const char* path, uint32_t& size, bool text = false)
    {
#ifdef THORVG_FILE_IO_SUPPORT
        auto f = fopen(path, text ? "r" : "rb");
        if (!f) return nullptr;

        fseek(f, 0, SEEK_END);

        size = ftell(f);
        if (size == 0) {
            fclose(f);
            return nullptr;
        }

        auto content = tvg::malloc<char>(sizeof(char) * (text ? size + 1 : size));
        fseek(f, 0, SEEK_SET);
        size = fread(content, sizeof(char), size, f);
        if (text) content[size] = '\0';

        fclose(f);

        return content;
#endif
        return nullptr;
    }
};

struct ImageLoader : Loader
{
    float w = 0, h = 0;
    bool playable;

    ImageLoader(FileType type, bool playable = false) : Loader(type), playable(playable) {}

    virtual const AccessorEntity* access(uint32_t id) { return nullptr; }
    virtual void access(AccessorCallback& cb) {}
    virtual Paint* paint() { return nullptr; }
    virtual RenderSurface* bitmap() { return nullptr; }
};

struct BitmapLoader : ImageLoader
{
    static atomic<ColorSpace> cs;

    RenderSurface surface;

    BitmapLoader(FileType type, bool playable = false) : ImageLoader(type, playable) {}

    RenderSurface* bitmap() override
    {
        return surface.data ? &surface : nullptr;
    }
};

struct AnimLoader : ImageLoader
{
    float segmentBegin = 0.0f;
    float segmentEnd;

    AnimLoader(FileType type) : ImageLoader(type, true) {}
    virtual ~AnimLoader() {}

    virtual bool frame(float no) = 0;
    virtual float totalFrame() = 0;
    virtual float curFrame() = 0;
    virtual float duration() = 0;
    virtual Result segment(float begin, float end) = 0;

    void segment(float* begin, float* end)
    {
        if (begin) *begin = segmentBegin;
        if (end) *end = segmentEnd;
    }
};

struct FontMetrics
{
    Point size;
    float scale;
    Point align{}, box{}, spacing{1.0f, 1.0f};
    float fontSize = 0.0f;
    uint32_t lines = 1;
    TextWrap wrap = TextWrap::None;

    void* engine = nullptr;

    ~FontMetrics()
    {
        tvg::free(engine);
    }
};

struct FontLoader : Loader
{
    static constexpr const float DPI = 96.0f / 72.0f;

    char* name = nullptr;

    FontLoader(FileType type) : Loader(type) {}

    using Loader::read;

    virtual bool get(FontMetrics& fm, char* text, uint32_t len, RenderPath& out) = 0;
    virtual void transform(Paint* paint, FontMetrics& fm, float italicShear) = 0;
    virtual void release(FontMetrics& fm) = 0;
    virtual void metrics(const FontMetrics& fm, TextMetrics& out) = 0;
    virtual bool metrics(const FontMetrics& fm, const char* ch, GlyphMetrics& out, const char** next) = 0;
    virtual void copy(const FontMetrics& in, FontMetrics& out) = 0;
};
}

#endif
