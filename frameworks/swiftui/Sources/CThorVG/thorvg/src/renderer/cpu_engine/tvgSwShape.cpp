#include "tvgSwCommon.h"

static void _drawPoint(SwDashStroke& dash, const Point& start)
{
    if (dash.move || dash.pattern[dash.curIdx] < FLOAT_EPSILON) {
        dash.path->moveTo(start);
        dash.move = false;
    }
    dash.path->lineTo(start);
}

static void _dashLineTo(SwDashStroke& dash, const Point& to, bool validPoint)
{
    Line cur = {dash.ptCur, to};
    auto len = cur.length();
    if (tvg::zero(len)) {
        dash.ptCur = to;
        return;
    }

    if (len <= dash.curLen) {
        dash.curLen -= len;
        if (!dash.curOpGap) {
            if (dash.move) {
                dash.path->moveTo(dash.ptCur);
                dash.move = false;
            }
            dash.path->lineTo(to);
        }
    } else {
        while (len - dash.curLen > DASH_PATTERN_THRESHOLD) {
            Line left, right;
            if (dash.curLen > 0) {
                len -= dash.curLen;
                cur.split(dash.curLen, left, right);
                if (!dash.curOpGap) {
                    if (dash.move || dash.pattern[dash.curIdx] - dash.curLen < FLOAT_EPSILON) {
                        dash.path->moveTo(left.pt1);
                        dash.move = false;
                    }
                    dash.path->lineTo(left.pt2);
                }
            } else {
                if (validPoint && !dash.curOpGap) _drawPoint(dash, cur.pt1);
                right = cur;
            }
            dash.curIdx = (dash.curIdx + 1) % dash.cnt;
            dash.curLen = dash.pattern[dash.curIdx];
            dash.curOpGap = !dash.curOpGap;
            cur = right;
            dash.ptCur = cur.pt1;
            dash.move = true;
        }
        dash.curLen -= len;
        if (!dash.curOpGap) {
            if (dash.move) {
                dash.path->moveTo(cur.pt1);
                dash.move = false;
            }
            dash.path->lineTo(cur.pt2);
        }
        if (dash.curLen < DASH_PATTERN_THRESHOLD && !tvg::zero(len)) {
            dash.curIdx = (dash.curIdx + 1) % dash.cnt;
            dash.curLen = dash.pattern[dash.curIdx];
            dash.curOpGap = !dash.curOpGap;
            dash.move = true;
        }
    }
    dash.ptCur = to;
}

static void _dashCubicTo(SwDashStroke& dash, const Point& ctrl1, const Point& ctrl2, const Point& to, bool validPoint)
{
    Bezier cur = {dash.ptCur, ctrl1, ctrl2, to};
    auto len = cur.length();
    if (tvg::zero(len)) {
        dash.ptCur = to;
        return;
    }

    if (len <= dash.curLen) {
        dash.curLen -= len;
        if (!dash.curOpGap) {
            if (dash.move) {
                dash.path->moveTo(dash.ptCur);
                dash.move = false;
            }
            dash.path->cubicTo(ctrl1, ctrl2, to);
        }
    } else {
        while ((len - dash.curLen) > DASH_PATTERN_THRESHOLD) {
            Bezier left, right;
            if (dash.curLen > 0) {
                len -= dash.curLen;
                cur.split(dash.curLen, left, right);
                if (!dash.curOpGap) {
                    if (dash.move || dash.pattern[dash.curIdx] - dash.curLen < FLOAT_EPSILON) {
                        dash.path->moveTo(left.start);
                        dash.move = false;
                    }
                    dash.path->cubicTo(left.ctrl1, left.ctrl2, left.end);
                }
            } else {
                if (validPoint && !dash.curOpGap) _drawPoint(dash, cur.start);
                right = cur;
            }
            dash.curIdx = (dash.curIdx + 1) % dash.cnt;
            dash.curLen = dash.pattern[dash.curIdx];
            dash.curOpGap = !dash.curOpGap;
            cur = right;
            dash.ptCur = right.start;
            dash.move = true;
        }
        dash.curLen -= len;
        if (!dash.curOpGap) {
            if (dash.move) {
                dash.path->moveTo(cur.start);
                dash.move = false;
            }
            dash.path->cubicTo(cur.ctrl1, cur.ctrl2, cur.end);
        }
        if (dash.curLen < DASH_PATTERN_THRESHOLD && !tvg::zero(len)) {
            dash.curIdx = (dash.curIdx + 1) % dash.cnt;
            dash.curLen = dash.pattern[dash.curIdx];
            dash.curOpGap = !dash.curOpGap;
            dash.move = true;
        }
    }
    dash.ptCur = to;
}

static void _dashClose(SwDashStroke& dash, bool validPoint, uint32_t cmdBegin, uint32_t ptBegin)
{
    _dashLineTo(dash, dash.ptStart, validPoint);
    auto& cmds = dash.path->cmds;
    auto& pts = dash.path->pts;

    if (cmds.count > cmdBegin + 1 &&
        tvg::closed(pts[ptBegin], dash.ptStart, DASH_PATTERN_THRESHOLD) &&
        tvg::closed(pts.last(), dash.ptStart, DASH_PATTERN_THRESHOLD)) {
        auto cmdEnd = cmdBegin + 1, ptEnd = ptBegin + 1;
        for (; cmdEnd < cmds.count && cmds[cmdEnd] != PathCommand::MoveTo; ++cmdEnd) {
            ptEnd += (cmds[cmdEnd] == PathCommand::CubicTo) ? 3 : 1;
        }

        if (cmdEnd < cmds.count) {
            auto rotate = [](auto& arr, uint32_t from, uint32_t to) {
                arr.grow(to - from);
                memcpy(arr.end(), arr.begin() + from, (to - from) * sizeof(*arr.data));
                memmove(arr.begin() + from, arr.begin() + to, (arr.count - from) * sizeof(*arr.data));
            };
            cmds[cmdBegin] = PathCommand::LineTo;
            rotate(pts, ptBegin, ptEnd);
            rotate(cmds, cmdBegin, cmdEnd);
        }
    }
    dash.move = true;
}

static void _dashMoveTo(SwDashStroke& dash, uint32_t offIdx, float offset, const Point& pts)
{
    dash.curIdx = offIdx % dash.cnt;
    dash.curLen = dash.pattern[dash.curIdx] - offset;
    dash.curOpGap = offIdx % 2;
    dash.ptStart = dash.ptCur = pts;
    dash.move = true;
}

static SwOutline* _genDashOutline(const RenderShape* rshape, SwMpool* mpool, unsigned tid, bool trimmed)
{
    RenderPath trim;
    auto path = &rshape->path;
    if (trimmed) {
        if (!rshape->stroke->trim.trim(*path, trim)) return nullptr;
        path = &trim;
    }

    if (path->cmds.empty() || path->empty()) return nullptr;

    auto cmds = path->cmds.data;
    auto cmdCnt = path->cmds.count;
    auto pts = path->pts.data;

    SwDashStroke dash;
    dash.pattern = rshape->stroke->dash.pattern;
    dash.cnt = rshape->stroke->dash.count;
    auto offset = rshape->stroke->dash.offset;

    uint32_t offIdx = 0;
    if (!tvg::zero(offset)) {
        auto length = rshape->stroke->dash.length;
        bool isOdd = dash.cnt % 2;
        if (isOdd) length *= 2;

        offset = fmodf(offset, length);
        if (offset < 0) offset += length;

        for (size_t i = 0; i < dash.cnt * (1 + (size_t)isOdd); ++i, ++offIdx) {
            auto curPattern = dash.pattern[i % dash.cnt];
            if (offset < curPattern) break;
            offset -= curPattern;
        }
    }

    auto outline = mpool->outline(tid);
    dash.path = const_cast<RenderPath*>(outline->path);
    auto cmdBegin = dash.path->cmds.count;
    auto ptBegin = dash.path->pts.count;

    if (cmds[0] == PathCommand::MoveTo) {
        _dashMoveTo(dash, offIdx, offset, *pts);
        cmds++;
        pts++;
    }

    auto validPoint = rshape->stroke->cap != StrokeCap::Butt;
    while (--cmdCnt > 0) {
        switch (*cmds) {
            case PathCommand::Close: {
                _dashClose(dash, validPoint, cmdBegin, ptBegin);
                cmdBegin = dash.path->cmds.count;
                ptBegin = dash.path->pts.count;
                break;
            }
            case PathCommand::MoveTo: {
                _dashMoveTo(dash, offIdx, offset, *pts);
                cmdBegin = dash.path->cmds.count;
                ptBegin = dash.path->pts.count;
                ++pts;
                break;
            }
            case PathCommand::LineTo: {
                _dashLineTo(dash, *pts, validPoint);
                ++pts;
                break;
            }
            case PathCommand::CubicTo: {
                _dashCubicTo(dash, *pts, pts[1], pts[2], validPoint);
                pts += 3;
                break;
            }
        }
        ++cmds;
    }

    outline->fillRule = rshape->rule;

    return outline;
}

static bool _axisAlignedRect(const SwOutline* outline)
{
    auto& path = *outline->path;
    if (path.cmds.count != 5 || (path.cmds[0] != PathCommand::MoveTo && path.cmds[0] != PathCommand::LineTo)) return false;
    for (uint32_t i = 1; i < 4; ++i) {
        if (path.cmds[i] != PathCommand::LineTo) return false;
    }
    if (path.cmds[4] != PathCommand::Close && path.cmds[4] != PathCommand::LineTo) return false;

    auto pt1 = outline->out.data + 0;
    auto pt2 = outline->out.data + 1;
    auto pt3 = outline->out.data + 2;
    auto pt4 = outline->out.data + 3;

    auto a = SwPoint{pt1->x, pt3->y};
    auto b = SwPoint{pt3->x, pt1->y};

    if ((*pt2 == a && *pt4 == b) || (*pt2 == b && *pt4 == a)) return true;

    return false;
}

static SwOutline* _genOutline(const RenderShape* rshape, SwMpool* mpool, unsigned tid, bool trimmed = false)
{
    auto outline = mpool->outline(tid);
    if (trimmed) {
        if (!rshape->stroke->trim.trim(rshape->path, *const_cast<RenderPath*>(outline->path))) return nullptr;
    } else {
        outline->path = &rshape->path;
    }

    auto path = outline->path;
    if (path->empty() || path->cmds.empty() || path->cmds.first() == PathCommand::CubicTo) return nullptr;

    outline->fillRule = rshape->rule;
    return outline;
}

bool shapeGenRle(SwShape& shape, const RenderShape* rshape, const Matrix& transform, const RenderRegion& clipBox, RenderRegion& renderBox, SwMpool* mpool, unsigned tid, bool composite, bool antiAlias)
{
    auto outline = _genOutline(rshape, mpool, tid, rshape->trimpath());
    if (!outline) {
        renderBox.reset();
        return false;
    }

    BBox bbox;
    utilExport(outline, transform, bbox);

    shape.outline = outline;
    shape.fastTrack = !composite && _axisAlignedRect(outline);

    if (!utilBBox(bbox, clipBox, renderBox, shape.fastTrack)) return false;
    shape.bbox = renderBox;

    if (shape.fastTrack) return true;

    shape.rle = rleRender(shape.rle, outline, renderBox, mpool, tid, antiAlias);
    return shape.rle ? true : false;
}

void shapeDelOutline(SwShape& shape)
{
    shape.outline = nullptr;
}

void shapeReset(SwShape& shape)
{
    rleReset(shape.rle);
    shape.outline = nullptr;
    shape.bbox.reset();
    shape.fastTrack = false;
}

void shapeFree(SwShape& shape)
{
    rleFree(shape.rle);
    shape.rle = nullptr;

    if (shape.fill) {
        tvg::free(shape.fill);
        shape.fill = nullptr;
    }

    if (shape.stroke) {
        rleFree(shape.strokeRle);
        shape.strokeRle = nullptr;
        strokeFree(shape.stroke);
        shape.stroke = nullptr;
    }
}

void shapeDelStroke(SwShape& shape)
{
    if (!shape.stroke) return;
    rleFree(shape.strokeRle);
    shape.strokeRle = nullptr;
    strokeFree(shape.stroke);
    shape.stroke = nullptr;
}

void shapeResetStroke(SwShape& shape, const RenderShape* rshape, const Matrix& transform, SwMpool* mpool, unsigned tid)
{
    if (!shape.stroke) shape.stroke = tvg::calloc<SwStroke>(1, sizeof(SwStroke));
    strokeReset(shape.stroke, rshape, transform, mpool, tid);
    rleReset(shape.strokeRle);
}

bool shapeGenStrokeRle(SwShape& shape, const RenderShape* rshape, const Matrix& transform, const RenderRegion& clipBox, RenderRegion& renderBox, SwMpool* mpool, unsigned tid, bool antiAlias)
{
    shapeResetStroke(shape, rshape, transform, mpool, tid);

    auto dash = (rshape->stroke->dash.length > DASH_PATTERN_THRESHOLD);
    SwOutline* outline;

    if (dash) outline = _genDashOutline(rshape, mpool, tid, rshape->trimpath());
    else outline = shape.outline ? shape.outline : _genOutline(rshape, mpool, tid, rshape->trimpath());
    if (!outline) return false;

    if (!strokeParseOutline(shape.stroke, *outline)) return false;
    BBox bbox;
    outline = strokeExportOutline(shape.stroke, mpool, tid);
    if (outline->path->empty()) return false;
    utilExport(outline, transform, bbox);
    if (!utilBBox(bbox, clipBox, renderBox, false)) return false;

    shape.strokeRle = rleRender(shape.strokeRle, outline, renderBox, mpool, tid, antiAlias);
    return shape.strokeRle ? true : false;
}

bool shapeStrokeBBox(SwShape& shape, const RenderShape* rshape, Point* pt4, const Matrix& m, SwMpool* mpool)
{
    if (rshape->strokeWidth() > 0.0f) {
        auto outline = _genOutline(rshape, mpool, 0, rshape->trimpath());
        if (!outline) return false;

        if (!shape.stroke) shape.stroke = tvg::calloc<SwStroke>(1, sizeof(SwStroke));
        strokeReset(shape.stroke, rshape, m, mpool, 0);
        strokeParseOutline(shape.stroke, *outline);

        auto func = [](SwStrokeBorder* border, const Matrix& m, Point& min, Point& max) {
            ARRAY_FOREACH(pts, border->pts)
            {
                auto t = *pts * m;
                if (t.x < min.x) min.x = t.x;
                if (t.x > max.x) max.x = t.x;
                if (t.y < min.y) min.y = t.y;
                if (t.y > max.y) max.y = t.y;
            }
        };

        Point min = {FLT_MAX, FLT_MAX};
        Point max = {-FLT_MAX, -FLT_MAX};
        func(shape.stroke->borders[0], m, min, max);
        func(shape.stroke->borders[1], m, min, max);

        pt4[0] = min;
        pt4[1] = {max.x, min.y};
        pt4[2] = max;
        pt4[3] = {min.x, max.y};

        return true;
    }
    return false;
}
