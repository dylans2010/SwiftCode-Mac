#ifndef _NV_ENCODEAPI_H_
#define _NV_ENCODEAPI_H_

#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
#endif

#ifdef _MSC_VER
#ifndef _STDINT
typedef __int32 int32_t;
typedef unsigned __int32 uint32_t;
typedef __int64 int64_t;
typedef unsigned __int64 uint64_t;
typedef signed char int8_t;
typedef unsigned char uint8_t;
typedef short int16_t;
typedef unsigned short uint16_t;
#endif
#else
#include <stdint.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) || defined(__CYGWIN__)
#define NVENCAPI __stdcall
#else
#define NVENCAPI
#endif

#ifdef _WIN32
typedef RECT NVENC_RECT;
#else
#if !defined(GUID) && !defined(GUID_DEFINED)
#define GUID_DEFINED
typedef struct _GUID
{
    uint32_t Data1;
    uint16_t Data2;
    uint16_t Data3;
    uint8_t  Data4[8];
} GUID, *LPGUID;
#endif

typedef struct _NVENC_RECT
{
    uint32_t left;
    uint32_t top;
    uint32_t right;
    uint32_t bottom;
} NVENC_RECT;

#endif

typedef void* NV_ENC_INPUT_PTR;
typedef void* NV_ENC_OUTPUT_PTR;
typedef void* NV_ENC_REGISTERED_PTR;
typedef void* NV_ENC_CUSTREAM_PTR;

#define NVENCAPI_MAJOR_VERSION 12
#define NVENCAPI_MINOR_VERSION 2

#define NVENCAPI_VERSION (NVENCAPI_MAJOR_VERSION | (NVENCAPI_MINOR_VERSION << 24))

#define NVENCAPI_STRUCT_VERSION(ver) ((uint32_t)NVENCAPI_VERSION | ((ver)<<16) | (0x7 << 28))

#define NVENC_INFINITE_GOPLENGTH  0xffffffff

#define NV_MAX_SEQ_HDR_LEN  (512)

#ifdef __GNUC__
#define NV_ENC_DEPRECATED __attribute__ ((deprecated("WILL BE REMOVED IN A FUTURE VIDEO CODEC SDK VERSION")))
#elif defined(_MSC_VER)
#define NV_ENC_DEPRECATED __declspec(deprecated("WILL BE REMOVED IN A FUTURE VIDEO CODEC SDK VERSION"))
#endif

static const GUID NV_ENC_CODEC_H264_GUID =
{ 0x6bc82762, 0x4e63, 0x4ca4, { 0xaa, 0x85, 0x1e, 0x50, 0xf3, 0x21, 0xf6, 0xbf } };

static const GUID NV_ENC_CODEC_HEVC_GUID =
{ 0x790cdc88, 0x4522, 0x4d7b, { 0x94, 0x25, 0xbd, 0xa9, 0x97, 0x5f, 0x76, 0x3 } };

static const GUID NV_ENC_CODEC_AV1_GUID =
{ 0x0a352289, 0x0aa7, 0x4759, { 0x86, 0x2d, 0x5d, 0x15, 0xcd, 0x16, 0xd2, 0x54 } };

static const GUID NV_ENC_CODEC_PROFILE_AUTOSELECT_GUID =
{ 0xbfd6f8e7, 0x233c, 0x4341, { 0x8b, 0x3e, 0x48, 0x18, 0x52, 0x38, 0x3, 0xf4 } };

static const GUID  NV_ENC_H264_PROFILE_BASELINE_GUID =
{ 0x727bcaa, 0x78c4, 0x4c83, { 0x8c, 0x2f, 0xef, 0x3d, 0xff, 0x26, 0x7c, 0x6a } };

static const GUID  NV_ENC_H264_PROFILE_MAIN_GUID =
{ 0x60b5c1d4, 0x67fe, 0x4790, { 0x94, 0xd5, 0xc4, 0x72, 0x6d, 0x7b, 0x6e, 0x6d } };

static const GUID NV_ENC_H264_PROFILE_HIGH_GUID =
{ 0xe7cbc309, 0x4f7a, 0x4b89, { 0xaf, 0x2a, 0xd5, 0x37, 0xc9, 0x2b, 0xe3, 0x10 } };

static const GUID  NV_ENC_H264_PROFILE_HIGH_444_GUID =
{ 0x7ac663cb, 0xa598, 0x4960, { 0xb8, 0x44, 0x33, 0x9b, 0x26, 0x1a, 0x7d, 0x52 } };

static const GUID NV_ENC_H264_PROFILE_STEREO_GUID =
{ 0x40847bf5, 0x33f7, 0x4601, { 0x90, 0x84, 0xe8, 0xfe, 0x3c, 0x1d, 0xb8, 0xb7 } };

static const GUID NV_ENC_H264_PROFILE_PROGRESSIVE_HIGH_GUID =
{ 0xb405afac, 0xf32b, 0x417b, { 0x89, 0xc4, 0x9a, 0xbe, 0xed, 0x3e, 0x59, 0x78 } };

static const GUID NV_ENC_H264_PROFILE_CONSTRAINED_HIGH_GUID =
{ 0xaec1bd87, 0xe85b, 0x48f2, { 0x84, 0xc3, 0x98, 0xbc, 0xa6, 0x28, 0x50, 0x72 } };

static const GUID NV_ENC_HEVC_PROFILE_MAIN_GUID =
{ 0xb514c39a, 0xb55b, 0x40fa, { 0x87, 0x8f, 0xf1, 0x25, 0x3b, 0x4d, 0xfd, 0xec } };

static const GUID NV_ENC_HEVC_PROFILE_MAIN10_GUID =
{ 0xfa4d2b6c, 0x3a5b, 0x411a, { 0x80, 0x18, 0x0a, 0x3f, 0x5e, 0x3c, 0x9b, 0xe5 } };

static const GUID NV_ENC_HEVC_PROFILE_FREXT_GUID =
{ 0x51ec32b5, 0x1b4c, 0x453c, { 0x9c, 0xbd, 0xb6, 0x16, 0xbd, 0x62, 0x13, 0x41 } };

static const GUID NV_ENC_AV1_PROFILE_MAIN_GUID =
{ 0x5f2a39f5, 0xf14e, 0x4f95, { 0x9a, 0x9e, 0xb7, 0x6d, 0x56, 0x8f, 0xcf, 0x97 } };

static const GUID NV_ENC_PRESET_P1_GUID   =
{ 0xfc0a8d3e, 0x45f8, 0x4cf8, { 0x80, 0xc7, 0x29, 0x88, 0x71, 0x59, 0xe, 0xbf } };

static const GUID NV_ENC_PRESET_P2_GUID   =
{ 0xf581cfb8, 0x88d6, 0x4381, { 0x93, 0xf0, 0xdf, 0x13, 0xf9, 0xc2, 0x7d, 0xab } };

static const GUID NV_ENC_PRESET_P3_GUID   =
{ 0x36850110, 0x3a07, 0x441f, { 0x94, 0xd5, 0x36, 0x70, 0x63, 0x1f, 0x91, 0xf6 } };

static const GUID NV_ENC_PRESET_P4_GUID   =
{ 0x90a7b826, 0xdf06, 0x4862, { 0xb9, 0xd2, 0xcd, 0x6d, 0x73, 0xa0, 0x86, 0x81 } };

static const GUID NV_ENC_PRESET_P5_GUID   =
{ 0x21c6e6b4, 0x297a, 0x4cba, { 0x99, 0x8f, 0xb6, 0xcb, 0xde, 0x72, 0xad, 0xe3 } };

static const GUID NV_ENC_PRESET_P6_GUID   =
{ 0x8e75c279, 0x6299, 0x4ab6, { 0x83, 0x2, 0xb, 0x21, 0x5a, 0x33, 0x5c, 0xf5 } };

static const GUID NV_ENC_PRESET_P7_GUID   =
{ 0x84848c12, 0x6f71, 0x4c13, { 0x93, 0x1b, 0x53, 0xe2, 0x83, 0xf5, 0x79, 0x74 } };

typedef enum _NV_ENC_PARAMS_FRAME_FIELD_MODE
{
    NV_ENC_PARAMS_FRAME_FIELD_MODE_FRAME = 0x01,
    NV_ENC_PARAMS_FRAME_FIELD_MODE_FIELD = 0x02,
    NV_ENC_PARAMS_FRAME_FIELD_MODE_MBAFF = 0x03
} NV_ENC_PARAMS_FRAME_FIELD_MODE;

typedef enum _NV_ENC_PARAMS_RC_MODE
{
    NV_ENC_PARAMS_RC_CONSTQP                = 0x0,
    NV_ENC_PARAMS_RC_VBR                    = 0x1,
    NV_ENC_PARAMS_RC_CBR                    = 0x2,
} NV_ENC_PARAMS_RC_MODE;

typedef enum _NV_ENC_MULTI_PASS
{
    NV_ENC_MULTI_PASS_DISABLED              = 0x0,
    NV_ENC_TWO_PASS_QUARTER_RESOLUTION      = 0x1,
    NV_ENC_TWO_PASS_FULL_RESOLUTION         = 0x2,
} NV_ENC_MULTI_PASS;

typedef enum _NV_ENC_STATE_RESTORE_TYPE
{
    NV_ENC_STATE_RESTORE_FULL               = 0x01,
    NV_ENC_STATE_RESTORE_RATE_CONTROL       = 0x02,
    NV_ENC_STATE_RESTORE_ENCODE             = 0x03,
} NV_ENC_STATE_RESTORE_TYPE;

typedef enum _NV_ENC_OUTPUT_STATS_LEVEL
{
    NV_ENC_OUTPUT_STATS_NONE          = 0,
    NV_ENC_OUTPUT_STATS_BLOCK_LEVEL   = 1,
    NV_ENC_OUTPUT_STATS_ROW_LEVEL     = 2,
} NV_ENC_OUTPUT_STATS_LEVEL;

typedef enum _NV_ENC_EMPHASIS_MAP_LEVEL
{
    NV_ENC_EMPHASIS_MAP_LEVEL_0               = 0x0,
    NV_ENC_EMPHASIS_MAP_LEVEL_1               = 0x1,
    NV_ENC_EMPHASIS_MAP_LEVEL_2               = 0x2,
    NV_ENC_EMPHASIS_MAP_LEVEL_3               = 0x3,
    NV_ENC_EMPHASIS_MAP_LEVEL_4               = 0x4,
    NV_ENC_EMPHASIS_MAP_LEVEL_5               = 0x5
} NV_ENC_EMPHASIS_MAP_LEVEL;

typedef enum _NV_ENC_QP_MAP_MODE
{
    NV_ENC_QP_MAP_DISABLED               = 0x0,
    NV_ENC_QP_MAP_EMPHASIS               = 0x1,
    NV_ENC_QP_MAP_DELTA                  = 0x2,
    NV_ENC_QP_MAP                        = 0x3,
} NV_ENC_QP_MAP_MODE;

typedef enum _NV_ENC_PIC_STRUCT
{
    NV_ENC_PIC_STRUCT_FRAME             = 0x01,
    NV_ENC_PIC_STRUCT_FIELD_TOP_BOTTOM  = 0x02,
    NV_ENC_PIC_STRUCT_FIELD_BOTTOM_TOP  = 0x03
} NV_ENC_PIC_STRUCT;

typedef enum _NV_ENC_DISPLAY_PIC_STRUCT
{
    NV_ENC_PIC_STRUCT_DISPLAY_FRAME             = 0x00,
    NV_ENC_PIC_STRUCT_DISPLAY_FIELD_TOP_BOTTOM  = 0x01,
    NV_ENC_PIC_STRUCT_DISPLAY_FIELD_BOTTOM_TOP  = 0x02,
    NV_ENC_PIC_STRUCT_DISPLAY_FRAME_DOUBLING    = 0x03,
    NV_ENC_PIC_STRUCT_DISPLAY_FRAME_TRIPLING    = 0x04
} NV_ENC_DISPLAY_PIC_STRUCT;

typedef enum _NV_ENC_PIC_TYPE
{
    NV_ENC_PIC_TYPE_P               = 0x0,
    NV_ENC_PIC_TYPE_B               = 0x01,
    NV_ENC_PIC_TYPE_I               = 0x02,
    NV_ENC_PIC_TYPE_IDR             = 0x03,
    NV_ENC_PIC_TYPE_BI              = 0x04,
    NV_ENC_PIC_TYPE_SKIPPED         = 0x05,
    NV_ENC_PIC_TYPE_INTRA_REFRESH   = 0x06,
    NV_ENC_PIC_TYPE_NONREF_P        = 0x07,
    NV_ENC_PIC_TYPE_SWITCH          = 0x08,
    NV_ENC_PIC_TYPE_UNKNOWN         = 0xFF
} NV_ENC_PIC_TYPE;

typedef enum _NV_ENC_MV_PRECISION
{
    NV_ENC_MV_PRECISION_DEFAULT     = 0x0,
    NV_ENC_MV_PRECISION_FULL_PEL    = 0x01,
    NV_ENC_MV_PRECISION_HALF_PEL    = 0x02,
    NV_ENC_MV_PRECISION_QUARTER_PEL = 0x03
} NV_ENC_MV_PRECISION;

typedef enum _NV_ENC_BUFFER_FORMAT
{
    NV_ENC_BUFFER_FORMAT_UNDEFINED                       = 0x00000000,

    NV_ENC_BUFFER_FORMAT_NV12                            = 0x00000001,
    NV_ENC_BUFFER_FORMAT_YV12                            = 0x00000010,
    NV_ENC_BUFFER_FORMAT_IYUV                            = 0x00000100,
    NV_ENC_BUFFER_FORMAT_YUV444                          = 0x00001000,
    NV_ENC_BUFFER_FORMAT_YUV420_10BIT                    = 0x00010000,
    NV_ENC_BUFFER_FORMAT_YUV444_10BIT                    = 0x00100000,
    NV_ENC_BUFFER_FORMAT_ARGB                            = 0x01000000,
    NV_ENC_BUFFER_FORMAT_ARGB10                          = 0x02000000,
    NV_ENC_BUFFER_FORMAT_AYUV                            = 0x04000000,
    NV_ENC_BUFFER_FORMAT_ABGR                            = 0x10000000,
    NV_ENC_BUFFER_FORMAT_ABGR10                          = 0x20000000,
    NV_ENC_BUFFER_FORMAT_U8                              = 0x40000000,
} NV_ENC_BUFFER_FORMAT;

typedef enum _NV_ENC_LEVEL
{
    NV_ENC_LEVEL_AUTOSELECT         = 0,

    NV_ENC_LEVEL_H264_1             = 10,
    NV_ENC_LEVEL_H264_1b            = 9,
    NV_ENC_LEVEL_H264_11            = 11,
    NV_ENC_LEVEL_H264_12            = 12,
    NV_ENC_LEVEL_H264_13            = 13,
    NV_ENC_LEVEL_H264_2             = 20,
    NV_ENC_LEVEL_H264_21            = 21,
    NV_ENC_LEVEL_H264_22            = 22,
    NV_ENC_LEVEL_H264_3             = 30,
    NV_ENC_LEVEL_H264_31            = 31,
    NV_ENC_LEVEL_H264_32            = 32,
    NV_ENC_LEVEL_H264_4             = 40,
    NV_ENC_LEVEL_H264_41            = 41,
    NV_ENC_LEVEL_H264_42            = 42,
    NV_ENC_LEVEL_H264_5             = 50,
    NV_ENC_LEVEL_H264_51            = 51,
    NV_ENC_LEVEL_H264_52            = 52,
    NV_ENC_LEVEL_H264_60            = 60,
    NV_ENC_LEVEL_H264_61            = 61,
    NV_ENC_LEVEL_H264_62            = 62,

    NV_ENC_LEVEL_HEVC_1             = 30,
    NV_ENC_LEVEL_HEVC_2             = 60,
    NV_ENC_LEVEL_HEVC_21            = 63,
    NV_ENC_LEVEL_HEVC_3             = 90,
    NV_ENC_LEVEL_HEVC_31            = 93,
    NV_ENC_LEVEL_HEVC_4             = 120,
    NV_ENC_LEVEL_HEVC_41            = 123,
    NV_ENC_LEVEL_HEVC_5             = 150,
    NV_ENC_LEVEL_HEVC_51            = 153,
    NV_ENC_LEVEL_HEVC_52            = 156,
    NV_ENC_LEVEL_HEVC_6             = 180,
    NV_ENC_LEVEL_HEVC_61            = 183,
    NV_ENC_LEVEL_HEVC_62            = 186,

    NV_ENC_TIER_HEVC_MAIN           = 0,
    NV_ENC_TIER_HEVC_HIGH           = 1,

    NV_ENC_LEVEL_AV1_2              = 0,
    NV_ENC_LEVEL_AV1_21             = 1,
    NV_ENC_LEVEL_AV1_22             = 2,
    NV_ENC_LEVEL_AV1_23             = 3,
    NV_ENC_LEVEL_AV1_3              = 4,
    NV_ENC_LEVEL_AV1_31             = 5,
    NV_ENC_LEVEL_AV1_32             = 6,
    NV_ENC_LEVEL_AV1_33             = 7,
    NV_ENC_LEVEL_AV1_4              = 8,
    NV_ENC_LEVEL_AV1_41             = 9,
    NV_ENC_LEVEL_AV1_42             = 10,
    NV_ENC_LEVEL_AV1_43             = 11,
    NV_ENC_LEVEL_AV1_5              = 12,
    NV_ENC_LEVEL_AV1_51             = 13,
    NV_ENC_LEVEL_AV1_52             = 14,
    NV_ENC_LEVEL_AV1_53             = 15,
    NV_ENC_LEVEL_AV1_6              = 16,
    NV_ENC_LEVEL_AV1_61             = 17,
    NV_ENC_LEVEL_AV1_62             = 18,
    NV_ENC_LEVEL_AV1_63             = 19,
    NV_ENC_LEVEL_AV1_7              = 20,
    NV_ENC_LEVEL_AV1_71             = 21,
    NV_ENC_LEVEL_AV1_72             = 22,
    NV_ENC_LEVEL_AV1_73             = 23,
    NV_ENC_LEVEL_AV1_AUTOSELECT         ,

    NV_ENC_TIER_AV1_0               = 0,
    NV_ENC_TIER_AV1_1               = 1
} NV_ENC_LEVEL;

typedef enum _NVENCSTATUS
{
    NV_ENC_SUCCESS,

    NV_ENC_ERR_NO_ENCODE_DEVICE,

    NV_ENC_ERR_UNSUPPORTED_DEVICE,

    NV_ENC_ERR_INVALID_ENCODERDEVICE,

    NV_ENC_ERR_INVALID_DEVICE,

    NV_ENC_ERR_DEVICE_NOT_EXIST,

    NV_ENC_ERR_INVALID_PTR,

    NV_ENC_ERR_INVALID_EVENT,

    NV_ENC_ERR_INVALID_PARAM,

    NV_ENC_ERR_INVALID_CALL,

    NV_ENC_ERR_OUT_OF_MEMORY,

    NV_ENC_ERR_ENCODER_NOT_INITIALIZED,

    NV_ENC_ERR_UNSUPPORTED_PARAM,

    NV_ENC_ERR_LOCK_BUSY,

    NV_ENC_ERR_NOT_ENOUGH_BUFFER,

    NV_ENC_ERR_INVALID_VERSION,

    NV_ENC_ERR_MAP_FAILED,

    NV_ENC_ERR_NEED_MORE_INPUT,

    NV_ENC_ERR_ENCODER_BUSY,

    NV_ENC_ERR_EVENT_NOT_REGISTERD,

    NV_ENC_ERR_GENERIC,

    NV_ENC_ERR_INCOMPATIBLE_CLIENT_KEY,

    NV_ENC_ERR_UNIMPLEMENTED,

    NV_ENC_ERR_RESOURCE_REGISTER_FAILED,

    NV_ENC_ERR_RESOURCE_NOT_REGISTERED,

    NV_ENC_ERR_RESOURCE_NOT_MAPPED,

    NV_ENC_ERR_NEED_MORE_OUTPUT,

} NVENCSTATUS;

typedef enum _NV_ENC_PIC_FLAGS
{
    NV_ENC_PIC_FLAG_FORCEINTRA                = 0x1,
    NV_ENC_PIC_FLAG_FORCEIDR                  = 0x2,
    NV_ENC_PIC_FLAG_OUTPUT_SPSPPS             = 0x4,
    NV_ENC_PIC_FLAG_EOS                       = 0x8,
    NV_ENC_PIC_FLAG_DISABLE_ENC_STATE_ADVANCE = 0x10,
    NV_ENC_PIC_FLAG_OUTPUT_RECON_FRAME        = 0x20,
} NV_ENC_PIC_FLAGS;

typedef enum _NV_ENC_MEMORY_HEAP
{
    NV_ENC_MEMORY_HEAP_AUTOSELECT      = 0,
    NV_ENC_MEMORY_HEAP_VID             = 1,
    NV_ENC_MEMORY_HEAP_SYSMEM_CACHED   = 2,
    NV_ENC_MEMORY_HEAP_SYSMEM_UNCACHED = 3
} NV_ENC_MEMORY_HEAP;

typedef enum _NV_ENC_BFRAME_REF_MODE
{
    NV_ENC_BFRAME_REF_MODE_DISABLED = 0x0,
    NV_ENC_BFRAME_REF_MODE_EACH     = 0x1,
    NV_ENC_BFRAME_REF_MODE_MIDDLE   = 0x2,
} NV_ENC_BFRAME_REF_MODE;

typedef enum _NV_ENC_H264_ENTROPY_CODING_MODE
{
    NV_ENC_H264_ENTROPY_CODING_MODE_AUTOSELECT = 0x0,
    NV_ENC_H264_ENTROPY_CODING_MODE_CABAC      = 0x1,
    NV_ENC_H264_ENTROPY_CODING_MODE_CAVLC      = 0x2
} NV_ENC_H264_ENTROPY_CODING_MODE;

typedef enum _NV_ENC_H264_BDIRECT_MODE
{
    NV_ENC_H264_BDIRECT_MODE_AUTOSELECT = 0x0,
    NV_ENC_H264_BDIRECT_MODE_DISABLE    = 0x1,
    NV_ENC_H264_BDIRECT_MODE_TEMPORAL   = 0x2,
    NV_ENC_H264_BDIRECT_MODE_SPATIAL    = 0x3
} NV_ENC_H264_BDIRECT_MODE;

typedef enum _NV_ENC_H264_FMO_MODE
{
    NV_ENC_H264_FMO_AUTOSELECT          = 0x0,
    NV_ENC_H264_FMO_ENABLE              = 0x1,
    NV_ENC_H264_FMO_DISABLE             = 0x2,
} NV_ENC_H264_FMO_MODE;

typedef enum _NV_ENC_H264_ADAPTIVE_TRANSFORM_MODE
{
    NV_ENC_H264_ADAPTIVE_TRANSFORM_AUTOSELECT = 0x0,
    NV_ENC_H264_ADAPTIVE_TRANSFORM_DISABLE    = 0x1,
    NV_ENC_H264_ADAPTIVE_TRANSFORM_ENABLE     = 0x2,
} NV_ENC_H264_ADAPTIVE_TRANSFORM_MODE;

typedef enum _NV_ENC_STEREO_PACKING_MODE
{
    NV_ENC_STEREO_PACKING_MODE_NONE             = 0x0,
    NV_ENC_STEREO_PACKING_MODE_CHECKERBOARD     = 0x1,
    NV_ENC_STEREO_PACKING_MODE_COLINTERLEAVE    = 0x2,
    NV_ENC_STEREO_PACKING_MODE_ROWINTERLEAVE    = 0x3,
    NV_ENC_STEREO_PACKING_MODE_SIDEBYSIDE       = 0x4,
    NV_ENC_STEREO_PACKING_MODE_TOPBOTTOM        = 0x5,
    NV_ENC_STEREO_PACKING_MODE_FRAMESEQ         = 0x6
} NV_ENC_STEREO_PACKING_MODE;

typedef enum _NV_ENC_INPUT_RESOURCE_TYPE
{
    NV_ENC_INPUT_RESOURCE_TYPE_DIRECTX          = 0x0,
    NV_ENC_INPUT_RESOURCE_TYPE_CUDADEVICEPTR    = 0x1,
    NV_ENC_INPUT_RESOURCE_TYPE_CUDAARRAY        = 0x2,
    NV_ENC_INPUT_RESOURCE_TYPE_OPENGL_TEX       = 0x3
} NV_ENC_INPUT_RESOURCE_TYPE;

typedef enum _NV_ENC_BUFFER_USAGE
{
    NV_ENC_INPUT_IMAGE              = 0x0,
    NV_ENC_OUTPUT_MOTION_VECTOR     = 0x1,
    NV_ENC_OUTPUT_BITSTREAM         = 0x2,
    NV_ENC_OUTPUT_RECON             = 0x4,
} NV_ENC_BUFFER_USAGE;

typedef enum _NV_ENC_DEVICE_TYPE
{
    NV_ENC_DEVICE_TYPE_DIRECTX          = 0x0,
    NV_ENC_DEVICE_TYPE_CUDA             = 0x1,
    NV_ENC_DEVICE_TYPE_OPENGL           = 0x2
} NV_ENC_DEVICE_TYPE;

typedef enum _NV_ENC_NUM_REF_FRAMES
{
    NV_ENC_NUM_REF_FRAMES_AUTOSELECT       = 0x0,
    NV_ENC_NUM_REF_FRAMES_1                = 0x1,
    NV_ENC_NUM_REF_FRAMES_2                = 0x2,
    NV_ENC_NUM_REF_FRAMES_3                = 0x3,
    NV_ENC_NUM_REF_FRAMES_4                = 0x4,
    NV_ENC_NUM_REF_FRAMES_5                = 0x5,
    NV_ENC_NUM_REF_FRAMES_6                = 0x6,
    NV_ENC_NUM_REF_FRAMES_7                = 0x7
} NV_ENC_NUM_REF_FRAMES;

typedef enum _NV_ENC_TEMPORAL_FILTER_LEVEL
{
    NV_ENC_TEMPORAL_FILTER_LEVEL_0 = 0,
    NV_ENC_TEMPORAL_FILTER_LEVEL_4 = 4,
}NV_ENC_TEMPORAL_FILTER_LEVEL;
typedef enum _NV_ENC_CAPS
{
    NV_ENC_CAPS_NUM_MAX_BFRAMES,

    NV_ENC_CAPS_SUPPORTED_RATECONTROL_MODES,

     NV_ENC_CAPS_SUPPORT_FIELD_ENCODING,

    NV_ENC_CAPS_SUPPORT_MONOCHROME,

    NV_ENC_CAPS_SUPPORT_FMO,

    NV_ENC_CAPS_SUPPORT_QPELMV,

    NV_ENC_CAPS_SUPPORT_BDIRECT_MODE,

    NV_ENC_CAPS_SUPPORT_CABAC,

    NV_ENC_CAPS_SUPPORT_ADAPTIVE_TRANSFORM,

    NV_ENC_CAPS_SUPPORT_STEREO_MVC,

    NV_ENC_CAPS_NUM_MAX_TEMPORAL_LAYERS,

    NV_ENC_CAPS_SUPPORT_HIERARCHICAL_PFRAMES,

    NV_ENC_CAPS_SUPPORT_HIERARCHICAL_BFRAMES,

    NV_ENC_CAPS_LEVEL_MAX,

    NV_ENC_CAPS_LEVEL_MIN,

    NV_ENC_CAPS_SEPARATE_COLOUR_PLANE,

    NV_ENC_CAPS_WIDTH_MAX,

    NV_ENC_CAPS_HEIGHT_MAX,

    NV_ENC_CAPS_SUPPORT_TEMPORAL_SVC,

    NV_ENC_CAPS_SUPPORT_DYN_RES_CHANGE,

    NV_ENC_CAPS_SUPPORT_DYN_BITRATE_CHANGE,

    NV_ENC_CAPS_SUPPORT_DYN_FORCE_CONSTQP,

    NV_ENC_CAPS_SUPPORT_DYN_RCMODE_CHANGE,

    NV_ENC_CAPS_SUPPORT_SUBFRAME_READBACK,

    NV_ENC_CAPS_SUPPORT_CONSTRAINED_ENCODING,

    NV_ENC_CAPS_SUPPORT_INTRA_REFRESH,

    NV_ENC_CAPS_SUPPORT_CUSTOM_VBV_BUF_SIZE,

    NV_ENC_CAPS_SUPPORT_DYNAMIC_SLICE_MODE,

    NV_ENC_CAPS_SUPPORT_REF_PIC_INVALIDATION,

    NV_ENC_CAPS_PREPROC_SUPPORT,

    NV_ENC_CAPS_ASYNC_ENCODE_SUPPORT,

    NV_ENC_CAPS_MB_NUM_MAX,

    NV_ENC_CAPS_MB_PER_SEC_MAX,

    NV_ENC_CAPS_SUPPORT_YUV444_ENCODE,

    NV_ENC_CAPS_SUPPORT_LOSSLESS_ENCODE,

    NV_ENC_CAPS_SUPPORT_SAO,

    NV_ENC_CAPS_SUPPORT_MEONLY_MODE,

    NV_ENC_CAPS_SUPPORT_LOOKAHEAD,

    NV_ENC_CAPS_SUPPORT_TEMPORAL_AQ,
    NV_ENC_CAPS_SUPPORT_10BIT_ENCODE,
    NV_ENC_CAPS_NUM_MAX_LTR_FRAMES,

    NV_ENC_CAPS_SUPPORT_WEIGHTED_PREDICTION,

    NV_ENC_CAPS_DYNAMIC_QUERY_ENCODER_CAPACITY,

    NV_ENC_CAPS_SUPPORT_BFRAME_REF_MODE,

    NV_ENC_CAPS_SUPPORT_EMPHASIS_LEVEL_MAP,

    NV_ENC_CAPS_WIDTH_MIN,

    NV_ENC_CAPS_HEIGHT_MIN,

    NV_ENC_CAPS_SUPPORT_MULTIPLE_REF_FRAMES,

    NV_ENC_CAPS_SUPPORT_ALPHA_LAYER_ENCODING,

    NV_ENC_CAPS_NUM_ENCODER_ENGINES,

    NV_ENC_CAPS_SINGLE_SLICE_INTRA_REFRESH,

    NV_ENC_CAPS_DISABLE_ENC_STATE_ADVANCE,

    NV_ENC_CAPS_OUTPUT_RECON_SURFACE,

    NV_ENC_CAPS_OUTPUT_BLOCK_STATS,

    NV_ENC_CAPS_OUTPUT_ROW_STATS,

     NV_ENC_CAPS_SUPPORT_TEMPORAL_FILTER,

    NV_ENC_CAPS_SUPPORT_LOOKAHEAD_LEVEL,

    NV_ENC_CAPS_SUPPORT_UNIDIRECTIONAL_B,

    NV_ENC_CAPS_EXPOSED_COUNT

} NV_ENC_CAPS;

typedef enum _NV_ENC_HEVC_CUSIZE
{
    NV_ENC_HEVC_CUSIZE_AUTOSELECT = 0,
    NV_ENC_HEVC_CUSIZE_8x8        = 1,
    NV_ENC_HEVC_CUSIZE_16x16      = 2,
    NV_ENC_HEVC_CUSIZE_32x32      = 3,
    NV_ENC_HEVC_CUSIZE_64x64      = 4,
}NV_ENC_HEVC_CUSIZE;

typedef enum _NV_ENC_AV1_PART_SIZE
{
    NV_ENC_AV1_PART_SIZE_AUTOSELECT    = 0,
    NV_ENC_AV1_PART_SIZE_4x4           = 1,
    NV_ENC_AV1_PART_SIZE_8x8           = 2,
    NV_ENC_AV1_PART_SIZE_16x16         = 3,
    NV_ENC_AV1_PART_SIZE_32x32         = 4,
    NV_ENC_AV1_PART_SIZE_64x64         = 5,
}NV_ENC_AV1_PART_SIZE;

typedef enum _NV_ENC_VUI_VIDEO_FORMAT
{
    NV_ENC_VUI_VIDEO_FORMAT_COMPONENT   = 0,
    NV_ENC_VUI_VIDEO_FORMAT_PAL         = 1,
    NV_ENC_VUI_VIDEO_FORMAT_NTSC        = 2,
    NV_ENC_VUI_VIDEO_FORMAT_SECAM       = 3,
    NV_ENC_VUI_VIDEO_FORMAT_MAC         = 4,
    NV_ENC_VUI_VIDEO_FORMAT_UNSPECIFIED = 5,
}NV_ENC_VUI_VIDEO_FORMAT;

typedef enum _NV_ENC_VUI_COLOR_PRIMARIES
{
    NV_ENC_VUI_COLOR_PRIMARIES_UNDEFINED   = 0,
    NV_ENC_VUI_COLOR_PRIMARIES_BT709       = 1,
    NV_ENC_VUI_COLOR_PRIMARIES_UNSPECIFIED = 2,
    NV_ENC_VUI_COLOR_PRIMARIES_RESERVED    = 3,
    NV_ENC_VUI_COLOR_PRIMARIES_BT470M      = 4,
    NV_ENC_VUI_COLOR_PRIMARIES_BT470BG     = 5,
    NV_ENC_VUI_COLOR_PRIMARIES_SMPTE170M   = 6,
    NV_ENC_VUI_COLOR_PRIMARIES_SMPTE240M   = 7,
    NV_ENC_VUI_COLOR_PRIMARIES_FILM        = 8,
    NV_ENC_VUI_COLOR_PRIMARIES_BT2020      = 9,
    NV_ENC_VUI_COLOR_PRIMARIES_SMPTE428    = 10,
    NV_ENC_VUI_COLOR_PRIMARIES_SMPTE431    = 11,
    NV_ENC_VUI_COLOR_PRIMARIES_SMPTE432    = 12,
    NV_ENC_VUI_COLOR_PRIMARIES_JEDEC_P22   = 22,
}NV_ENC_VUI_COLOR_PRIMARIES;

typedef enum _NV_ENC_VUI_TRANSFER_CHARACTERISTIC
{
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_UNDEFINED     = 0,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_BT709         = 1,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_UNSPECIFIED   = 2,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_RESERVED      = 3,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_BT470M        = 4,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_BT470BG       = 5,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_SMPTE170M     = 6,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_SMPTE240M     = 7,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_LINEAR        = 8,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_LOG           = 9,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_LOG_SQRT      = 10,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_IEC61966_2_4  = 11,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_BT1361_ECG    = 12,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_SRGB          = 13,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_BT2020_10     = 14,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_BT2020_12     = 15,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_SMPTE2084     = 16,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_SMPTE428      = 17,
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC_ARIB_STD_B67  = 18,
}NV_ENC_VUI_TRANSFER_CHARACTERISTIC;

typedef enum _NV_ENC_VUI_MATRIX_COEFFS
{
    NV_ENC_VUI_MATRIX_COEFFS_RGB         = 0,
    NV_ENC_VUI_MATRIX_COEFFS_BT709       = 1,
    NV_ENC_VUI_MATRIX_COEFFS_UNSPECIFIED = 2,
    NV_ENC_VUI_MATRIX_COEFFS_RESERVED    = 3,
    NV_ENC_VUI_MATRIX_COEFFS_FCC         = 4,
    NV_ENC_VUI_MATRIX_COEFFS_BT470BG     = 5,
    NV_ENC_VUI_MATRIX_COEFFS_SMPTE170M   = 6,
    NV_ENC_VUI_MATRIX_COEFFS_SMPTE240M   = 7,
    NV_ENC_VUI_MATRIX_COEFFS_YCGCO       = 8,
    NV_ENC_VUI_MATRIX_COEFFS_BT2020_NCL  = 9,
    NV_ENC_VUI_MATRIX_COEFFS_BT2020_CL   = 10,
    NV_ENC_VUI_MATRIX_COEFFS_SMPTE2085   = 11,
}NV_ENC_VUI_MATRIX_COEFFS;

typedef enum _NV_ENC_LOOKAHEAD_LEVEL
{
    NV_ENC_LOOKAHEAD_LEVEL_0             = 0,
    NV_ENC_LOOKAHEAD_LEVEL_1             = 1,
    NV_ENC_LOOKAHEAD_LEVEL_2             = 2,
    NV_ENC_LOOKAHEAD_LEVEL_3             = 3,
    NV_ENC_LOOKAHEAD_LEVEL_AUTOSELECT    = 15,
}NV_ENC_LOOKAHEAD_LEVEL;

typedef enum _NV_ENC_BIT_DEPTH
{
    NV_ENC_BIT_DEPTH_INVALID             = 0,
    NV_ENC_BIT_DEPTH_8                   = 8,
    NV_ENC_BIT_DEPTH_10                  = 10,
}NV_ENC_BIT_DEPTH;

typedef struct _NV_ENC_CAPS_PARAM
{
    uint32_t version;
    NV_ENC_CAPS  capsToQuery;
    uint32_t reserved[62];
} NV_ENC_CAPS_PARAM;

#define NV_ENC_CAPS_PARAM_VER NVENCAPI_STRUCT_VERSION(1)

typedef struct _NV_ENC_RESTORE_ENCODER_STATE_PARAMS
{
    uint32_t                  version;
    uint32_t                  bufferIdx;
    NV_ENC_STATE_RESTORE_TYPE state;
    uint32_t                  reserved;
    NV_ENC_OUTPUT_PTR         outputBitstream;
    void*                     completionEvent;
    uint32_t                  reserved1[64];
    void*                     reserved2[64];
} NV_ENC_RESTORE_ENCODER_STATE_PARAMS;

#define NV_ENC_RESTORE_ENCODER_STATE_PARAMS_VER NVENCAPI_STRUCT_VERSION(2)

typedef struct _NV_ENC_OUTPUT_STATS_BLOCK
{
   uint32_t                 version;
   uint8_t                  QP;
   uint8_t                  reserved[3];
   uint32_t                 bitcount;
   uint32_t                 reserved1[13];
} NV_ENC_OUTPUT_STATS_BLOCK;

#define NV_ENC_OUTPUT_STATS_BLOCK_VER NVENCAPI_STRUCT_VERSION(1)

typedef struct _NV_ENC_OUTPUT_STATS_ROW
{
   uint32_t                 version;
   uint8_t                  QP;
   uint8_t                  reserved[3];
   uint32_t                 bitcount;
   uint32_t                 reserved1[13];
} NV_ENC_OUTPUT_STATS_ROW;

#define NV_ENC_OUTPUT_STATS_ROW_VER NVENCAPI_STRUCT_VERSION(1)

typedef struct _NV_ENC_ENCODE_OUT_PARAMS
{
    uint32_t                  version;
    uint32_t                  bitstreamSizeInBytes;
    uint32_t                  reserved[62];
} NV_ENC_ENCODE_OUT_PARAMS;

#define NV_ENC_ENCODE_OUT_PARAMS_VER NVENCAPI_STRUCT_VERSION(1)

typedef struct _NV_ENC_LOOKAHEAD_PIC_PARAMS
{
    uint32_t                  version;
    uint32_t                  reserved;
    NV_ENC_INPUT_PTR          inputBuffer;
    NV_ENC_PIC_TYPE           pictureType;
    uint32_t                  reserved1[63];
    void*                     reserved2[64];
} NV_ENC_LOOKAHEAD_PIC_PARAMS;

#define NV_ENC_LOOKAHEAD_PIC_PARAMS_VER NVENCAPI_STRUCT_VERSION(2)

typedef struct _NV_ENC_CREATE_INPUT_BUFFER
{
    uint32_t                  version;
    uint32_t                  width;
    uint32_t                  height;
    NV_ENC_MEMORY_HEAP        memoryHeap;
    NV_ENC_BUFFER_FORMAT      bufferFmt;
    uint32_t                  reserved;
    NV_ENC_INPUT_PTR          inputBuffer;
    void*                     pSysMemBuffer;
    uint32_t                  reserved1[58];
    void*                     reserved2[63];
} NV_ENC_CREATE_INPUT_BUFFER;

#define NV_ENC_CREATE_INPUT_BUFFER_VER NVENCAPI_STRUCT_VERSION(2)

typedef struct _NV_ENC_CREATE_BITSTREAM_BUFFER
{
    uint32_t              version;
    uint32_t              size;
    NV_ENC_MEMORY_HEAP    memoryHeap;
    uint32_t              reserved;
    NV_ENC_OUTPUT_PTR     bitstreamBuffer;
    void*                 bitstreamBufferPtr;
    uint32_t              reserved1[58];
    void*                 reserved2[64];
} NV_ENC_CREATE_BITSTREAM_BUFFER;

#define NV_ENC_CREATE_BITSTREAM_BUFFER_VER NVENCAPI_STRUCT_VERSION(1)

typedef struct _NV_ENC_MVECTOR
{
    int16_t             mvx;
    int16_t             mvy;
} NV_ENC_MVECTOR;

typedef struct _NV_ENC_H264_MV_DATA
{
    NV_ENC_MVECTOR      mv[4];
    uint8_t             mbType;
    uint8_t             partitionType;
    uint16_t            reserved;
    uint32_t            mbCost;
} NV_ENC_H264_MV_DATA;

typedef struct _NV_ENC_HEVC_MV_DATA
{
    NV_ENC_MVECTOR    mv[4];
    uint8_t           cuType;
    uint8_t           cuSize;
    uint8_t           partitionMode;
    uint8_t           lastCUInCTB;
} NV_ENC_HEVC_MV_DATA;

typedef struct _NV_ENC_CREATE_MV_BUFFER
{
    uint32_t            version;
    uint32_t            reserved;
    NV_ENC_OUTPUT_PTR   mvBuffer;
    uint32_t            reserved1[254];
    void*               reserved2[63];
} NV_ENC_CREATE_MV_BUFFER;

#define NV_ENC_CREATE_MV_BUFFER_VER NVENCAPI_STRUCT_VERSION(2)

typedef struct _NV_ENC_QP
{
    uint32_t        qpInterP;
    uint32_t        qpInterB;
    uint32_t        qpIntra;
} NV_ENC_QP;

 typedef struct _NV_ENC_RC_PARAMS
 {
    uint32_t                        version;
    NV_ENC_PARAMS_RC_MODE           rateControlMode;
    NV_ENC_QP                       constQP;
    uint32_t                        averageBitRate;
    uint32_t                        maxBitRate;
    uint32_t                        vbvBufferSize;
    uint32_t                        vbvInitialDelay;
    uint32_t                        enableMinQP          :1;
    uint32_t                        enableMaxQP          :1;
    uint32_t                        enableInitialRCQP    :1;
    uint32_t                        enableAQ             :1;
    uint32_t                        reservedBitField1    :1;
    uint32_t                        enableLookahead      :1;
    uint32_t                        disableIadapt        :1;
    uint32_t                        disableBadapt        :1;
    uint32_t                        enableTemporalAQ     :1;
    uint32_t                        zeroReorderDelay     :1;
    uint32_t                        enableNonRefP        :1;
    uint32_t                        strictGOPTarget      :1;
    uint32_t                        aqStrength           :4;
    uint32_t                        enableExtLookahead   :1;
    uint32_t                        reservedBitFields    :15;
    NV_ENC_QP                       minQP;
    NV_ENC_QP                       maxQP;
    NV_ENC_QP                       initialRCQP;
    uint32_t                        temporallayerIdxMask;
    uint8_t                         temporalLayerQP[8];
    uint8_t                         targetQuality;
    uint8_t                         targetQualityLSB;
    uint16_t                        lookaheadDepth;
    uint8_t                         lowDelayKeyFrameScale;
    int8_t                          yDcQPIndexOffset;
    int8_t                          uDcQPIndexOffset;
    int8_t                          vDcQPIndexOffset;
    NV_ENC_QP_MAP_MODE              qpMapMode;
    NV_ENC_MULTI_PASS               multiPass;
    uint32_t                        alphaLayerBitrateRatio;
    int8_t                          cbQPIndexOffset;
    int8_t                          crQPIndexOffset;
    uint16_t                        reserved2;
    NV_ENC_LOOKAHEAD_LEVEL          lookaheadLevel;
    uint32_t                        reserved[3];
 } NV_ENC_RC_PARAMS;

#define NV_ENC_RC_PARAMS_VER NVENCAPI_STRUCT_VERSION(1)

#define MAX_NUM_CLOCK_TS    3

typedef struct _NV_ENC_CLOCK_TIMESTAMP_SET
{
    uint32_t        countingType            : 1;
    uint32_t        discontinuityFlag       : 1;
    uint32_t        cntDroppedFrames        : 1;
    uint32_t        nFrames                 : 8;
    uint32_t        secondsValue            : 6;
    uint32_t        minutesValue            : 6;
    uint32_t        hoursValue              : 5;
    uint32_t        reserved2               : 4;
    uint32_t        timeOffset;
} NV_ENC_CLOCK_TIMESTAMP_SET;

typedef struct _NV_ENC_TIME_CODE
{
    NV_ENC_DISPLAY_PIC_STRUCT       displayPicStruct;
    NV_ENC_CLOCK_TIMESTAMP_SET      clockTimestamp[MAX_NUM_CLOCK_TS];
    uint32_t                        skipClockTimestampInsertion;
} NV_ENC_TIME_CODE;

typedef struct _NV_ENC_CONFIG_H264_VUI_PARAMETERS
{
    uint32_t                            overscanInfoPresentFlag;
    uint32_t                            overscanInfo;
    uint32_t                            videoSignalTypePresentFlag;
    NV_ENC_VUI_VIDEO_FORMAT             videoFormat;
    uint32_t                            videoFullRangeFlag;
    uint32_t                            colourDescriptionPresentFlag;
    NV_ENC_VUI_COLOR_PRIMARIES          colourPrimaries;
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC  transferCharacteristics;
    NV_ENC_VUI_MATRIX_COEFFS            colourMatrix;
    uint32_t                            chromaSampleLocationFlag;
    uint32_t                            chromaSampleLocationTop;
    uint32_t                            chromaSampleLocationBot;
    uint32_t                            bitstreamRestrictionFlag;
    uint32_t                            timingInfoPresentFlag;
    uint32_t                            numUnitInTicks;
    uint32_t                            timeScale;
    uint32_t                            reserved[12];
}NV_ENC_CONFIG_H264_VUI_PARAMETERS;

typedef NV_ENC_CONFIG_H264_VUI_PARAMETERS NV_ENC_CONFIG_HEVC_VUI_PARAMETERS;

typedef struct _NVENC_EXTERNAL_ME_HINT_COUNTS_PER_BLOCKTYPE
{
    uint32_t   numCandsPerBlk16x16                   : 4;
    uint32_t   numCandsPerBlk16x8                    : 4;
    uint32_t   numCandsPerBlk8x16                    : 4;
    uint32_t   numCandsPerBlk8x8                     : 4;
    uint32_t   numCandsPerSb                         : 8;
    uint32_t   reserved                              : 8;
    uint32_t   reserved1[3];
} NVENC_EXTERNAL_ME_HINT_COUNTS_PER_BLOCKTYPE;

typedef struct _NVENC_EXTERNAL_ME_HINT
{
    int32_t    mvx         : 12;
    int32_t    mvy         : 10;
    int32_t    refidx      : 5;
    int32_t    dir         : 1;
    int32_t    partType    : 2;
    int32_t    lastofPart  : 1;
    int32_t    lastOfMB    : 1;
} NVENC_EXTERNAL_ME_HINT;

typedef struct _NVENC_EXTERNAL_ME_SB_HINT
{
    int16_t    refidx         : 5;
    int16_t    direction      : 1;
    int16_t    bi             : 1;
    int16_t    partition_type : 3;
    int16_t    x8             : 3;
    int16_t    last_of_cu     : 1;
    int16_t    last_of_sb     : 1;
    int16_t    reserved0      : 1;
    int16_t    mvx            : 14;
    int16_t    cu_size        : 2;
    int16_t    mvy            : 12;
    int16_t    y8             : 3;
    int16_t    reserved1      : 1;
} NVENC_EXTERNAL_ME_SB_HINT;

typedef struct _NV_ENC_CONFIG_H264
{
    uint32_t enableTemporalSVC         :1;
    uint32_t enableStereoMVC           :1;
    uint32_t hierarchicalPFrames       :1;
    uint32_t hierarchicalBFrames       :1;
    uint32_t outputBufferingPeriodSEI  :1;
    uint32_t outputPictureTimingSEI    :1;
    uint32_t outputAUD                 :1;
    uint32_t disableSPSPPS             :1;
    uint32_t outputFramePackingSEI     :1;
    uint32_t outputRecoveryPointSEI    :1;
    uint32_t enableIntraRefresh        :1;
    uint32_t enableConstrainedEncoding :1;
    uint32_t repeatSPSPPS              :1;
    uint32_t enableVFR                 :1;
    uint32_t enableLTR                 :1;
    uint32_t qpPrimeYZeroTransformBypassFlag :1;
    uint32_t useConstrainedIntraPred   :1;
    uint32_t enableFillerDataInsertion :1;
    uint32_t disableSVCPrefixNalu      :1;
    uint32_t enableScalabilityInfoSEI  :1;
    uint32_t singleSliceIntraRefresh   :1;
    uint32_t enableTimeCode            :1;
    uint32_t reservedBitFields         :10;
    uint32_t level;
    uint32_t idrPeriod;
    uint32_t separateColourPlaneFlag;
    uint32_t disableDeblockingFilterIDC;
    uint32_t numTemporalLayers;
    uint32_t spsId;
    uint32_t ppsId;
    NV_ENC_H264_ADAPTIVE_TRANSFORM_MODE adaptiveTransformMode;
    NV_ENC_H264_FMO_MODE                fmoMode;
    NV_ENC_H264_BDIRECT_MODE            bdirectMode;
    NV_ENC_H264_ENTROPY_CODING_MODE     entropyCodingMode;
    NV_ENC_STEREO_PACKING_MODE          stereoMode;
    uint32_t                            intraRefreshPeriod;
    uint32_t                            intraRefreshCnt;
    uint32_t                            maxNumRefFrames;
    uint32_t                            sliceMode;
    uint32_t                            sliceModeData;
    NV_ENC_CONFIG_H264_VUI_PARAMETERS   h264VUIParameters;
    uint32_t                            ltrNumFrames;
    uint32_t                            ltrTrustMode;
    uint32_t                            chromaFormatIDC;
    uint32_t                            maxTemporalLayers;
    NV_ENC_BFRAME_REF_MODE              useBFramesAsRef;
    NV_ENC_NUM_REF_FRAMES               numRefL0;
    NV_ENC_NUM_REF_FRAMES               numRefL1;
    NV_ENC_BIT_DEPTH                    outputBitDepth;
    NV_ENC_BIT_DEPTH                    inputBitDepth;
    uint32_t                            reserved1[265];
    void*                               reserved2[64];
} NV_ENC_CONFIG_H264;

typedef struct _NV_ENC_CONFIG_HEVC
{
    uint32_t level;
    uint32_t tier;
    NV_ENC_HEVC_CUSIZE minCUSize;
    NV_ENC_HEVC_CUSIZE maxCUSize;
    uint32_t useConstrainedIntraPred               :1;
    uint32_t disableDeblockAcrossSliceBoundary     :1;
    uint32_t outputBufferingPeriodSEI              :1;
    uint32_t outputPictureTimingSEI                :1;
    uint32_t outputAUD                             :1;
    uint32_t enableLTR                             :1;
    uint32_t disableSPSPPS                         :1;
    uint32_t repeatSPSPPS                          :1;
    uint32_t enableIntraRefresh                    :1;
    uint32_t chromaFormatIDC                       :2;
    uint32_t reserved3                             :3;
    uint32_t enableFillerDataInsertion             :1;
    uint32_t enableConstrainedEncoding             :1;
    uint32_t enableAlphaLayerEncoding              :1;
    uint32_t singleSliceIntraRefresh               :1;
    uint32_t outputRecoveryPointSEI                :1;
    uint32_t outputTimeCodeSEI                     :1;
    uint32_t reserved                              :12;
    uint32_t idrPeriod;
    uint32_t intraRefreshPeriod;
    uint32_t intraRefreshCnt;
    uint32_t maxNumRefFramesInDPB;
    uint32_t ltrNumFrames;
    uint32_t vpsId;
    uint32_t spsId;
    uint32_t ppsId;
    uint32_t sliceMode;
    uint32_t sliceModeData;
    uint32_t maxTemporalLayersMinus1;
    NV_ENC_CONFIG_HEVC_VUI_PARAMETERS   hevcVUIParameters;
    uint32_t ltrTrustMode;
    NV_ENC_BFRAME_REF_MODE              useBFramesAsRef;
    NV_ENC_NUM_REF_FRAMES               numRefL0;
    NV_ENC_NUM_REF_FRAMES               numRefL1;
    NV_ENC_TEMPORAL_FILTER_LEVEL        tfLevel;
    uint32_t                            disableDeblockingFilterIDC;
   NV_ENC_BIT_DEPTH                     outputBitDepth;
   NV_ENC_BIT_DEPTH                     inputBitDepth;
    uint32_t                            reserved1[210];
    void*                               reserved2[64];
} NV_ENC_CONFIG_HEVC;

#define NV_MAX_TILE_COLS_AV1               64
#define NV_MAX_TILE_ROWS_AV1               64

typedef struct _NV_ENC_FILM_GRAIN_PARAMS_AV1
{
    uint32_t applyGrain                 :1;
    uint32_t chromaScalingFromLuma      :1;
    uint32_t overlapFlag                :1;
    uint32_t clipToRestrictedRange      :1;
    uint32_t grainScalingMinus8         :2;
    uint32_t arCoeffLag                 :2;
    uint32_t numYPoints                 :4;
    uint32_t numCbPoints                :4;
    uint32_t numCrPoints                :4;
    uint32_t arCoeffShiftMinus6         :2;
    uint32_t grainScaleShift            :2;
    uint32_t reserved1                  :8;
    uint8_t  pointYValue[14];
    uint8_t  pointYScaling[14];
    uint8_t  pointCbValue[10];
    uint8_t  pointCbScaling[10];
    uint8_t  pointCrValue[10];
    uint8_t  pointCrScaling[10];
    uint8_t  arCoeffsYPlus128[24];
    uint8_t  arCoeffsCbPlus128[25];
    uint8_t  arCoeffsCrPlus128[25];
    uint8_t  reserved2[2];
    uint8_t  cbMult;
    uint8_t  cbLumaMult;
    uint16_t cbOffset;
    uint8_t  crMult;
    uint8_t  crLumaMult;
    uint16_t crOffset;
} NV_ENC_FILM_GRAIN_PARAMS_AV1;

typedef struct _NV_ENC_CONFIG_AV1
{
    uint32_t level;
    uint32_t tier;
    NV_ENC_AV1_PART_SIZE minPartSize;
    NV_ENC_AV1_PART_SIZE maxPartSize;
    uint32_t outputAnnexBFormat             : 1;
    uint32_t enableTimingInfo               : 1;
    uint32_t enableDecoderModelInfo         : 1;
    uint32_t enableFrameIdNumbers           : 1;
    uint32_t disableSeqHdr                  : 1;
    uint32_t repeatSeqHdr                   : 1;
    uint32_t enableIntraRefresh             : 1;
    uint32_t chromaFormatIDC                : 2;
    uint32_t enableBitstreamPadding         : 1;
    uint32_t enableCustomTileConfig         : 1;
    uint32_t enableFilmGrainParams          : 1;
    uint32_t reserved4                      : 6;
    uint32_t reserved                       : 14;
    uint32_t idrPeriod;
    uint32_t intraRefreshPeriod;
    uint32_t intraRefreshCnt;
    uint32_t maxNumRefFramesInDPB;
    uint32_t numTileColumns;
    uint32_t numTileRows;
    uint32_t reserved2;
    uint32_t *tileWidths;
    uint32_t *tileHeights;
    uint32_t maxTemporalLayersMinus1;
    NV_ENC_VUI_COLOR_PRIMARIES colorPrimaries;
    NV_ENC_VUI_TRANSFER_CHARACTERISTIC transferCharacteristics;
    NV_ENC_VUI_MATRIX_COEFFS matrixCoefficients;
    uint32_t colorRange;
    uint32_t chromaSamplePosition;
    NV_ENC_BFRAME_REF_MODE useBFramesAsRef;
    NV_ENC_FILM_GRAIN_PARAMS_AV1 *filmGrainParams;
    NV_ENC_NUM_REF_FRAMES  numFwdRefs;
    NV_ENC_NUM_REF_FRAMES  numBwdRefs;
   NV_ENC_BIT_DEPTH outputBitDepth;
   NV_ENC_BIT_DEPTH inputBitDepth;
    uint32_t reserved1[233];
    void*    reserved3[62];
} NV_ENC_CONFIG_AV1;

typedef struct _NV_ENC_CONFIG_H264_MEONLY
{
    uint32_t disablePartition16x16 :1;
    uint32_t disablePartition8x16  :1;
    uint32_t disablePartition16x8  :1;
    uint32_t disablePartition8x8   :1;
    uint32_t disableIntraSearch    :1;
    uint32_t bStereoEnable         :1;
    uint32_t reserved              :26;
    uint32_t reserved1 [255];
    void*    reserved2[64];
} NV_ENC_CONFIG_H264_MEONLY;

typedef struct _NV_ENC_CONFIG_HEVC_MEONLY
{
    uint32_t reserved [256];
    void*    reserved1[64];
} NV_ENC_CONFIG_HEVC_MEONLY;

typedef union _NV_ENC_CODEC_CONFIG
{
    NV_ENC_CONFIG_H264        h264Config;
    NV_ENC_CONFIG_HEVC        hevcConfig;
    NV_ENC_CONFIG_AV1         av1Config;
    NV_ENC_CONFIG_H264_MEONLY h264MeOnlyConfig;
    NV_ENC_CONFIG_HEVC_MEONLY hevcMeOnlyConfig;
    uint32_t                reserved[320];
} NV_ENC_CODEC_CONFIG;

typedef struct _NV_ENC_CONFIG
{
    uint32_t                        version;
    GUID                            profileGUID;
    uint32_t                        gopLength;
    int32_t                         frameIntervalP;
    uint32_t                        monoChromeEncoding;
    NV_ENC_PARAMS_FRAME_FIELD_MODE  frameFieldMode;
    NV_ENC_MV_PRECISION             mvPrecision;
    NV_ENC_RC_PARAMS                rcParams;
    NV_ENC_CODEC_CONFIG             encodeCodecConfig;
    uint32_t                        reserved [278];
    void*                           reserved2[64];
} NV_ENC_CONFIG;

#define NV_ENC_CONFIG_VER (NVENCAPI_STRUCT_VERSION(9) | ( 1u<<31 ))

typedef enum NV_ENC_TUNING_INFO
{
    NV_ENC_TUNING_INFO_UNDEFINED         = 0,
    NV_ENC_TUNING_INFO_HIGH_QUALITY      = 1,
    NV_ENC_TUNING_INFO_LOW_LATENCY       = 2,
    NV_ENC_TUNING_INFO_ULTRA_LOW_LATENCY = 3,
    NV_ENC_TUNING_INFO_LOSSLESS          = 4,
    NV_ENC_TUNING_INFO_ULTRA_HIGH_QUALITY = 5,
    NV_ENC_TUNING_INFO_COUNT
}NV_ENC_TUNING_INFO;

typedef enum _NV_ENC_SPLIT_ENCODE_MODE
{
    NV_ENC_SPLIT_AUTO_MODE               = 0,
    NV_ENC_SPLIT_AUTO_FORCED_MODE        = 1,
    NV_ENC_SPLIT_TWO_FORCED_MODE         = 2,
    NV_ENC_SPLIT_THREE_FORCED_MODE       = 3,
    NV_ENC_SPLIT_DISABLE_MODE            = 15,
} NV_ENC_SPLIT_ENCODE_MODE;

typedef struct _NV_ENC_INITIALIZE_PARAMS
{
    uint32_t                                   version;
    GUID                                       encodeGUID;
    GUID                                       presetGUID;
    uint32_t                                   encodeWidth;
    uint32_t                                   encodeHeight;
    uint32_t                                   darWidth;
    uint32_t                                   darHeight;
    uint32_t                                   frameRateNum;
    uint32_t                                   frameRateDen;
    uint32_t                                   enableEncodeAsync;
    uint32_t                                   enablePTD;
    uint32_t                                   reportSliceOffsets        :1;
    uint32_t                                   enableSubFrameWrite       :1;
    uint32_t                                   enableExternalMEHints     :1;
    uint32_t                                   enableMEOnlyMode          :1;
    uint32_t                                   enableWeightedPrediction  :1;
    uint32_t                                   splitEncodeMode           :4;
    uint32_t                                   enableOutputInVidmem      :1;
    uint32_t                                   enableReconFrameOutput    :1;
    uint32_t                                   enableOutputStats         :1;
    uint32_t                                   enableUniDirectionalB     :1;
    uint32_t                                   reservedBitFields         :19;
    uint32_t                                   privDataSize;
    uint32_t                                   reserved;
    void*                                      privData;
    NV_ENC_CONFIG*                             encodeConfig;
    uint32_t                                   maxEncodeWidth;
    uint32_t                                   maxEncodeHeight;
    NVENC_EXTERNAL_ME_HINT_COUNTS_PER_BLOCKTYPE maxMEHintCountsPerBlock[2];
    NV_ENC_TUNING_INFO                         tuningInfo;
    NV_ENC_BUFFER_FORMAT                       bufferFormat;
    uint32_t                                   numStateBuffers;
    NV_ENC_OUTPUT_STATS_LEVEL                  outputStatsLevel;
    uint32_t                                   reserved1 [284];
    void*                                      reserved2[64];
} NV_ENC_INITIALIZE_PARAMS;

#define NV_ENC_INITIALIZE_PARAMS_VER (NVENCAPI_STRUCT_VERSION(7) | ( 1u<<31 ))

typedef struct _NV_ENC_RECONFIGURE_PARAMS
{
    uint32_t                                    version;
    uint32_t                                    reserved;
    NV_ENC_INITIALIZE_PARAMS                    reInitEncodeParams;
    uint32_t                                    resetEncoder            :1;
    uint32_t                                    forceIDR                :1;
    uint32_t                                    reserved1                :30;
    uint32_t                                    reserved2;

}NV_ENC_RECONFIGURE_PARAMS;

#define NV_ENC_RECONFIGURE_PARAMS_VER (NVENCAPI_STRUCT_VERSION(2) | ( 1u<<31 ))

typedef struct _NV_ENC_PRESET_CONFIG
{
    uint32_t      version;
    uint32_t      reserved;
    NV_ENC_CONFIG presetCfg;
    uint32_t      reserved1[256];
    void*         reserved2[64];
}NV_ENC_PRESET_CONFIG;

#define NV_ENC_PRESET_CONFIG_VER (NVENCAPI_STRUCT_VERSION(5) | ( 1u<<31 ))

typedef struct _NV_ENC_PIC_PARAMS_MVC
{
    uint32_t version;
    uint32_t viewID;
    uint32_t temporalID;
    uint32_t priorityID;
    uint32_t reserved1[12];
    void*    reserved2[8];
}NV_ENC_PIC_PARAMS_MVC;

#define NV_ENC_PIC_PARAMS_MVC_VER NVENCAPI_STRUCT_VERSION(1)

typedef union _NV_ENC_PIC_PARAMS_H264_EXT
{
    NV_ENC_PIC_PARAMS_MVC mvcPicParams;
    uint32_t reserved1[32];
}NV_ENC_PIC_PARAMS_H264_EXT;

typedef struct _NV_ENC_SEI_PAYLOAD
{
    uint32_t payloadSize;
    uint32_t payloadType;
    uint8_t *payload;
} NV_ENC_SEI_PAYLOAD;

#define NV_ENC_H264_SEI_PAYLOAD NV_ENC_SEI_PAYLOAD

typedef struct _NV_ENC_PIC_PARAMS_H264
{
    uint32_t displayPOCSyntax;
    uint32_t reserved3;
    uint32_t refPicFlag;
    uint32_t colourPlaneId;
    uint32_t forceIntraRefreshWithFrameCnt;
    uint32_t constrainedFrame           :1;
    uint32_t sliceModeDataUpdate        :1;
    uint32_t ltrMarkFrame               :1;
    uint32_t ltrUseFrames               :1;
    uint32_t reservedBitFields          :28;
    uint8_t* sliceTypeData;
    uint32_t sliceTypeArrayCnt;
    uint32_t seiPayloadArrayCnt;
    NV_ENC_SEI_PAYLOAD* seiPayloadArray;
    uint32_t sliceMode;
    uint32_t sliceModeData;
    uint32_t ltrMarkFrameIdx;
    uint32_t ltrUseFrameBitmap;
    uint32_t ltrUsageMode;
    uint32_t forceIntraSliceCount;
    uint32_t *forceIntraSliceIdx;
    NV_ENC_PIC_PARAMS_H264_EXT h264ExtPicParams;
    NV_ENC_TIME_CODE timeCode;
    uint32_t reserved [202];
    void*    reserved2[61];
} NV_ENC_PIC_PARAMS_H264;

typedef struct _NV_ENC_PIC_PARAMS_HEVC
{
    uint32_t displayPOCSyntax;
    uint32_t refPicFlag;
    uint32_t temporalId;
    uint32_t forceIntraRefreshWithFrameCnt;
    uint32_t constrainedFrame           :1;
    uint32_t sliceModeDataUpdate        :1;
    uint32_t ltrMarkFrame               :1;
    uint32_t ltrUseFrames               :1;
    uint32_t reservedBitFields          :28;
    uint32_t reserved1;
    uint8_t* sliceTypeData;
    uint32_t sliceTypeArrayCnt;
    uint32_t sliceMode;
    uint32_t sliceModeData;
    uint32_t ltrMarkFrameIdx;
    uint32_t ltrUseFrameBitmap;
    uint32_t ltrUsageMode;
    uint32_t seiPayloadArrayCnt;
    uint32_t reserved;
    NV_ENC_SEI_PAYLOAD* seiPayloadArray;
    NV_ENC_TIME_CODE timeCode;
    uint32_t reserved2[236];
    void* reserved3[61];
} NV_ENC_PIC_PARAMS_HEVC;

#define NV_ENC_AV1_OBU_PAYLOAD NV_ENC_SEI_PAYLOAD

typedef struct _NV_ENC_PIC_PARAMS_AV1
{
    uint32_t displayPOCSyntax;
    uint32_t refPicFlag;
    uint32_t temporalId;
    uint32_t forceIntraRefreshWithFrameCnt;
    uint32_t goldenFrameFlag            : 1;
    uint32_t arfFrameFlag               : 1;
    uint32_t arf2FrameFlag              : 1;
    uint32_t bwdFrameFlag               : 1;
    uint32_t overlayFrameFlag           : 1;
    uint32_t showExistingFrameFlag      : 1;
    uint32_t errorResilientModeFlag     : 1;

    uint32_t tileConfigUpdate           : 1;
    uint32_t enableCustomTileConfig     : 1;
    uint32_t filmGrainParamsUpdate      : 1;
    uint32_t reservedBitFields          : 22;
    uint32_t numTileColumns;
    uint32_t numTileRows;
    uint32_t reserved;
    uint32_t *tileWidths;
    uint32_t *tileHeights;
    uint32_t obuPayloadArrayCnt;
    uint32_t reserved1;
    NV_ENC_AV1_OBU_PAYLOAD* obuPayloadArray;
    NV_ENC_FILM_GRAIN_PARAMS_AV1 *filmGrainParams;
    uint32_t reserved2[246];
    void*    reserved3[61];
} NV_ENC_PIC_PARAMS_AV1;

typedef union _NV_ENC_CODEC_PIC_PARAMS
{
    NV_ENC_PIC_PARAMS_H264 h264PicParams;
    NV_ENC_PIC_PARAMS_HEVC hevcPicParams;
    NV_ENC_PIC_PARAMS_AV1  av1PicParams;
    uint32_t               reserved[256];
} NV_ENC_CODEC_PIC_PARAMS;

typedef struct _NV_ENC_PIC_PARAMS
{
    uint32_t                                    version;
    uint32_t                                    inputWidth;
    uint32_t                                    inputHeight;
    uint32_t                                    inputPitch;
    uint32_t                                    encodePicFlags;
    uint32_t                                    frameIdx;
    uint64_t                                    inputTimeStamp;
    uint64_t                                    inputDuration;
    NV_ENC_INPUT_PTR                            inputBuffer;
    NV_ENC_OUTPUT_PTR                           outputBitstream;
    void*                                       completionEvent;
    NV_ENC_BUFFER_FORMAT                        bufferFmt;
    NV_ENC_PIC_STRUCT                           pictureStruct;
    NV_ENC_PIC_TYPE                             pictureType;
    NV_ENC_CODEC_PIC_PARAMS                     codecPicParams;
    NVENC_EXTERNAL_ME_HINT_COUNTS_PER_BLOCKTYPE meHintCountsPerBlock[2];
    NVENC_EXTERNAL_ME_HINT                     *meExternalHints;
    uint32_t                                    reserved2[7];
    void*                                       reserved5[2];
    int8_t                                     *qpDeltaMap;
    uint32_t                                    qpDeltaMapSize;
    uint32_t                                    reservedBitFields;
    uint16_t                                    meHintRefPicDist[2];
     uint32_t                                    reserved4;
    NV_ENC_INPUT_PTR                            alphaBuffer;
    NVENC_EXTERNAL_ME_SB_HINT                  *meExternalSbHints;
    uint32_t                                    meSbHintsCount;
    uint32_t                                    stateBufferIdx;
    NV_ENC_OUTPUT_PTR                           outputReconBuffer;
    uint32_t                                    reserved3[284];
    void*                                       reserved6[57];
} NV_ENC_PIC_PARAMS;

#define NV_ENC_PIC_PARAMS_VER (NVENCAPI_STRUCT_VERSION(7) | ( 1u<<31 ))

typedef struct _NV_ENC_MEONLY_PARAMS
{
    uint32_t                version;
    uint32_t                inputWidth;
    uint32_t                inputHeight;
    uint32_t                reserved;
    NV_ENC_INPUT_PTR        inputBuffer;
    NV_ENC_INPUT_PTR        referenceFrame;
    NV_ENC_OUTPUT_PTR       mvBuffer;
    uint32_t                reserved2;
    NV_ENC_BUFFER_FORMAT    bufferFmt;
    void*                   completionEvent;
    uint32_t                viewID;
    NVENC_EXTERNAL_ME_HINT_COUNTS_PER_BLOCKTYPE
                            meHintCountsPerBlock[2];
    NVENC_EXTERNAL_ME_HINT  *meExternalHints;
    uint32_t                reserved1[241];
    void*                   reserved3[59];
} NV_ENC_MEONLY_PARAMS;

#define NV_ENC_MEONLY_PARAMS_VER NVENCAPI_STRUCT_VERSION(4)

typedef struct _NV_ENC_LOCK_BITSTREAM
{
    uint32_t                version;
    uint32_t                doNotWait         :1;
    uint32_t                ltrFrame          :1;
    uint32_t                getRCStats        :1;
    uint32_t                reservedBitFields :29;
    void*                   outputBitstream;
    uint32_t*               sliceOffsets;
    uint32_t                frameIdx;
    uint32_t                hwEncodeStatus;
    uint32_t                numSlices;
    uint32_t                bitstreamSizeInBytes;
    uint64_t                outputTimeStamp;
    uint64_t                outputDuration;
    void*                   bitstreamBufferPtr;
    NV_ENC_PIC_TYPE         pictureType;
    NV_ENC_PIC_STRUCT       pictureStruct;
    uint32_t                frameAvgQP;
    uint32_t                frameSatd;
    uint32_t                ltrFrameIdx;
    uint32_t                ltrFrameBitmap;
    uint32_t                temporalId;
    uint32_t                intraMBCount;
    uint32_t                interMBCount;
    int32_t                 averageMVX;
    int32_t                 averageMVY;
    uint32_t                alphaLayerSizeInBytes;
    uint32_t                outputStatsPtrSize;
    uint32_t                reserved;
    void*                   outputStatsPtr;
    uint32_t                frameIdxDisplay;
    uint32_t                reserved1[219];
    void*                   reserved2[63];
    uint32_t                reservedInternal[8];
} NV_ENC_LOCK_BITSTREAM;

#define NV_ENC_LOCK_BITSTREAM_VER (NVENCAPI_STRUCT_VERSION(2) | ( 1u<<31 ))

typedef struct _NV_ENC_LOCK_INPUT_BUFFER
{
    uint32_t                  version;
    uint32_t                  doNotWait         :1;
    uint32_t                  reservedBitFields :31;
    NV_ENC_INPUT_PTR          inputBuffer;
    void*                     bufferDataPtr;
    uint32_t                  pitch;
    uint32_t                  reserved1[251];
    void*                     reserved2[64];
} NV_ENC_LOCK_INPUT_BUFFER;

#define NV_ENC_LOCK_INPUT_BUFFER_VER NVENCAPI_STRUCT_VERSION(1)

typedef struct _NV_ENC_MAP_INPUT_RESOURCE
{
    uint32_t                   version;
    uint32_t                   subResourceIndex;
    void*                      inputResource;
    NV_ENC_REGISTERED_PTR      registeredResource;
    NV_ENC_INPUT_PTR           mappedResource;
    NV_ENC_BUFFER_FORMAT       mappedBufferFmt;
    uint32_t                   reserved1[251];
    void*                      reserved2[63];
} NV_ENC_MAP_INPUT_RESOURCE;

#define NV_ENC_MAP_INPUT_RESOURCE_VER NVENCAPI_STRUCT_VERSION(4)

typedef struct _NV_ENC_INPUT_RESOURCE_OPENGL_TEX
{
    uint32_t texture;
    uint32_t target;
} NV_ENC_INPUT_RESOURCE_OPENGL_TEX;

typedef struct _NV_ENC_FENCE_POINT_D3D12
{
    uint32_t                version;
    uint32_t                reserved;
    void*                   pFence;
    uint64_t                waitValue;
    uint64_t                signalValue;
    uint32_t                bWait:1;
    uint32_t                bSignal:1;
    uint32_t                reservedBitField:30;
    uint32_t                reserved1[7];
} NV_ENC_FENCE_POINT_D3D12;

#define NV_ENC_FENCE_POINT_D3D12_VER NVENCAPI_STRUCT_VERSION(1)

typedef struct _NV_ENC_INPUT_RESOURCE_D3D12
{
    uint32_t                    version;
    uint32_t                    reserved;
    NV_ENC_INPUT_PTR            pInputBuffer;
    NV_ENC_FENCE_POINT_D3D12    inputFencePoint;
    uint32_t                    reserved1[16];
    void*                       reserved2[16];
} NV_ENC_INPUT_RESOURCE_D3D12;

#define NV_ENC_INPUT_RESOURCE_D3D12_VER NVENCAPI_STRUCT_VERSION(1)

typedef struct _NV_ENC_OUTPUT_RESOURCE_D3D12
{
    uint32_t                    version;
    uint32_t                    reserved;
    NV_ENC_INPUT_PTR            pOutputBuffer;
    NV_ENC_FENCE_POINT_D3D12    outputFencePoint;
    uint32_t                    reserved1[16];
    void*                       reserved2[16];
} NV_ENC_OUTPUT_RESOURCE_D3D12;

#define NV_ENC_OUTPUT_RESOURCE_D3D12_VER NVENCAPI_STRUCT_VERSION(1)

typedef struct _NV_ENC_REGISTER_RESOURCE
{
    uint32_t                    version;
    NV_ENC_INPUT_RESOURCE_TYPE  resourceType;
    uint32_t                    width;
    uint32_t                    height;
    uint32_t                    pitch;
    uint32_t                    subResourceIndex;
    void*                       resourceToRegister;
    NV_ENC_REGISTERED_PTR       registeredResource;
    NV_ENC_BUFFER_FORMAT        bufferFormat;
    NV_ENC_BUFFER_USAGE         bufferUsage;
    NV_ENC_FENCE_POINT_D3D12*   pInputFencePoint;
    uint32_t                    chromaOffset[2];
    uint32_t                    reserved1[246];
    void*                       reserved2[61];
} NV_ENC_REGISTER_RESOURCE;

#define NV_ENC_REGISTER_RESOURCE_VER NVENCAPI_STRUCT_VERSION(5)

typedef struct _NV_ENC_STAT
{
    uint32_t            version;
    uint32_t            reserved;
    NV_ENC_OUTPUT_PTR   outputBitStream;
    uint32_t            bitStreamSize;
    uint32_t            picType;
    uint32_t            lastValidByteOffset;
    uint32_t            sliceOffsets[16];
    uint32_t            picIdx;
    uint32_t            frameAvgQP;
    uint32_t            ltrFrame          :1;
    uint32_t            reservedBitFields :31;
    uint32_t            ltrFrameIdx;
    uint32_t            intraMBCount;
    uint32_t            interMBCount;
    int32_t             averageMVX;
    int32_t             averageMVY;
    uint32_t            reserved1[227];
    void*               reserved2[64];
} NV_ENC_STAT;

#define NV_ENC_STAT_VER NVENCAPI_STRUCT_VERSION(2)

typedef struct _NV_ENC_SEQUENCE_PARAM_PAYLOAD
{
    uint32_t            version;
    uint32_t            inBufferSize;
    uint32_t            spsId;
    uint32_t            ppsId;
    void*               spsppsBuffer;
    uint32_t*           outSPSPPSPayloadSize;
    uint32_t            reserved [250];
    void*               reserved2[64];
} NV_ENC_SEQUENCE_PARAM_PAYLOAD;

#define NV_ENC_SEQUENCE_PARAM_PAYLOAD_VER NVENCAPI_STRUCT_VERSION(1)

typedef struct _NV_ENC_EVENT_PARAMS
{
    uint32_t            version;
    uint32_t            reserved;
    void*               completionEvent;
    uint32_t            reserved1[254];
    void*               reserved2[64];
} NV_ENC_EVENT_PARAMS;

#define NV_ENC_EVENT_PARAMS_VER NVENCAPI_STRUCT_VERSION(2)

typedef struct _NV_ENC_OPEN_ENCODE_SESSIONEX_PARAMS
{
    uint32_t            version;
    NV_ENC_DEVICE_TYPE  deviceType;
    void*               device;
    void*               reserved;
    uint32_t            apiVersion;
    uint32_t            reserved1[253];
    void*               reserved2[64];
} NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS;
#define NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS_VER NVENCAPI_STRUCT_VERSION(1)

NVENCSTATUS NVENCAPI NvEncOpenEncodeSession                     (void* device, uint32_t deviceType, void** encoder);

NVENCSTATUS NVENCAPI NvEncGetEncodeGUIDCount                    (void* encoder, uint32_t* encodeGUIDCount);

NVENCSTATUS NVENCAPI NvEncGetEncodeGUIDs                        (void* encoder, GUID* GUIDs, uint32_t guidArraySize, uint32_t* GUIDCount);

NVENCSTATUS NVENCAPI NvEncGetEncodeProfileGUIDCount                    (void* encoder, GUID encodeGUID, uint32_t* encodeProfileGUIDCount);

NVENCSTATUS NVENCAPI NvEncGetEncodeProfileGUIDs                               (void* encoder, GUID encodeGUID, GUID* profileGUIDs, uint32_t guidArraySize, uint32_t* GUIDCount);

NVENCSTATUS NVENCAPI NvEncGetInputFormatCount                   (void* encoder, GUID encodeGUID, uint32_t* inputFmtCount);

NVENCSTATUS NVENCAPI NvEncGetInputFormats                       (void* encoder, GUID encodeGUID, NV_ENC_BUFFER_FORMAT* inputFmts, uint32_t inputFmtArraySize, uint32_t* inputFmtCount);

NVENCSTATUS NVENCAPI NvEncGetEncodeCaps                     (void* encoder, GUID encodeGUID, NV_ENC_CAPS_PARAM* capsParam, int* capsVal);

NVENCSTATUS NVENCAPI NvEncGetEncodePresetCount              (void* encoder, GUID encodeGUID, uint32_t* encodePresetGUIDCount);

NVENCSTATUS NVENCAPI NvEncGetEncodePresetGUIDs                  (void* encoder, GUID encodeGUID, GUID* presetGUIDs, uint32_t guidArraySize, uint32_t* encodePresetGUIDCount);

NVENCSTATUS NVENCAPI NvEncGetEncodePresetConfig               (void* encoder, GUID encodeGUID, GUID  presetGUID, NV_ENC_PRESET_CONFIG* presetConfig);

NVENCSTATUS NVENCAPI NvEncGetEncodePresetConfigEx               (void* encoder, GUID encodeGUID, GUID  presetGUID, NV_ENC_TUNING_INFO tuningInfo, NV_ENC_PRESET_CONFIG* presetConfig);

NVENCSTATUS NVENCAPI NvEncInitializeEncoder                     (void* encoder, NV_ENC_INITIALIZE_PARAMS* createEncodeParams);

NVENCSTATUS NVENCAPI NvEncCreateInputBuffer                     (void* encoder, NV_ENC_CREATE_INPUT_BUFFER* createInputBufferParams);

NVENCSTATUS NVENCAPI NvEncDestroyInputBuffer                    (void* encoder, NV_ENC_INPUT_PTR inputBuffer);

NVENCSTATUS NVENCAPI NvEncSetIOCudaStreams                     (void* encoder, NV_ENC_CUSTREAM_PTR inputStream, NV_ENC_CUSTREAM_PTR outputStream);

NVENCSTATUS NVENCAPI NvEncCreateBitstreamBuffer                 (void* encoder, NV_ENC_CREATE_BITSTREAM_BUFFER* createBitstreamBufferParams);

NVENCSTATUS NVENCAPI NvEncDestroyBitstreamBuffer                (void* encoder, NV_ENC_OUTPUT_PTR bitstreamBuffer);

NVENCSTATUS NVENCAPI NvEncEncodePicture                         (void* encoder, NV_ENC_PIC_PARAMS* encodePicParams);

NVENCSTATUS NVENCAPI NvEncLockBitstream                         (void* encoder, NV_ENC_LOCK_BITSTREAM* lockBitstreamBufferParams);

NVENCSTATUS NVENCAPI NvEncUnlockBitstream                       (void* encoder, NV_ENC_OUTPUT_PTR bitstreamBuffer);

NVENCSTATUS NVENCAPI NvEncRestoreEncoderState                    (void* encoder, NV_ENC_RESTORE_ENCODER_STATE_PARAMS* restoreState);

NVENCSTATUS NVENCAPI NvEncLockInputBuffer                      (void* encoder, NV_ENC_LOCK_INPUT_BUFFER* lockInputBufferParams);

NVENCSTATUS NVENCAPI NvEncUnlockInputBuffer                     (void* encoder, NV_ENC_INPUT_PTR inputBuffer);

NVENCSTATUS NVENCAPI NvEncGetEncodeStats                        (void* encoder, NV_ENC_STAT* encodeStats);

NVENCSTATUS NVENCAPI NvEncGetSequenceParams                     (void* encoder, NV_ENC_SEQUENCE_PARAM_PAYLOAD* sequenceParamPayload);

NVENCSTATUS NVENCAPI NvEncGetSequenceParamEx                     (void* encoder, NV_ENC_INITIALIZE_PARAMS* encInitParams, NV_ENC_SEQUENCE_PARAM_PAYLOAD* sequenceParamPayload);

NVENCSTATUS NVENCAPI NvEncRegisterAsyncEvent                    (void* encoder, NV_ENC_EVENT_PARAMS* eventParams);

NVENCSTATUS NVENCAPI NvEncUnregisterAsyncEvent                  (void* encoder, NV_ENC_EVENT_PARAMS* eventParams);

NVENCSTATUS NVENCAPI NvEncMapInputResource                         (void* encoder, NV_ENC_MAP_INPUT_RESOURCE* mapInputResParams);

NVENCSTATUS NVENCAPI NvEncUnmapInputResource                         (void* encoder, NV_ENC_INPUT_PTR mappedInputBuffer);

NVENCSTATUS NVENCAPI NvEncDestroyEncoder                        (void* encoder);

NVENCSTATUS NVENCAPI NvEncInvalidateRefFrames(void* encoder, uint64_t invalidRefFrameTimeStamp);

NVENCSTATUS NVENCAPI NvEncOpenEncodeSessionEx                   (NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS *openSessionExParams, void** encoder);

NVENCSTATUS NVENCAPI NvEncRegisterResource                      (void* encoder, NV_ENC_REGISTER_RESOURCE* registerResParams);

NVENCSTATUS NVENCAPI NvEncUnregisterResource                    (void* encoder, NV_ENC_REGISTERED_PTR registeredResource);

NVENCSTATUS NVENCAPI NvEncReconfigureEncoder                   (void *encoder, NV_ENC_RECONFIGURE_PARAMS* reInitEncodeParams);

NVENCSTATUS NVENCAPI NvEncCreateMVBuffer                        (void* encoder, NV_ENC_CREATE_MV_BUFFER* createMVBufferParams);

NVENCSTATUS NVENCAPI NvEncDestroyMVBuffer                       (void* encoder, NV_ENC_OUTPUT_PTR mvBuffer);

NVENCSTATUS NVENCAPI NvEncRunMotionEstimationOnly               (void* encoder, NV_ENC_MEONLY_PARAMS* meOnlyParams);

NVENCSTATUS NVENCAPI NvEncodeAPIGetMaxSupportedVersion          (uint32_t* version);

const char * NVENCAPI NvEncGetLastErrorString          (void* encoder);

NVENCSTATUS NVENCAPI NvEncLookaheadPicture          (void* encoder, NV_ENC_LOOKAHEAD_PIC_PARAMS *lookaheadParamas);

typedef NVENCSTATUS (NVENCAPI* PNVENCOPENENCODESESSION)         (void* device, uint32_t deviceType, void** encoder);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETENCODEGUIDCOUNT)        (void* encoder, uint32_t* encodeGUIDCount);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETENCODEGUIDS)            (void* encoder, GUID* GUIDs, uint32_t guidArraySize, uint32_t* GUIDCount);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETENCODEPROFILEGUIDCOUNT) (void* encoder, GUID encodeGUID, uint32_t* encodeProfileGUIDCount);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETENCODEPROFILEGUIDS)     (void* encoder, GUID encodeGUID, GUID* profileGUIDs, uint32_t guidArraySize, uint32_t* GUIDCount);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETINPUTFORMATCOUNT)       (void* encoder, GUID encodeGUID, uint32_t* inputFmtCount);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETINPUTFORMATS)           (void* encoder, GUID encodeGUID, NV_ENC_BUFFER_FORMAT* inputFmts, uint32_t inputFmtArraySize, uint32_t* inputFmtCount);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETENCODECAPS)             (void* encoder, GUID encodeGUID, NV_ENC_CAPS_PARAM* capsParam, int* capsVal);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETENCODEPRESETCOUNT)      (void* encoder, GUID encodeGUID, uint32_t* encodePresetGUIDCount);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETENCODEPRESETGUIDS)      (void* encoder, GUID encodeGUID, GUID* presetGUIDs, uint32_t guidArraySize, uint32_t* encodePresetGUIDCount);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETENCODEPRESETCONFIG)     (void* encoder, GUID encodeGUID, GUID  presetGUID, NV_ENC_PRESET_CONFIG* presetConfig);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETENCODEPRESETCONFIGEX)   (void* encoder, GUID encodeGUID, GUID  presetGUID, NV_ENC_TUNING_INFO tuningInfo, NV_ENC_PRESET_CONFIG* presetConfig);
typedef NVENCSTATUS (NVENCAPI* PNVENCINITIALIZEENCODER)         (void* encoder, NV_ENC_INITIALIZE_PARAMS* createEncodeParams);
typedef NVENCSTATUS (NVENCAPI* PNVENCCREATEINPUTBUFFER)         (void* encoder, NV_ENC_CREATE_INPUT_BUFFER* createInputBufferParams);
typedef NVENCSTATUS (NVENCAPI* PNVENCDESTROYINPUTBUFFER)        (void* encoder, NV_ENC_INPUT_PTR inputBuffer);
typedef NVENCSTATUS (NVENCAPI* PNVENCCREATEBITSTREAMBUFFER)     (void* encoder, NV_ENC_CREATE_BITSTREAM_BUFFER* createBitstreamBufferParams);
typedef NVENCSTATUS (NVENCAPI* PNVENCDESTROYBITSTREAMBUFFER)    (void* encoder, NV_ENC_OUTPUT_PTR bitstreamBuffer);
typedef NVENCSTATUS (NVENCAPI* PNVENCENCODEPICTURE)             (void* encoder, NV_ENC_PIC_PARAMS* encodePicParams);
typedef NVENCSTATUS (NVENCAPI* PNVENCLOCKBITSTREAM)             (void* encoder, NV_ENC_LOCK_BITSTREAM* lockBitstreamBufferParams);
typedef NVENCSTATUS (NVENCAPI* PNVENCUNLOCKBITSTREAM)           (void* encoder, NV_ENC_OUTPUT_PTR bitstreamBuffer);
typedef NVENCSTATUS (NVENCAPI* PNVENCLOCKINPUTBUFFER)           (void* encoder, NV_ENC_LOCK_INPUT_BUFFER* lockInputBufferParams);
typedef NVENCSTATUS (NVENCAPI* PNVENCUNLOCKINPUTBUFFER)         (void* encoder, NV_ENC_INPUT_PTR inputBuffer);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETENCODESTATS)            (void* encoder, NV_ENC_STAT* encodeStats);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETSEQUENCEPARAMS)         (void* encoder, NV_ENC_SEQUENCE_PARAM_PAYLOAD* sequenceParamPayload);
typedef NVENCSTATUS (NVENCAPI* PNVENCREGISTERASYNCEVENT)        (void* encoder, NV_ENC_EVENT_PARAMS* eventParams);
typedef NVENCSTATUS (NVENCAPI* PNVENCUNREGISTERASYNCEVENT)      (void* encoder, NV_ENC_EVENT_PARAMS* eventParams);
typedef NVENCSTATUS (NVENCAPI* PNVENCMAPINPUTRESOURCE)          (void* encoder, NV_ENC_MAP_INPUT_RESOURCE* mapInputResParams);
typedef NVENCSTATUS (NVENCAPI* PNVENCUNMAPINPUTRESOURCE)        (void* encoder, NV_ENC_INPUT_PTR mappedInputBuffer);
typedef NVENCSTATUS (NVENCAPI* PNVENCDESTROYENCODER)            (void* encoder);
typedef NVENCSTATUS (NVENCAPI* PNVENCINVALIDATEREFFRAMES)       (void* encoder, uint64_t invalidRefFrameTimeStamp);
typedef NVENCSTATUS (NVENCAPI* PNVENCOPENENCODESESSIONEX)       (NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS *openSessionExParams, void** encoder);
typedef NVENCSTATUS (NVENCAPI* PNVENCREGISTERRESOURCE)          (void* encoder, NV_ENC_REGISTER_RESOURCE* registerResParams);
typedef NVENCSTATUS (NVENCAPI* PNVENCUNREGISTERRESOURCE)        (void* encoder, NV_ENC_REGISTERED_PTR registeredRes);
typedef NVENCSTATUS (NVENCAPI* PNVENCRECONFIGUREENCODER)        (void* encoder, NV_ENC_RECONFIGURE_PARAMS* reInitEncodeParams);

typedef NVENCSTATUS (NVENCAPI* PNVENCCREATEMVBUFFER)            (void* encoder, NV_ENC_CREATE_MV_BUFFER* createMVBufferParams);
typedef NVENCSTATUS (NVENCAPI* PNVENCDESTROYMVBUFFER)           (void* encoder, NV_ENC_OUTPUT_PTR mvBuffer);
typedef NVENCSTATUS (NVENCAPI* PNVENCRUNMOTIONESTIMATIONONLY)   (void* encoder, NV_ENC_MEONLY_PARAMS* meOnlyParams);
typedef const char * (NVENCAPI* PNVENCGETLASTERROR)             (void* encoder);
typedef NVENCSTATUS (NVENCAPI* PNVENCSETIOCUDASTREAMS)          (void* encoder, NV_ENC_CUSTREAM_PTR inputStream, NV_ENC_CUSTREAM_PTR outputStream);
typedef NVENCSTATUS (NVENCAPI* PNVENCGETSEQUENCEPARAMEX)        (void* encoder, NV_ENC_INITIALIZE_PARAMS* encInitParams, NV_ENC_SEQUENCE_PARAM_PAYLOAD* sequenceParamPayload);
typedef NVENCSTATUS (NVENCAPI* PNVENCRESTOREENCODERSTATE)       (void* encoder, NV_ENC_RESTORE_ENCODER_STATE_PARAMS* restoreState);
typedef NVENCSTATUS (NVENCAPI* PNVENCLOOKAHEADPICTURE)          (void* encoder, NV_ENC_LOOKAHEAD_PIC_PARAMS* lookaheadParams);

typedef struct _NV_ENCODE_API_FUNCTION_LIST
{
    uint32_t                        version;
    uint32_t                        reserved;
    PNVENCOPENENCODESESSION         nvEncOpenEncodeSession;
    PNVENCGETENCODEGUIDCOUNT        nvEncGetEncodeGUIDCount;
    PNVENCGETENCODEPRESETCOUNT      nvEncGetEncodeProfileGUIDCount;
    PNVENCGETENCODEPRESETGUIDS      nvEncGetEncodeProfileGUIDs;
    PNVENCGETENCODEGUIDS            nvEncGetEncodeGUIDs;
    PNVENCGETINPUTFORMATCOUNT       nvEncGetInputFormatCount;
    PNVENCGETINPUTFORMATS           nvEncGetInputFormats;
    PNVENCGETENCODECAPS             nvEncGetEncodeCaps;
    PNVENCGETENCODEPRESETCOUNT      nvEncGetEncodePresetCount;
    PNVENCGETENCODEPRESETGUIDS      nvEncGetEncodePresetGUIDs;
    PNVENCGETENCODEPRESETCONFIG     nvEncGetEncodePresetConfig;
    PNVENCINITIALIZEENCODER         nvEncInitializeEncoder;
    PNVENCCREATEINPUTBUFFER         nvEncCreateInputBuffer;
    PNVENCDESTROYINPUTBUFFER        nvEncDestroyInputBuffer;
    PNVENCCREATEBITSTREAMBUFFER     nvEncCreateBitstreamBuffer;
    PNVENCDESTROYBITSTREAMBUFFER    nvEncDestroyBitstreamBuffer;
    PNVENCENCODEPICTURE             nvEncEncodePicture;
    PNVENCLOCKBITSTREAM             nvEncLockBitstream;
    PNVENCUNLOCKBITSTREAM           nvEncUnlockBitstream;
    PNVENCLOCKINPUTBUFFER           nvEncLockInputBuffer;
    PNVENCUNLOCKINPUTBUFFER         nvEncUnlockInputBuffer;
    PNVENCGETENCODESTATS            nvEncGetEncodeStats;
    PNVENCGETSEQUENCEPARAMS         nvEncGetSequenceParams;
    PNVENCREGISTERASYNCEVENT        nvEncRegisterAsyncEvent;
    PNVENCUNREGISTERASYNCEVENT      nvEncUnregisterAsyncEvent;
    PNVENCMAPINPUTRESOURCE          nvEncMapInputResource;
    PNVENCUNMAPINPUTRESOURCE        nvEncUnmapInputResource;
    PNVENCDESTROYENCODER            nvEncDestroyEncoder;
    PNVENCINVALIDATEREFFRAMES       nvEncInvalidateRefFrames;
    PNVENCOPENENCODESESSIONEX       nvEncOpenEncodeSessionEx;
    PNVENCREGISTERRESOURCE          nvEncRegisterResource;
    PNVENCUNREGISTERRESOURCE        nvEncUnregisterResource;
    PNVENCRECONFIGUREENCODER        nvEncReconfigureEncoder;
    void*                           reserved1;
    PNVENCCREATEMVBUFFER            nvEncCreateMVBuffer;
    PNVENCDESTROYMVBUFFER           nvEncDestroyMVBuffer;
    PNVENCRUNMOTIONESTIMATIONONLY   nvEncRunMotionEstimationOnly;
    PNVENCGETLASTERROR              nvEncGetLastErrorString;
    PNVENCSETIOCUDASTREAMS          nvEncSetIOCudaStreams;
    PNVENCGETENCODEPRESETCONFIGEX   nvEncGetEncodePresetConfigEx;
    PNVENCGETSEQUENCEPARAMEX        nvEncGetSequenceParamEx;
    PNVENCRESTOREENCODERSTATE       nvEncRestoreEncoderState;
    PNVENCLOOKAHEADPICTURE          nvEncLookaheadPicture;
    void*                           reserved2[275];
} NV_ENCODE_API_FUNCTION_LIST;

#define NV_ENCODE_API_FUNCTION_LIST_VER NVENCAPI_STRUCT_VERSION(2)

NVENCSTATUS NVENCAPI NvEncodeAPICreateInstance(NV_ENCODE_API_FUNCTION_LIST *functionList);

#ifdef __cplusplus
}
#endif

#endif
