#ifndef _THORVG_H_
#define _THORVG_H_

#include <cstdint>
#include <functional>
#include <list>
#include <cstdarg>

#define TVG_VERSION_MAJOR 1
#define TVG_VERSION_MINOR 1
#define TVG_VERSION_MICRO 3

#ifdef TVG_API
    #undef TVG_API
#endif

#ifndef TVG_STATIC
    #ifdef _WIN32
        #if TVG_BUILD
            #define TVG_API __declspec(dllexport)
        #else
            #define TVG_API __declspec(dllimport)
        #endif
    #elif (defined(__SUNPRO_C)  || defined(__SUNPRO_CC))
        #define TVG_API __global
    #else
        #if (defined(__GNUC__) && __GNUC__ >= 4) || defined(__INTEL_COMPILER)
            #define TVG_API __attribute__ ((visibility("default")))
        #else
            #define TVG_API
        #endif
    #endif
#else
    #define TVG_API
#endif

#ifdef TVG_DEPRECATED
    #undef TVG_DEPRECATED
#endif

#ifdef _WIN32
    #define TVG_DEPRECATED __declspec(deprecated)
#elif __GNUC__ > 3 || (__GNUC__ == 3 && __GNUC_MINOR__ >= 1)
    #define TVG_DEPRECATED __attribute__ ((__deprecated__))
#else
    #define TVG_DEPRECATED
#endif

#define _TVG_PROTECTED_CTOR(A) \
protected: \
    A(const A&) = delete; \
    const A& operator=(const A&) = delete; \
    A()

#define _TVG_PROTECTED_CTOR_PIMPL(A) \
    _TVG_PROTECTED_CTOR(A); \
public: \
    struct Impl; \
    Impl* pImpl

#define _TVG_PUBLIC_DTOR_PIMPL(A) \
    _TVG_PROTECTED_CTOR_PIMPL(A); \
    virtual ~A()

#define _TVG_PUBLIC_DTOR(A) \
    _TVG_PROTECTED_CTOR(A); \
public: \
    virtual ~A() = default;

#define _TVG_DISABLE_INST(A) \
    A() = delete; \
    ~A() = delete

#define _TVG_FRIEND(A) \
    friend A

namespace tvg
{

struct Animation;
struct Shape;

enum struct Result
{
    Success = 0,
    InvalidArguments,
    InsufficientCondition,
    FailedAllocation,
    MemoryCorruption,
    NonSupport,
    SystemError,
    Unknown = 255
};

enum struct ColorSpace : uint8_t
{
    ABGR8888 = 0,
    ARGB8888,
    ABGR8888S,
    ARGB8888S,
    Grayscale8,
    XBGR8888,
    XRGB8888,
    Unknown = 255
};

enum struct EngineOption : uint8_t
{
    None = 0,
    Default = 1 << 0,
    SmartRender = 1 << 1,
    Aliased = 1 << 2
};

enum struct PathCommand : uint8_t
{
    Close = 0,
    MoveTo,
    LineTo,
    CubicTo
};

enum struct StrokeCap : uint8_t
{
    Butt = 0,
    Round,
    Square
};

enum struct StrokeJoin : uint8_t
{
    Miter = 0,
    Round,
    Bevel
};

enum struct FillSpread : uint8_t
{
    Pad = 0,
    Reflect,
    Repeat
};

enum struct FillRule : uint8_t
{
    NonZero = 0,
    EvenOdd
};

enum struct FilterMethod : uint8_t
{
    Bilinear = 0,
    Nearest
};

enum struct MaskMethod : uint8_t
{
    None = 0,
    Alpha,
    InvAlpha,
    Luma,
    InvLuma,
    Add,
    Subtract,
    Intersect,
    Difference,
    Lighten,
    Darken
};

enum struct BlendMethod : uint8_t
{
    Normal = 0,
    Multiply,
    Screen,
    Overlay,
    Darken,
    Lighten,
    ColorDodge,
    ColorBurn,
    HardLight,
    SoftLight,
    Difference,
    Exclusion,
    Hue,
    Saturation,
    Color,
    Luminosity,
    Add,
    Composition = 255
};

enum struct SceneEffect : uint8_t
{
    Clear = 0,
    GaussianBlur,
    DropShadow,
    Fill,
    Tint,
    Tritone,
    MotionBlur
};

enum struct TextWrap : uint8_t
{
    None = 0,
    Character,
    Word,
    Smart,
    Ellipsis
};

enum struct Type : uint8_t
{
    Undefined = 0,
    Shape,
    Scene,
    Picture,
    Text,
    LinearGradient = 10,
    RadialGradient,
    ConicGradient
};

struct Point
{
    float x;
    float y;
};

struct Matrix
{
    float e11, e12, e13;
    float e21, e22, e23;
    float e31, e32, e33;
};

struct Region
{
    int32_t xMin, yMin;
    int32_t xMax, yMax;
};

struct TextMetrics
{
    float ascent;
    float descent;
    float linegap;
    float advance;
};

struct GlyphMetrics
{
    float advance;
    float bearing;
    Point min;
    Point max;
};

struct TVG_API Paint
{
    const Paint* parent() const noexcept;

    Result visible(bool on) noexcept;

    Result rotate(float degree) noexcept;

    Result scale(float factor) noexcept;

    Result translate(float x, float y) noexcept;

    Result transform(const Matrix& m) noexcept;

    Matrix& transform() noexcept;

    Result opacity(uint8_t o) noexcept;

    Result mask(Paint* target, MaskMethod method) noexcept;

    Result clip(Shape* clipper) noexcept;

    Result blend(BlendMethod method) noexcept;

    Result bounds(Point* pt4) noexcept;

    Result bounds(float* x, float* y, float* w, float* h) noexcept;

    bool intersects(int32_t x, int32_t y, int32_t w = 1, int32_t h = 1) noexcept;

    bool intersects(int32_t x, int32_t y, int32_t w, int32_t h, bool visibleOnly) noexcept;

    Paint* duplicate() const noexcept;

    uint8_t opacity() const noexcept;

    MaskMethod mask(const Paint** target) const noexcept;

    Shape* clip() const noexcept;

    bool visible() const noexcept;

    uint16_t ref() noexcept;

    uint16_t unref(bool free = true) noexcept;

    uint16_t refCnt() const noexcept;

    virtual Type type() const noexcept = 0;

    uint32_t id = 0;

    void* data = nullptr;

    static void rel(Paint* paint) noexcept;

    _TVG_PUBLIC_DTOR_PIMPL(Paint);
};

struct TVG_API Fill
{
    struct ColorStop
    {
        float offset;
        uint8_t r;
        uint8_t g;
        uint8_t b;
        uint8_t a;
    };

    virtual ~Fill();

    Result colorStops(const ColorStop* colorStops, uint32_t cnt) noexcept;

    Result spread(FillSpread s) noexcept;

    Result transform(const Matrix& m) noexcept;

    uint32_t colorStops(const ColorStop** colorStops = nullptr) const noexcept;

    FillSpread spread() const noexcept;

    Matrix& transform() const noexcept;

    Fill* duplicate() const noexcept;

    virtual Type type() const noexcept = 0;

    _TVG_PROTECTED_CTOR_PIMPL(Fill);
};

struct TVG_API Canvas
{
    const std::list<Paint*>& paints() const noexcept;

    Result add(Paint* target, Paint* at = nullptr) noexcept;

    Result remove(Paint* paint = nullptr) noexcept;

    Result update() noexcept;

    Result draw(bool clear = false) noexcept;

    Result viewport(int32_t x, int32_t y, int32_t w, int32_t h) noexcept;

    Result sync() noexcept;

    uint32_t dirtyRegions() const noexcept;

    Result dirtyRegions(Region* regions, uint32_t cnt) const noexcept;

    _TVG_PUBLIC_DTOR_PIMPL(Canvas);
};

struct TVG_API LinearGradient : Fill
{
    Result linear(float x1, float y1, float x2, float y2) noexcept;

    Result linear(float* x1, float* y1, float* x2, float* y2) const noexcept;

    static LinearGradient* gen() noexcept;

    Type type() const noexcept override;

    _TVG_PROTECTED_CTOR(LinearGradient);
};

struct TVG_API RadialGradient : Fill
{
    Result radial(float cx, float cy, float r, float fx, float fy, float fr) noexcept;

    Result radial(float* cx, float* cy, float* r, float* fx = nullptr, float* fy = nullptr, float* fr = nullptr) const noexcept;

    static RadialGradient* gen() noexcept;

    Type type() const noexcept override;

    _TVG_PROTECTED_CTOR(RadialGradient);
};

struct TVG_API ConicGradient : Fill
{
    Result conic(float cx, float cy, float angle = 0.0f) noexcept;

    Result conic(float* cx, float* cy, float* angle = nullptr) const noexcept;

    static ConicGradient* gen() noexcept;

    Type type() const noexcept override;

    _TVG_PROTECTED_CTOR(ConicGradient);
};

struct TVG_API Shape : Paint
{
    Result reset() noexcept;

    Result moveTo(float x, float y) noexcept;

    Result lineTo(float x, float y) noexcept;

    Result cubicTo(float cx1, float cy1, float cx2, float cy2, float x, float y) noexcept;

    Result close() noexcept;

    Result appendRect(float x, float y, float w, float h, float rx = 0, float ry = 0, bool cw = true) noexcept;

    Result appendCircle(float cx, float cy, float rx, float ry, bool cw = true) noexcept;

    Result appendPath(const PathCommand* cmds, uint32_t cmdCnt, const Point* pts, uint32_t ptsCnt) noexcept;

    Result strokeWidth(float width) noexcept;

    Result strokeFill(uint8_t r, uint8_t g, uint8_t b, uint8_t a = 255) noexcept;

    Result strokeFill(Fill* f) noexcept;

    Result strokeDash(const float* dashPattern, uint32_t cnt, float offset = 0.0f) noexcept;

    Result strokeCap(StrokeCap cap) noexcept;

    Result strokeJoin(StrokeJoin join) noexcept;

    Result strokeMiterlimit(float miterlimit) noexcept;

    Result trimpath(float begin, float end, bool simultaneous = true) noexcept;

    Result fill(uint8_t r, uint8_t g, uint8_t b, uint8_t a = 255) noexcept;

    Result fill(Fill* f) noexcept;

    Result fillRule(FillRule r) noexcept;

    Result order(bool strokeFirst) noexcept;

    Result path(const PathCommand** cmds, uint32_t* cmdsCnt, const Point** pts, uint32_t* ptsCnt) const noexcept;

    const Fill* fill() const noexcept;

    Result fill(uint8_t* r, uint8_t* g, uint8_t* b, uint8_t* a = nullptr) const noexcept;

    FillRule fillRule() const noexcept;

    float strokeWidth() const noexcept;

    Result strokeFill(uint8_t* r, uint8_t* g, uint8_t* b, uint8_t* a = nullptr) const noexcept;

    const Fill* strokeFill() const noexcept;

    uint32_t strokeDash(const float** dashPattern, float* offset = nullptr) const noexcept;

    StrokeCap strokeCap() const noexcept;

    StrokeJoin strokeJoin() const noexcept;

    float strokeMiterlimit() const noexcept;

    static Shape* gen() noexcept;

    Type type() const noexcept override;

    _TVG_PROTECTED_CTOR(Shape);
};

struct TVG_API Picture : Paint
{
    Result load(const char* filename) noexcept;

    Result load(const char* data, uint32_t size, const char* mimeType, const char* rpath = nullptr, bool copy = false) noexcept;

    Result size(float w, float h) noexcept;

    Result size(float* w, float* h) const noexcept;

    Result origin(float x, float y) noexcept;

    Result origin(float* x, float* y) const noexcept;

    Result load(const uint32_t* data, uint32_t w, uint32_t h, ColorSpace cs, bool copy = false) noexcept;

    Result resolver(std::function<bool(Paint* paint, const char* src, void* data)> func, void* data) noexcept;

    Result filter(FilterMethod method) noexcept;

    const Paint* paint(uint32_t id) noexcept;

    static Picture* gen() noexcept;

    Type type() const noexcept override;

    bool accessible = false;

    _TVG_FRIEND(Animation);
    _TVG_PROTECTED_CTOR(Picture);
};

struct TVG_API Scene : Paint
{
    Result add(Paint* target, Paint* at = nullptr) noexcept;

    const std::list<Paint*>& paints() const noexcept;

    Result remove(Paint* paint = nullptr) noexcept;

    Result add(SceneEffect effect, ...) noexcept;

    static Scene* gen() noexcept;

    Type type() const noexcept override;

    _TVG_PROTECTED_CTOR(Scene);
};

struct TVG_API Text : Paint
{
    Result font(const char* name) noexcept;

    Result size(float size) noexcept;

    Result text(const char* text) noexcept;

    const char* text() const noexcept;

    Result align(float x, float y) noexcept;

    Result layout(float w, float h) noexcept;

    Result wrap(TextWrap mode) noexcept;

    uint32_t lines() noexcept;

    Result italic(float shear = 0.18f) noexcept;

    Result outline(float width, uint8_t r, uint8_t g, uint8_t b) noexcept;

    Result fill(uint8_t r, uint8_t g, uint8_t b) noexcept;

    Result fill(Fill* f) noexcept;

    Result spacing(float letter, float line) noexcept;

    Result metrics(TextMetrics& metrics) const noexcept;

    Result metrics(const char* ch, GlyphMetrics& metrics, const char** next = nullptr) const noexcept;

    static Result load(const char* filename) noexcept;

    static Result load(const char* name, const char* data, uint32_t size, const char* mimeType = "ttf", bool copy = false) noexcept;

    static Result unload(const char* filename) noexcept;

    static Text* gen() noexcept;

    Type type() const noexcept override;

    _TVG_PROTECTED_CTOR(Text);
};

struct TVG_API SwCanvas final : Canvas
{
    ~SwCanvas() override;

    Result target(uint32_t* buffer, uint32_t stride, uint32_t w, uint32_t h, ColorSpace cs) noexcept;

    static SwCanvas* gen(EngineOption op = EngineOption::Default) noexcept;

    _TVG_PROTECTED_CTOR(SwCanvas);
};

struct TVG_API GlCanvas final : Canvas
{
    ~GlCanvas() override;

    Result target(void* display, void* surface, void* context, int32_t id, uint32_t w, uint32_t h, ColorSpace cs) noexcept;

    static GlCanvas* gen(EngineOption op = EngineOption::Default) noexcept;

    _TVG_PROTECTED_CTOR(GlCanvas);
};

struct TVG_API WgCanvas final : Canvas
{
    ~WgCanvas() override;

    struct Context
    {
        void* instance;
        void* adapter;
        void* device;
    };

    Result target(void* device, void* instance, void* target, uint32_t w, uint32_t h, ColorSpace cs, int type = 0) noexcept;

    Result target(const Context& context, void* target, uint32_t w, uint32_t h, ColorSpace cs, int type = 0) noexcept;

    static WgCanvas* gen(EngineOption op = EngineOption::Default) noexcept;

    _TVG_PROTECTED_CTOR(WgCanvas);
};

struct TVG_API Initializer final
{
    static Result init(uint32_t threads = 0) noexcept;

    static Result term() noexcept;

    static const char* version(uint32_t* major, uint32_t* minor, uint32_t* micro) noexcept;

    _TVG_DISABLE_INST(Initializer);
};

struct TVG_API Animation
{
    Result frame(float no) noexcept;

    Picture* picture() const noexcept;

    float curFrame() const noexcept;

    float totalFrame() const noexcept;

    float duration() const noexcept;

    Result segment(float begin, float end) noexcept;

    Result segment(float* begin, float* end = nullptr) noexcept;

    static Animation* gen() noexcept;

    _TVG_PUBLIC_DTOR_PIMPL(Animation);
};

struct TVG_API Saver
{
    Result background(Paint* paint) noexcept;

    Result save(Paint* paint, const char* filename, uint32_t quality = 100) noexcept;

    Result save(Animation* animation, const char* filename, uint32_t quality = 100, uint32_t fps = 0) noexcept;

    Result sync() noexcept;

    static Saver* gen() noexcept;

    _TVG_PUBLIC_DTOR(Saver);
};

struct TVG_API Accessor
{
    Result set(Paint* paint, std::function<bool(const Paint* paint, void* data)> func, void* data) noexcept;

    static uint32_t id(const char* name) noexcept;

    const char* name(uint32_t id) noexcept;

    static Accessor* gen() noexcept;

    _TVG_PUBLIC_DTOR(Accessor);
};

}

#endif
