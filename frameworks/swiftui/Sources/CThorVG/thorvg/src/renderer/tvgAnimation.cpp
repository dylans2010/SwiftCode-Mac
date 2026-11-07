#include "tvgLoader.h"
#include "tvgAnimation.h"

Animation::~Animation()
{
    delete(pImpl);
}

Animation::Animation() : pImpl(new Impl)
{
}

Result Animation::frame(float no) noexcept
{
    auto loader = to<PictureImpl>(pImpl->picture)->loader;

    if (!loader) return Result::InsufficientCondition;
    if (!loader->playable) return Result::NonSupport;

    if (static_cast<AnimLoader*>(loader)->frame(no)) {
        PAINT(pImpl->picture)->mark(RenderUpdateFlag::Children);
        return Result::Success;
    }
    return Result::InsufficientCondition;
}

Picture* Animation::picture() const noexcept
{
    return pImpl->picture;
}

float Animation::curFrame() const noexcept
{
    auto loader = to<PictureImpl>(pImpl->picture)->loader;
    if (!loader || !loader->playable) return 0;
    return static_cast<AnimLoader*>(loader)->curFrame();
}

float Animation::totalFrame() const noexcept
{
    auto loader = to<PictureImpl>(pImpl->picture)->loader;
    if (!loader || !loader->playable) return 0;
    return static_cast<AnimLoader*>(loader)->totalFrame();
}

float Animation::duration() const noexcept
{
    auto loader = to<PictureImpl>(pImpl->picture)->loader;
    if (!loader || !loader->playable) return 0;
    return static_cast<AnimLoader*>(loader)->duration();
}

Result Animation::segment(float begin, float end) noexcept
{
    auto loader = to<PictureImpl>(pImpl->picture)->loader;
    if (!loader) return Result::InsufficientCondition;
    if (!loader->playable) return Result::NonSupport;

    return static_cast<AnimLoader*>(loader)->segment(begin, end);
}

Result Animation::segment(float *begin, float *end) noexcept
{
    auto loader = to<PictureImpl>(pImpl->picture)->loader;
    if (!loader) return Result::InsufficientCondition;
    if (!loader->playable) return Result::NonSupport;
    if (!begin && !end) return Result::InvalidArguments;

    static_cast<AnimLoader*>(loader)->segment(begin, end);

    return Result::Success;
}

Animation* Animation::gen() noexcept
{
    return new Animation;
}
