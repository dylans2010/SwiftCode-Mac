#include "tvgScene.h"

Scene::Scene() = default;

Scene* Scene::gen() noexcept
{
    return new SceneImpl;
}

Type Scene::type() const noexcept
{
    return Type::Scene;
}

Result Scene::add(Paint* target, Paint* at) noexcept
{
    return to<SceneImpl>(this)->insert(target, at);
}

Result Scene::remove(Paint* paint) noexcept
{
    if (paint) return to<SceneImpl>(this)->remove(paint);
    else return to<SceneImpl>(this)->clearPaints();
}

const list<Paint*>& Scene::paints() const noexcept
{
    return to<SceneImpl>(this)->paints;
}

Result Scene::add(SceneEffect effect, ...) noexcept
{
    va_list args;
    va_start(args, effect);
    auto ret = to<SceneImpl>(this)->add(effect, args);
    va_end(args);
    return ret;
}
