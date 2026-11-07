#include "tvgMath.h"
#include "tvgSwCommon.h"

static SwOutline* _genOutline(SwImage& image, SwMpool* mpool, unsigned tid)
{
    auto outline = mpool->outline(tid);
    auto& path = *const_cast<RenderPath*>(outline->path);
    path.pts.reserve(4);
    path.cmds.reserve(5);

    auto w = static_cast<float>(image.w);
    auto h = static_cast<float>(image.h);

    path.moveTo({0.0f, 0.0f});
    path.lineTo({w, 0.0f});
    path.lineTo({w, h});
    path.lineTo({0.0f, h});
    path.close();

    outline->fillRule = FillRule::NonZero;

    return outline;
}

bool imagePrepare(SwImage& image, const Matrix& transform, const RenderRegion& clipBox, RenderRegion& renderBox, SwMpool* mpool, unsigned tid)
{
    image.direct = tvg::equal(transform.e11, 1.0f) && tvg::equal(transform.e22, 1.0f) && tvg::zero(transform.e12) && tvg::zero(transform.e21);

    if (image.direct) {
        image.ox = -static_cast<int32_t>(nearbyint(transform.e13));
        image.oy = -static_cast<int32_t>(nearbyint(transform.e23));
    } else {
        image.scale = scaling(transform);
        image.scaled = (tvg::zero(transform.e12) && tvg::zero(transform.e21)) ? true : false;
    }
    image.outline = _genOutline(image, mpool, tid);
    if (!image.outline) return false;

    BBox bbox;
    utilExport(image.outline, transform, bbox);
    return utilBBox(bbox, clipBox, renderBox, image.direct);
}

bool imageGenRle(SwImage& image, const RenderRegion& renderBox, SwMpool* mpool, unsigned tid, bool antiAlias)
{
    image.rle = rleRender(image.rle, image.outline, renderBox, mpool, tid, antiAlias);
    return image.rle ? true : false;
}

void imageReset(SwImage& image)
{
    rleReset(image.rle);
}

void imageFree(SwImage& image)
{
    rleFree(image.rle);
    image.rle = nullptr;
}
