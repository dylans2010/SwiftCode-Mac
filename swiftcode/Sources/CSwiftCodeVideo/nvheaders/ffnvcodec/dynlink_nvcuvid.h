#if !defined(__NVCUVID_H__)
#define __NVCUVID_H__

#include "dynlink_cuviddec.h"

#if defined(__cplusplus)
extern "C" {
#endif

#define MAX_CLOCK_TS 3

typedef void *CUvideosource;
typedef void *CUvideoparser;
typedef long long CUvideotimestamp;

typedef enum {
    cudaVideoState_Error   = -1,
    cudaVideoState_Stopped = 0,
    cudaVideoState_Started = 1
} cudaVideoState;

typedef enum {
    cudaAudioCodec_MPEG1=0,
    cudaAudioCodec_MPEG2,
    cudaAudioCodec_MP3,
    cudaAudioCodec_AC3,
    cudaAudioCodec_LPCM,
    cudaAudioCodec_AAC,
} cudaAudioCodec;

typedef struct _TIMECODESET
{
    unsigned int time_offset_value;
    unsigned short n_frames;
    unsigned char clock_timestamp_flag;
    unsigned char units_field_based_flag;
    unsigned char counting_type;
    unsigned char full_timestamp_flag;
    unsigned char discontinuity_flag;
    unsigned char cnt_dropped_flag;
    unsigned char seconds_value;
    unsigned char minutes_value;
    unsigned char hours_value;
    unsigned char seconds_flag;
    unsigned char minutes_flag;
    unsigned char hours_flag;
    unsigned char time_offset_length;
    unsigned char reserved;
} TIMECODESET;

typedef struct _TIMECODE
{
    TIMECODESET time_code_set[MAX_CLOCK_TS];
    unsigned char num_clock_ts;
} TIMECODE;

typedef struct _SEIMASTERINGDISPLAYINFO
{
    unsigned short display_primaries_x[3];
    unsigned short display_primaries_y[3];
    unsigned short white_point_x;
    unsigned short white_point_y;
    unsigned int max_display_mastering_luminance;
    unsigned int min_display_mastering_luminance;
} SEIMASTERINGDISPLAYINFO;

typedef struct _SEICONTENTLIGHTLEVELINFO
{
    unsigned short max_content_light_level;
    unsigned short max_pic_average_light_level;
    unsigned int reserved;
} SEICONTENTLIGHTLEVELINFO;

typedef struct _TIMECODEMPEG2
{
    unsigned char drop_frame_flag;
    unsigned char time_code_hours;
    unsigned char time_code_minutes;
    unsigned char marker_bit;
    unsigned char time_code_seconds;
    unsigned char time_code_pictures;
} TIMECODEMPEG2;

typedef struct _SEIALTERNATIVETRANSFERCHARACTERISTICS
{
    unsigned char preferred_transfer_characteristics;
} SEIALTERNATIVETRANSFERCHARACTERISTICS;

typedef struct _CUSEIMESSAGE
{
    unsigned char sei_message_type;
    unsigned char reserved[3];
    unsigned int sei_message_size;
} CUSEIMESSAGE;

typedef struct
{
    cudaVideoCodec codec;
    struct {
        unsigned int numerator;
        unsigned int denominator;
    } frame_rate;
    unsigned char progressive_sequence;
    unsigned char bit_depth_luma_minus8;
    unsigned char bit_depth_chroma_minus8;
    unsigned char min_num_decode_surfaces;
    unsigned int coded_width;
    unsigned int coded_height;
    struct {
        int left;
        int top;
        int right;
        int bottom;
    } display_area;
    cudaVideoChromaFormat chroma_format;
    unsigned int bitrate;
    struct {
        int x;
        int y;
    } display_aspect_ratio;
    struct {
        unsigned char video_format          : 3;
        unsigned char video_full_range_flag : 1;
        unsigned char reserved_zero_bits    : 4;
        unsigned char color_primaries;
        unsigned char transfer_characteristics;
        unsigned char matrix_coefficients;
    } video_signal_description;
    unsigned int seqhdr_data_length;
} CUVIDEOFORMAT;

typedef struct
{
    cudaVideoCodec codec;
    union
    {
        struct
        {
            unsigned char  operating_points_cnt;
            unsigned char  reserved24_bits[3];
            unsigned short operating_points_idc[32];
        } av1;
        unsigned char CodecReserved[1024];
    };
} CUVIDOPERATINGPOINTINFO;

typedef struct _CUVIDSEIMESSAGEINFO
{
    void *pSEIData;
    CUSEIMESSAGE *pSEIMessage;
    unsigned int sei_message_count;
    unsigned int picIdx;
} CUVIDSEIMESSAGEINFO;

typedef struct {
    unsigned int max_width;
    unsigned int max_height;
    unsigned char reserved[1016];
} CUVIDAV1SEQHDR;

typedef struct
{
    CUVIDEOFORMAT format;
    union {
        CUVIDAV1SEQHDR av1;
        unsigned char raw_seqhdr_data[1024];
    };
} CUVIDEOFORMATEX;

typedef struct
{
    cudaAudioCodec codec;
    unsigned int channels;
    unsigned int samplespersec;
    unsigned int bitrate;
    unsigned int reserved1;
    unsigned int reserved2;
} CUAUDIOFORMAT;

typedef enum {
    CUVID_PKT_ENDOFSTREAM   = 0x01,
    CUVID_PKT_TIMESTAMP     = 0x02,
    CUVID_PKT_DISCONTINUITY = 0x04,
    CUVID_PKT_ENDOFPICTURE  = 0x08,
    CUVID_PKT_NOTIFY_EOS    = 0x10,
} CUvideopacketflags;

typedef struct _CUVIDSOURCEDATAPACKET
{
    tcu_ulong flags;
    tcu_ulong payload_size;
    const unsigned char *payload;
    CUvideotimestamp timestamp;
} CUVIDSOURCEDATAPACKET;

typedef int (CUDAAPI *PFNVIDSOURCECALLBACK)(void *, CUVIDSOURCEDATAPACKET *);

typedef struct _CUVIDSOURCEPARAMS
{
    unsigned int ulClockRate;
    unsigned int bAnnexb : 1;
    unsigned int uReserved : 31;
    unsigned int uReserved1[6];
    void *pUserData;
    PFNVIDSOURCECALLBACK pfnVideoDataHandler;
    PFNVIDSOURCECALLBACK pfnAudioDataHandler;
    void *pvReserved2[8];
} CUVIDSOURCEPARAMS;

typedef enum {
    CUVID_FMT_EXTFORMATINFO = 0x100
} CUvideosourceformat_flags;

#if !defined(__APPLE__)
typedef CUresult CUDAAPI tcuvidCreateVideoSource(CUvideosource *pObj, const char *pszFileName, CUVIDSOURCEPARAMS *pParams);

typedef CUresult CUDAAPI tcuvidCreateVideoSourceW(CUvideosource *pObj, const wchar_t *pwszFileName, CUVIDSOURCEPARAMS *pParams);

typedef CUresult CUDAAPI tcuvidDestroyVideoSource(CUvideosource obj);

typedef CUresult CUDAAPI tcuvidSetVideoSourceState(CUvideosource obj, cudaVideoState state);

typedef cudaVideoState CUDAAPI tcuvidGetVideoSourceState(CUvideosource obj);

typedef CUresult CUDAAPI tcuvidGetSourceVideoFormat(CUvideosource obj, CUVIDEOFORMAT *pvidfmt, unsigned int flags);

typedef CUresult CUDAAPI tcuvidGetSourceAudioFormat(CUvideosource obj, CUAUDIOFORMAT *paudfmt, unsigned int flags);

#endif
typedef struct _CUVIDPARSERDISPINFO
{
    int picture_index;
    int progressive_frame;
    int top_field_first;
    int repeat_first_field;
    CUvideotimestamp timestamp;
} CUVIDPARSERDISPINFO;

typedef int (CUDAAPI *PFNVIDSEQUENCECALLBACK)(void *, CUVIDEOFORMAT *);
typedef int (CUDAAPI *PFNVIDDECODECALLBACK)(void *, CUVIDPICPARAMS *);
typedef int (CUDAAPI *PFNVIDDISPLAYCALLBACK)(void *, CUVIDPARSERDISPINFO *);
typedef int (CUDAAPI *PFNVIDOPPOINTCALLBACK)(void *, CUVIDOPERATINGPOINTINFO*);
typedef int (CUDAAPI *PFNVIDSEIMSGCALLBACK) (void *, CUVIDSEIMESSAGEINFO *);

typedef struct _CUVIDPARSERPARAMS
{
    cudaVideoCodec CodecType;
    unsigned int ulMaxNumDecodeSurfaces;
    unsigned int ulClockRate;
    unsigned int ulErrorThreshold;
    unsigned int ulMaxDisplayDelay;
    unsigned int bAnnexb : 1;
    unsigned int uReserved : 31;
    unsigned int uReserved1[4];
    void *pUserData;
    PFNVIDSEQUENCECALLBACK pfnSequenceCallback;
    PFNVIDDECODECALLBACK pfnDecodePicture;
    PFNVIDDISPLAYCALLBACK pfnDisplayPicture;
    PFNVIDOPPOINTCALLBACK pfnGetOperatingPoint;
    PFNVIDSEIMSGCALLBACK pfnGetSEIMsg;
    void *pvReserved2[5];
    CUVIDEOFORMATEX *pExtVideoInfo;
} CUVIDPARSERPARAMS;

typedef CUresult CUDAAPI tcuvidCreateVideoParser(CUvideoparser *pObj, CUVIDPARSERPARAMS *pParams);

typedef CUresult CUDAAPI tcuvidParseVideoData(CUvideoparser obj, CUVIDSOURCEDATAPACKET *pPacket);

typedef CUresult CUDAAPI tcuvidDestroyVideoParser(CUvideoparser obj);

#if defined(__cplusplus)
}
#endif

#endif
