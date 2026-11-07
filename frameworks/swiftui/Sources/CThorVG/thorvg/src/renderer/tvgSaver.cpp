#include <cstring>
#include "tvgCommon.h"
#include "tvgStr.h"
#include "tvgMath.h"
#include "tvgSaveModule.h"

#ifdef THORVG_GIF_SAVER_SUPPORT
    #include "tvgGifSaver.h"
#endif

#define IMPL static_cast<SaverImpl*>(this)

Saver::Saver() = default;

struct SaverImpl : Saver
{
    SaveModule* saveModule = nullptr;
    Paint* bg = nullptr;

    ~SaverImpl()
    {
        delete(saveModule);
        if (bg) bg->unref();
    }
};

static SaveModule* _find(FileType type)
{
    switch(type) {
        case FileType::Gif: {
#ifdef THORVG_GIF_SAVER_SUPPORT
            return new GifSaver;
#endif
            break;
        }
        default: {
            break;
        }
    }

#ifdef THORVG_LOG_ENABLED
    const char *format;
    switch(type) {
        case FileType::Gif: {
            format = "GIF";
            break;
        }
        default: {
            format = "???";
            break;
        }
    }
    TVGLOG("RENDERER", "%s format is not supported", format);
#endif
    return nullptr;
}

static SaveModule* _find(const char* filename)
{
    auto ext = fileext(filename);
    if (ext && !strcmp(ext, "gif")) return _find(FileType::Gif);
    return nullptr;
}

Result Saver::save(Paint* paint, const char* filename, uint32_t quality) noexcept
{
    if (!paint) return Result::InvalidArguments;

    if (IMPL->saveModule) {
        Paint::rel(paint);
        return Result::InsufficientCondition;
    }

    if (auto saveModule = _find(filename)) {
        if (saveModule->save(paint, IMPL->bg, filename, quality)) {
            IMPL->saveModule = saveModule;
            return Result::Success;
        } else {
            Paint::rel(paint);
            delete(saveModule);
            return Result::Unknown;
        }
    }
    Paint::rel(paint);
    return Result::NonSupport;
}

Result Saver::background(Paint* paint) noexcept
{
    if (!paint) return Result::InvalidArguments;

    if (IMPL->bg) IMPL->bg->unref();
    paint->ref();
    IMPL->bg = paint;

    return Result::Success;
}

Result Saver::save(Animation* animation, const char* filename, uint32_t quality, uint32_t fps) noexcept
{
    if (!animation) return Result::InvalidArguments;

    auto remove = animation->picture()->refCnt() <= 1 ? true : false;

    if (tvg::zero(animation->totalFrame())) {
        if (remove) delete(animation);
        return Result::InsufficientCondition;
    }

    if (IMPL->saveModule) {
        if (remove) delete(animation);
        return Result::InsufficientCondition;
    }

    if (auto saveModule = _find(filename)) {
        if (saveModule->save(animation, IMPL->bg, filename, quality, fps)) {
            IMPL->saveModule = saveModule;
            return Result::Success;
        } else {
            if (remove) delete(animation);
            delete(saveModule);
            return Result::Unknown;
        }
    }
    if (remove) delete(animation);
    return Result::NonSupport;
}

Result Saver::sync() noexcept
{
    if (!IMPL->saveModule) return Result::InsufficientCondition;
    IMPL->saveModule->close();
    delete(IMPL->saveModule);
    IMPL->saveModule = nullptr;

    return Result::Success;
}

Saver* Saver::gen() noexcept
{
    return new SaverImpl;
}
