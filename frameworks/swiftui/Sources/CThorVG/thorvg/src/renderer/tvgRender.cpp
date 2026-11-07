#include "tvgMath.h"
#include "tvgRender.h"

RenderSurface::RenderSurface(const RenderSurface* rhs)
{
    data = rhs->data;
    stride = rhs->stride;
    w = rhs->w;
    h = rhs->h;
    cs = rhs->cs;
    channelSize = rhs->channelSize;
    premultiplied = rhs->premultiplied;
    opaque = rhs->opaque;
}

void RenderSurface::setup(pixel_t* data, uint32_t stride, uint32_t w, uint32_t h, uint8_t channelSize, ColorSpace cs)
{
    if (cs == ColorSpace::XBGR8888) {
        cs = ColorSpace::ABGR8888;
        this->opaque = true;
    } else if (cs == ColorSpace::XRGB8888) {
        cs = ColorSpace::ARGB8888;
        this->opaque = true;
    }

    this->data = data;
    this->stride = stride;
    this->w = w;
    this->h = h;
    this->channelSize = channelSize;
    this->cs = cs;
    this->premultiplied = (cs == ColorSpace::ABGR8888 || cs == ColorSpace::ARGB8888);
}

uint32_t RenderMethod::ref()
{
    ScopedLock lock(key);
    return (++refCnt);
}

uint32_t RenderMethod::unref()
{
    ScopedLock lock(key);
    return (--refCnt);
}

RenderRegion RenderMethod::viewport()
{
    return vport;
}

bool RenderMethod::viewport(const RenderRegion& vp)
{
    vport = vp;
    return true;
}

RenderPath& RenderPath::scratch()
{
    static thread_local RenderPath dbuffers[3];
    static thread_local int idx = 0;
    if (++idx > 2) idx = 0;
    dbuffers[(idx)].clear();
    return dbuffers[(int)idx];
}

void RenderPath::addCircle(float cx, float cy, float rx, float ry, bool cw)
{
    auto rxKappa = rx * PATH_KAPPA;
    auto ryKappa = ry * PATH_KAPPA;

    cmds.grow(6);
    auto cmds = this->cmds.end();

    cmds[0] = PathCommand::MoveTo;
    cmds[1] = PathCommand::CubicTo;
    cmds[2] = PathCommand::CubicTo;
    cmds[3] = PathCommand::CubicTo;
    cmds[4] = PathCommand::CubicTo;
    cmds[5] = PathCommand::Close;

    this->cmds.count += 6;

    int table[2][13] = {{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}, {0, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 12}};
    int* idx = cw ? table[0] : table[1];

    pts.grow(13);
    auto pts = this->pts.end();

    pts[idx[0]] = {cx, cy - ry};
    pts[idx[1]] = {cx + rxKappa, cy - ry};
    pts[idx[2]] = {cx + rx, cy - ryKappa};
    pts[idx[3]] = {cx + rx, cy};
    pts[idx[4]] = {cx + rx, cy + ryKappa};
    pts[idx[5]] = {cx + rxKappa, cy + ry};
    pts[idx[6]] = {cx, cy + ry};
    pts[idx[7]] = {cx - rxKappa, cy + ry};
    pts[idx[8]] = {cx - rx, cy + ryKappa};
    pts[idx[9]] = {cx - rx, cy};
    pts[idx[10]] = {cx - rx, cy - ryKappa};
    pts[idx[11]] = {cx - rxKappa, cy - ry};
    pts[idx[12]] = {cx, cy - ry};

    this->pts.count += 13;
}

void RenderPath::addRect(float x, float y, float w, float h, float rx, float ry, bool cw)
{
    if (tvg::zero(rx) && tvg::zero(ry)) {
        cmds.grow(5);
        pts.grow(4);

        auto cmds = this->cmds.end();
        auto pts = this->pts.end();

        cmds[0] = PathCommand::MoveTo;
        cmds[1] = cmds[2] = cmds[3] = PathCommand::LineTo;
        cmds[4] = PathCommand::Close;

        pts[0] = {x + w, y};
        pts[2] = {x, y + h};
        if (cw) {
            pts[1] = {x + w, y + h};
            pts[3] = {x, y};
        } else {
            pts[1] = {x, y};
            pts[3] = {x + w, y + h};
        }

        this->cmds.count += 5;
        this->pts.count += 4;
    } else {
        auto hsize = Point{w * 0.5f, h * 0.5f};
        rx = (rx > hsize.x) ? hsize.x : rx;
        ry = (ry > hsize.y) ? hsize.y : ry;
        auto hr = Point{rx * PATH_KAPPA, ry * PATH_KAPPA};

        cmds.grow(10);
        pts.grow(17);

        auto cmds = this->cmds.end();
        auto pts = this->pts.end();

        cmds[0] = PathCommand::MoveTo;
        cmds[9] = PathCommand::Close;
        pts[0] = {x + w, y + ry};

        if (cw) {
            cmds[1] = cmds[3] = cmds[5] = cmds[7] = PathCommand::LineTo;
            cmds[2] = cmds[4] = cmds[6] = cmds[8] = PathCommand::CubicTo;

            pts[1] = {x + w, y + h - ry};
            pts[2] = {x + w, y + h - ry + hr.y};
            pts[3] = {x + w - rx + hr.x, y + h};
            pts[4] = {x + w - rx, y + h};
            pts[5] = {x + rx, y + h};
            pts[6] = {x + rx - hr.x, y + h};
            pts[7] = {x, y + h - ry + hr.y};
            pts[8] = {x, y + h - ry};
            pts[9] = {x, y + ry};
            pts[10] = {x, y + ry - hr.y};
            pts[11] = {x + rx - hr.x, y};
            pts[12] = {x + rx, y};
            pts[13] = {x + w - rx, y};
            pts[14] = {x + w - rx + hr.x, y};
            pts[15] = {x + w, y + ry - hr.y};
            pts[16] = {x + w, y + ry};
        } else {
            cmds[1] = cmds[3] = cmds[5] = cmds[7] = PathCommand::CubicTo;
            cmds[2] = cmds[4] = cmds[6] = cmds[8] = PathCommand::LineTo;

            pts[1] = {x + w, y + ry - hr.y};
            pts[2] = {x + w - rx + hr.x, y};
            pts[3] = {x + w - rx, y};
            pts[4] = {x + rx, y};
            pts[5] = {x + rx - hr.x, y};
            pts[6] = {x, y + ry - hr.y};
            pts[7] = {x, y + ry};
            pts[8] = {x, y + h - ry};
            pts[9] = {x, y + h - ry + hr.y};
            pts[10] = {x + rx - hr.x, y + h};
            pts[11] = {x + rx, y + h};
            pts[12] = {x + w - rx, y + h};
            pts[13] = {x + w - rx + hr.x, y + h};
            pts[14] = {x + w, y + h - ry + hr.y};
            pts[15] = {x + w, y + h - ry};
            pts[16] = {x + w, y + ry};
        }

        this->cmds.count += 10;
        this->pts.count += 17;
    }
}

bool RenderPath::bounds(const Matrix* m, BBox& box)
{
    if (cmds.empty() || cmds.first() == PathCommand::CubicTo) return false;

    box.init();

    auto pt = pts.begin();
    auto cmd = cmds.begin();

    auto assign = [&](const Point& pt, BBox& box) -> void {
        if (pt.x < box.min.x) box.min.x = pt.x;
        if (pt.y < box.min.y) box.min.y = pt.y;
        if (pt.x > box.max.x) box.max.x = pt.x;
        if (pt.y > box.max.y) box.max.y = pt.y;
    };

    while (cmd < cmds.end()) {
        switch (*cmd) {
            case PathCommand::MoveTo: {
                if (cmd + 1 < cmds.end()) {
                    auto next = *(cmd + 1);
                    if (next == PathCommand::LineTo || next == PathCommand::CubicTo) {
                        assign(*pt * m, box);
                    }
                }
                ++pt;
                break;
            }
            case PathCommand::LineTo: {
                assign(*pt * m, box);
                ++pt;
                break;
            }
            case PathCommand::CubicTo: {
                Bezier::bounds(box, pt[-1] * m, pt[0] * m, pt[1] * m, pt[2] * m);
                pt += 3;
                break;
            }
            default: break;
        }
        ++cmd;
    }
    return true;
}

void RenderRegion::intersect(const RenderRegion& rhs)
{
    if (xMin < rhs.xMin) xMin = rhs.xMin;
    if (yMin < rhs.yMin) yMin = rhs.yMin;
    if (xMax > rhs.xMax) xMax = rhs.xMax;
    if (yMax > rhs.yMax) yMax = rhs.yMax;

    if (xMax < xMin) xMax = xMin;
    if (yMax < yMin) yMax = yMin;
}

#ifdef THORVG_PARTIAL_RENDER_SUPPORT

#include <algorithm>

void RenderDirtyRegion::init(uint32_t w, uint32_t h)
{
    auto cnt = int(sqrt(PARTITIONING));
    auto px = int32_t(w / cnt);
    auto py = int32_t(h / cnt);
    auto lx = int32_t(w % cnt);
    auto ly = int32_t(h % cnt);

    for (int y = 0; y < cnt; ++y) {
        for (int x = 0; x < cnt; ++x) {
            auto& partition = partitions[y * cnt + x];
            partition.list[0].reserve(64);
            auto& region = partition.region;
            region.xMin = x * px;
            region.yMin = y * py;
            region.xMax = region.xMin + px;
            region.yMax = region.yMin + py;
            if (x == cnt - 1) region.xMax += lx;
            if (y == cnt - 1) region.yMax += ly;
        }
    }
}

bool RenderDirtyRegion::add(const RenderRegion& bbox)
{
    for (int idx = 0; idx < PARTITIONING; ++idx) {
        auto& partition = partitions[idx];
        if (bbox.yMax <= partition.region.yMin) break;
        if (bbox.intersected(partition.region)) {
            ScopedLock lock(key);
            partition.list[partition.current].push(RenderRegion::intersect(bbox, partition.region));
        }
    }
    return true;
}

bool RenderDirtyRegion::add(const RenderRegion& prv, const RenderRegion& cur)
{
    if (prv == cur) return add(prv);

    for (int idx = 0; idx < PARTITIONING; ++idx) {
        auto& partition = partitions[idx];
        if (prv.intersected(partition.region)) {
            ScopedLock lock(key);
            partition.list[partition.current].push(RenderRegion::intersect(prv, partition.region));
        }
        if (cur.intersected(partition.region)) {
            ScopedLock lock(key);
            partition.list[partition.current].push(RenderRegion::intersect(cur, partition.region));
        }
    }
    return true;
}

void RenderDirtyRegion::clear()
{
    for (int idx = 0; idx < PARTITIONING; ++idx) {
        partitions[idx].list[0].clear();
        partitions[idx].list[1].clear();
    }
}

void RenderDirtyRegion::subdivide(Array<RenderRegion>& targets, uint32_t idx, RenderRegion& lhs, RenderRegion& rhs)
{
    RenderRegion temp[3];
    uint32_t cnt = 0;

    if (rhs.yMin < lhs.yMin) {
        temp[cnt++] = {rhs.xMin, rhs.yMin, rhs.xMax, lhs.yMin};
        rhs.yMin = lhs.yMin;
    }
    if (rhs.yMax > lhs.yMax) {
        temp[cnt++] = {rhs.xMin, lhs.yMax, rhs.xMax, rhs.yMax};
        rhs.yMax = lhs.yMax;
    }
    if (rhs.xMax > lhs.xMax) {
        temp[cnt++] = {lhs.xMax, rhs.yMin, rhs.xMax, rhs.yMax};
    }

    if (targets.count + cnt - 1 >= targets.reserved) {
        TVGERR("RENDERER", "reserved(%d), required(%d)", targets.reserved, targets.count + cnt - 1);
        return;
    }

    auto src = &targets[idx + 1];
    auto dst = &targets[idx + cnt];
    auto nmove = targets.count - idx - 1;
    memmove(dst, src, sizeof(RenderRegion) * nmove);
    memcpy(&targets[idx], temp, sizeof(RenderRegion) * cnt);
    targets.count += (cnt - 1);

    while (dst < targets.end() && dst->xMin < rhs.xMax) ++dst;
    stable_sort(&targets[idx], dst, [](const RenderRegion& a, const RenderRegion& b) -> bool {
        return a.xMin < b.xMin;
    });
}

void RenderDirtyRegion::commit()
{
    if (disabled) return;

    for (int idx = 0; idx < PARTITIONING; ++idx) {
        auto current = partitions[idx].current;
        auto& targets = partitions[idx].list[current];
        if (targets.empty()) continue;

        current = !current;
        auto& output = partitions[idx].list[current];

        targets.reserve(targets.count * 10);
        output.reserve(targets.count);

        partitions[idx].current = current;

        stable_sort(targets.begin(), targets.end(), [](const RenderRegion& a, const RenderRegion& b) -> bool {
            return a.xMin < b.xMin;
        });

        for (uint32_t i = 0; i < targets.count; ++i) {
            auto& lhs = targets[i];
            if (lhs.invalid()) continue;
            auto merged = false;

            for (uint32_t j = i + 1; j < targets.count; ++j) {
                auto& rhs = targets[j];
                if (rhs.invalid()) continue;
                if (lhs.xMax < rhs.xMin) break;

                if (rhs.contained(lhs)) {
                    merged = true;
                    break;
                }
                if (lhs.contained(rhs)) {
                    rhs = {};
                    continue;
                }
                if (lhs.yMin == rhs.yMin && lhs.yMax == rhs.yMax) {
                    if (lhs.xMax >= rhs.xMin) {
                        lhs.xMax = rhs.xMax;
                        rhs = {};
                        j = i;
                        continue;
                    }
                }
                if (lhs.xMin == rhs.xMin && lhs.xMax == rhs.xMax) {
                    if (lhs.yMin <= rhs.yMax && rhs.yMin <= lhs.yMax) {
                        rhs.yMin = std::min(lhs.yMin, rhs.yMin);
                        rhs.yMax = std::max(lhs.yMax, rhs.yMax);
                        merged = true;
                        break;
                    }
                }
                if (lhs.intersected(rhs)) {
                    subdivide(targets, j, lhs, rhs);
                    --j;
                }
            }
            if (!merged) output.push(lhs);
            lhs = {};
        }
    }
}

#endif

#define EPSILON 1e-4f

static void _trimAt(const PathCommand* cmds, const Point* pts, Point& moveTo, float at1, float at2, bool start, RenderPath& out)
{
    switch (*cmds) {
        case PathCommand::LineTo: {
            Line tmp, left, right;
            Line{*(pts - 1), *pts}.split(at1, left, tmp);
            tmp.split(at2, left, right);
            if (start) {
                out.pts.push(left.pt1);
                moveTo = left.pt1;
                out.cmds.push(PathCommand::MoveTo);
            }
            out.pts.push(left.pt2);
            out.cmds.push(PathCommand::LineTo);
            break;
        }
        case PathCommand::CubicTo: {
            Bezier tmp, left, right;
            Bezier{*(pts - 1), *pts, *(pts + 1), *(pts + 2)}.split(at1, left, tmp);
            tmp.split(at2, left, right);
            if (start) {
                moveTo = left.start;
                out.pts.push(left.start);
                out.cmds.push(PathCommand::MoveTo);
            }
            out.pts.push(left.ctrl1);
            out.pts.push(left.ctrl2);
            out.pts.push(left.end);
            out.cmds.push(PathCommand::CubicTo);
            break;
        }
        case PathCommand::Close: {
            Line tmp, left, right;
            Line{*(pts - 1), moveTo}.split(at1, left, tmp);
            tmp.split(at2, left, right);
            if (start) {
                moveTo = left.pt1;
                out.pts.push(left.pt1);
                out.cmds.push(PathCommand::MoveTo);
            }
            out.pts.push(left.pt2);
            out.cmds.push(PathCommand::LineTo);
            break;
        }
        default: break;
    }
}

static void _add(const PathCommand* cmds, const Point* pts, const Point& moveTo, bool& start, RenderPath& out)
{
    switch (*cmds) {
        case PathCommand::MoveTo: {
            out.cmds.push(PathCommand::MoveTo);
            out.pts.push(*pts);
            start = false;
            break;
        }
        case PathCommand::LineTo: {
            if (start) {
                out.cmds.push(PathCommand::MoveTo);
                out.pts.push(*(pts - 1));
            }
            out.cmds.push(PathCommand::LineTo);
            out.pts.push(*pts);
            start = false;
            break;
        }
        case PathCommand::CubicTo: {
            if (start) {
                out.cmds.push(PathCommand::MoveTo);
                out.pts.push(*(pts - 1));
            }
            out.cmds.push(PathCommand::CubicTo);
            out.pts.push(*pts);
            out.pts.push(*(pts + 1));
            out.pts.push(*(pts + 2));
            start = false;
            break;
        }
        case PathCommand::Close: {
            if (start) {
                out.cmds.push(PathCommand::MoveTo);
                out.pts.push(*(pts - 1));
            }
            out.cmds.push(PathCommand::LineTo);
            out.pts.push(moveTo);
            start = true;
            break;
        }
    }
}

static void _trimPath(const PathCommand* inCmds, uint32_t inCmdsCnt, const Point* inPts, TVG_UNUSED uint32_t inPtsCnt, float trimStart, float trimEnd, RenderPath& out, bool connect = false)
{
    auto cmds = const_cast<PathCommand*>(inCmds);
    auto pts = const_cast<Point*>(inPts);
    auto moveToTrimmed = *pts;
    auto moveTo = *pts;
    auto len = 0.0f;

    auto _length = [&]() -> float {
        switch (*cmds) {
            case PathCommand::MoveTo: return 0.0f;
            case PathCommand::LineTo: return tvg::length(*(pts - 1), *pts);
            case PathCommand::CubicTo: return Bezier{*(pts - 1), *pts, *(pts + 1), *(pts + 2)}.length();
            case PathCommand::Close: return tvg::length(*(pts - 1), moveTo);
        }
        return 0.0f;
    };

    auto _shift = [&]() -> void {
        switch (*cmds) {
            case PathCommand::MoveTo:
                moveTo = *pts;
                moveToTrimmed = *pts;
                ++pts;
                break;
            case PathCommand::LineTo:
                ++pts;
                break;
            case PathCommand::CubicTo:
                pts += 3;
                break;
            case PathCommand::Close:
                break;
        }
        ++cmds;
    };

    auto start = !connect;

    for (uint32_t i = 0; i < inCmdsCnt; ++i) {
        auto dLen = _length();

        if (len <= trimStart) {
            if (len + dLen > trimEnd) {
                _trimAt(cmds, pts, moveToTrimmed, trimStart - len, trimEnd - trimStart, start, out);
                start = false;
            } else if (len + dLen > trimStart + EPSILON) {
                _trimAt(cmds, pts, moveToTrimmed, trimStart - len, len + dLen - trimStart, start, out);
                start = false;
            }
        } else if (len <= trimEnd - EPSILON) {
            if (len + dLen > trimEnd) {
                _trimAt(cmds, pts, moveTo, 0.0f, trimEnd - len, start, out);
                start = true;
            } else if (len + dLen > trimStart + EPSILON) _add(cmds, pts, moveTo, start, out);
        }

        len += dLen;
        _shift();
    }
}

static void _trim(const PathCommand* inCmds, uint32_t inCmdsCnt, const Point* inPts, uint32_t inPtsCnt, float begin, float end, bool connect, RenderPath& out)
{
    auto totalLength = tvg::length(inCmds, inCmdsCnt, inPts, inPtsCnt);
    auto trimStart = begin * totalLength;
    auto trimEnd = end * totalLength;

    if (begin >= end) {
        auto cnt = out.cmds.count;
        _trimPath(inCmds, inCmdsCnt, inPts, inPtsCnt, trimStart, totalLength, out);
        _trimPath(inCmds, inCmdsCnt, inPts, inPtsCnt, 0.0f, trimEnd, out, connect && out.cmds.count > cnt);
    } else {
        _trimPath(inCmds, inCmdsCnt, inPts, inPtsCnt, trimStart, trimEnd, out);
    }
}

static void _get(float& begin, float& end)
{
    auto loop = true;

    if (begin > 1.0f && end > 1.0f) loop = false;
    if (begin < 0.0f && end < 0.0f) loop = false;
    if (begin >= 0.0f && begin <= 1.0f && end >= 0.0f  && end <= 1.0f) loop = false;

    if (begin > 1.0f) begin -= 1.0f;
    if (begin < 0.0f) begin += 1.0f;
    if (end > 1.0f) end -= 1.0f;
    if (end < 0.0f) end += 1.0f;

    if ((loop && begin < end) || (!loop && begin > end)) std::swap(begin, end);
}

bool RenderTrimPath::trim(const RenderPath& in, RenderPath& out) const
{
    if (in.pts.count < 2 || tvg::zero(begin - end)) return false;

    float begin = this->begin, end = this->end;
    _get(begin, end);

    out.cmds.reserve(in.cmds.count * 2);
    out.pts.reserve(in.pts.count * 2);

    auto pts = in.pts.data;
    auto cmds = in.cmds.data;

    if (simultaneous) {
        auto startCmds = cmds;
        auto startPts = pts;
        uint32_t i = 0;
        while (i < in.cmds.count) {
            switch (in.cmds[i]) {
                case PathCommand::MoveTo: {
                    if (startCmds != cmds) _trim(startCmds, cmds - startCmds, startPts, pts - startPts, begin, end, *(cmds - 1) == PathCommand::Close, out);
                    startPts = pts;
                    startCmds = cmds;
                    ++pts;
                    ++cmds;
                    break;
                }
                case PathCommand::LineTo: {
                    ++pts;
                    ++cmds;
                    break;
                }
                case PathCommand::CubicTo: {
                    pts += 3;
                    ++cmds;
                    break;
                }
                case PathCommand::Close: {
                    ++cmds;
                    if (startCmds != cmds) _trim(startCmds, cmds - startCmds, startPts, pts - startPts, begin, end, *(cmds - 1) == PathCommand::Close, out);
                    startPts = pts;
                    startCmds = cmds;
                    break;
                }
            }
            i++;
        }
        if (startCmds != cmds) _trim(startCmds, cmds - startCmds, startPts, pts - startPts, begin, end, *(cmds - 1) == PathCommand::Close, out);
    } else {
        _trim(in.cmds.data, in.cmds.count, in.pts.data, in.pts.count, begin, end, false, out);
    }

    return out.pts.count >= 2;
}
