#ifndef SDL_blendmode_h_
#define SDL_blendmode_h_

#include <SDL3/SDL_stdinc.h>

#include <SDL3/SDL_begin_code.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef Uint32 SDL_BlendMode;

#define SDL_BLENDMODE_NONE                  0x00000000u
#define SDL_BLENDMODE_BLEND                 0x00000001u
#define SDL_BLENDMODE_BLEND_PREMULTIPLIED   0x00000010u
#define SDL_BLENDMODE_ADD                   0x00000002u
#define SDL_BLENDMODE_ADD_PREMULTIPLIED     0x00000020u
#define SDL_BLENDMODE_MOD                   0x00000004u
#define SDL_BLENDMODE_MUL                   0x00000008u
#define SDL_BLENDMODE_INVALID               0x7FFFFFFFu

typedef enum SDL_BlendOperation
{
    SDL_BLENDOPERATION_ADD              = 0x1,
    SDL_BLENDOPERATION_SUBTRACT         = 0x2,
    SDL_BLENDOPERATION_REV_SUBTRACT     = 0x3,
    SDL_BLENDOPERATION_MINIMUM          = 0x4,
    SDL_BLENDOPERATION_MAXIMUM          = 0x5
} SDL_BlendOperation;

typedef enum SDL_BlendFactor
{
    SDL_BLENDFACTOR_ZERO                = 0x1,
    SDL_BLENDFACTOR_ONE                 = 0x2,
    SDL_BLENDFACTOR_SRC_COLOR           = 0x3,
    SDL_BLENDFACTOR_ONE_MINUS_SRC_COLOR = 0x4,
    SDL_BLENDFACTOR_SRC_ALPHA           = 0x5,
    SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA = 0x6,
    SDL_BLENDFACTOR_DST_COLOR           = 0x7,
    SDL_BLENDFACTOR_ONE_MINUS_DST_COLOR = 0x8,
    SDL_BLENDFACTOR_DST_ALPHA           = 0x9,
    SDL_BLENDFACTOR_ONE_MINUS_DST_ALPHA = 0xA
} SDL_BlendFactor;

extern SDL_DECLSPEC SDL_BlendMode SDLCALL SDL_ComposeCustomBlendMode(SDL_BlendFactor srcColorFactor,
                                                                 SDL_BlendFactor dstColorFactor,
                                                                 SDL_BlendOperation colorOperation,
                                                                 SDL_BlendFactor srcAlphaFactor,
                                                                 SDL_BlendFactor dstAlphaFactor,
                                                                 SDL_BlendOperation alphaOperation);

#ifdef __cplusplus
}
#endif
#include <SDL3/SDL_close_code.h>

#endif
