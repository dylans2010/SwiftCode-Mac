#include "tvgFill.h"

Fill::Fill() = default;
Fill::~Fill() = default;

Result Fill::colorStops(const ColorStop* colorStops, uint32_t cnt) noexcept
{
    return pImpl->update(colorStops, cnt);
}

uint32_t Fill::colorStops(const ColorStop** colorStops) const noexcept
{
    if (colorStops) *colorStops = pImpl->colorStops;
    return pImpl->cnt;
}

Result Fill::spread(FillSpread s) noexcept
{
    pImpl->spread = s;
    return Result::Success;
}

FillSpread Fill::spread() const noexcept
{
    return pImpl->spread;
}

Result Fill::transform(const Matrix& m) noexcept
{
    pImpl->transform = m;
    return Result::Success;
}

Matrix& Fill::transform() const noexcept
{
    return pImpl->transform;
}

Fill* Fill::duplicate() const noexcept
{
    if (type() == Type::LinearGradient) return CONST_LINEAR(this)->duplicate();
    else if (type() == Type::RadialGradient) return CONST_RADIAL(this)->duplicate();
    else if (type() == Type::ConicGradient) return CONST_CONIC(this)->duplicate();
    return nullptr;
}

RadialGradient::RadialGradient() = default;

Result RadialGradient::radial(float cx, float cy, float r, float fx, float fy, float fr) noexcept
{
    return RADIAL(this)->radial(cx, cy, r, fx, fy, fr);
}

Result RadialGradient::radial(float* cx, float* cy, float* r, float* fx, float* fy, float* fr) const noexcept
{
    return CONST_RADIAL(this)->radial(cx, cy, r, fx, fy, fr);
}

RadialGradient* RadialGradient::gen() noexcept
{
    return new RadialGradientImpl;
}

Type RadialGradient::type() const noexcept
{
    return Type::RadialGradient;
}

LinearGradient::LinearGradient() = default;

Result LinearGradient::linear(float x1, float y1, float x2, float y2) noexcept
{
    return LINEAR(this)->linear(x1, y1, x2, y2);
}

Result LinearGradient::linear(float* x1, float* y1, float* x2, float* y2) const noexcept
{
    return CONST_LINEAR(this)->linear(x1, y1, x2, y2);
}

LinearGradient* LinearGradient::gen() noexcept
{
    return new LinearGradientImpl;
}

Type LinearGradient::type() const noexcept
{
    return Type::LinearGradient;
}

ConicGradient::ConicGradient() = default;

Result ConicGradient::conic(float cx, float cy, float angle) noexcept
{
    return CONIC(this)->conic(cx, cy, angle);
}

Result ConicGradient::conic(float* cx, float* cy, float* angle) const noexcept
{
    return CONST_CONIC(this)->conic(cx, cy, angle);
}

ConicGradient* ConicGradient::gen() noexcept
{
    return new ConicGradientImpl;
}

Type ConicGradient::type() const noexcept
{
    return Type::ConicGradient;
}
