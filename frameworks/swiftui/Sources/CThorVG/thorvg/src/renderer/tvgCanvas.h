#ifndef _TVG_CANVAS_H_
#define _TVG_CANVAS_H_

#include "tvgPaint.h"

enum Status : uint8_t {Synced = 0, Painting, Updating, Drawing, Damaged};

struct Canvas::Impl
{
    Scene* scene;
    RenderMethod* renderer;
    RenderRegion vport = {0, 0, INT32_MAX, INT32_MAX};
    Array<RenderData> clips;
    Status status = Status::Synced;

    Impl() : scene(Scene::gen())
    {
        scene->ref();
    }

    ~Impl()
    {
        renderer->sync();
        scene->unref();
        if (renderer->unref() == 0) delete(renderer);
    }

    Result add(Paint* target, Paint* at)
    {
        if (PAINT(target)->renderer && PAINT(target)->renderer != renderer) {
            TVGERR("RENDERER", "Target paint(%p) is already owned by a different renderer.", target);
            return Result::InsufficientCondition;
        }

        if (status == Status::Drawing) {
            TVGLOG("RENDERER", "add() was called during drawing.");
            return Result::InsufficientCondition;
        }
        status = Status::Painting;
        return scene->add(target, at);
    }

    Result remove(Paint* paint)
    {
        if (status == Status::Drawing) {
            TVGLOG("RENDERER", "remove() was called during drawing.");
            return Result::InsufficientCondition;
        }
        status = Status::Painting;
        return scene->remove(paint);
    }

    Result update()
    {
        if (status == Status::Updating) return Result::Success;

        if (status == Status::Drawing) {
            TVGLOG("RENDERER", "update() was called during drawing.");
            return Result::InsufficientCondition;
        }

        auto flag = RenderUpdateFlag::None;

        if (status == Status::Damaged) flag = RenderUpdateFlag::All;

        if (!renderer->preUpdate()) return Result::InsufficientCondition;

        clips.clear();

        auto m = tvg::identity();
        PAINT(scene)->update(renderer, m, clips, 255, flag);

        if (!renderer->postUpdate()) return Result::InsufficientCondition;

        status = Status::Updating;
        return Result::Success;
    }

    Result draw(bool clear)
    {
        if (status == Status::Drawing) {
            TVGLOG("RENDERER", "draw() was called multiple times.");
            return Result::InsufficientCondition;
        }
        if (status == Status::Painting || status == Status::Damaged) update();
        if (status != Status::Updating) return Result::InsufficientCondition;
        if (clear && !renderer->clear()) return Result::InsufficientCondition;
        if (!renderer->preRender()) return Result::InsufficientCondition;
        if (!PAINT(scene)->render(renderer) || !renderer->postRender()) return Result::InsufficientCondition;

        status = Status::Drawing;

        return Result::Success;
    }

    Result sync()
    {
        if (status == Status::Synced) return Result::Success;
        if (renderer->sync()) {
            status = Status::Synced;
            return Result::Success;
        }
        return Result::Unknown;
    }

    Result viewport(int32_t x, int32_t y, int32_t w, int32_t h)
    {
        if (status == Status::Synced || status == Status::Damaged) {
            RenderRegion val = {x, y, x + w, y + h};
            auto surface = renderer->mainSurface();
            if (surface && surface->w > 0 && surface->h > 0) {
                val.intersect({0, 0, (int32_t)surface->w, (int32_t)surface->h});
            }
            if (vport == val) return Result::Success;
            renderer->viewport(val);
            vport = val;
            status = Status::Damaged;
            return Result::Success;
        }
        TVGLOG("RENDERER", "viewport() is only allowed after sync.");
        return Result::InsufficientCondition;
    }

    uint32_t dirtyRegions() const
    {
        return (status == Status::Drawing) ? renderer->dirtyRegions() : 0;
    }

    Result dirtyRegions(Region* regions, uint32_t cnt) const
    {
        return (status == Status::Drawing) ? renderer->dirtyRegions(regions, cnt) : Result::InsufficientCondition;
    }
};

#endif
