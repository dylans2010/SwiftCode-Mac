#ifndef _TVG_JPGD_H_
#define _TVG_JPGD_H_

class jpeg_decoder;

jpeg_decoder* jpgdHeader(const char* data, int size, int* width, int* height);
jpeg_decoder* jpgdHeader(const char* filename, int* width, int* height);
unsigned char* jpgdDecompress(jpeg_decoder* decoder);
void jpgdDelete(jpeg_decoder* decoder);

#endif
