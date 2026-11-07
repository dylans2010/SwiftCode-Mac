#ifndef _TVG_SCENE_H_
#define _TVG_SCENE_H_

#include <algorithm>
#include "tvgMath.h"
#include "tvgPaint.h"
#include "tvgAccessor.h"

struct SceneImpl : Scene
{
    Paint::Impl impl;
    list<Paint*> paints;
    RenderRegion vport = {};
    Array<RenderEffect*>* effects = nullptr;
    Point fsize;
    bool fixed = false;
    bool vdirty = false;
    uint8_t opacity;

    SceneImpl() : impl(Paint::Impl(this))
    {
    }

    ~SceneImpl()
    {
        clearPaints();
        resetEffects(false);
    }

    void size(const Point& size)
    {
        this->fsize = size;
        fixed = (size.x > 0 && size.y > 0) ? true : false;
    }

    uint8_t needComposition(uint8_t opacity)
    {
        if (opacity == 0 || paints.empty()) return 0;

        if (effects) impl.mark(CompositionFlag::PostProcessing);
        if (PAINT(this)->mask(nullptr) != MaskMethod::None) impl.mark(CompositionFlag::Masking);
        if (impl.blendMethod != BlendMethod::Normal) impl.mark(CompositionFlag::Blending);

        if (opacity == 255) return impl.cmpFlag;

        if (paints.size() == 1) {
            auto type = paints.front()->type();
            if (type == Type::Shape || type == Type::Picture) return impl.cmpFlag;
        }

        impl.mark(CompositionFlag::Opacity);

        return 1;
    }

    bool skip(RenderUpdateFlag flag)
    {
        return false;
    }

    bool update(RenderMethod* renderer, const Matrix& transform, Array<RenderData>& clips, uint8_t opacity, RenderUpdateFlag flag, TVG_UNUSED bool clipper)
    {
        if (paints.empty()) return true;

        if (needComposition(opacity)) {
            this->opacity = opacity;
            opacity = 255;
        }

        auto recover = fixed ? renderer->partial(true) : false;

        for (auto paint : paints) {
            PAINT(paint)->update(renderer, transform, clips, opacity, flag, false);
        }

        if (fixed) renderer->partial(recover);

        if (effects) {
            ARRAY_FOREACH(p, *effects) {
                renderer->prepare(*p, transform);
            }
        }

        vport = renderer->viewport();

        if (fixed) {
            auto pt = fsize * transform;
            vport.intersect({int32_t(round(transform.e13)), int32_t(round(transform.e23)), int32_t(round(pt.x)), int32_t(round(pt.y))});
        } else {
            vdirty = true;
        }

        if (fixed || effects) impl.damage(vport);

        return true;
    }

    bool render(RenderMethod* renderer, CompositionFlag flag)
    {
        if (paints.empty()) return true;

        RenderCompositor* cmp = nullptr;
        auto incomposite = (uint8_t(CompositionFlag::PostProcessing) & uint8_t(flag)) && !effects;
        auto ret = true;

        renderer->blend(impl.blendMethod);

        if (!incomposite && impl.cmpFlag) {
            cmp = renderer->target(bounds(), renderer->colorSpace(), impl.cmpFlag);
            renderer->beginComposite(cmp, MaskMethod::None, opacity);
        }

        for (auto paint : paints) {
            ret &= paint->pImpl->render(renderer, impl.cmpFlag);
        }

        if (cmp) {
            if (effects) {
                auto direct = (effects->count == 1) & (impl.marked(CompositionFlag::PostProcessing));
                ARRAY_FOREACH(p, *effects) {
                    if ((*p)->valid) renderer->render(cmp, *p, direct);
                }
            }
            renderer->endComposite(cmp);
        }

        return ret;
    }

    RenderRegion bounds()
    {
        if (paints.empty()) return {};
        if (!vdirty) return vport;
        vdirty = false;

        RenderRegion pRegion = {INT32_MAX, INT32_MAX, 0, 0};
        for (auto paint : paints) {
            auto region = paint->pImpl->bounds();
            if (region.xMin < pRegion.xMin) pRegion.xMin = region.xMin;
            if (pRegion.xMax < region.xMax) pRegion.xMax = region.xMax;
            if (region.yMin < pRegion.yMin) pRegion.yMin = region.yMin;
            if (pRegion.yMax < region.yMax) pRegion.yMax = region.yMax;
        }

        if (effects) {
            ARRAY_FOREACH(p, *effects) {
                auto effect = *p;
                if (!effect->valid || !impl.renderer->region(effect)) continue;
                pRegion.xMin += effect->extend.xMin;
                pRegion.yMin += effect->extend.yMin;
                pRegion.xMax += effect->extend.xMax;
                pRegion.yMax += effect->extend.yMax;
            }
        }

        vport = RenderRegion::intersect(vport, pRegion);
        return vport;
    }

    bool bounds(Point* pt4, const Matrix& m, bool obb)
    {
        if (paints.empty()) return false;

        Point min = {FLT_MAX, FLT_MAX};
        Point max = {-FLT_MAX, -FLT_MAX};
        auto ret = false;

        for (auto paint : paints) {
            Point tmp[4];
            if (!PAINT(paint)->bounds(tmp, obb ? nullptr : &m, false)) continue;
            for (int i = 0; i < 4; ++i) {
                if (tmp[i].x < min.x) min.x = tmp[i].x;
                if (tmp[i].x > max.x) max.x = tmp[i].x;
                if (tmp[i].y < min.y) min.y = tmp[i].y;
                if (tmp[i].y > max.y) max.y = tmp[i].y;
            }
            ret = true;
        }
        pt4[0] = min;
        pt4[1] = Point{max.x, min.y};
        pt4[2] = max;
        pt4[3] = Point{min.x, max.y};

        if (obb) {
            pt4[0] *= m;
            pt4[1] *= m;
            pt4[2] *= m;
            pt4[3] *= m;
        }

        return ret;
    }

    bool intersects(const RenderRegion& region, bool visibleOnly)
    {
        if (!impl.renderer) return false;

        if (this->bounds().intersected(region)) {
            for (auto paint : paints) {
                if (PAINT(paint)->intersects(region, visibleOnly)) return true;
            }
        }

        return false;
    }

    Paint* duplicate(Paint* ret)
    {
        if (ret) TVGERR("RENDERER", "TODO: duplicate()");

        auto scene = Scene::gen();
        auto dup = to<SceneImpl>(scene);

        for (auto paint : paints) {
            auto cdup = paint->duplicate();
            PAINT(cdup)->parent = scene;
            cdup->ref();
            dup->paints.push_back(cdup);
        }

        if (effects) {
            dup->effects = new Array<RenderEffect*>;
            ARRAY_FOREACH(p, *effects) {
                RenderEffect* ret = nullptr;
                switch ((*p)->type) {
                    case SceneEffect::GaussianBlur: {
                        ret = new RenderEffectGaussianBlur(*(RenderEffectGaussianBlur*)(*p));
                        break;
                    }
                    case SceneEffect::MotionBlur: {
                        ret = new RenderEffectMotionBlur(*(RenderEffectMotionBlur*)(*p));
                        break;
                    }
                    case SceneEffect::DropShadow: {
                        ret = new RenderEffectDropShadow(*(RenderEffectDropShadow*)(*p));
                        break;
                    }
                    case SceneEffect::Fill: {
                        ret = new RenderEffectFill(*(RenderEffectFill*)(*p));
                        break;
                    }
                    case SceneEffect::Tint: {
                        ret = new RenderEffectTint(*(RenderEffectTint*)(*p));
                        break;
                    }
                    case SceneEffect::Tritone: {
                        ret = new RenderEffectTritone(*(RenderEffectTritone*)(*p));
                        break;
                    }
                    default: break;
                }
                if (ret) {
                    ret->rd = nullptr;
                    ret->valid = false;
                    dup->effects->push(ret);
                }
            }
        }

        if (fixed) dup->size(fsize);

        return scene;
    }

    Result clearPaints()
    {
        if (paints.empty()) return Result::Success;

        auto recover = (fixed && impl.renderer) ? impl.renderer->partial(true) : false;
        auto partialDmg = !(effects || fixed || recover);

        auto itr = paints.begin();
        while (itr != paints.end()) {
            auto paint = PAINT((*itr));
            if (paint->refCnt > 1 && partialDmg) paint->damage();
            paint->unref();
            paints.erase(itr++);
        }
        if (fixed && impl.renderer) impl.renderer->partial(recover);
        if (effects || fixed) impl.damage(vport);

        return Result::Success;
    }

    Result remove(Paint* paint)
    {
        if (PAINT(paint)->parent != this) return Result::InsufficientCondition;
        if (PAINT(paint)->refCnt > 1) PAINT(paint)->damage();
        PAINT(paint)->unref();
        paints.remove(paint);
        return Result::Success;
    }

    Result insert(Paint* target, Paint* at)
    {
        if (!target) return Result::InvalidArguments;
        auto timpl = PAINT(target);

        if (timpl->parent) {
            TVGERR("RENDERER", "Target paint(%p) is already owned by a parent(%p)", target, timpl->parent);
            return Result::InsufficientCondition;
        }

        target->ref();

        timpl->mark(RenderUpdateFlag::Transform);

        if (!at) {
            paints.push_back(target);
        } else {
            auto itr = find_if(paints.begin(), paints.end(),[&at](const Paint* paint){ return at == paint; });
            if (itr == paints.end()) return Result::InvalidArguments;
            paints.insert(itr, target);
        }
        timpl->attachTo(this);
        return Result::Success;
    }

    AccessorIterator* iterator()
    {
        struct SceneIterator : AccessorIterator
        {
            list<Paint*>* paints;
            list<Paint*>::iterator itr;

            SceneIterator(list<Paint*>* p) : paints(p)
            {
                itr = paints->begin();
            }

            const Paint* next() override
            {
                if (itr == paints->end()) return nullptr;
                auto paint = *itr;
                ++itr;
                return paint;
            }
        };

        return new SceneIterator(&paints);
    }

    Result resetEffects(bool damage = true)
    {
        if (effects) {
            ARRAY_FOREACH(p, *effects) {
                if (impl.renderer) impl.renderer->dispose(*p);
                delete(*p);
            }
            delete(effects);
            effects = nullptr;
            if (damage) impl.damage(vport);
        }
        return Result::Success;
    }

    Result add(SceneEffect effect, va_list& args)
    {
        if (effect == SceneEffect::Clear) return resetEffects();

        if (!this->effects) this->effects = new Array<RenderEffect*>;

        RenderEffect* re = nullptr;

        switch (effect) {
            case SceneEffect::GaussianBlur: {
                re = RenderEffectGaussianBlur::gen(args);
                break;
            }
            case SceneEffect::DropShadow: {
                re = RenderEffectDropShadow::gen(args);
                break;
            }
            case SceneEffect::Fill: {
                re = RenderEffectFill::gen(args);
                break;
            }
            case SceneEffect::Tint: {
                re = RenderEffectTint::gen(args);
                break;
            }
            case SceneEffect::Tritone: {
                re = RenderEffectTritone::gen(args);
                break;
            }
            case SceneEffect::MotionBlur: {
                re = RenderEffectMotionBlur::gen(args);
                break;
            }
            default: break;
        }

        if (!re) return Result::InvalidArguments;

        this->effects->push(re);

        return Result::Success;
    }
};

#endif
