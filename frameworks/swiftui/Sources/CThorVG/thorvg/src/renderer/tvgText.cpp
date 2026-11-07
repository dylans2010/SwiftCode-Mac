#include "tvgText.h"

Text::Text() = default;

Result Text::text(const char* text) noexcept
{
    return to<TextImpl>(this)->text(text);
}

Result Text::font(const char* name) noexcept
{
    return to<TextImpl>(this)->font(name);
}

Result Text::size(float size) noexcept
{
    return to<TextImpl>(this)->size(size);
}

Result Text::load(const char* filename) noexcept
{
    LoaderOps ops = {Type::Text, Ownership::Transfer};
    auto ret = Result::InvalidArguments;
    return LoaderMgr::loader(filename, ops, ret) ? Result::Success: ret;
}

Result Text::load(const char* name, const char* data, uint32_t size, const char* mimeType, bool copy) noexcept
{
    return TextImpl::load(name, data, size, mimeType, copy ? Ownership::Copy : Ownership::Borrow);
}

Result Text::unload(const char* filename) noexcept
{
    if (!filename) return Result::InvalidArguments;
    if (LoaderMgr::retrieve(filename)) return Result::Success;
    return Result::InsufficientCondition;
}

Result Text::align(float x, float y) noexcept
{
    to<TextImpl>(this)->fm.align = {x, y};
    PAINT(this)->mark(RenderUpdateFlag::Transform);
    return Result::Success;
}

Result Text::layout(float w, float h) noexcept
{
    to<TextImpl>(this)->layout(w, h);
    return Result::Success;
}

Result Text::fill(uint8_t r, uint8_t g, uint8_t b) noexcept
{
    return to<TextImpl>(this)->shape->fill(r, g, b);
}

Result Text::outline(float width, uint8_t r, uint8_t g, uint8_t b) noexcept
{
    to<TextImpl>(this)->outlineWidth = width;
    to<TextImpl>(this)->shape->strokeFill(r, g, b);
    PAINT(this)->mark(RenderUpdateFlag::Stroke);
    return Result::Success;
}

Result Text::fill(Fill* f) noexcept
{
    return to<TextImpl>(this)->shape->fill(f);
}

Result Text::italic(float shear) noexcept
{
    if (shear < 0.0f) shear = 0.0f;
    else if (shear > 0.5f) shear = 0.5f;
    to<TextImpl>(this)->italicShear = shear;
    to<TextImpl>(this)->updated = true;
    return Result::Success;
}

Result Text::spacing(float letter, float line) noexcept
{
    return to<TextImpl>(this)->spacing(letter, line);
}

Result Text::wrap(TextWrap mode) noexcept
{
    to<TextImpl>(this)->wrapping(mode);
    return Result::Success;
}

uint32_t Text::lines() noexcept
{
    return to<TextImpl>(this)->lines();
}

Result Text::metrics(TextMetrics& metrics) const noexcept
{
    return to<TextImpl>(this)->metrics(metrics);
}

Result Text::metrics(const char* ch, GlyphMetrics& metrics, const char** next) const noexcept
{
    return to<TextImpl>(this)->metrics(ch, metrics, next);
}

const char* Text::text() const noexcept
{
    return to<TextImpl>(this)->utf8;
}

Text* Text::gen() noexcept
{
    return new TextImpl;
}

Type Text::type() const noexcept
{
    return Type::Text;
}
