#include <limits.h>
#include "tvgSwCommon.h"

constexpr auto PIXEL_BITS = 8;
constexpr auto ONE_PIXEL = (1 << PIXEL_BITS);

struct Band
{
    int32_t min, max;
};

struct RleWorker
{
    SwRle* rle;

    SwPoint cellPos;
    SwPoint cellMin;
    SwPoint cellMax;
    int32_t cellXCnt;
    int32_t cellYCnt;

    long area;
    int32_t cover;

    SwCell* cells;
    ptrdiff_t maxCells;
    ptrdiff_t cellsCnt;

    SwPoint pos;

#define BEZ_STACK_SIZE (32 * 3 + 1)
    SwPoint bezStack[BEZ_STACK_SIZE];

#define LINE_STACK_SIZE (32 + 1)
    SwPoint lineStack[LINE_STACK_SIZE];
    int levStack[32];

    const SwOutline* outline;

    int bandSize;
    int bandShoot;

    SwCell* buffer;
    uint32_t bufferSize;

    SwCell** yCells;
    int32_t yCnt;

    bool invalid;
    bool antiAlias;
};

static inline SwPoint UPSCALE(const SwPoint& pt)
{
    return {int32_t(((unsigned long) pt.x) << (PIXEL_BITS - 6)), int32_t(((unsigned long) pt.y) << (PIXEL_BITS - 6))};
}

static inline int32_t TRUNC(const int32_t x)
{
    return  x >> PIXEL_BITS;
}

static inline SwPoint TRUNC(const SwPoint& pt)
{
    return  {TRUNC(pt.x), TRUNC(pt.y)};
}

static inline SwPoint FRACT(const SwPoint& pt)
{

    return {pt.x & (ONE_PIXEL - 1), pt.y & (ONE_PIXEL - 1)};
}

static inline int32_t HYPOT(SwPoint pt)
{
    if (pt.x < 0) pt.x = -pt.x;
    if (pt.y < 0) pt.y = -pt.y;
    return ((pt.x > pt.y) ? (pt.x + (3 * pt.y >> 3)) : (pt.y + (3 * pt.x >> 3)));
}

static void _splitCubic(SwPoint* base)
{
    int32_t a, b, c, d;

    base[6].x = base[3].x;
    c = base[1].x;
    d = base[2].x;
    base[1].x = a = (base[0].x + c) >> 1;
    base[5].x = b = (base[3].x + d) >> 1;
    c = (c + d) >> 1;
    base[2].x = a = (a + c) >> 1;
    base[4].x = b = (b + c) >> 1;
    base[3].x = (a + b) >> 1;

    base[6].y = base[3].y;
    c = base[1].y;
    d = base[2].y;
    base[1].y = a = (base[0].y + c) >> 1;
    base[5].y = b = (base[3].y + d) >> 1;
    c = (c + d) >> 1;
    base[2].y = a = (a + c) >> 1;
    base[4].y = b = (b + c) >> 1;
    base[3].y = (a + b) >> 1;
}

static void _splitLine(SwPoint* base)
{
    base[2] = base[1];
    base[1] = {(base[0].x >> 1) + (base[1].x >> 1), (base[0].y >> 1) + (base[1].y >> 1)};
}

static void _horizLine(RleWorker& rw, int32_t x, int32_t y, int32_t area, int32_t aCount)
{
    x += rw.cellMin.x;
    y += rw.cellMin.y;

    if (y < rw.cellMin.y || y >= rw.cellMax.y) return;

    auto coverage = static_cast<int>(area >> (PIXEL_BITS * 2 + 1 - 8));
    if (coverage < 0) coverage = -coverage;

    if (rw.outline->fillRule == FillRule::EvenOdd) {
        coverage &= 511;
        if (coverage > 255) coverage = 511 - coverage;
    } else {
        if (coverage > 255) coverage = 255;
    }

    if (coverage == 0) return;

    auto rle = rw.rle;

    if (!rw.antiAlias) coverage = 255;

    if (!rle->spans.empty()) {
        auto& span = rle->spans.last();
        if ((span.coverage == coverage) && (span.y == y) && (span.x + span.len == x)) {
            int32_t xOver = 0;
            if (x + aCount >= rw.cellMax.x) xOver -= (x + aCount - rw.cellMax.x);
            if (x < rw.cellMin.x) xOver -= (rw.cellMin.x - x);
            span.len += (aCount + xOver);
            return;
        }
    }

    int32_t xOver = 0;
    if (x + aCount >= rw.cellMax.x) xOver -= (x + aCount - rw.cellMax.x);
    if (x < rw.cellMin.x) {
        xOver -= (rw.cellMin.x - x);
        x = rw.cellMin.x;
    }

    if (aCount + xOver <= 0) return;

    rle->spans.next() = {x, y,  aCount + xOver, (uint8_t)coverage};
}

static void _sweep(RleWorker& rw)
{
    if (rw.cellsCnt == 0) return;

    for (int y = 0; y < rw.yCnt; ++y) {
        auto cover = 0;
        auto x = 0;
        auto cell = rw.yCells[y];

        while (cell) {
            if (cell->x > x && cover != 0) _horizLine(rw, x, y, cover * (ONE_PIXEL * 2), cell->x - x);
            cover += cell->cover;
            auto area = cover * (ONE_PIXEL * 2) - cell->area;
            if (area != 0 && cell->x >= 0) _horizLine(rw, cell->x, y, area, 1);
            x = cell->x + 1;
            cell = cell->next;
        }

        if (cover != 0) _horizLine(rw, x, y, cover * (ONE_PIXEL * 2), rw.cellXCnt - x);
    }
}

static SwCell* _findCell(RleWorker& rw)
{
    auto x = rw.cellPos.x;
    if (x > rw.cellXCnt) x = rw.cellXCnt;

    auto pcell = &rw.yCells[rw.cellPos.y];

    while(true) {
        auto cell = *pcell;
        if (!cell || cell->x > x) break;
        if (cell->x == x) return cell;
        pcell = &cell->next;
    }

    if (rw.cellsCnt >= rw.maxCells) return nullptr;

    auto cell = rw.cells + rw.cellsCnt++;
    cell->x = x;
    cell->area = 0;
    cell->cover = 0;
    cell->next = *pcell;
    *pcell = cell;

    return cell;
}

static bool _recordCell(RleWorker& rw)
{
    if (rw.area | rw.cover) {
        auto cell = _findCell(rw);
        if (!cell) return false;
        cell->area += rw.area;
        cell->cover += rw.cover;
    }

    return true;
}

static bool _setCell(RleWorker& rw, SwPoint pos)
{

    pos -= rw.cellMin;

    if (pos.x < 0) pos.x = -1;
    else if (pos.x > rw.cellMax.x) pos.x = rw.cellMax.x;

    if (pos != rw.cellPos) {
        if (!rw.invalid && !_recordCell(rw)) return false;
        rw.area = rw.cover = 0;
        rw.cellPos = pos;
    }
    rw.invalid = ((unsigned)pos.y >= (unsigned)rw.cellYCnt || pos.x >= rw.cellXCnt);

    return true;
}

static bool _startCell(RleWorker& rw, SwPoint pos)
{
    if (pos.x > rw.cellMax.x) pos.x = rw.cellMax.x;
    if (pos.x < rw.cellMin.x) pos.x = rw.cellMin.x - 1;

    rw.area = 0;
    rw.cover = 0;
    rw.cellPos = pos - rw.cellMin;
    rw.invalid = false;

    return _setCell(rw, pos);
}

static bool _moveTo(RleWorker& rw, const SwPoint& to)
{
    if (!rw.invalid && !_recordCell(rw)) return false;

    if (!_startCell(rw, TRUNC(to))) return false;

    rw.pos = to;

    return true;
}

static bool _lineTo(RleWorker& rw, const SwPoint& to)
{
    auto e1 = TRUNC(rw.pos);
    auto e2 = TRUNC(to);

    if ((e1.y >= rw.cellMax.y && e2.y >= rw.cellMax.y) || (e1.y < rw.cellMin.y && e2.y < rw.cellMin.y)) {
        rw.pos = to;
        return true;
    }

    auto line = rw.lineStack;
    auto end = line + LINE_STACK_SIZE;
    line[0] = to;
    line[1] = rw.pos;

    while (line < end) {
        auto diff = line[0] - line[1];

        if (HYPOT(diff) > SHRT_MAX) {
            _splitLine(line);
            ++line;
            continue;
        }

        e1 = TRUNC(line[1]);
        e2 = TRUNC(line[0]);

        auto f1 = FRACT(line[1]);
        SwPoint f2;

        if (e1 == e2) {
            ;
        } else if (diff.y == 0) {
            e1.x = e2.x;
            if (!_setCell(rw, e1)) return false;
        } else if (diff.x == 0) {
            if (diff.y > 0) {
                do {
                    f2.y = ONE_PIXEL;
                    rw.cover += (f2.y - f1.y);
                    rw.area += (f2.y - f1.y) * f1.x * 2;
                    f1.y = 0;
                    ++e1.y;
                    if (!_setCell(rw, e1)) return false;
                } while(e1.y != e2.y);
            } else {
                do {
                    f2.y = 0;
                    rw.cover += (f2.y - f1.y);
                    rw.area += (f2.y - f1.y) * f1.x * 2;
                    f1.y = ONE_PIXEL;
                    --e1.y;
                    if (!_setCell(rw, e1)) return false;
                } while(e1.y != e2.y);
            }
        } else {
            #define SW_UDIV(a, b) (int32_t)((uint64_t(a) * uint64_t(b)) >> 32)

            long prod = diff.x * f1.y - diff.y * f1.x;

            auto dxr = (e1.x != e2.x) ? (int64_t)0xffffffff / diff.x : 0;
            auto dyr = (e1.y != e2.y) ? (int64_t)0xffffffff / diff.y : 0;
            auto px = diff.x * ONE_PIXEL;
            auto py = diff.y * ONE_PIXEL;

            do {
                if (prod <= 0 && prod - px > 0) {
                    f2 = {0, SW_UDIV(-prod, -dxr)};
                    prod -= py;
                    rw.cover += (f2.y - f1.y);
                    rw.area += (f2.y - f1.y) * (f1.x + f2.x);
                    f1 = {ONE_PIXEL, f2.y};
                    --e1.x;
                } else if (prod - px <= 0 && prod - px + py > 0) {
                    prod -= px;
                    f2 = {SW_UDIV(-prod, dyr), ONE_PIXEL};
                    rw.cover += (f2.y - f1.y);
                    rw.area += (f2.y - f1.y) * (f1.x + f2.x);
                    f1 = {f2.x, 0};
                    ++e1.y;
                } else if (prod - px + py <= 0 && prod + py >= 0) {
                    prod += py;
                    f2 = {ONE_PIXEL, SW_UDIV(prod, dxr)};
                    rw.cover += (f2.y - f1.y);
                    rw.area += (f2.y - f1.y) * (f1.x + f2.x);
                    f1 = {0, f2.y};
                    ++e1.x;
                } else {
                    f2 = {SW_UDIV(prod, -dyr), 0};
                    prod += px;
                    rw.cover += (f2.y - f1.y);
                    rw.area += (f2.y - f1.y) * (f1.x + f2.x);
                    f1 = {f2.x, ONE_PIXEL};
                    --e1.y;
                }

                if (!_setCell(rw, e1)) return false;

            } while(e1 != e2);
        }

        f2 = FRACT(line[0]);
        rw.cover += (f2.y - f1.y);
        rw.area += (f2.y - f1.y) * (f1.x + f2.x);
        rw.pos = line[0];

        if (line-- == rw.lineStack) return true;
    }
    return false;
}

static bool _cubicTo(RleWorker& rw, const SwPoint& ctrl1, const SwPoint& ctrl2, const SwPoint& to)
{
    auto arc = rw.bezStack;
    auto end = rw.bezStack + BEZ_STACK_SIZE;
    arc[0] = to;
    arc[1] = ctrl2;
    arc[2] = ctrl1;
    arc[3] = rw.pos;

    auto min = arc[0].y;
    auto max = arc[0].y;

    int32_t y;
    for (auto i = 1; i < 4; ++i) {
        y = arc[i].y;
        if (y < min) min = y;
        if (y > max) max = y;
    }

    if (TRUNC(min) >= rw.cellMax.y || TRUNC(max) < rw.cellMin.y) goto draw;

    while (arc < end) {
        {
            auto diff = arc[3] - arc[0];
            auto L = HYPOT(diff);

            if (L > SHRT_MAX) goto split;

            auto sLimit = L * (ONE_PIXEL / 6);

            auto diff1 = arc[1] - arc[0];
            if (abs(diff.y * diff1.x - diff.x * diff1.y) > sLimit) goto split;

            auto diff2 = arc[2] - arc[0];
            if (abs(diff.y * diff2.x - diff.x * diff2.y) > sLimit) goto split;

            if (diff1.x * (diff1.x - diff.x) + diff1.y * (diff1.y - diff.y) > 0 ||
                diff2.x * (diff2.x - diff.x) + diff2.y * (diff2.y - diff.y) > 0)
                goto split;

            goto draw;
        }
    split:
        _splitCubic(arc);
        arc += 3;
        continue;

    draw:
        if (!_lineTo(rw, arc[0])) return false;
        if (arc == rw.bezStack) return true;
        arc -= 3;
    }
    return false;
}

static bool _decomposeOutline(RleWorker& rw)
{
    auto outline = rw.outline;
    auto pts = outline->out.data;
    auto start = UPSCALE(*pts);
    auto open = false;

    for (auto cmd : outline->path->cmds) {
        switch (cmd) {
            case PathCommand::MoveTo: {
                if (open && !_lineTo(rw, start)) return false;
                start = UPSCALE(*pts++);
                if (!_moveTo(rw, start)) return false;
                open = true;
                break;
            }
            case PathCommand::LineTo: {
                if (!open && !_moveTo(rw, start)) return false;
                if (!_lineTo(rw, UPSCALE(*pts++))) return false;
                open = true;
                break;
            }
            case PathCommand::CubicTo: {
                if (!open && !_moveTo(rw, start)) return false;
                if (!_cubicTo(rw, UPSCALE(pts[0]), UPSCALE(pts[1]), UPSCALE(pts[2]))) return false;
                pts += 3;
                open = true;
                break;
            }
            case PathCommand::Close: {
                if (open && !_lineTo(rw, start)) return false;
                open = false;
                break;
            }
        }
    }
    return !open || _lineTo(rw, start);
}

static bool _genRle(RleWorker& rw)
{
    if (!_decomposeOutline(rw)) return false;
    if (!rw.invalid && !_recordCell(rw)) return false;
    return true;
}

SwRle* rleRender(SwRle* rle, const SwOutline* outline, const RenderRegion& bbox, SwMpool* mpool, unsigned tid, bool antiAlias)
{
    if (!outline) return nullptr;

    RleWorker rw;
    auto cellPool = mpool->cell(tid);
    auto reqSize = uint32_t(std::max(bbox.w(), bbox.h()) * 0.75f) * sizeof(SwCell);

    if (reqSize > cellPool->size) {
        cellPool->size = ((reqSize + (reqSize >> 2)) / sizeof(SwCell)) * sizeof(SwCell);
        tvg::free(cellPool->buffer);
        cellPool->buffer = tvg::malloc<SwCell>(cellPool->size);
    }

    rw.buffer = cellPool->buffer;
    rw.bufferSize = cellPool->size;
    rw.yCells = reinterpret_cast<SwCell**>(cellPool->buffer);
    rw.cells = nullptr;
    rw.maxCells = 0;
    rw.cellsCnt = 0;
    rw.area = 0;
    rw.cover = 0;
    rw.invalid = true;
    rw.cellMin = {bbox.xMin, bbox.yMin};
    rw.cellMax = {bbox.xMax, bbox.yMax};
    rw.cellXCnt = rw.cellMax.x - rw.cellMin.x;
    rw.cellYCnt = rw.cellMax.y - rw.cellMin.y;
    rw.outline = outline;
    rw.bandSize = rw.bufferSize / (sizeof(SwCell) * 2);
    rw.bandShoot = 0;
    rw.antiAlias = antiAlias;

    if (!rle) rw.rle = new SwRle;
    else rw.rle = rle;
    rw.rle->spans.reserve(256);

    constexpr auto BAND_SIZE = 40;

    Band bands[BAND_SIZE];
    Band* band;

    auto bandCnt = static_cast<int>((rw.cellMax.y - rw.cellMin.y) / rw.bandSize);
    if (bandCnt == 0) bandCnt = 1;
    else if (bandCnt >= BAND_SIZE) bandCnt = (BAND_SIZE - 1);

    auto min = rw.cellMin.y;
    auto yMax = rw.cellMax.y;
    int32_t max;

    for (int n = 0; n < bandCnt; ++n, min = max) {
        max = min + rw.bandSize;
        if (n == bandCnt -1 || max > yMax) max = yMax;

        bands[0].min = min;
        bands[0].max = max;
        band = bands;

        while (band >= bands) {
            rw.yCells = reinterpret_cast<SwCell**>(rw.buffer);
            rw.yCnt = band->max - band->min;

            int cellStart = sizeof(SwCell*) * (int)rw.yCnt;
            int cellMod = cellStart % sizeof(SwCell);

            if (cellMod > 0) cellStart += sizeof(SwCell) - cellMod;

            auto cellsMax = reinterpret_cast<SwCell*>((char*)rw.buffer + rw.bufferSize);
            rw.cells = reinterpret_cast<SwCell*>((char*)rw.buffer + cellStart);

            if (rw.cells >= cellsMax) goto reduce_bands;

            rw.maxCells = cellsMax - rw.cells;
            if (rw.maxCells < 2) goto reduce_bands;

            for (int y = 0; y < rw.yCnt; ++y)
                rw.yCells[y] = nullptr;

            rw.cellsCnt = 0;
            rw.invalid = true;
            rw.cellMin.y = band->min;
            rw.cellMax.y = band->max;
            rw.cellYCnt = band->max - band->min;

            if (_genRle(rw)) {
                _sweep(rw);
                --band;
                continue;
            }

        reduce_bands:
            auto bottom = band->min;
            auto top = band->max;
            auto middle = bottom + ((top - bottom) >> 1);

            if (middle == bottom) {
                rleFree(rw.rle);
                return nullptr;
            }

            if (bottom - top >= rw.bandSize) ++rw.bandShoot;

            band[1].min = bottom;
            band[1].max = middle;
            band[0].min = middle;
            band[0].max = top;
            ++band;
        }
    }
    if (rw.bandShoot > 8 && rw.bandSize > 16) {
        rw.bandSize = (rw.bandSize >> 1);
    }
    return rw.rle;
}

SwRle* rleRender(const RenderRegion* bbox)
{
    auto rle = tvg::calloc<SwRle>(sizeof(SwRle), 1);
    rle->spans.reserve(bbox->h());
    rle->spans.count = bbox->h();

    auto x = bbox->xMin;
    auto y = bbox->yMin;
    auto len = (int32_t)bbox->w();

    ARRAY_FOREACH(p, rle->spans) {
        *p = {x, y++, len, 255};
    }

    return rle;
}

void rleReset(SwRle* rle)
{
    if (rle) rle->spans.clear();
}

void rleFree(SwRle* rle)
{
    delete(rle);
}

bool rleClip(SwRle* rle, const SwRle *clip)
{
    if (rle->spans.empty() || clip->spans.empty()) return false;

    Array<SwSpan> out;
    out.reserve(std::max(rle->spans.count, clip->spans.count));

    const SwSpan *end;
    auto spans = rle->fetch(clip->spans.first().y, clip->spans.last().y, &end);

    if (spans >= end) {
        rle->spans.clear();
        return false;
    }

    const SwSpan *cend;
    auto cspans = clip->fetch(spans->y, (end - 1)->y, &cend);

    while (spans < end && cspans < cend) {
        if (cspans->y > spans->y) {
            ++spans;
            continue;
        }
        if (spans->y > cspans->y) {
            ++cspans;
            continue;
        }

        if (spans->len <= 0) {
            ++spans;
            continue;
        }
        if (cspans->len <= 0) {
            ++cspans;
            continue;
        }

        auto spanEnd = spans->x + spans->len;
        auto clipEnd = cspans->x + cspans->len;

        if (spanEnd <= cspans->x) {
            ++spans;
            continue;
        }
        if (clipEnd <= spans->x) {
            ++cspans;
            continue;
        }

        auto x = std::max(spans->x, cspans->x);
        auto len = std::min(spanEnd, clipEnd) - x;
        out.next() = {x, spans->y, len, (uint8_t)(((spans->coverage * cspans->coverage) + 0xff) >> 8)};

        if (spanEnd <= clipEnd) ++spans;
        if (clipEnd <= spanEnd) ++cspans;
    }
    out.move(rle->spans);
    return !rle->spans.empty();
}

bool rleClip(SwRle *rle, const RenderRegion* clip)
{
    if (rle->spans.empty() || clip->invalid()) return false;

    Array<SwSpan> out;
    out.reserve(rle->spans.count);
    auto data = out.data;
    const SwSpan* end;
    int32_t x, len;

    for (auto p = rle->fetch(*clip, &end); p < end; ++p) {
        if (p->y >= clip->yMax) break;
        if (p->y < clip->yMin || p->x >= clip->xMax || (p->x + p->len) <= clip->xMin) continue;
        if (p->x < clip->xMin) {
            x = clip->xMin;
            len = std::min(p->len - (x - p->x), (clip->xMax - x));
        } else {
            x = p->x;
            len = std::min(p->len, clip->xMax - x);
        }
        if (len > 0) {
            *data = {x, p->y, len, p->coverage};
            ++data;
            ++out.count;
        }
    }
    out.move(rle->spans);
    return !rle->spans.empty();
}

bool rleIntersect(const SwRle* rle, const RenderRegion& region)
{
    if (!rle || rle->spans.empty()) return false;

    const SwSpan* end;
    for (auto p = rle->fetch(region, &end); p < end; ++p) {
        if (p->y >= region.yMax) break;
        if (p->y < region.yMin || p->x >= region.xMax || (p->x + p->len) <= region.xMin) continue;
        return true;
    }
    return false;
}
