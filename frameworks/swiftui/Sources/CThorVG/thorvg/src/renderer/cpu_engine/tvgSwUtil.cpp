#include "tvgMath.h"
#include "tvgSwCommon.h"

void utilExport(SwOutline* outline, const Matrix& transform, BBox& bbox)
{
    outline->out.reserve(outline->path->pts.count);

    bbox = {{FLT_MAX, FLT_MAX}, {-FLT_MAX, -FLT_MAX}};

    ARRAY_FOREACH(pt, outline->path->pts) {
        auto t = *pt * transform;
        if (bbox.min.x > t.x) bbox.min.x = t.x;
        if (bbox.max.x < t.x) bbox.max.x = t.x;
        if (bbox.min.y > t.y) bbox.min.y = t.y;
        if (bbox.max.y < t.y) bbox.max.y = t.y;
        outline->out.push({int32_t(t.x * 64.0f), int32_t(t.y * 64.0f)});
    }
}

bool utilBBox(const BBox& bbox, const RenderRegion& clipBox, RenderRegion& renderBox, bool fastTrack)
{
    if (fastTrack) {
        renderBox.xMin = (int32_t)round(bbox.min.x);
        renderBox.yMin = (int32_t)round(bbox.min.y);
        renderBox.xMax = (int32_t)round(bbox.max.x);
        renderBox.yMax = (int32_t)round(bbox.max.y);
    } else {
        renderBox.xMin = (int32_t)floorf(bbox.min.x);
        renderBox.yMin = (int32_t)floorf(bbox.min.y);
        renderBox.xMax = (int32_t)ceilf(bbox.max.x);
        renderBox.yMax = (int32_t)ceilf(bbox.max.y);
    }
    renderBox.intersect(clipBox);
    return renderBox.valid();
}
