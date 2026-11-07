#include "tvgPaint.h"
#include "tvgPicture.h"

Picture::Picture() = default;

Picture* Picture::gen() noexcept
{
    return new PictureImpl;
}

Type Picture::type() const noexcept
{
    return Type::Picture;
}

Result Picture::load(const char* filename) noexcept
{
    if (!filename) return Result::InvalidArguments;
    return to<PictureImpl>(this)->load(filename);
}

Result Picture::load(const char* data, uint32_t size, const char* mimeType, const char* rpath, bool copy) noexcept
{
    return to<PictureImpl>(this)->load(data, size, mimeType, rpath, copy ? Ownership::Copy : Ownership::Borrow);
}

Result Picture::load(const uint32_t* data, uint32_t w, uint32_t h, ColorSpace cs, bool copy) noexcept
{
    return to<PictureImpl>(this)->load(data, w, h, cs, copy ? Ownership::Copy : Ownership::Borrow);
}

Result Picture::resolver(std::function<bool(Paint* paint, const char* src, void* data)> func, void* data) noexcept
{
    return to<PictureImpl>(this)->set(func, data);
}

Result Picture::size(float w, float h) noexcept
{
    to<PictureImpl>(this)->size(w, h);
    return Result::Success;
}

Result Picture::size(float* w, float* h) const noexcept
{
    return to<PictureImpl>(this)->size(w, h);
}

Result Picture::origin(float x, float y) noexcept
{
    to<PictureImpl>(this)->origin = {x, y};
    PAINT(this)->mark(RenderUpdateFlag::Transform);
    return Result::Success;
}

Result Picture::origin(float* x, float* y) const noexcept
{
    if (x) *x = to<PictureImpl>(this)->origin.x;
    if (y) *y = to<PictureImpl>(this)->origin.y;
    return Result::Success;
}

const Paint* Picture::paint(uint32_t id) noexcept
{
    if (accessible) {
        auto entity = to<PictureImpl>(this)->access(id);
        return entity ? entity->paint : nullptr;
    }

    struct Value
    {
        uint32_t id;
        const Paint* ret;
    } value = {id, nullptr};

    auto cb = [](const tvg::Paint* paint, void* data) -> bool
    {
        auto p = static_cast<Value*>(data);
        if (p->id == paint->id) {
            p->ret = paint;
            return false;
        }
        return true;
    };

    auto accessor = tvg::Accessor::gen();
    accessor->set(this, cb, &value);
    delete(accessor);

    return value.ret;
}

Result Picture::filter(FilterMethod method) noexcept
{
    return to<PictureImpl>(this)->filterMethod(method);
}
