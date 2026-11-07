#include "yc_pthread.h"

YC_EXPORT int YC_FN(__is_threaded) = 0;

YC_EXPORT const yc_u16 YC_FN(pthread_layout_offsets)[4] = { 1, YC_PTHREAD_TSD_OFFSET, 0, 8 };
