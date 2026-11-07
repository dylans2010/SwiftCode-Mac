#include "tvgAccessor.h"
#include "tvgCompressor.h"
#include "tvgPicture.h"

#define IMPL static_cast<AccessorImpl*>(this)

Accessor::Accessor() = default;

struct AccessorImpl : Accessor
{
    Paint* paint;
    AccessorCallback cb;
    bool accessible = false;

    bool access(AccessorIterator* it)
    {
        while (auto child = it->next()) {
            if (!cb.func(child, cb.data)) return false;

            if (auto it2 = AccessorIterator::iterator(child)) {
                if (!access(it2)) {
                    delete (it2);
                    return false;
                }
                delete(it2);
            }
        }
        return true;
    }

    void search()
    {
        if (!cb.func(paint, cb.data)) return;

        if (auto it = AccessorIterator::iterator(paint)) {
            access(it);
            delete (it);
        }
    }
};

Result Accessor::set(Paint* paint, function<bool(const Paint* paint, void* data)> func, void* data) noexcept
{
    if (paint && func) {
        IMPL->paint = paint;
        IMPL->cb = {func, data};
        IMPL->accessible = (paint->type() == Type::Picture && static_cast<Picture*>(paint)->accessible);

        paint->ref();

        if (IMPL->accessible) to<PictureImpl>(IMPL->paint)->access(IMPL->cb);
        else IMPL->search();

        paint->unref(false);

        IMPL->accessible = false;

        return Result::Success;
    }
    return Result::InvalidArguments;
}

const char* Accessor::name(uint32_t id) noexcept
{
    if (IMPL->accessible) {
        auto entity = to<PictureImpl>(IMPL->paint)->access(id);
        if (entity) return entity->name;
    } else TVGLOG("RENDERER", "Did you enable Picture::accessible?");
    return nullptr;
}

uint32_t Accessor::id(const char* name) noexcept
{
    return djb2Encode(name);
}

Accessor* Accessor::gen() noexcept
{
    return new AccessorImpl;
}
