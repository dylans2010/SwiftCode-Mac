#include "tvgSwCommon.h"

#define SW_STROKE_TAG_POINT 1
#define SW_STROKE_TAG_CUBIC 2
#define SW_STROKE_TAG_BEGIN 4
#define SW_STROKE_TAG_END 8

static inline float _sideToRotate(int32_t s)
{
    return (MATH_PI2 - float(s) * MATH_PI);
}

static inline bool _tiny(const Point& pt)
{
    constexpr float EPSILON = 2.0f / 64.0f;
    return fabsf(pt.x) < EPSILON && fabsf(pt.y) < EPSILON;
}

static inline float _mean(float angle1, float angle2)
{
    return angle1 + remainderf(angle2 - angle1, MATH_2PI) * 0.5f;
}

static void _rotate(Point& pt, float radian)
{
    if (tvg::zero(radian)) return;
    auto cosv = cosf(radian);
    auto sinv = sinf(radian);
    auto x = pt.x * cosv - pt.y * sinv;
    auto y = pt.x * sinv + pt.y * cosv;
    pt = {x, y};
}

static void _growBorder(SwStrokeBorder* border, uint32_t newPts)
{
    if (border->pts.count + newPts <= border->pts.reserved) return;
    border->pts.grow(newPts * 20);
    border->tags = tvg::realloc<uint8_t>(border->tags, border->pts.reserved);
}

static void _borderClose(SwStrokeBorder* border, bool reverse)
{
    auto start = border->start;
    auto count = border->pts.count;

    if (count <= start + 1U) {
        border->pts.count = start;
    } else {
        border->pts.count = --count;
        border->pts[start] = border->pts[count];

        if (reverse) {
            auto pt1 = border->pts.data + start + 1;
            auto pt2 = border->pts.data + count - 1;

            while (pt1 < pt2) {
                std::swap(*pt1, *pt2);
                ++pt1;
                --pt2;
            }

            auto tag1 = border->tags + start + 1;
            auto tag2 = border->tags + count - 1;

            while (tag1 < tag2) {
                std::swap(*tag1, *tag2);
                ++tag1;
                --tag2;
            }
        }

        border->tags[start] |= SW_STROKE_TAG_BEGIN;
        border->tags[count - 1] |=  SW_STROKE_TAG_END;
    }

    border->start = -1;
    border->movable = false;
}

static void _borderCubicTo(SwStrokeBorder* border, const Point& ctrl1, const Point& ctrl2, const Point& to)
{
    _growBorder(border, 3);

    auto tag = border->tags + border->pts.count;

    border->pts.push(ctrl1);
    border->pts.push(ctrl2);
    border->pts.push(to);

    tag[0] = SW_STROKE_TAG_CUBIC;
    tag[1] = SW_STROKE_TAG_CUBIC;
    tag[2] = SW_STROKE_TAG_POINT;

    border->movable = false;
}

static void _borderLineTo(SwStrokeBorder* border, const Point& to, bool movable)
{
    if (border->movable) {
        border->pts.last() = to;
    } else {
        if (!border->pts.empty() && _tiny(border->pts.last() - to)) return;
        _growBorder(border, 1);
        border->tags[border->pts.count] = SW_STROKE_TAG_POINT;
        border->pts.push(to);
    }
    border->movable = movable;
}

static void _borderMoveTo(SwStrokeBorder* border, const Point& to)
{
    if (border->start >= 0) _borderClose(border, false);

    border->start = border->pts.count;
    border->movable = false;

    _borderLineTo(border, to, false);
}

static void _borderArcTo(SwStroke& stroke, int32_t side)
{
    auto border = stroke.borders[side];
    auto rotate = _sideToRotate(side);
    auto angleStart = stroke.angleIn + rotate;
    auto angleDiff = remainderf(stroke.angleOut - stroke.angleIn, MATH_2PI);
    if (tvg::equal(angleDiff, MATH_PI)) angleDiff = -rotate * 2.0f;

    auto a = Point{stroke.width, 0.0f};
    _rotate(a, angleStart);
    a += stroke.center;

    auto total = angleDiff;
    auto angle = angleStart;
    rotate = (angleDiff >= 0) ? MATH_PI2 : -MATH_PI2;

    while (!tvg::zero(total)) {
        auto step = total;
        if (step > MATH_PI2) step = MATH_PI2;
        else if (step < -MATH_PI2) step = -MATH_PI2;

        auto next = angle + step;
        auto theta = step;
        if (theta < 0) theta = -theta;
        theta *= 0.5f;

        auto b = Point{stroke.width, 0.0f};
        _rotate(b, next);
        b += stroke.center;

        auto length = stroke.width * (4.0f / 3.0f) * std::tan(theta * 0.5f);

        auto a2 = Point{length, 0.0f};
        _rotate(a2, angle + rotate);
        a2 += a;

        auto b2 = Point{length, 0.0f};
        _rotate(b2, next - rotate);
        b2 += b;

        _borderCubicTo(border, a2, b2, b);

        a = b;
        total -= step;
        angle = next;
    }

    border->movable = false;
}

static void _outside(SwStroke& stroke, int32_t side, float length)
{
    auto border = stroke.borders[side];

    if (stroke.join == StrokeJoin::Round) {
        _borderArcTo(stroke, side);
    } else {
        auto rotate = _sideToRotate(side);
        auto bevel = stroke.join == StrokeJoin::Bevel;
        auto phi = 0.0f;
        auto thcos = 0.0f;

        if (!bevel) {
            auto theta = remainderf(stroke.angleOut - stroke.angleIn, MATH_2PI);
            if (tvg::equal(theta, MATH_PI)) {
                theta = rotate;
                phi = stroke.angleIn;
            } else {
                theta *= 0.5f;
                phi = stroke.angleIn + theta + rotate;
            }
            thcos = std::cos(theta);

            if (stroke.miterlimit * thcos < 1.0f) bevel = true;
        }

        if (bevel) {
            auto delta = Point{stroke.width, 0.0f};
            _rotate(delta, stroke.angleOut + rotate);
            delta += stroke.center;
            border->movable = false;
            _borderLineTo(border, delta, false);
        } else {
            auto delta = Point{stroke.width / thcos, 0.0f};
            _rotate(delta, phi);
            delta += stroke.center;
            _borderLineTo(border, delta, false);

            if (tvg::zero(length)) {
                delta = {stroke.width, 0.0f};
                _rotate(delta, stroke.angleOut + rotate);
                delta += stroke.center;
                _borderLineTo(border, delta, false);
            }
        }
    }
}

static void _inside(SwStroke& stroke, int32_t side, float length)
{
    auto border = stroke.borders[side];
    auto theta = remainderf(stroke.angleOut - stroke.angleIn, MATH_2PI) * 0.5f;
    auto intersect = false;

    if (border->movable && length > 0.0f) {
        auto minLength = fabsf(stroke.width * std::tan(theta));
        if (stroke.length >= minLength && length >= minLength) intersect = true;
    }

    auto rotate = _sideToRotate(side);
    Point delta;

    if (!intersect) {
        delta = {stroke.width, 0.0f};
        _rotate(delta, stroke.angleOut + rotate);
        delta += stroke.center;
        border->movable = false;
    } else {
        auto phi = stroke.angleIn + theta;
        auto thcos = std::cos(theta);
        delta = {stroke.width / thcos, 0.0f};
        _rotate(delta, phi + rotate);
        delta += stroke.center;
    }
    _borderLineTo(border, delta, false);
}

static void _processCorner(SwStroke& stroke, float length)
{
    auto turn = remainderf(stroke.angleOut - stroke.angleIn, MATH_2PI);

    if (tvg::zero(turn)) return;

    auto inside = (turn < 0.0f) ? 1 : 0;

    _inside(stroke, inside, length);
    _outside(stroke, 1 - inside, length);
}

static void _firstSubPath(SwStroke& stroke, float startAngle, float length)
{
    auto delta = Point{stroke.width, 0.0f};
    _rotate(delta, startAngle + MATH_PI2);

    _borderMoveTo(stroke.borders[0], stroke.center + delta);
    _borderMoveTo(stroke.borders[1], stroke.center - delta);

    stroke.subPathAngle = startAngle;
    stroke.firstPt = false;
    stroke.subPathLength = length;
}

static void _lineTo(SwStroke& stroke, const Point& to)
{
    auto delta = to - stroke.center;

    if (tvg::zero(delta)) {
        if (stroke.firstPt && stroke.cap != StrokeCap::Butt) _firstSubPath(stroke, 0.0f, 0.0f);
        return;
    }

    auto length = tvg::length(delta);
    auto angle = tvg::atan(delta);

    delta = {stroke.width, 0.0f};
    _rotate(delta, angle + MATH_PI2);

    if (stroke.firstPt) {
        _firstSubPath(stroke, angle, length);
    } else {
        stroke.angleOut = angle;
        _processCorner(stroke, length);
    }

    for (int side = 0; side < 2; ++side) {
        _borderLineTo(stroke.borders[side], to + delta, true);
        delta.x = -delta.x;
        delta.y = -delta.y;
    }

    stroke.angleIn = angle;
    stroke.center = to;
    stroke.length = length;
}

static int _cubicAngle(const Point* base, float& angleIn, float& angleMid, float& angleOut)
{
    auto d1 = base[2] - base[3];
    auto d2 = base[1] - base[2];
    auto d3 = base[0] - base[1];

    if (_tiny(d1)) {
        if (_tiny(d2)) {
            if (_tiny(d3)) {
                angleIn = angleMid = angleOut = 0;
                return -1;
            } else {
                angleIn = angleMid = angleOut = tvg::atan(d3);
            }
        } else {
            if (_tiny(d3)) {
                angleIn = angleMid = angleOut = tvg::atan(d2);
            } else {
                angleIn = angleMid = tvg::atan(d2);
                angleOut = tvg::atan(d3);
            }
        }
    } else {
        if (_tiny(d2)) {
            if (_tiny(d3)) {
                angleIn = angleMid = angleOut = tvg::atan(d1);
            } else {
                angleIn = tvg::atan(d1);
                angleOut = tvg::atan(d3);
                angleMid = _mean(angleIn, angleOut);
            }
        } else {
            if (_tiny(d3)) {
                angleIn = tvg::atan(d1);
                angleMid = angleOut = tvg::atan(d2);
            } else {
                angleIn = tvg::atan(d1);
                angleMid = tvg::atan(d2);
                angleOut = tvg::atan(d3);
            }
        }
    }

    auto theta1 = fabsf(remainderf(angleMid - angleIn, MATH_2PI));
    auto theta2 = fabsf(remainderf(angleOut - angleMid, MATH_2PI));

    if ((theta1 < (MATH_PI / 8)) && (theta2 < (MATH_PI / 8))) return 0;
    return 1;
}

static void _splitCubic(Point* base)
{
    auto p01 = (base[0] + base[1]) * 0.5f;
    auto p12 = (base[1] + base[2]) * 0.5f;
    auto p23 = (base[2] + base[3]) * 0.5f;
    auto p012 = (p01 + p12) * 0.5f;
    auto p123 = (p12 + p23) * 0.5f;
    auto mid = (p012 + p123) * 0.5f;

    base[6] = base[3];
    base[1] = p01;
    base[2] = p012;
    base[3] = mid;
    base[4] = p123;
    base[5] = p23;
}

static void _cubicTo(SwStroke& stroke, const Point& ctrl1, const Point& ctrl2, const Point& to)
{
    Point bezStack[37];
    auto limit = bezStack + 32;
    auto arc = bezStack;
    auto firstArc = true;
    arc[0] = to;
    arc[1] = ctrl2;
    arc[2] = ctrl1;
    arc[3] = stroke.center;

    auto join = stroke.join;

    while (arc >= bezStack) {
        float angleIn, angleOut, angleMid;

        angleIn = angleOut = angleMid = stroke.angleIn;
        auto valid = _cubicAngle(arc, angleIn, angleMid, angleOut);

        if (valid > 0 && arc < limit) {
            if (stroke.firstPt) stroke.angleIn = angleIn;
            _splitCubic(arc);
            arc += 3;
            continue;
        }

        if (valid < 0 && arc == bezStack) {
            stroke.center = to;
            if (stroke.firstPt && stroke.cap != StrokeCap::Butt) _firstSubPath(stroke, 0.0f, 0.0f);
            return;
        }

        if (firstArc) {
            firstArc = false;
            if (stroke.firstPt) {
                _firstSubPath(stroke, angleIn, 0.0f);
            } else {
                stroke.angleOut = angleIn;
                _processCorner(stroke, 0.0f);
            }
        } else if (fabsf(remainderf(angleIn - stroke.angleIn, MATH_2PI)) > (MATH_PI / 8) / 4) {
            stroke.center = arc[3];
            stroke.angleOut = angleIn;
            stroke.join = StrokeJoin::Round;

            _processCorner(stroke, 0.0f);

            stroke.join = join;
        }

        auto theta1 = remainderf(angleMid - angleIn, MATH_2PI) * 0.5f;
        auto theta2 = remainderf(angleOut - angleMid, MATH_2PI) * 0.5f;
        auto phi1 = _mean(angleIn, angleMid);
        auto phi2 = _mean(angleMid, angleOut);
        auto length1 = stroke.width / std::cos(theta1);
        auto length2 = stroke.width / std::cos(theta2);
        auto alpha0 = 0.0f;

        if (stroke.handleWideStrokes) {
            alpha0 = tvg::atan(arc[0] - arc[3]);
        }

        for (int side = 0; side < 2; ++side) {
            auto border = stroke.borders[side];
            auto rotate = _sideToRotate(side);

            auto c1 = Point{length1, 0.0f};
            _rotate(c1, phi1 + rotate);
            c1 += arc[2];

            auto c2 = Point{length2, 0.0f};
            _rotate(c2, phi2 + rotate);
            c2 += arc[1];

            auto end = Point{stroke.width, 0.0f};
            _rotate(end, angleOut + rotate);
            end += arc[0];

            if (stroke.handleWideStrokes) {
                auto start = border->pts.last();
                auto alpha1 = tvg::atan(end - start);

                if (fabsf(remainderf(alpha1 - alpha0, MATH_2PI)) > MATH_PI2) {
                    auto beta = tvg::atan(arc[3] - start);
                    auto gamma = tvg::atan(arc[0] - end);
                    auto bvec = end - start;
                    auto blen = tvg::length(bvec);
                    auto sinA = fabsf(std::sin(alpha1 - gamma));
                    auto sinB = fabsf(std::sin(beta - gamma));
                    auto alen = (blen * sinA) / sinB;

                    auto delta = Point{alen, 0.0f};
                    _rotate(delta, beta);
                    delta += start;

                    border->movable = false;
                    _borderLineTo(border, delta, false);
                    _borderLineTo(border, end, false);
                    _borderCubicTo(border, c2, c1, start);

                    _borderLineTo(border, end, false);
                    continue;
                }
            }
            _borderCubicTo(border, c1, c2, end);
        }
        arc -= 3;
        stroke.angleIn = angleOut;
    }
    stroke.center = to;
}

static void _addCap(SwStroke& stroke, float angle, int32_t side)
{
    auto rotate = _sideToRotate(side);
    auto border = stroke.borders[side];
    auto delta = Point{stroke.width, 0.0f};

    if (stroke.cap == StrokeCap::Square) {
        _rotate(delta, angle);

        auto delta2 = Point{stroke.width, 0.0f};
        _rotate(delta2, angle + rotate);
        delta += stroke.center + delta2;
        _borderLineTo(border, delta, false);

        delta = {stroke.width, 0.0f};
        _rotate(delta, angle);

        delta2 = {stroke.width, 0.0f};
        _rotate(delta2, angle - rotate);
        delta += delta2 + stroke.center;
        _borderLineTo(border, delta, false);
    } else if (stroke.cap == StrokeCap::Round) {
        stroke.angleIn = angle;
        stroke.angleOut = angle + MATH_PI;
        _borderArcTo(stroke, side);
    } else {
        _rotate(delta, angle + rotate);
        delta += stroke.center;
        _borderLineTo(border, delta, false);

        delta = {stroke.width, 0.0f};
        _rotate(delta, angle - rotate);
        delta += stroke.center;
        _borderLineTo(border, delta, false);
    }
}

static void _addReverseLeft(SwStroke& stroke, bool opened)
{
    auto right = stroke.borders[0];
    auto left = stroke.borders[1];
    auto newPts = left->pts.count - left->start;

    if (newPts <= 0) return;

    _growBorder(right, newPts);

    auto dstTag = right->tags + right->pts.count;
    auto srcPt = left->pts.end() - 1;
    auto srcTag = left->tags + left->pts.count - 1;

    while (srcPt >= left->pts.data + left->start) {
        right->pts.push(*srcPt);
        *dstTag = *srcTag;

        if (opened) {
             dstTag[0] &= ~(SW_STROKE_TAG_BEGIN | SW_STROKE_TAG_END);
        } else {
            auto ttag = dstTag[0] & (SW_STROKE_TAG_BEGIN | SW_STROKE_TAG_END);
            if (ttag == SW_STROKE_TAG_BEGIN || ttag == SW_STROKE_TAG_END)
              dstTag[0] ^= (SW_STROKE_TAG_BEGIN | SW_STROKE_TAG_END);
        }
        --srcPt;
        --srcTag;
        ++dstTag;
    }

    left->pts.count = left->start;
    right->movable = false;
    left->movable = false;
}

static void _beginSubPath(SwStroke& stroke, const Point& to, bool closed)
{

    stroke.firstPt = true;
    stroke.center = to;
    stroke.closedSubPath = closed;

    if ((stroke.join != StrokeJoin::Round) || (!stroke.closedSubPath && stroke.cap == StrokeCap::Butt))
        stroke.handleWideStrokes = true;
    else
        stroke.handleWideStrokes = false;

    stroke.subPathStart = to;
    stroke.angleIn = 0.0f;
}

static void _endSubPath(SwStroke& stroke)
{
    auto right = stroke.borders[0];
    auto left = stroke.borders[1];

    auto zeroLength = (right->pts.count == right->start + 1U) && (left->pts.count == left->start + 1U);

    if (stroke.closedSubPath && !zeroLength) {
        if (stroke.center != stroke.subPathStart) _lineTo(stroke, stroke.subPathStart);

        stroke.angleOut = stroke.subPathAngle;
        auto turn = remainderf(stroke.angleOut - stroke.angleIn, MATH_2PI);

        if (!tvg::zero(turn)) {
            int32_t inside = 0;
            if (turn < 0) inside = 1;
            _inside(stroke, inside, stroke.subPathLength);
            _outside(stroke, 1 - inside, stroke.subPathLength);
        }
        _borderClose(right, false);
        _borderClose(left, true);
    } else {
        _addCap(stroke, stroke.angleIn, 0);

        _addReverseLeft(stroke, true);

        stroke.center = stroke.subPathStart;
        _addCap(stroke, stroke.subPathAngle + MATH_PI, 0);

        _borderClose(right, false);
    }
}

static void _exportBorderOutline(const SwStroke& stroke, RenderPath& path, uint32_t side)
{
    auto border = stroke.borders[side];
    if (border->pts.empty()) return;

    Point start{};

    for (uint32_t i = 0; i < border->pts.count; ++i) {
        auto tag = border->tags[i];
        if (tag & SW_STROKE_TAG_BEGIN) {
            start = border->pts[i];
            path.moveTo(start);
        } else if (tag & SW_STROKE_TAG_CUBIC) {
            if (border->tags[i + 1] & SW_STROKE_TAG_END) {
                path.cubicTo(border->pts[i], border->pts[i + 1], start);
                ++i;
            } else {
                path.cubicTo(border->pts[i], border->pts[i + 1], border->pts[i + 2]);
                i += 2;
            }
        } else {
            path.lineTo(border->pts[i]);
        }
        if (border->tags[i] & SW_STROKE_TAG_END) path.close();
    }
}

void strokeFree(SwStroke* stroke)
{
    if (stroke && stroke->fill) tvg::free(stroke->fill);
    tvg::free(stroke);
}

void strokeReset(SwStroke* stroke, const RenderShape* rshape, const Matrix& transform, SwMpool* mpool, unsigned tid)
{
    stroke->width = rshape->strokeWidth() * 0.5f;
    stroke->cap = rshape->strokeCap();
    stroke->miterlimit = rshape->strokeMiterlimit();
    stroke->join = rshape->strokeJoin();

    stroke->borders[0] = mpool->strokeLBorder(tid);
    stroke->borders[1] = mpool->strokeRBorder(tid);
}

bool strokeParseOutline(SwStroke* stroke, const SwOutline& outline)
{
    auto& path = *outline.path;
    auto cmd = path.cmds.begin();
    auto pts = path.pts.data;
    Point start;

    while (cmd < path.cmds.end()) {
        if (*cmd == PathCommand::Close) {
            ++cmd;
            continue;
        }
        if (*cmd == PathCommand::MoveTo || pts == path.pts.data) {
            if (*cmd == PathCommand::CubicTo) return false;
            start = *pts++;
            ++cmd;
        }

        auto end = cmd;
        while (end < path.cmds.end() && *end != PathCommand::MoveTo && *end != PathCommand::Close) {
            ++end;
        }
        auto closed = end < path.cmds.end() && *end == PathCommand::Close;
        _beginSubPath(*stroke, start, closed);

        for (; cmd < end; ++cmd) {
            if (*cmd == PathCommand::LineTo) {
                _lineTo(*stroke, *pts++);
            } else {
                _cubicTo(*stroke, pts[0], pts[1], pts[2]);
                pts += 3;
            }
        }
        if (closed) _lineTo(*stroke, start);
        if (!stroke->firstPt) _endSubPath(*stroke);
    }
    return true;
}

SwOutline* strokeExportOutline(SwStroke* stroke, SwMpool* mpool, unsigned tid)
{
    auto reserve = stroke->borders[0]->pts.count + stroke->borders[1]->pts.count;
    auto outline = mpool->outline(tid);
    auto& path = *const_cast<RenderPath*>(outline->path);
    path.pts.reserve(reserve);
    path.cmds.reserve(reserve);
    outline->fillRule = FillRule::NonZero;

    _exportBorderOutline(*stroke, path, 0);
    _exportBorderOutline(*stroke, path, 1);

    return outline;
}
