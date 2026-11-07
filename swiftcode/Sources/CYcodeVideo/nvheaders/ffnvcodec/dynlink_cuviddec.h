#if !defined(__CUDA_VIDEO_H__)
#define __CUDA_VIDEO_H__

#if defined(_WIN64) || defined(__LP64__) || defined(__x86_64) || defined(AMD64) || defined(_M_AMD64)
#if (CUDA_VERSION >= 3020) && (!defined(CUDA_FORCE_API_VERSION) || (CUDA_FORCE_API_VERSION >= 3020))
#define __CUVID_DEVPTR64
#endif
#endif

#define NVDECAPI_MAJOR_VERSION 12
#define NVDECAPI_MINOR_VERSION 2

#define NVDECAPI_VERSION (NVDECAPI_MAJOR_VERSION | (NVDECAPI_MINOR_VERSION << 24))

#if defined(__cplusplus)
extern "C" {
#endif

#if defined(__CYGWIN__)
typedef unsigned int tcu_ulong;
#else
typedef unsigned long tcu_ulong;
#endif

typedef void *CUvideodecoder;
typedef struct _CUcontextlock_st *CUvideoctxlock;

typedef enum cudaVideoCodec_enum {
    cudaVideoCodec_MPEG1=0,
    cudaVideoCodec_MPEG2,
    cudaVideoCodec_MPEG4,
    cudaVideoCodec_VC1,
    cudaVideoCodec_H264,
    cudaVideoCodec_JPEG,
    cudaVideoCodec_H264_SVC,
    cudaVideoCodec_H264_MVC,
    cudaVideoCodec_HEVC,
    cudaVideoCodec_VP8,
    cudaVideoCodec_VP9,
    cudaVideoCodec_AV1,
    cudaVideoCodec_NumCodecs,
    cudaVideoCodec_YUV420 = (('I'<<24)|('Y'<<16)|('U'<<8)|('V')),
    cudaVideoCodec_YV12   = (('Y'<<24)|('V'<<16)|('1'<<8)|('2')),
    cudaVideoCodec_NV12   = (('N'<<24)|('V'<<16)|('1'<<8)|('2')),
    cudaVideoCodec_YUYV   = (('Y'<<24)|('U'<<16)|('Y'<<8)|('V')),
    cudaVideoCodec_UYVY   = (('U'<<24)|('Y'<<16)|('V'<<8)|('Y'))
} cudaVideoCodec;

typedef enum cudaVideoSurfaceFormat_enum {
    cudaVideoSurfaceFormat_NV12=0,
    cudaVideoSurfaceFormat_P016=1,
    cudaVideoSurfaceFormat_YUV444=2,
    cudaVideoSurfaceFormat_YUV444_16Bit=3,
} cudaVideoSurfaceFormat;

typedef enum cudaVideoDeinterlaceMode_enum {
    cudaVideoDeinterlaceMode_Weave=0,
    cudaVideoDeinterlaceMode_Bob,
    cudaVideoDeinterlaceMode_Adaptive
} cudaVideoDeinterlaceMode;

typedef enum cudaVideoChromaFormat_enum {
    cudaVideoChromaFormat_Monochrome=0,
    cudaVideoChromaFormat_420,
    cudaVideoChromaFormat_422,
    cudaVideoChromaFormat_444
} cudaVideoChromaFormat;

typedef enum cudaVideoCreateFlags_enum {
    cudaVideoCreate_Default     = 0x00,
    cudaVideoCreate_PreferCUDA  = 0x01,
    cudaVideoCreate_PreferDXVA  = 0x02,
    cudaVideoCreate_PreferCUVID = 0x04
} cudaVideoCreateFlags;

typedef enum cuvidDecodeStatus_enum
{
    cuvidDecodeStatus_Invalid         = 0,
    cuvidDecodeStatus_InProgress      = 1,
    cuvidDecodeStatus_Success         = 2,
    cuvidDecodeStatus_Error           = 8,
    cuvidDecodeStatus_Error_Concealed = 9,
} cuvidDecodeStatus;

typedef struct _CUVIDDECODECAPS
{
    cudaVideoCodec          eCodecType;
    cudaVideoChromaFormat   eChromaFormat;
    unsigned int            nBitDepthMinus8;
    unsigned int            reserved1[3];

    unsigned char           bIsSupported;
    unsigned char           nNumNVDECs;
    unsigned short          nOutputFormatMask;
    unsigned int            nMaxWidth;
    unsigned int            nMaxHeight;
    unsigned int            nMaxMBCount;
    unsigned short          nMinWidth;
    unsigned short          nMinHeight;
    unsigned char           bIsHistogramSupported;
    unsigned char           nCounterBitDepth;
    unsigned short          nMaxHistogramBins;
    unsigned int            reserved3[10];
} CUVIDDECODECAPS;

typedef struct _CUVIDDECODECREATEINFO
{
    tcu_ulong ulWidth;
    tcu_ulong ulHeight;
    tcu_ulong ulNumDecodeSurfaces;
    cudaVideoCodec CodecType;
    cudaVideoChromaFormat ChromaFormat;
    tcu_ulong ulCreationFlags;
    tcu_ulong bitDepthMinus8;
    tcu_ulong ulIntraDecodeOnly;
    tcu_ulong ulMaxWidth;
    tcu_ulong ulMaxHeight;
    tcu_ulong Reserved1;
    struct {
        short left;
        short top;
        short right;
        short bottom;
    } display_area;

    cudaVideoSurfaceFormat OutputFormat;
    cudaVideoDeinterlaceMode DeinterlaceMode;
    tcu_ulong ulTargetWidth;
    tcu_ulong ulTargetHeight;
    tcu_ulong ulNumOutputSurfaces;
    CUvideoctxlock vidLock;
    struct {
        short left;
        short top;
        short right;
        short bottom;
    } target_rect;

    tcu_ulong enableHistogram;
    tcu_ulong Reserved2[4];
} CUVIDDECODECREATEINFO;

typedef struct _CUVIDH264DPBENTRY
{
    int PicIdx;
    int FrameIdx;
    int is_long_term;
    int not_existing;
    int used_for_reference;
    int FieldOrderCnt[2];
} CUVIDH264DPBENTRY;

typedef struct _CUVIDH264MVCEXT
{
    int num_views_minus1;
    int view_id;
    unsigned char inter_view_flag;
    unsigned char num_inter_view_refs_l0;
    unsigned char num_inter_view_refs_l1;
    unsigned char MVCReserved8Bits;
    int InterViewRefsL0[16];
    int InterViewRefsL1[16];
} CUVIDH264MVCEXT;

typedef struct _CUVIDH264SVCEXT
{
    unsigned char profile_idc;
    unsigned char level_idc;
    unsigned char DQId;
    unsigned char DQIdMax;
    unsigned char disable_inter_layer_deblocking_filter_idc;
    unsigned char ref_layer_chroma_phase_y_plus1;
    signed char   inter_layer_slice_alpha_c0_offset_div2;
    signed char   inter_layer_slice_beta_offset_div2;

    unsigned short DPBEntryValidFlag;
    unsigned char inter_layer_deblocking_filter_control_present_flag;
    unsigned char extended_spatial_scalability_idc;
    unsigned char adaptive_tcoeff_level_prediction_flag;
    unsigned char slice_header_restriction_flag;
    unsigned char chroma_phase_x_plus1_flag;
    unsigned char chroma_phase_y_plus1;

    unsigned char tcoeff_level_prediction_flag;
    unsigned char constrained_intra_resampling_flag;
    unsigned char ref_layer_chroma_phase_x_plus1_flag;
    unsigned char store_ref_base_pic_flag;
    unsigned char Reserved8BitsA;
    unsigned char Reserved8BitsB;

    short scaled_ref_layer_left_offset;
    short scaled_ref_layer_top_offset;
    short scaled_ref_layer_right_offset;
    short scaled_ref_layer_bottom_offset;
    unsigned short Reserved16Bits;
    struct _CUVIDPICPARAMS *pNextLayer;
    int bRefBaseLayer;
} CUVIDH264SVCEXT;

typedef struct _CUVIDH264PICPARAMS
{
    int log2_max_frame_num_minus4;
    int pic_order_cnt_type;
    int log2_max_pic_order_cnt_lsb_minus4;
    int delta_pic_order_always_zero_flag;
    int frame_mbs_only_flag;
    int direct_8x8_inference_flag;
    int num_ref_frames;
    unsigned char residual_colour_transform_flag;
    unsigned char bit_depth_luma_minus8;
    unsigned char bit_depth_chroma_minus8;
    unsigned char qpprime_y_zero_transform_bypass_flag;
    int entropy_coding_mode_flag;
    int pic_order_present_flag;
    int num_ref_idx_l0_active_minus1;
    int num_ref_idx_l1_active_minus1;
    int weighted_pred_flag;
    int weighted_bipred_idc;
    int pic_init_qp_minus26;
    int deblocking_filter_control_present_flag;
    int redundant_pic_cnt_present_flag;
    int transform_8x8_mode_flag;
    int MbaffFrameFlag;
    int constrained_intra_pred_flag;
    int chroma_qp_index_offset;
    int second_chroma_qp_index_offset;
    int ref_pic_flag;
    int frame_num;
    int CurrFieldOrderCnt[2];
    CUVIDH264DPBENTRY dpb[16];
    unsigned char WeightScale4x4[6][16];
    unsigned char WeightScale8x8[2][64];
    unsigned char fmo_aso_enable;
    unsigned char num_slice_groups_minus1;
    unsigned char slice_group_map_type;
    signed char pic_init_qs_minus26;
    unsigned int slice_group_change_rate_minus1;
    union
    {
        unsigned long long slice_group_map_addr;
        const unsigned char *pMb2SliceGroupMap;
    } fmo;
    unsigned int Reserved[12];
    union
    {
        CUVIDH264MVCEXT mvcext;
        CUVIDH264SVCEXT svcext;
    };
} CUVIDH264PICPARAMS;

typedef struct _CUVIDMPEG2PICPARAMS
{
    int ForwardRefIdx;
    int BackwardRefIdx;
    int picture_coding_type;
    int full_pel_forward_vector;
    int full_pel_backward_vector;
    int f_code[2][2];
    int intra_dc_precision;
    int frame_pred_frame_dct;
    int concealment_motion_vectors;
    int q_scale_type;
    int intra_vlc_format;
    int alternate_scan;
    int top_field_first;
    unsigned char QuantMatrixIntra[64];
    unsigned char QuantMatrixInter[64];
} CUVIDMPEG2PICPARAMS;

#define I_VOP 0
#define P_VOP 1
#define B_VOP 2
#define S_VOP 3

typedef struct _CUVIDMPEG4PICPARAMS
{
    int ForwardRefIdx;
    int BackwardRefIdx;
    int video_object_layer_width;
    int video_object_layer_height;
    int vop_time_increment_bitcount;
    int top_field_first;
    int resync_marker_disable;
    int quant_type;
    int quarter_sample;
    int short_video_header;
    int divx_flags;
    int vop_coding_type;
    int vop_coded;
    int vop_rounding_type;
    int alternate_vertical_scan_flag;
    int interlaced;
    int vop_fcode_forward;
    int vop_fcode_backward;
    int trd[2];
    int trb[2];
    unsigned char QuantMatrixIntra[64];
    unsigned char QuantMatrixInter[64];
    int gmc_enabled;
} CUVIDMPEG4PICPARAMS;

typedef struct _CUVIDVC1PICPARAMS
{
    int ForwardRefIdx;
    int BackwardRefIdx;
    int FrameWidth;
    int FrameHeight;
    int intra_pic_flag;
    int ref_pic_flag;
    int progressive_fcm;
    int profile;
    int postprocflag;
    int pulldown;
    int interlace;
    int tfcntrflag;
    int finterpflag;
    int psf;
    int multires;
    int syncmarker;
    int rangered;
    int maxbframes;
    int panscan_flag;
    int refdist_flag;
    int extended_mv;
    int dquant;
    int vstransform;
    int loopfilter;
    int fastuvmc;
    int overlap;
    int quantizer;
    int extended_dmv;
    int range_mapy_flag;
    int range_mapy;
    int range_mapuv_flag;
    int range_mapuv;
    int rangeredfrm;
} CUVIDVC1PICPARAMS;

typedef struct _CUVIDJPEGPICPARAMS
{
    int Reserved;
} CUVIDJPEGPICPARAMS;

typedef struct _CUVIDHEVCPICPARAMS
{
    int pic_width_in_luma_samples;
    int pic_height_in_luma_samples;
    unsigned char log2_min_luma_coding_block_size_minus3;
    unsigned char log2_diff_max_min_luma_coding_block_size;
    unsigned char log2_min_transform_block_size_minus2;
    unsigned char log2_diff_max_min_transform_block_size;
    unsigned char pcm_enabled_flag;
    unsigned char log2_min_pcm_luma_coding_block_size_minus3;
    unsigned char log2_diff_max_min_pcm_luma_coding_block_size;
    unsigned char pcm_sample_bit_depth_luma_minus1;

    unsigned char pcm_sample_bit_depth_chroma_minus1;
    unsigned char pcm_loop_filter_disabled_flag;
    unsigned char strong_intra_smoothing_enabled_flag;
    unsigned char max_transform_hierarchy_depth_intra;
    unsigned char max_transform_hierarchy_depth_inter;
    unsigned char amp_enabled_flag;
    unsigned char separate_colour_plane_flag;
    unsigned char log2_max_pic_order_cnt_lsb_minus4;

    unsigned char num_short_term_ref_pic_sets;
    unsigned char long_term_ref_pics_present_flag;
    unsigned char num_long_term_ref_pics_sps;
    unsigned char sps_temporal_mvp_enabled_flag;
    unsigned char sample_adaptive_offset_enabled_flag;
    unsigned char scaling_list_enable_flag;
    unsigned char IrapPicFlag;
    unsigned char IdrPicFlag;

    unsigned char bit_depth_luma_minus8;
    unsigned char bit_depth_chroma_minus8;
    unsigned char log2_max_transform_skip_block_size_minus2;
    unsigned char log2_sao_offset_scale_luma;
    unsigned char log2_sao_offset_scale_chroma;
    unsigned char high_precision_offsets_enabled_flag;
    unsigned char reserved1[10];

    unsigned char dependent_slice_segments_enabled_flag;
    unsigned char slice_segment_header_extension_present_flag;
    unsigned char sign_data_hiding_enabled_flag;
    unsigned char cu_qp_delta_enabled_flag;
    unsigned char diff_cu_qp_delta_depth;
    signed char init_qp_minus26;
    signed char pps_cb_qp_offset;
    signed char pps_cr_qp_offset;

    unsigned char constrained_intra_pred_flag;
    unsigned char weighted_pred_flag;
    unsigned char weighted_bipred_flag;
    unsigned char transform_skip_enabled_flag;
    unsigned char transquant_bypass_enabled_flag;
    unsigned char entropy_coding_sync_enabled_flag;
    unsigned char log2_parallel_merge_level_minus2;
    unsigned char num_extra_slice_header_bits;

    unsigned char loop_filter_across_tiles_enabled_flag;
    unsigned char loop_filter_across_slices_enabled_flag;
    unsigned char output_flag_present_flag;
    unsigned char num_ref_idx_l0_default_active_minus1;
    unsigned char num_ref_idx_l1_default_active_minus1;
    unsigned char lists_modification_present_flag;
    unsigned char cabac_init_present_flag;
    unsigned char pps_slice_chroma_qp_offsets_present_flag;

    unsigned char deblocking_filter_override_enabled_flag;
    unsigned char pps_deblocking_filter_disabled_flag;
    signed char   pps_beta_offset_div2;
    signed char   pps_tc_offset_div2;
    unsigned char tiles_enabled_flag;
    unsigned char uniform_spacing_flag;
    unsigned char num_tile_columns_minus1;
    unsigned char num_tile_rows_minus1;

    unsigned short column_width_minus1[21];
    unsigned short row_height_minus1[21];

    unsigned char sps_range_extension_flag;
    unsigned char transform_skip_rotation_enabled_flag;
    unsigned char transform_skip_context_enabled_flag;
    unsigned char implicit_rdpcm_enabled_flag;

    unsigned char explicit_rdpcm_enabled_flag;
    unsigned char extended_precision_processing_flag;
    unsigned char intra_smoothing_disabled_flag;
    unsigned char persistent_rice_adaptation_enabled_flag;

    unsigned char cabac_bypass_alignment_enabled_flag;
    unsigned char pps_range_extension_flag;
    unsigned char cross_component_prediction_enabled_flag;
    unsigned char chroma_qp_offset_list_enabled_flag;

    unsigned char diff_cu_chroma_qp_offset_depth;
    unsigned char chroma_qp_offset_list_len_minus1;
    signed char cb_qp_offset_list[6];

    signed char cr_qp_offset_list[6];
    unsigned char reserved2[2];

    unsigned int   reserved3[8];

    int NumBitsForShortTermRPSInSlice;
    int NumDeltaPocsOfRefRpsIdx;
    int NumPocTotalCurr;
    int NumPocStCurrBefore;
    int NumPocStCurrAfter;
    int NumPocLtCurr;
    int CurrPicOrderCntVal;
    int RefPicIdx[16];
    int PicOrderCntVal[16];
    unsigned char IsLongTerm[16];
    unsigned char RefPicSetStCurrBefore[8];
    unsigned char RefPicSetStCurrAfter[8];
    unsigned char RefPicSetLtCurr[8];
    unsigned char RefPicSetInterLayer0[8];
    unsigned char RefPicSetInterLayer1[8];
    unsigned int  reserved4[12];

    unsigned char ScalingList4x4[6][16];
    unsigned char ScalingList8x8[6][64];
    unsigned char ScalingList16x16[6][64];
    unsigned char ScalingList32x32[2][64];
    unsigned char ScalingListDCCoeff16x16[6];
    unsigned char ScalingListDCCoeff32x32[2];
} CUVIDHEVCPICPARAMS;

typedef struct _CUVIDVP8PICPARAMS
{
    int width;
    int height;
    unsigned int first_partition_size;
    unsigned char LastRefIdx;
    unsigned char GoldenRefIdx;
    unsigned char AltRefIdx;
    union {
        struct {
            unsigned char frame_type : 1;
            unsigned char version : 3;
            unsigned char show_frame : 1;
            unsigned char update_mb_segmentation_data : 1;
            unsigned char Reserved2Bits : 2;
        }vp8_frame_tag;
        unsigned char wFrameTagFlags;
    };
    unsigned char Reserved1[4];
    unsigned int  Reserved2[3];
} CUVIDVP8PICPARAMS;

typedef struct _CUVIDVP9PICPARAMS
{
    unsigned int width;
    unsigned int height;

    unsigned char LastRefIdx;
    unsigned char GoldenRefIdx;
    unsigned char AltRefIdx;
    unsigned char colorSpace;

    unsigned short profile : 3;
    unsigned short frameContextIdx : 2;
    unsigned short frameType : 1;
    unsigned short showFrame : 1;
    unsigned short errorResilient : 1;
    unsigned short frameParallelDecoding : 1;
    unsigned short subSamplingX : 1;
    unsigned short subSamplingY : 1;
    unsigned short intraOnly : 1;
    unsigned short allow_high_precision_mv : 1;
    unsigned short refreshEntropyProbs : 1;
    unsigned short reserved2Bits : 2;

    unsigned short reserved16Bits;

    unsigned char  refFrameSignBias[4];

    unsigned char bitDepthMinus8Luma;
    unsigned char bitDepthMinus8Chroma;
    unsigned char loopFilterLevel;
    unsigned char loopFilterSharpness;

    unsigned char modeRefLfEnabled;
    unsigned char log2_tile_columns;
    unsigned char log2_tile_rows;

    unsigned char segmentEnabled : 1;
    unsigned char segmentMapUpdate : 1;
    unsigned char segmentMapTemporalUpdate : 1;
    unsigned char segmentFeatureMode : 1;
    unsigned char reserved4Bits : 4;

    unsigned char segmentFeatureEnable[8][4];
    short         segmentFeatureData[8][4];
    unsigned char mb_segment_tree_probs[7];
    unsigned char segment_pred_probs[3];
    unsigned char reservedSegment16Bits[2];

    int qpYAc;
    int qpYDc;
    int qpChDc;
    int qpChAc;

    unsigned int activeRefIdx[3];
    unsigned int resetFrameContext;
    unsigned int mcomp_filter_type;
    unsigned int mbRefLfDelta[4];
    unsigned int mbModeLfDelta[2];
    unsigned int frameTagSize;
    unsigned int offsetToDctParts;
    unsigned int reserved128Bits[4];

} CUVIDVP9PICPARAMS;

typedef struct _CUVIDAV1PICPARAMS
{
    unsigned int   width;
    unsigned int   height;
    unsigned int   frame_offset;
    int            decodePicIdx;

    unsigned int   profile : 3;
    unsigned int   use_128x128_superblock : 1;
    unsigned int   subsampling_x : 1;
    unsigned int   subsampling_y : 1;
    unsigned int   mono_chrome : 1;
    unsigned int   bit_depth_minus8 : 4;
    unsigned int   enable_filter_intra : 1;
    unsigned int   enable_intra_edge_filter : 1;
    unsigned int   enable_interintra_compound : 1;
    unsigned int   enable_masked_compound : 1;
    unsigned int   enable_dual_filter : 1;
    unsigned int   enable_order_hint : 1;
    unsigned int   order_hint_bits_minus1 : 3;
    unsigned int   enable_jnt_comp : 1;
    unsigned int   enable_superres : 1;
    unsigned int   enable_cdef : 1;
    unsigned int   enable_restoration : 1;
    unsigned int   enable_fgs : 1;
    unsigned int   reserved0_7bits : 7;

    unsigned int   frame_type : 2 ;
    unsigned int   show_frame : 1 ;
    unsigned int   disable_cdf_update : 1;
    unsigned int   allow_screen_content_tools : 1;
    unsigned int   force_integer_mv : 1;
    unsigned int   coded_denom : 3;
    unsigned int   allow_intrabc : 1;
    unsigned int   allow_high_precision_mv : 1;
    unsigned int   interp_filter : 3;
    unsigned int   switchable_motion_mode : 1;
    unsigned int   use_ref_frame_mvs : 1;
    unsigned int   disable_frame_end_update_cdf : 1;
    unsigned int   delta_q_present : 1;
    unsigned int   delta_q_res : 2;
    unsigned int   using_qmatrix : 1;
    unsigned int   coded_lossless : 1;
    unsigned int   use_superres : 1;
    unsigned int   tx_mode : 2;
    unsigned int   reference_mode : 1;
    unsigned int   allow_warped_motion : 1;
    unsigned int   reduced_tx_set : 1;
    unsigned int   skip_mode : 1;
    unsigned int   reserved1_3bits : 3;

    unsigned int   num_tile_cols : 8;
    unsigned int   num_tile_rows : 8;
    unsigned int   context_update_tile_id : 16;
    unsigned short tile_widths[64];
    unsigned short tile_heights[64];

    unsigned char  cdef_damping_minus_3 : 2;
    unsigned char  cdef_bits : 2;
    unsigned char  reserved2_4bits : 4;
    unsigned char  cdef_y_strength[8];
    unsigned char  cdef_uv_strength[8];

    unsigned char   SkipModeFrame0 : 4;
    unsigned char   SkipModeFrame1 : 4;

    unsigned char  base_qindex;
    char           qp_y_dc_delta_q;
    char           qp_u_dc_delta_q;
    char           qp_v_dc_delta_q;
    char           qp_u_ac_delta_q;
    char           qp_v_ac_delta_q;
    unsigned char  qm_y;
    unsigned char  qm_u;
    unsigned char  qm_v;

    unsigned char segmentation_enabled : 1;
    unsigned char segmentation_update_map : 1;
    unsigned char segmentation_update_data : 1;
    unsigned char segmentation_temporal_update : 1;
    unsigned char reserved3_4bits : 4;
    short         segmentation_feature_data[8][8];
    unsigned char segmentation_feature_mask[8];

    unsigned char  loop_filter_level[2];
    unsigned char  loop_filter_level_u;
    unsigned char  loop_filter_level_v;
    unsigned char  loop_filter_sharpness;
    char           loop_filter_ref_deltas[8];
    char           loop_filter_mode_deltas[2];
    unsigned char  loop_filter_delta_enabled : 1;
    unsigned char  loop_filter_delta_update : 1;
    unsigned char  delta_lf_present : 1;
    unsigned char  delta_lf_res : 2;
    unsigned char  delta_lf_multi  : 1;
    unsigned char  reserved4_2bits : 2;

    unsigned char lr_unit_size[3];
    unsigned char lr_type[3] ;

    unsigned char primary_ref_frame;
    unsigned char ref_frame_map[8];

    unsigned char temporal_layer_id : 4;
    unsigned char spatial_layer_id : 4;

    unsigned char reserved5_32bits[4];

    struct
    {
        unsigned int   width;
        unsigned int   height;
        unsigned char  index;
        unsigned char  reserved24Bits[3];
    } ref_frame[7];

    struct {
        unsigned char invalid : 1;
        unsigned char wmtype : 2;
        unsigned char reserved5Bits : 5;
        char          reserved24Bits[3];
        int           wmmat[6];
    } global_motion[7];

    unsigned short apply_grain : 1;
    unsigned short overlap_flag : 1;
    unsigned short scaling_shift_minus8 : 2;
    unsigned short chroma_scaling_from_luma : 1;
    unsigned short ar_coeff_lag : 2;
    unsigned short ar_coeff_shift_minus6 : 2;
    unsigned short grain_scale_shift : 2;
    unsigned short clip_to_restricted_range : 1;
    unsigned short reserved6_4bits : 4;
    unsigned char  num_y_points;
    unsigned char  scaling_points_y[14][2];
    unsigned char  num_cb_points;
    unsigned char  scaling_points_cb[10][2];
    unsigned char  num_cr_points;
    unsigned char  scaling_points_cr[10][2];
    unsigned char  reserved7_8bits;
    unsigned short random_seed;
    short          ar_coeffs_y[24];
    short          ar_coeffs_cb[25];
    short          ar_coeffs_cr[25];
    unsigned char  cb_mult;
    unsigned char  cb_luma_mult;
    short          cb_offset;
    unsigned char  cr_mult;
    unsigned char  cr_luma_mult;
    short          cr_offset;

    int            reserved[7];
} CUVIDAV1PICPARAMS;

typedef struct _CUVIDPICPARAMS
{
    int PicWidthInMbs;
    int FrameHeightInMbs;
    int CurrPicIdx;
    int field_pic_flag;
    int bottom_field_flag;
    int second_field;
    unsigned int nBitstreamDataLen;
    const unsigned char *pBitstreamData;
    unsigned int nNumSlices;
    const unsigned int *pSliceDataOffsets;
    int ref_pic_flag;
    int intra_pic_flag;
    unsigned int Reserved[30];
    union {
        CUVIDMPEG2PICPARAMS mpeg2;
        CUVIDH264PICPARAMS  h264;
        CUVIDVC1PICPARAMS   vc1;
        CUVIDMPEG4PICPARAMS mpeg4;
        CUVIDJPEGPICPARAMS  jpeg;
        CUVIDHEVCPICPARAMS  hevc;
        CUVIDVP8PICPARAMS   vp8;
        CUVIDVP9PICPARAMS   vp9;
        CUVIDAV1PICPARAMS   av1;
        unsigned int CodecReserved[1024];
    } CodecSpecific;
} CUVIDPICPARAMS;

typedef struct _CUVIDPROCPARAMS
{
    int progressive_frame;
    int second_field;
    int top_field_first;
    int unpaired_field;
    unsigned int reserved_flags;
    unsigned int reserved_zero;
    unsigned long long raw_input_dptr;
    unsigned int raw_input_pitch;
    unsigned int raw_input_format;
    unsigned long long raw_output_dptr;
    unsigned int raw_output_pitch;
    unsigned int Reserved1;
    CUstream output_stream;
    unsigned int Reserved[46];
    unsigned long long *histogram_dptr;
    void *Reserved2[1];
} CUVIDPROCPARAMS;

typedef struct _CUVIDGETDECODESTATUS
{
    cuvidDecodeStatus decodeStatus;
    unsigned int reserved[31];
    void *pReserved[8];
} CUVIDGETDECODESTATUS;

typedef struct _CUVIDRECONFIGUREDECODERINFO
{
    unsigned int ulWidth;
    unsigned int ulHeight;
    unsigned int ulTargetWidth;
    unsigned int ulTargetHeight;
    unsigned int ulNumDecodeSurfaces;
    unsigned int reserved1[12];
    struct {
        short left;
        short top;
        short right;
        short bottom;
    } display_area;
    struct {
        short left;
        short top;
        short right;
        short bottom;
    } target_rect;
    unsigned int reserved2[11];
} CUVIDRECONFIGUREDECODERINFO;

typedef CUresult CUDAAPI tcuvidGetDecoderCaps(CUVIDDECODECAPS *pdc);

typedef CUresult CUDAAPI tcuvidCreateDecoder(CUvideodecoder *phDecoder, CUVIDDECODECREATEINFO *pdci);

typedef CUresult CUDAAPI tcuvidDestroyDecoder(CUvideodecoder hDecoder);

typedef CUresult CUDAAPI tcuvidDecodePicture(CUvideodecoder hDecoder, CUVIDPICPARAMS *pPicParams);

typedef CUresult CUDAAPI tcuvidGetDecodeStatus(CUvideodecoder hDecoder, int nPicIdx, CUVIDGETDECODESTATUS* pDecodeStatus);

typedef CUresult CUDAAPI tcuvidReconfigureDecoder(CUvideodecoder hDecoder, CUVIDRECONFIGUREDECODERINFO *pDecReconfigParams);

#if !defined(__CUVID_DEVPTR64) || defined(__CUVID_INTERNAL)
typedef CUresult CUDAAPI tcuvidMapVideoFrame(CUvideodecoder hDecoder, int nPicIdx,
                                             unsigned int *pDevPtr, unsigned int *pPitch,
                                             CUVIDPROCPARAMS *pVPP);

typedef CUresult CUDAAPI tcuvidUnmapVideoFrame(CUvideodecoder hDecoder, unsigned int DevPtr);
#endif

typedef CUresult CUDAAPI tcuvidMapVideoFrame64(CUvideodecoder hDecoder, int nPicIdx, unsigned long long *pDevPtr,
                                               unsigned int *pPitch, CUVIDPROCPARAMS *pVPP);

typedef CUresult CUDAAPI tcuvidUnmapVideoFrame64(CUvideodecoder hDecoder, unsigned long long DevPtr);

#if defined(__CUVID_DEVPTR64) && !defined(__CUVID_INTERNAL)
#define tcuvidMapVideoFrame      tcuvidMapVideoFrame64
#define tcuvidUnmapVideoFrame    tcuvidUnmapVideoFrame64
#endif

typedef CUresult CUDAAPI tcuvidCtxLockCreate(CUvideoctxlock *pLock, CUcontext ctx);

typedef CUresult CUDAAPI tcuvidCtxLockDestroy(CUvideoctxlock lck);

typedef CUresult CUDAAPI tcuvidCtxLock(CUvideoctxlock lck, unsigned int reserved_flags);

typedef CUresult CUDAAPI tcuvidCtxUnlock(CUvideoctxlock lck, unsigned int reserved_flags);

#if defined(__cplusplus)
}
#endif

#endif
