#ifndef _TVG_TEXT_H
#define _TVG_TEXT_H

#include "tvgStr.h"
#include "tvgMath.h"
#include "tvgShape.h"
#include "tvgFill.h"
#include "tvgLoaderMgr.h"

namespace tvg
{

struct TextImpl : Text
{
    Paint::Impl impl;
    Shape* shape;
    FontLoader* loader = nullptr;
    FontMetrics fm;
    char* utf8 = nullptr;
    uint32_t utf8len = 0;
    float outlineWidth = 0.0f;
    float italicShear = 0.0f;
    bool updated = false;

    TextImpl() : impl(Paint::Impl(this)), shape(Shape::gen())
    {
        PAINT(shape)->parent = this;
        shape->strokeJoin(StrokeJoin::Round);
    }

    ~TextImpl()
    {
        tvg::free(utf8);
        if (loader) {
            loader->release(fm);
            LoaderMgr::retrieve(loader);
        }
        Paint::rel(shape);
    }

    Result text(const char* utf8)
    {
        tvg::free(this->utf8);
        this->utf8 = tvg::duplicate(utf8, SIZE_MAX, &utf8len);
        updated = true;
        impl.mark(RenderUpdateFlag::Path);

        return Result::Success;
    }

    Result font(const char* name)
    {
        auto loader = static_cast<FontLoader*>(name ? LoaderMgr::font(name) : LoaderMgr::anyfont());
        if (!loader) return Result::InsufficientCondition;

        if (this->loader == loader) {
            this->loader->sharing--;
            return Result::Success;
        } else if (this->loader) {
            this->loader->release(fm);
            LoaderMgr::retrieve(this->loader);
        }
        this->loader = loader;
        updated = true;

        return Result::Success;
    }

    Result size(float fontSize)
    {
        if (fontSize > 0.0f) {
            if (fm.fontSize != fontSize) {
                fm.fontSize = fontSize;
                updated = true;
            }
            return Result::Success;
        }
        return Result::InvalidArguments;
    }

    RenderRegion bounds()
    {
        if (!load()) return {};
        return to<ShapeImpl>(shape)->bounds();
    }

    bool render(RenderMethod* renderer, TVG_UNUSED CompositionFlag flag)
    {
        if (!loader || !fm.engine) return true;
        renderer->blend(impl.blendMethod);
        return PAINT(shape)->render(renderer);
    }

    bool load()
    {
        if (!loader) return false;
        if (updated) {
            if (loader->get(fm, utf8, utf8len, to<ShapeImpl>(shape)->rs.path)) {
                loader->transform(shape, fm, italicShear);
            }
            updated = false;
        }
        return true;
    }

    Result metrics(TextMetrics& metrics)
    {
        if (!loader || fm.fontSize <= 0.0f) return Result::InsufficientCondition;
        loader->metrics(fm, metrics);
        return Result::Success;
    }

    Result metrics(const char* ch, GlyphMetrics& metrics, const char** next)
    {
        if (!loader || fm.fontSize <= 0.0f) return Result::InsufficientCondition;
        if (ch && loader->metrics(fm, ch, metrics, next)) return Result::Success;
        return Result::InvalidArguments;
    }

    bool skip(RenderUpdateFlag flag)
    {
        return (flag == RenderUpdateFlag::None);
    }

    void wrapping(TextWrap mode)
    {
        if (fm.wrap == mode) return;
        fm.wrap = mode;
        updated = true;
        impl.mark(RenderUpdateFlag::Path);
    }

    uint32_t lines()
    {
        if (load()) return fm.lines;
        return 0;
    }

    void layout(float w, float h)
    {
        fm.box = {w, h};
        updated = true;
    }

    Result spacing(float letter, float line)
    {
        if (letter < 0.0f || line < 0.0f) return Result::InvalidArguments;

        fm.spacing = {letter, line};
        updated = true;

        return Result::Success;
    }

    bool update(RenderMethod* renderer, const Matrix& transform, Array<RenderData>& clips, uint8_t opacity, RenderUpdateFlag flag, TVG_UNUSED bool clipper)
    {
        if (!load()) return true;

        auto scale = fm.scale;

        auto fill = to<ShapeImpl>(shape)->rs.fill;
        if (fill && to<ShapeImpl>(shape)->impl.marked(RenderUpdateFlag::Gradient)) {
            if (fill->type() == Type::LinearGradient) {
                LINEAR(fill)->p1 *= scale;
                LINEAR(fill)->p2 *= scale;
            } else if (fill->type() == Type::RadialGradient) {
                RADIAL(fill)->center *= scale;
                RADIAL(fill)->r *= scale;
                RADIAL(fill)->focal *= scale;
                RADIAL(fill)->fr *= scale;
            } else if (fill->type() == Type::ConicGradient) {
                CONIC(fill)->center *= scale;
            }
        }

        if (outlineWidth > 0.0f && impl.marked(RenderUpdateFlag::Stroke)) shape->strokeWidth(outlineWidth * scale);

        PAINT(shape)->update(renderer, transform, clips, opacity, flag, false);
        return true;
    }

    bool intersects(const RenderRegion& region, TVG_UNUSED bool visibleOnly)
    {
        if (!load()) return false;
        return to<ShapeImpl>(shape)->intersects(region, false);
    }

    bool bounds(Point* pt4, const Matrix& m, bool obb)
    {
        if (!load()) return true;
        return PAINT(shape)->bounds(pt4, &const_cast<Matrix&>(m), obb);
    }

    Paint* duplicate(Paint* ret)
    {
        if (ret) TVGERR("RENDERER", "TODO: duplicate()");

        load();

        auto text = Text::gen();
        auto dup = to<TextImpl>(text);

        to<ShapeImpl>(shape)->duplicate(dup->shape);

        if (loader) {
            dup->loader = loader;
            ++dup->loader->sharing;
            loader->copy(fm, dup->fm);
        }

        dup->utf8 = tvg::duplicate(utf8);
        dup->utf8len = utf8len;
        dup->italicShear = italicShear;
        dup->outlineWidth = outlineWidth;
        dup->updated = true;

        return text;
    }

    AccessorIterator* iterator()
    {
        return nullptr;
    }

    static Result load(const char* name, const char* data, uint32_t size, const char* mimeType, Ownership owner) noexcept
    {
        if (!name || (size == 0 && data)) return Result::InvalidArguments;

        if (!data) {
            if (LoaderMgr::retrieve(LoaderMgr::font(name))) return Result::Success;
            return Result::InsufficientCondition;
        }

        LoaderOps ops = {Type::Text, owner};
        if (!LoaderMgr::loader(name, data, size, mimeType, ops)) return Result::NonSupport;
        return Result::Success;
    }
};

}

#endif
