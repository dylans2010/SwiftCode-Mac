#ifndef _TVG_SW_RENDERER_H_
#define _TVG_SW_RENDERER_H_

#include "tvgRender.h"

struct SwSurface;
struct SwTask;
struct SwCompositor;
struct SwMpool;

namespace tvg
{

struct SwRenderer : RenderMethod
{
    bool preUpdate() override;
    RenderData prepare(const RenderShape& rshape, RenderData data, const Matrix& transform, const Array<RenderData>& clips, uint8_t opacity, RenderUpdateFlag flags, bool clipper) override;
    RenderData prepare(RenderSurface* surface, RenderData data, const Matrix& transform, const Array<RenderData>& clips, uint8_t opacity, FilterMethod filter, RenderUpdateFlag flags) override;
    bool postUpdate() override;
    bool preRender() override;
    bool renderShape(RenderData data) override;
    bool renderImage(RenderData data) override;
    bool postRender() override;
    void dispose(RenderData data) override;
    RenderRegion region(RenderData data) override;
    bool bounds(RenderData data, Point* pt4, const Matrix& m) override;
    bool blend(BlendMethod method) override;
    ColorSpace colorSpace() override;
    const RenderSurface* mainSurface() override;
    bool clear() override;
    bool sync() override;
    bool intersectsShape(RenderData data, const RenderRegion& region) override;
    bool intersectsImage(RenderData data, const RenderRegion& region) override;
    Result target(pixel_t* data, uint32_t stride, uint32_t w, uint32_t h, ColorSpace cs);

    SwSurface* request(int channelSize, bool square);
    RenderCompositor* target(const RenderRegion& region, ColorSpace cs, CompositionFlag flags) override;
    bool beginComposite(RenderCompositor* cmp, MaskMethod method, uint8_t opacity) override;
    bool endComposite(RenderCompositor* cmp) override;
    void clearCompositors();

    void prepare(RenderEffect* effect, const Matrix& transform) override;
    bool region(RenderEffect* effect) override;
    bool render(RenderCompositor* cmp, const RenderEffect* effect, bool direct) override;
    void dispose(RenderEffect* effect) override;

    void damage(RenderData rd, const RenderRegion& region) override;
    bool partial(bool disable) override;
    uint32_t dirtyRegions() const override;
    Result dirtyRegions(Region* regions, uint32_t cnt) const override;

    SwRenderer(uint32_t threads, EngineOption op);
    static bool term();

    SwSurface*           surface = nullptr;
    SwMpool*             mpool;
    bool                 antiAlias;

private:
    bool                 fulldraw = true;
    bool                 rendered = false;
    Array<SwTask*>       tasks;
    Array<SwSurface*>    compositors;
    RenderDirtyRegion    dirtyRegion;

    ~SwRenderer();

    SwTask* prepareCommon(SwTask* task, const Matrix& transform, const Array<RenderData>& clips, uint8_t opacity, RenderUpdateFlag flags, bool ready);
};

}

#endif
