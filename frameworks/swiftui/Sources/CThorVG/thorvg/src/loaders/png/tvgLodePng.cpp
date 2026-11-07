#include "tvgCommon.h"
#include "tvgLodePng.h"

#if defined(_MSC_VER) && (_MSC_VER >= 1310)
    #pragma warning( disable : 4244 )
    #pragma warning( disable : 4996 )
#endif

#if (defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L)) || (defined(__cplusplus) && (__cplusplus >= 199711L))
    #define LODEPNG_INLINE inline
#else
    #define LODEPNG_INLINE
#endif

#if (defined(__GNUC__) && (__GNUC__ > 3 || (__GNUC__ == 3 && __GNUC_MINOR__ >= 1))) ||\
    (defined(_MSC_VER) && (_MSC_VER >= 1400)) || \
    (defined(__WATCOMC__) && (__WATCOMC__ >= 1250) && !defined(__cplusplus))
    #define LODEPNG_RESTRICT __restrict
#else
    #define LODEPNG_RESTRICT
#endif

#define LODEPNG_MAX(a, b) (((a) > (b)) ? (a) : (b))
#define LODEPNG_MIN(a, b) (((a) < (b)) ? (a) : (b))
#define LODEPNG_ABS(x) ((x) < 0 ? -(x) : (x))

static void lodepng_memcpy(void* LODEPNG_RESTRICT dst, const void* LODEPNG_RESTRICT src, size_t size)
{
    size_t i;
    for (i = 0; i < size; i++) ((char*)dst)[i] = ((const char*)src)[i];
}

static void lodepng_memset(void* LODEPNG_RESTRICT dst, int value, size_t num)
{
    size_t i;
    for (i = 0; i < num; i++) ((char*)dst)[i] = (char)value;
}

static size_t lodepng_strlen(const char* a)
{
    const char* orig = a;
    (void)(&lodepng_strlen);
    while (*a) a++;
    return (size_t)(a - orig);
}

static int lodepng_addofl(size_t a, size_t b, size_t* result)
{
    *result = a + b;
    return *result < a;
}

static int lodepng_mulofl(size_t a, size_t b, size_t* result)
{
    *result = a * b;
    return (a != 0 && *result / a != b);
}

static int lodepng_gtofl(size_t a, size_t b, size_t c)
{
    size_t d;
    if (lodepng_addofl(a, b, &d)) return 1;
    return d > c;
}

#define CERROR_BREAK(errorvar, code){\
  errorvar = code;\
  break;\
}

#define ERROR_BREAK(code) CERROR_BREAK(error, code)

#define CERROR_RETURN_ERROR(errorvar, code){\
  errorvar = code;\
  return code;\
}

#define CERROR_TRY_RETURN(call){\
  unsigned error = call;\
  if(error) return error;\
}

#define CERROR_RETURN(errorvar, code){\
  errorvar = code;\
  return;\
}

struct ucvector
{
    unsigned char* data;
    size_t size;
    size_t allocsize;
};

static unsigned ucvector_resize(ucvector* p, size_t size)
{
    if (size > p->allocsize) {
        size_t newsize = size + (p->allocsize >> 1u);
        auto data = tvg::realloc(p->data, newsize);
        if(data) {
            p->allocsize = newsize;
            p->data = (unsigned char*)data;
        }
        else return 0;
    }
    p->size = size;
    return 1;
}

static ucvector ucvector_init(unsigned char* buffer, size_t size)
{
    ucvector v;
    v.data = buffer;
    v.allocsize = v.size = size;
    return v;
}

static unsigned lodepng_read32bitInt(const unsigned char* buffer)
{
    return (((unsigned)buffer[0] << 24u) | ((unsigned)buffer[1] << 16u) | ((unsigned)buffer[2] << 8u) | (unsigned)buffer[3]);
}

struct LodePNGBitReader
{
    const unsigned char* data;
    size_t size;
    size_t bitsize;
    size_t bp;
    unsigned buffer;
};

static unsigned LodePNGBitReader_init(LodePNGBitReader* reader, const unsigned char* data, size_t size)
{
    size_t temp;
    reader->data = data;
    reader->size = size;
    if (lodepng_mulofl(size, 8u, &reader->bitsize)) return 105;
    if (lodepng_addofl(reader->bitsize, 64u, &temp)) return 105;
    reader->bp = 0;
    reader->buffer = 0;
    return 0;
  }

static unsigned ensureBits9(LodePNGBitReader* reader, size_t nbits)
{
    size_t start = reader->bp >> 3u;
    size_t size = reader->size;
    if (start + 1u < size) {
        reader->buffer = (unsigned)reader->data[start + 0] | ((unsigned)reader->data[start + 1] << 8u);
        reader->buffer >>= (reader->bp & 7u);
        return 1;
    } else {
        reader->buffer = 0;
        if (start + 0u < size) reader->buffer |= reader->data[start + 0];
        reader->buffer >>= (reader->bp & 7u);
        return reader->bp + nbits <= reader->bitsize;
    }
}

static unsigned ensureBits17(LodePNGBitReader* reader, size_t nbits)
{
    size_t start = reader->bp >> 3u;
    size_t size = reader->size;
    if (start + 2u < size) {
        reader->buffer = (unsigned)reader->data[start + 0] | ((unsigned)reader->data[start + 1] << 8u) | ((unsigned)reader->data[start + 2] << 16u);
        reader->buffer >>= (reader->bp & 7u);
        return 1;
    } else {
        reader->buffer = 0;
        if (start + 0u < size) reader->buffer |= reader->data[start + 0];
        if (start + 1u < size) reader->buffer |= ((unsigned)reader->data[start + 1] << 8u);
        reader->buffer >>= (reader->bp & 7u);
        return reader->bp + nbits <= reader->bitsize;
    }
}

static LODEPNG_INLINE unsigned ensureBits25(LodePNGBitReader* reader, size_t nbits)
{
    size_t start = reader->bp >> 3u;
    size_t size = reader->size;
    if (start + 3u < size) {
        reader->buffer = (unsigned)reader->data[start + 0] | ((unsigned)reader->data[start + 1] << 8u) |  ((unsigned)reader->data[start + 2] << 16u) | ((unsigned)reader->data[start + 3] << 24u);
        reader->buffer >>= (reader->bp & 7u);
        return 1;
    } else {
        reader->buffer = 0;
        if (start + 0u < size) reader->buffer |= reader->data[start + 0];
        if (start + 1u < size) reader->buffer |= ((unsigned)reader->data[start + 1] << 8u);
        if (start + 2u < size) reader->buffer |= ((unsigned)reader->data[start + 2] << 16u);
        reader->buffer >>= (reader->bp & 7u);
        return reader->bp + nbits <= reader->bitsize;
    }
}

static LODEPNG_INLINE unsigned ensureBits32(LodePNGBitReader* reader, size_t nbits)
{
    size_t start = reader->bp >> 3u;
    size_t size = reader->size;
    if(start + 4u < size) {
        reader->buffer = (unsigned)reader->data[start + 0] | ((unsigned)reader->data[start + 1] << 8u) | ((unsigned)reader->data[start + 2] << 16u) | ((unsigned)reader->data[start + 3] << 24u);
        reader->buffer >>= (reader->bp & 7u);
        reader->buffer |= (((unsigned)reader->data[start + 4] << 24u) << (8u - (reader->bp & 7u)));
        return 1;
    } else {
        reader->buffer = 0;
        if (start + 0u < size) reader->buffer |= reader->data[start + 0];
        if (start + 1u < size) reader->buffer |= ((unsigned)reader->data[start + 1] << 8u);
        if (start + 2u < size) reader->buffer |= ((unsigned)reader->data[start + 2] << 16u);
        if (start + 3u < size) reader->buffer |= ((unsigned)reader->data[start + 3] << 24u);
        reader->buffer >>= (reader->bp & 7u);
        return reader->bp + nbits <= reader->bitsize;
    }
}

static unsigned peekBits(LodePNGBitReader* reader, size_t nbits)
{
    return reader->buffer & ((1u << nbits) - 1u);
}

static void advanceBits(LodePNGBitReader* reader, size_t nbits)
{
    reader->buffer >>= nbits;
    reader->bp += nbits;
}

static unsigned readBits(LodePNGBitReader* reader, size_t nbits)
{
    unsigned result = peekBits(reader, nbits);
    advanceBits(reader, nbits);
    return result;
}

unsigned lode_png_test_bitreader(const unsigned char* data, size_t size, size_t numsteps, const size_t* steps, unsigned* result)
{
    size_t i;
    LodePNGBitReader reader;
    unsigned error = LodePNGBitReader_init(&reader, data, size);
    if (error) return 0;
    for (i = 0; i < numsteps; i++) {
        size_t step = steps[i];
        unsigned ok;
        if (step > 25) ok = ensureBits32(&reader, step);
        else if (step > 17) ok = ensureBits25(&reader, step);
        else if (step > 9) ok = ensureBits17(&reader, step);
        else ok = ensureBits9(&reader, step);
        if (!ok) return 0;
        result[i] = readBits(&reader, step);
    }
    return 1;
}

static unsigned reverseBits(unsigned bits, unsigned num)
{
    unsigned i, result = 0;
    for (i = 0; i < num; i++) result |= ((bits >> (num - i - 1u)) & 1u) << i;
    return result;
}

#define FIRST_LENGTH_CODE_INDEX 257
#define LAST_LENGTH_CODE_INDEX 285
#define NUM_DEFLATE_CODE_SYMBOLS 288
#define NUM_DISTANCE_SYMBOLS 32
#define NUM_CODE_LENGTH_CODES 19

static const unsigned LENGTHBASE[29]
  = {3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
     67, 83, 99, 115, 131, 163, 195, 227, 258};

static const unsigned LENGTHEXTRA[29]
  = {0, 0, 0, 0, 0, 0, 0,  0,  1,  1,  1,  1,  2,  2,  2,  2,  3,  3,  3,  3,
      4,  4,  4,   4,   5,   5,   5,   5,   0};

static const unsigned DISTANCEBASE[30]
  = {1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513,
     769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577};

static const unsigned DISTANCEEXTRA[30]
  = {0, 0, 0, 0, 1, 1, 2,  2,  3,  3,  4,  4,  5,  5,   6,   6,   7,   7,   8,
       8,    9,    9,   10,   10,   11,   11,   12,    12,    13,    13};

static const unsigned CLCL_ORDER[NUM_CODE_LENGTH_CODES]
  = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};

struct HuffmanTree
{
    unsigned* codes;
    unsigned* lengths;
    unsigned maxbitlen;
    unsigned numcodes;
    unsigned char* table_len;
    unsigned short* table_value;
};

static void HuffmanTree_init(HuffmanTree* tree)
{
    tree->codes = 0;
    tree->lengths = 0;
    tree->table_len = 0;
    tree->table_value = 0;
}

static void HuffmanTree_cleanup(HuffmanTree* tree)
{
    tvg::free(tree->codes);
    tvg::free(tree->lengths);
    tvg::free(tree->table_len);
    tvg::free(tree->table_value);
}

#define FIRSTBITS 9u

#define INVALIDSYMBOL 65535u

static unsigned HuffmanTree_makeTable(HuffmanTree* tree)
{
    static const unsigned headsize = 1u << FIRSTBITS;
    static const unsigned mask = (1u << FIRSTBITS)  - 1u;
    size_t i, numpresent, pointer, size;
    unsigned* maxlens = tvg::malloc<unsigned>(headsize * sizeof(unsigned));
    if (!maxlens) return 83;

    lodepng_memset(maxlens, 0, headsize * sizeof(*maxlens));
    for (i = 0; i < tree->numcodes; i++) {
        unsigned symbol = tree->codes[i];
        unsigned l = tree->lengths[i];
        unsigned index;
        if(l <= FIRSTBITS) continue;
        index = reverseBits(symbol >> (l - FIRSTBITS), FIRSTBITS);
        maxlens[index] = LODEPNG_MAX(maxlens[index], l);
    }
    size = headsize;
    for (i = 0; i < headsize; ++i) {
        unsigned l = maxlens[i];
        if (l > FIRSTBITS) size += (1u << (l - FIRSTBITS));
    }
    tree->table_len = tvg::malloc<unsigned char>(size * sizeof(*tree->table_len));
    tree->table_value = tvg::malloc<unsigned short>(size * sizeof(*tree->table_value));
    if (!tree->table_len || !tree->table_value) {
        tvg::free(maxlens);
        return 83;
    }
    for (i = 0; i < size; ++i) tree->table_len[i] = 16;

    pointer = headsize;
    for (i = 0; i < headsize; ++i) {
        unsigned l = maxlens[i];
        if(l <= FIRSTBITS) continue;
        tree->table_len[i] = l;
        tree->table_value[i] = pointer;
        pointer += (1u << (l - FIRSTBITS));
    }
    tvg::free(maxlens);

    numpresent = 0;
    for (i = 0; i < tree->numcodes; ++i) {
        unsigned l = tree->lengths[i];
        unsigned symbol = tree->codes[i];
        unsigned reverse = reverseBits(symbol, l);
        if (l == 0) continue;
        numpresent++;

        if (l <= FIRSTBITS) {
            unsigned num = 1u << (FIRSTBITS - l);
            unsigned j;
            for (j = 0; j < num; ++j) {
                unsigned index = reverse | (j << l);
                if(tree->table_len[index] != 16) return 55;
                tree->table_len[index] = l;
                tree->table_value[index] = i;
            }
        } else {
            unsigned index = reverse & mask;
            unsigned maxlen = tree->table_len[index];
            unsigned tablelen = maxlen - FIRSTBITS;
            unsigned start = tree->table_value[index];
            unsigned num = 1u << (tablelen - (l - FIRSTBITS));
            unsigned j;
            if (maxlen < l) return 55;
            for (j = 0; j < num; ++j) {
                unsigned reverse2 = reverse >> FIRSTBITS;
                unsigned index2 = start + (reverse2 | (j << (l - FIRSTBITS)));
                tree->table_len[index2] = l;
                tree->table_value[index2] = i;
            }
        }
    }

    if (numpresent < 2) {
        for (i = 0; i < size; ++i) {
            if (tree->table_len[i] == 16) {
                tree->table_len[i] = (i < headsize) ? 1 : (FIRSTBITS + 1);
                tree->table_value[i] = INVALIDSYMBOL;
            }
        }
    } else {
        for (i = 0; i < size; ++i) {
            if (tree->table_len[i] == 16) return 55;
        }
    }
    return 0;
}

static unsigned HuffmanTree_makeFromLengths2(HuffmanTree* tree)
{
    unsigned* blcount;
    unsigned* nextcode;
    unsigned error = 0;
    unsigned bits, n;

    tree->codes = tvg::malloc<unsigned>(tree->numcodes * sizeof(unsigned));
    blcount = tvg::malloc<unsigned>((tree->maxbitlen + 1) * sizeof(unsigned));
    nextcode = tvg::malloc<unsigned>((tree->maxbitlen + 1) * sizeof(unsigned));
    if (!tree->codes || !blcount || !nextcode) error = 83;

    if (!error) {
        for (n = 0; n != tree->maxbitlen + 1; n++) blcount[n] = nextcode[n] = 0;
        for (bits = 0; bits != tree->numcodes; ++bits) ++blcount[tree->lengths[bits]];
        for(bits = 1; bits <= tree->maxbitlen; ++bits) {
            nextcode[bits] = (nextcode[bits - 1] + blcount[bits - 1]) << 1u;
        }
        for (n = 0; n != tree->numcodes; ++n) {
            if (tree->lengths[n] != 0) {
                tree->codes[n] = nextcode[tree->lengths[n]]++;
                tree->codes[n] &= ((1u << tree->lengths[n]) - 1u);
            }
        }
    }

    tvg::free(blcount);
    tvg::free(nextcode);

    if (!error) error = HuffmanTree_makeTable(tree);
    return error;
}

static unsigned HuffmanTree_makeFromLengths(HuffmanTree* tree, const unsigned* bitlen, size_t numcodes, unsigned maxbitlen)
{
    unsigned i;
    tree->lengths = tvg::malloc<unsigned>(numcodes * sizeof(unsigned));
    if (!tree->lengths) return 83;
    for (i = 0; i != numcodes; ++i) tree->lengths[i] = bitlen[i];
    tree->numcodes = (unsigned)numcodes;
    tree->maxbitlen = maxbitlen;
    return HuffmanTree_makeFromLengths2(tree);
}

static unsigned generateFixedLitLenTree(HuffmanTree* tree)
{
    unsigned i, error = 0;
    unsigned* bitlen = tvg::malloc<unsigned>(NUM_DEFLATE_CODE_SYMBOLS * sizeof(unsigned));
    if (!bitlen) return 83;

    for (i =   0; i <= 143; ++i) bitlen[i] = 8;
    for (i = 144; i <= 255; ++i) bitlen[i] = 9;
    for (i = 256; i <= 279; ++i) bitlen[i] = 7;
    for (i = 280; i <= 287; ++i) bitlen[i] = 8;

    error = HuffmanTree_makeFromLengths(tree, bitlen, NUM_DEFLATE_CODE_SYMBOLS, 15);

    tvg::free(bitlen);
    return error;
}

static unsigned generateFixedDistanceTree(HuffmanTree* tree)
{
    unsigned i, error = 0;
    unsigned* bitlen = tvg::malloc<unsigned>(NUM_DISTANCE_SYMBOLS * sizeof(unsigned));
    if (!bitlen) return 83;

    for (i = 0; i != NUM_DISTANCE_SYMBOLS; ++i) bitlen[i] = 5;
    error = HuffmanTree_makeFromLengths(tree, bitlen, NUM_DISTANCE_SYMBOLS, 15);

    tvg::free(bitlen);
    return error;
}

static unsigned huffmanDecodeSymbol(LodePNGBitReader* reader, const HuffmanTree* codetree)
{
    unsigned short code = peekBits(reader, FIRSTBITS);
    unsigned short l = codetree->table_len[code];
    unsigned short value = codetree->table_value[code];
    if (l <= FIRSTBITS) {
        advanceBits(reader, l);
        return value;
    } else {
        unsigned index2;
        advanceBits(reader, FIRSTBITS);
        index2 = value + peekBits(reader, l - FIRSTBITS);
        advanceBits(reader, codetree->table_len[index2] - FIRSTBITS);
        return codetree->table_value[index2];
    }
}

static unsigned getTreeInflateFixed(HuffmanTree* tree_ll, HuffmanTree* tree_d)
{
    unsigned error = generateFixedLitLenTree(tree_ll);
    if (error) return error;
    return generateFixedDistanceTree(tree_d);
}

static unsigned getTreeInflateDynamic(HuffmanTree* tree_ll, HuffmanTree* tree_d, LodePNGBitReader* reader)
{
    unsigned error = 0;
    unsigned n, HLIT, HDIST, HCLEN, i;

    unsigned* bitlen_ll = 0;
    unsigned* bitlen_d = 0;
    unsigned* bitlen_cl = 0;
    HuffmanTree tree_cl;

    if (!ensureBits17(reader, 14)) return 49;

    HLIT =  readBits(reader, 5) + 257;
    HDIST = readBits(reader, 5) + 1;
    HCLEN = readBits(reader, 4) + 4;

    bitlen_cl = tvg::malloc<unsigned>(NUM_CODE_LENGTH_CODES * sizeof(unsigned));
    if(!bitlen_cl) return 83 ;

    HuffmanTree_init(&tree_cl);

    while (!error) {
        if (lodepng_gtofl(reader->bp, HCLEN * 3, reader->bitsize)) {
            ERROR_BREAK(50);
        }
        for (i = 0; i != HCLEN; ++i) {
            ensureBits9(reader, 3);
            bitlen_cl[CLCL_ORDER[i]] = readBits(reader, 3);
        }
        for (i = HCLEN; i != NUM_CODE_LENGTH_CODES; ++i) {
            bitlen_cl[CLCL_ORDER[i]] = 0;
        }

        error = HuffmanTree_makeFromLengths(&tree_cl, bitlen_cl, NUM_CODE_LENGTH_CODES, 7);
        if(error) break;

        bitlen_ll = tvg::malloc<unsigned>(NUM_DEFLATE_CODE_SYMBOLS * sizeof(unsigned));
        bitlen_d = tvg::malloc<unsigned>(NUM_DISTANCE_SYMBOLS * sizeof(unsigned));
        if (!bitlen_ll || !bitlen_d) ERROR_BREAK(83 );
        lodepng_memset(bitlen_ll, 0, NUM_DEFLATE_CODE_SYMBOLS * sizeof(*bitlen_ll));
        lodepng_memset(bitlen_d, 0, NUM_DISTANCE_SYMBOLS * sizeof(*bitlen_d));

        i = 0;
        while (i < HLIT + HDIST) {
            unsigned code;
            ensureBits25(reader, 22);
            code = huffmanDecodeSymbol(reader, &tree_cl);
            if (code <= 15)  {
                if (i < HLIT) bitlen_ll[i] = code;
                else bitlen_d[i - HLIT] = code;
                ++i;
            } else if (code == 16)  {
                unsigned replength = 3;
                unsigned value;

                if (i == 0) ERROR_BREAK(54);

                replength += readBits(reader, 2);

                if (i < HLIT + 1) value = bitlen_ll[i - 1];
                else value = bitlen_d[i - HLIT - 1];
                for (n = 0; n < replength; ++n) {
                    if (i >= HLIT + HDIST) ERROR_BREAK(13);
                    if (i < HLIT) bitlen_ll[i] = value;
                    else bitlen_d[i - HLIT] = value;
                    ++i;
                }
            } else if(code == 17)  {
                unsigned replength = 3;
                replength += readBits(reader, 3);

                for (n = 0; n < replength; ++n) {
                    if (i >= HLIT + HDIST) ERROR_BREAK(14);

                    if (i < HLIT) bitlen_ll[i] = 0;
                    else bitlen_d[i - HLIT] = 0;
                    ++i;
                }
            } else if(code == 18)  {
                unsigned replength = 11;
                replength += readBits(reader, 7);

                for (n = 0; n < replength; ++n) {
                    if(i >= HLIT + HDIST) ERROR_BREAK(15);

                    if(i < HLIT) bitlen_ll[i] = 0;
                    else bitlen_d[i - HLIT] = 0;
                    ++i;
                }
            } else  {
                ERROR_BREAK(16);
            }
            if (reader->bp > reader->bitsize) {
                ERROR_BREAK(50);
            }
        }
        if (error) break;

        if (bitlen_ll[256] == 0) ERROR_BREAK(64);

        error = HuffmanTree_makeFromLengths(tree_ll, bitlen_ll, NUM_DEFLATE_CODE_SYMBOLS, 15);
        if (error) break;
        error = HuffmanTree_makeFromLengths(tree_d, bitlen_d, NUM_DISTANCE_SYMBOLS, 15);

        break;
    }

    tvg::free(bitlen_cl);
    tvg::free(bitlen_ll);
    tvg::free(bitlen_d);
    HuffmanTree_cleanup(&tree_cl);

    return error;
}

static unsigned inflateHuffmanBlock(ucvector* out, LodePNGBitReader* reader, unsigned btype)
{
    unsigned error = 0;
    HuffmanTree tree_ll;
    HuffmanTree tree_d;

    HuffmanTree_init(&tree_ll);
    HuffmanTree_init(&tree_d);

    if (btype == 1) error = getTreeInflateFixed(&tree_ll, &tree_d);
    else  error = getTreeInflateDynamic(&tree_ll, &tree_d, reader);

    while (!error)  {
        unsigned code_ll;
        ensureBits25(reader, 20);
        code_ll = huffmanDecodeSymbol(reader, &tree_ll);
        if (code_ll <= 255)  {
            if (!ucvector_resize(out, out->size + 1)) ERROR_BREAK(83 );
            out->data[out->size - 1] = (unsigned char)code_ll;
        } else if (code_ll >= FIRST_LENGTH_CODE_INDEX && code_ll <= LAST_LENGTH_CODE_INDEX)  {
            unsigned code_d, distance;
            unsigned numextrabits_l, numextrabits_d;
            size_t start, backward, length;

            length = LENGTHBASE[code_ll - FIRST_LENGTH_CODE_INDEX];

            numextrabits_l = LENGTHEXTRA[code_ll - FIRST_LENGTH_CODE_INDEX];
            if (numextrabits_l != 0) {
                length += readBits(reader, numextrabits_l);
            }

            ensureBits32(reader, 28);
            code_d = huffmanDecodeSymbol(reader, &tree_d);
            if (code_d > 29) {
                if (code_d <= 31) {
                    ERROR_BREAK(18);
                } else {
                    ERROR_BREAK(16);
                }
            }
            distance = DISTANCEBASE[code_d];

            numextrabits_d = DISTANCEEXTRA[code_d];
            if (numextrabits_d != 0) {
                distance += readBits(reader, numextrabits_d);
            }

            start = out->size;
            if (distance > start) ERROR_BREAK(52);
            backward = start - distance;

            if (!ucvector_resize(out, out->size + length)) ERROR_BREAK(83 );
            if (distance < length) {
                size_t forward;
                lodepng_memcpy(out->data + start, out->data + backward, distance);
                start += distance;
                for (forward = distance; forward < length; ++forward) {
                  out->data[start++] = out->data[backward++];
                }
            } else {
                lodepng_memcpy(out->data + start, out->data + backward, length);
            }
        } else if (code_ll == 256) {
            break;
        } else  {
            ERROR_BREAK(16);
        }
        if (reader->bp > reader->bitsize) {
          ERROR_BREAK(51);
        }
    }

    HuffmanTree_cleanup(&tree_ll);
    HuffmanTree_cleanup(&tree_d);

    return error;
}

static unsigned inflateNoCompression(ucvector* out, LodePNGBitReader* reader, const LodePNGDecompressSettings* settings)
{
    size_t bytepos;
    size_t size = reader->size;
    unsigned LEN, NLEN, error = 0;

    bytepos = (reader->bp + 7u) >> 3u;

    if (bytepos + 4 >= size) return 52;
    LEN = (unsigned)reader->data[bytepos] + ((unsigned)reader->data[bytepos + 1] << 8u); bytepos += 2;
    NLEN = (unsigned)reader->data[bytepos] + ((unsigned)reader->data[bytepos + 1] << 8u); bytepos += 2;

    if (!settings->ignore_nlen && LEN + NLEN != 65535) {
        return 21;
    }

    if (!ucvector_resize(out, out->size + LEN)) return 83;

    if (bytepos + LEN > size) return 23;

    lodepng_memcpy(out->data + out->size - LEN, reader->data + bytepos, LEN);
    bytepos += LEN;

    reader->bp = bytepos << 3u;

    return error;
}

static unsigned lodepng_inflatev(ucvector* out, const unsigned char* in, size_t insize, const LodePNGDecompressSettings* settings)
{
    unsigned BFINAL = 0;
    LodePNGBitReader reader;
    unsigned error = LodePNGBitReader_init(&reader, in, insize);

    if (error) return error;

    while (!BFINAL) {
        unsigned BTYPE;
        if (!ensureBits9(&reader, 3)) return 52;
        BFINAL = readBits(&reader, 1);
        BTYPE = readBits(&reader, 2);

        if (BTYPE == 3) return 20;
        else if (BTYPE == 0) error = inflateNoCompression(out, &reader, settings);
        else error = inflateHuffmanBlock(out, &reader, BTYPE);

        if (error) return error;
    }

    return error;
}

static unsigned inflatev(ucvector* out, const unsigned char* in, size_t insize, const LodePNGDecompressSettings* settings)
{
    if (settings->custom_inflate) {
        unsigned error = settings->custom_inflate(&out->data, &out->size, in, insize, settings);
        out->allocsize = out->size;
        return error;
    } else {
        return lodepng_inflatev(out, in, insize, settings);
    }
}

static unsigned update_adler32(unsigned adler, const unsigned char* data, unsigned len)
{
    unsigned s1 = adler & 0xffffu;
    unsigned s2 = (adler >> 16u) & 0xffffu;

    while (len != 0u) {
        unsigned i;
        unsigned amount = len > 5552u ? 5552u : len;
        len -= amount;
        for (i = 0; i != amount; ++i) {
            s1 += (*data++);
            s2 += s1;
        }
        s1 %= 65521u;
        s2 %= 65521u;
    }

    return (s2 << 16u) | s1;
}

static unsigned adler32(const unsigned char* data, unsigned len)
{
    return update_adler32(1u, data, len);
}

static unsigned lodepng_zlib_decompressv(ucvector* out, const unsigned char* in, size_t insize, const LodePNGDecompressSettings* settings)
{
    unsigned error = 0;
    unsigned CM, CINFO, FDICT;

    if (insize < 2) return 53;
    if ((in[0] * 256 + in[1]) % 31 != 0) {
        return 24;
    }

    CM = in[0] & 15;
    CINFO = (in[0] >> 4) & 15;
    FDICT = (in[1] >> 5) & 1;

    if (CM != 8 || CINFO > 7) {
        return 25;
    }
    if (FDICT != 0) {
        return 26;
    }

    error = inflatev(out, in + 2, insize - 2, settings);
    if (error) return error;

    if (!settings->ignore_adler32) {
        unsigned ADLER32 = lodepng_read32bitInt(&in[insize - 4]);
        unsigned checksum = adler32(out->data, (unsigned)(out->size));
        if(checksum != ADLER32) return 58;
    }

    return 0;
}

static unsigned zlib_decompress(unsigned char** out, size_t* outsize, size_t expected_size, const unsigned char* in, size_t insize, const LodePNGDecompressSettings* settings)
{
    if(settings->custom_zlib) {
        return settings->custom_zlib(out, outsize, in, insize, settings);
    } else {
        unsigned error;
        ucvector v = ucvector_init(*out, *outsize);
        if (expected_size) {
            ucvector_resize(&v, *outsize + expected_size);
            v.size = *outsize;
        }
        error = lodepng_zlib_decompressv(&v, in, insize, settings);
        *out = v.data;
        *outsize = v.size;
        return error;
    }
}

static void lodepng_decompress_settings_init(LodePNGDecompressSettings* settings)
{
    settings->ignore_adler32 = 0;
    settings->ignore_nlen = 0;
    settings->custom_zlib = 0;
    settings->custom_inflate = 0;
    settings->custom_context = 0;
}

#if 0
static unsigned lodepng_crc32_table[256] = {
            0u, 1996959894u, 3993919788u, 2567524794u,  124634137u, 1886057615u, 3915621685u, 2657392035u,
    249268274u, 2044508324u, 3772115230u, 2547177864u,  162941995u, 2125561021u, 3887607047u, 2428444049u,
    498536548u, 1789927666u, 4089016648u, 2227061214u,  450548861u, 1843258603u, 4107580753u, 2211677639u,
    325883990u, 1684777152u, 4251122042u, 2321926636u,  335633487u, 1661365465u, 4195302755u, 2366115317u,
    997073096u, 1281953886u, 3579855332u, 2724688242u, 1006888145u, 1258607687u, 3524101629u, 2768942443u,
    901097722u, 1119000684u, 3686517206u, 2898065728u,  853044451u, 1172266101u, 3705015759u, 2882616665u,
    651767980u, 1373503546u, 3369554304u, 3218104598u,  565507253u, 1454621731u, 3485111705u, 3099436303u,
    671266974u, 1594198024u, 3322730930u, 2970347812u,  795835527u, 1483230225u, 3244367275u, 3060149565u,
    1994146192u,   31158534u, 2563907772u, 4023717930u, 1907459465u,  112637215u, 2680153253u, 3904427059u,
    2013776290u,  251722036u, 2517215374u, 3775830040u, 2137656763u,  141376813u, 2439277719u, 3865271297u,
    1802195444u,  476864866u, 2238001368u, 4066508878u, 1812370925u,  453092731u, 2181625025u, 4111451223u,
    1706088902u,  314042704u, 2344532202u, 4240017532u, 1658658271u,  366619977u, 2362670323u, 4224994405u,
    1303535960u,  984961486u, 2747007092u, 3569037538u, 1256170817u, 1037604311u, 2765210733u, 3554079995u,
    1131014506u,  879679996u, 2909243462u, 3663771856u, 1141124467u,  855842277u, 2852801631u, 3708648649u,
    1342533948u,  654459306u, 3188396048u, 3373015174u, 1466479909u,  544179635u, 3110523913u, 3462522015u,
    1591671054u,  702138776u, 2966460450u, 3352799412u, 1504918807u,  783551873u, 3082640443u, 3233442989u,
    3988292384u, 2596254646u,   62317068u, 1957810842u, 3939845945u, 2647816111u,   81470997u, 1943803523u,
    3814918930u, 2489596804u,  225274430u, 2053790376u, 3826175755u, 2466906013u,  167816743u, 2097651377u,
    4027552580u, 2265490386u,  503444072u, 1762050814u, 4150417245u, 2154129355u,  426522225u, 1852507879u,
    4275313526u, 2312317920u,  282753626u, 1742555852u, 4189708143u, 2394877945u,  397917763u, 1622183637u,
    3604390888u, 2714866558u,  953729732u, 1340076626u, 3518719985u, 2797360999u, 1068828381u, 1219638859u,
    3624741850u, 2936675148u,  906185462u, 1090812512u, 3747672003u, 2825379669u,  829329135u, 1181335161u,
    3412177804u, 3160834842u,  628085408u, 1382605366u, 3423369109u, 3138078467u,  570562233u, 1426400815u,
    3317316542u, 2998733608u,  733239954u, 1555261956u, 3268935591u, 3050360625u,  752459403u, 1541320221u,
    2607071920u, 3965973030u, 1969922972u,   40735498u, 2617837225u, 3943577151u, 1913087877u,   83908371u,
    2512341634u, 3803740692u, 2075208622u,  213261112u, 2463272603u, 3855990285u, 2094854071u,  198958881u,
    2262029012u, 4057260610u, 1759359992u,  534414190u, 2176718541u, 4139329115u, 1873836001u,  414664567u,
    2282248934u, 4279200368u, 1711684554u,  285281116u, 2405801727u, 4167216745u, 1634467795u,  376229701u,
    2685067896u, 3608007406u, 1308918612u,  956543938u, 2808555105u, 3495958263u, 1231636301u, 1047427035u,
    2932959818u, 3654703836u, 1088359270u,  936918000u, 2847714899u, 3736837829u, 1202900863u,  817233897u,
    3183342108u, 3401237130u, 1404277552u,  615818150u, 3134207493u, 3453421203u, 1423857449u,  601450431u,
    3009837614u, 3294710456u, 1567103746u,  711928724u, 3020668471u, 3272380065u, 1510334235u,  755167117u
};

static unsigned lodepng_crc32(const unsigned char* data, size_t length)
{
    unsigned r = 0xffffffffu;
    size_t i;
    for (i = 0; i < length; ++i) {
        r = lodepng_crc32_table[(r ^ data[i]) & 0xffu] ^ (r >> 8u);
    }
    return r ^ 0xffffffffu;
}
#endif

static unsigned char readBitFromReversedStream(size_t* bitpointer, const unsigned char* bitstream)
{
    unsigned char result = (unsigned char)((bitstream[(*bitpointer) >> 3] >> (7 - ((*bitpointer) & 0x7))) & 1);
    ++(*bitpointer);
    return result;
}

static unsigned readBitsFromReversedStream(size_t* bitpointer, const unsigned char* bitstream, size_t nbits)
{
    unsigned result = 0;
    size_t i;
    for (i = 0 ; i < nbits; ++i) {
        result <<= 1u;
        result |= (unsigned)readBitFromReversedStream(bitpointer, bitstream);
    }
    return result;
}

static void setBitOfReversedStream(size_t* bitpointer, unsigned char* bitstream, unsigned char bit)
{
    if (bit == 0) bitstream[(*bitpointer) >> 3u] &=  (unsigned char)(~(1u << (7u - ((*bitpointer) & 7u))));
    else bitstream[(*bitpointer) >> 3u] |=  (1u << (7u - ((*bitpointer) & 7u)));
    ++(*bitpointer);
}

static unsigned lodepng_chunk_length(const unsigned char* chunk)
{
    return lodepng_read32bitInt(&chunk[0]);
}

static unsigned char lodepng_chunk_type_equals(const unsigned char* chunk, const char* type)
{
    if (lodepng_strlen(type) != 4) return 0;
    return (chunk[4] == type[0] && chunk[5] == type[1] && chunk[6] == type[2] && chunk[7] == type[3]);
}

static unsigned char lodepng_chunk_ancillary(const unsigned char* chunk)
{
    return ((chunk[4] & 32) != 0);
}

static const unsigned char* lodepng_chunk_data_const(const unsigned char* chunk)
{
    return &chunk[8];
}

#if 0
static unsigned lodepng_chunk_check_crc(const unsigned char* chunk)
{
    unsigned length = lodepng_chunk_length(chunk);
    unsigned CRC = lodepng_read32bitInt(&chunk[length + 8]);
    unsigned checksum = lodepng_crc32(&chunk[4], length + 4);
    if (CRC != checksum) return 1;
    else return 0;
}
#endif

static const unsigned char* lodepng_chunk_next_const(const unsigned char* chunk, const unsigned char* end)
{
    if (chunk >= end || end - chunk < 12) return end;
    if (chunk[0] == 0x89 && chunk[1] == 0x50 && chunk[2] == 0x4e && chunk[3] == 0x47
        && chunk[4] == 0x0d && chunk[5] == 0x0a && chunk[6] == 0x1a && chunk[7] == 0x0a) {
        return chunk + 8;
    } else {
        size_t total_chunk_length;
        const unsigned char* result;
        if (lodepng_addofl(lodepng_chunk_length(chunk), 12, &total_chunk_length)) return end;
        result = chunk + total_chunk_length;
        if (result < chunk) return end;
        return result;
    }
}

static unsigned checkColorValidity(LodePNGColorType colortype, unsigned bd)
{
    switch(colortype) {
        case LCT_GREY:       if(!(bd == 1 || bd == 2 || bd == 4 || bd == 8 || bd == 16)) return 37; break;
        case LCT_RGB:        if(!(                                 bd == 8 || bd == 16)) return 37; break;
        case LCT_PALETTE:    if(!(bd == 1 || bd == 2 || bd == 4 || bd == 8            )) return 37; break;
        case LCT_GREY_ALPHA: if(!(                                 bd == 8 || bd == 16)) return 37; break;
        case LCT_RGBA:       if(!(                                 bd == 8 || bd == 16)) return 37; break;
        case LCT_MAX_OCTET_VALUE: return 31;
        default: return 31;
    }
    return 0;
}

static unsigned getNumColorChannels(LodePNGColorType colortype)
{
    switch(colortype) {
        case LCT_GREY: return 1;
        case LCT_RGB: return 3;
        case LCT_PALETTE: return 1;
        case LCT_GREY_ALPHA: return 2;
        case LCT_RGBA: return 4;
        case LCT_MAX_OCTET_VALUE: return 0;
        default: return 0;
    }
}

static unsigned lodepng_get_bpp_lct(LodePNGColorType colortype, unsigned bitdepth)
{
    return getNumColorChannels(colortype) * bitdepth;
}

static void lodepng_color_mode_init(LodePNGColorMode* info)
{
    info->key_defined = 0;
    info->key_r = info->key_g = info->key_b = 0;
    info->colortype = LCT_RGBA;
    info->bitdepth = 8;
    info->palette = 0;
    info->palettesize = 0;
}

static void lodepng_color_mode_alloc_palette(LodePNGColorMode* info)
{
    size_t i;
    if (!info->palette) info->palette = tvg::malloc<unsigned char>(1024);
    if (!info->palette) return;
    for (i = 0; i != 256; ++i) {
        info->palette[i * 4 + 0] = 0;
        info->palette[i * 4 + 1] = 0;
        info->palette[i * 4 + 2] = 0;
        info->palette[i * 4 + 3] = 255;
    }
}

static void lodepng_palette_clear(LodePNGColorMode* info)
{
    if (info->palette) tvg::free(info->palette);
    info->palette = 0;
    info->palettesize = 0;
}

static void lodepng_color_mode_cleanup(LodePNGColorMode* info)
{
    lodepng_palette_clear(info);
}

static unsigned lodepng_color_mode_copy(LodePNGColorMode* dest, const LodePNGColorMode* source)
{
    lodepng_color_mode_cleanup(dest);
    lodepng_memcpy(dest, source, sizeof(LodePNGColorMode));
    if (source->palette) {
        dest->palette = tvg::malloc<unsigned char>(1024);
        if (!dest->palette && source->palettesize) return 83;
        lodepng_memcpy(dest->palette, source->palette, source->palettesize * 4);
    }
    return 0;
}

static int lodepng_color_mode_equal(const LodePNGColorMode* a, const LodePNGColorMode* b)
{
    size_t i;
    if (a->colortype != b->colortype) return 0;
    if (a->bitdepth != b->bitdepth) return 0;
    if (a->key_defined != b->key_defined) return 0;
    if (a->key_defined) {
        if(a->key_r != b->key_r) return 0;
        if(a->key_g != b->key_g) return 0;
        if(a->key_b != b->key_b) return 0;
    }
    if (a->palettesize != b->palettesize) return 0;
    for (i = 0; i != a->palettesize * 4; ++i) {
        if (a->palette[i] != b->palette[i]) return 0;
    }
    return 1;
}

static size_t lodepng_get_raw_size_lct(unsigned w, unsigned h, LodePNGColorType colortype, unsigned bitdepth)
{
    size_t bpp = lodepng_get_bpp_lct(colortype, bitdepth);
    size_t n = (size_t)w * (size_t)h;
    return ((n / 8u) * bpp) + ((n & 7u) * bpp + 7u) / 8u;
}

static size_t lodepng_get_raw_size(unsigned w, unsigned h, const LodePNGColorMode* color)
{
    return lodepng_get_raw_size_lct(w, h, color->colortype, color->bitdepth);
}

static size_t lodepng_get_raw_size_idat(unsigned w, unsigned h, unsigned bpp)
{
    size_t line = ((size_t)(w / 8u) * bpp) + 1u + ((w & 7u) * bpp + 7u) / 8u;
    return (size_t)h * line;
}

static int lodepng_pixel_overflow(unsigned w, unsigned h, const LodePNGColorMode* pngcolor, const LodePNGColorMode* rawcolor)
{
    size_t bpp = LODEPNG_MAX(lodepng_get_bpp_lct(pngcolor->colortype, pngcolor->bitdepth), lodepng_get_bpp_lct(rawcolor->colortype, rawcolor->bitdepth));
    size_t numpixels, total;
    size_t line;

    if (lodepng_mulofl((size_t)w, (size_t)h, &numpixels)) return 1;
    if (lodepng_mulofl(numpixels, 8, &total)) return 1;

    if (lodepng_mulofl((size_t)(w / 8u), bpp, &line)) return 1;
    if (lodepng_addofl(line, ((w & 7u) * bpp + 7u) / 8u, &line)) return 1;

    if (lodepng_addofl(line, 5, &line)) return 1;
    if (lodepng_mulofl(line, h, &total)) return 1;

    return 0;
}

static void lodepng_clear_icc(LodePNGInfo* info)
{
    tvg::free(info->iccp_name);
    info->iccp_name = NULL;
    tvg::free(info->iccp_profile);
    info->iccp_profile = NULL;
    info->iccp_profile_size = 0;
    info->iccp_defined = 0;
}

static void lodepng_info_init(LodePNGInfo* info)
{
    lodepng_color_mode_init(&info->color);
    info->interlace_method = 0;
    info->compression_method = 0;
    info->filter_method = 0;
    info->iccp_defined = 0;
    info->iccp_name = NULL;
    info->iccp_profile = NULL;
}

static void lodepng_info_cleanup(LodePNGInfo* info)
{
    lodepng_color_mode_cleanup(&info->color);
    lodepng_clear_icc(info);
}

static void addColorBits(unsigned char* out, size_t index, unsigned bits, unsigned in)
{
    unsigned m = bits == 1 ? 7 : bits == 2 ? 3 : 1;
    unsigned p = index & m;
    in &= (1u << bits) - 1u;
    in = in << (bits * (m - p));
    if(p == 0) out[index * bits / 8u] = in;
    else out[index * bits / 8u] |= in;
}

struct ColorTree
{
    ColorTree* children[16];
    int index;
};

static void color_tree_init(ColorTree* tree)
{
    lodepng_memset(tree->children, 0, 16 * sizeof(*tree->children));
    tree->index = -1;
}

static void color_tree_cleanup(ColorTree* tree)
{
    int i;
    for (i = 0; i != 16; ++i) {
        if(tree->children[i]) {
            color_tree_cleanup(tree->children[i]);
            tvg::free(tree->children[i]);
        }
    }
}

static int color_tree_get(ColorTree* tree, unsigned char r, unsigned char g, unsigned char b, unsigned char a)
{
    int bit = 0;
    for (bit = 0; bit < 8; ++bit) {
        int i = 8 * ((r >> bit) & 1) + 4 * ((g >> bit) & 1) + 2 * ((b >> bit) & 1) + 1 * ((a >> bit) & 1);
        if (!tree->children[i]) return -1;
        else tree = tree->children[i];
    }
    return tree ? tree->index : -1;
}

static unsigned color_tree_add(ColorTree* tree, unsigned char r, unsigned char g, unsigned char b, unsigned char a, unsigned index)
{
    int bit;
    for (bit = 0; bit < 8; ++bit) {
        int i = 8 * ((r >> bit) & 1) + 4 * ((g >> bit) & 1) + 2 * ((b >> bit) & 1) + 1 * ((a >> bit) & 1);
        if (!tree->children[i]) {
            tree->children[i] = tvg::malloc<ColorTree>(sizeof(ColorTree));
            if (!tree->children[i]) return 83;
            color_tree_init(tree->children[i]);
        }
        tree = tree->children[i];
    }
    tree->index = (int)index;
    return 0;
}

static unsigned rgba8ToPixel(unsigned char* out, size_t i, const LodePNGColorMode* mode, ColorTree* tree , unsigned char r, unsigned char g, unsigned char b, unsigned char a)
{
    if (mode->colortype == LCT_GREY) {
        unsigned char gray = r;
        if (mode->bitdepth == 8) out[i] = gray;
        else if (mode->bitdepth == 16) out[i * 2 + 0] = out[i * 2 + 1] = gray;
        else {
            gray = ((unsigned)gray >> (8u - mode->bitdepth)) & ((1u << mode->bitdepth) - 1u);
            addColorBits(out, i, mode->bitdepth, gray);
        }
    } else if (mode->colortype == LCT_RGB) {
        if (mode->bitdepth == 8) {
            out[i * 3 + 0] = r;
            out[i * 3 + 1] = g;
            out[i * 3 + 2] = b;
        } else {
            out[i * 6 + 0] = out[i * 6 + 1] = r;
            out[i * 6 + 2] = out[i * 6 + 3] = g;
            out[i * 6 + 4] = out[i * 6 + 5] = b;
        }
    } else if(mode->colortype == LCT_PALETTE) {
        int index = color_tree_get(tree, r, g, b, a);
        if (index < 0) return 82;
        if (mode->bitdepth == 8) out[i] = index;
        else addColorBits(out, i, mode->bitdepth, (unsigned)index);
    } else if (mode->colortype == LCT_GREY_ALPHA) {
        unsigned char gray = r;
        if (mode->bitdepth == 8) {
            out[i * 2 + 0] = gray;
            out[i * 2 + 1] = a;
        } else if (mode->bitdepth == 16) {
            out[i * 4 + 0] = out[i * 4 + 1] = gray;
            out[i * 4 + 2] = out[i * 4 + 3] = a;
        }
    } else if (mode->colortype == LCT_RGBA) {
        if (mode->bitdepth == 8) {
            out[i * 4 + 0] = r;
            out[i * 4 + 1] = g;
            out[i * 4 + 2] = b;
            out[i * 4 + 3] = a;
        } else {
            out[i * 8 + 0] = out[i * 8 + 1] = r;
            out[i * 8 + 2] = out[i * 8 + 3] = g;
            out[i * 8 + 4] = out[i * 8 + 5] = b;
            out[i * 8 + 6] = out[i * 8 + 7] = a;
        }
    }
    return 0;
}

static void rgba16ToPixel(unsigned char* out, size_t i, const LodePNGColorMode* mode, unsigned short r, unsigned short g, unsigned short b, unsigned short a)
{
    if (mode->colortype == LCT_GREY) {
        unsigned short gray = r;
        out[i * 2 + 0] = (gray >> 8) & 255;
        out[i * 2 + 1] = gray & 255;
    } else if (mode->colortype == LCT_RGB) {
        out[i * 6 + 0] = (r >> 8) & 255;
        out[i * 6 + 1] = r & 255;
        out[i * 6 + 2] = (g >> 8) & 255;
        out[i * 6 + 3] = g & 255;
        out[i * 6 + 4] = (b >> 8) & 255;
        out[i * 6 + 5] = b & 255;
    } else if (mode->colortype == LCT_GREY_ALPHA) {
        unsigned short gray = r;
        out[i * 4 + 0] = (gray >> 8) & 255;
        out[i * 4 + 1] = gray & 255;
        out[i * 4 + 2] = (a >> 8) & 255;
        out[i * 4 + 3] = a & 255;
    } else if (mode->colortype == LCT_RGBA) {
        out[i * 8 + 0] = (r >> 8) & 255;
        out[i * 8 + 1] = r & 255;
        out[i * 8 + 2] = (g >> 8) & 255;
        out[i * 8 + 3] = g & 255;
        out[i * 8 + 4] = (b >> 8) & 255;
        out[i * 8 + 5] = b & 255;
        out[i * 8 + 6] = (a >> 8) & 255;
        out[i * 8 + 7] = a & 255;
    }
}

static void getPixelColorRGBA8(unsigned char* r, unsigned char* g, unsigned char* b, unsigned char* a, const unsigned char* in, size_t i, const LodePNGColorMode* mode)
{
    if (mode->colortype == LCT_GREY) {
        if (mode->bitdepth == 8) {
            *r = *g = *b = in[i];
            if (mode->key_defined && *r == mode->key_r) *a = 0;
            else *a = 255;
        } else if (mode->bitdepth == 16) {
            *r = *g = *b = in[i * 2 + 0];
            if (mode->key_defined && 256U * in[i * 2 + 0] + in[i * 2 + 1] == mode->key_r) *a = 0;
            else *a = 255;
        } else {
            unsigned highest = ((1U << mode->bitdepth) - 1U);
            size_t j = i * mode->bitdepth;
            unsigned value = readBitsFromReversedStream(&j, in, mode->bitdepth);
            *r = *g = *b = (value * 255) / highest;
            if (mode->key_defined && value == mode->key_r) *a = 0;
            else *a = 255;
        }
    } else if (mode->colortype == LCT_RGB) {
        if (mode->bitdepth == 8) {
            *r = in[i * 3 + 0]; *g = in[i * 3 + 1]; *b = in[i * 3 + 2];
            if (mode->key_defined && *r == mode->key_r && *g == mode->key_g && *b == mode->key_b) *a = 0;
            else *a = 255;
        } else {
            *r = in[i * 6 + 0];
            *g = in[i * 6 + 2];
            *b = in[i * 6 + 4];
            if (mode->key_defined && 256U * in[i * 6 + 0] + in[i * 6 + 1] == mode->key_r
              && 256U * in[i * 6 + 2] + in[i * 6 + 3] == mode->key_g
              && 256U * in[i * 6 + 4] + in[i * 6 + 5] == mode->key_b) *a = 0;
            else *a = 255;
        }
    } else if (mode->colortype == LCT_PALETTE) {
        unsigned index;
        if (mode->bitdepth == 8) index = in[i];
        else {
            size_t j = i * mode->bitdepth;
            index = readBitsFromReversedStream(&j, in, mode->bitdepth);
        }
        *r = mode->palette[index * 4 + 0];
        *g = mode->palette[index * 4 + 1];
        *b = mode->palette[index * 4 + 2];
        *a = mode->palette[index * 4 + 3];
    } else if (mode->colortype == LCT_GREY_ALPHA) {
        if (mode->bitdepth == 8) {
            *r = *g = *b = in[i * 2 + 0];
            *a = in[i * 2 + 1];
        } else {
            *r = *g = *b = in[i * 4 + 0];
            *a = in[i * 4 + 2];
        }
    } else if (mode->colortype == LCT_RGBA) {
        if (mode->bitdepth == 8) {
            *r = in[i * 4 + 0];
            *g = in[i * 4 + 1];
            *b = in[i * 4 + 2];
            *a = in[i * 4 + 3];
        } else {
            *r = in[i * 8 + 0];
            *g = in[i * 8 + 2];
            *b = in[i * 8 + 4];
            *a = in[i * 8 + 6];
        }
    }
}

static void getPixelColorsRGBA8(unsigned char* LODEPNG_RESTRICT buffer, size_t numpixels, const unsigned char* LODEPNG_RESTRICT in, const LodePNGColorMode* mode)
{
    unsigned num_channels = 4;
    size_t i;
    if (mode->colortype == LCT_GREY) {
        if (mode->bitdepth == 8) {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                buffer[0] = buffer[1] = buffer[2] = in[i];
                buffer[3] = 255;
            }
            if (mode->key_defined) {
                buffer -= numpixels * num_channels;
                for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                    if(buffer[0] == mode->key_r) buffer[3] = 0;
                }
            }
        } else if (mode->bitdepth == 16) {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                buffer[0] = buffer[1] = buffer[2] = in[i * 2];
                buffer[3] = mode->key_defined && 256U * in[i * 2 + 0] + in[i * 2 + 1] == mode->key_r ? 0 : 255;
            }
        } else {
            unsigned highest = ((1U << mode->bitdepth) - 1U);
            size_t j = 0;
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                unsigned value = readBitsFromReversedStream(&j, in, mode->bitdepth);
                buffer[0] = buffer[1] = buffer[2] = (value * 255) / highest;
                buffer[3] = mode->key_defined && value == mode->key_r ? 0 : 255;
            }
        }
    } else if (mode->colortype == LCT_RGB) {
        if (mode->bitdepth == 8) {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                lodepng_memcpy(buffer, &in[i * 3], 3);
                buffer[3] = 255;
            }
            if (mode->key_defined) {
                buffer -= numpixels * num_channels;
                for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                    if (buffer[0] == mode->key_r && buffer[1]== mode->key_g && buffer[2] == mode->key_b) buffer[3] = 0;
                }
            }
        } else {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                buffer[0] = in[i * 6 + 0];
                buffer[1] = in[i * 6 + 2];
                buffer[2] = in[i * 6 + 4];
                buffer[3] = mode->key_defined
                  && 256U * in[i * 6 + 0] + in[i * 6 + 1] == mode->key_r
                  && 256U * in[i * 6 + 2] + in[i * 6 + 3] == mode->key_g
                  && 256U * in[i * 6 + 4] + in[i * 6 + 5] == mode->key_b ? 0 : 255;
            }
        }
    } else if (mode->colortype == LCT_PALETTE) {
        if (mode->bitdepth == 8) {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
              unsigned index = in[i];
              lodepng_memcpy(buffer, &mode->palette[index * 4], 4);
            }
        } else {
            size_t j = 0;
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
              unsigned index = readBitsFromReversedStream(&j, in, mode->bitdepth);
              lodepng_memcpy(buffer, &mode->palette[index * 4], 4);
            }
        }
    } else if (mode->colortype == LCT_GREY_ALPHA) {
        if (mode->bitdepth == 8) {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
              buffer[0] = buffer[1] = buffer[2] = in[i * 2 + 0];
              buffer[3] = in[i * 2 + 1];
            }
        } else {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
              buffer[0] = buffer[1] = buffer[2] = in[i * 4 + 0];
              buffer[3] = in[i * 4 + 2];
            }
        }
    } else if (mode->colortype == LCT_RGBA) {
        if (mode->bitdepth == 8) {
            lodepng_memcpy(buffer, in, numpixels * 4);
        } else {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                buffer[0] = in[i * 8 + 0];
                buffer[1] = in[i * 8 + 2];
                buffer[2] = in[i * 8 + 4];
                buffer[3] = in[i * 8 + 6];
            }
        }
    }
}

static void getPixelColorsRGB8(unsigned char* LODEPNG_RESTRICT buffer, size_t numpixels, const unsigned char* LODEPNG_RESTRICT in, const LodePNGColorMode* mode)
{
    const unsigned num_channels = 3;
    size_t i;
    if (mode->colortype == LCT_GREY) {
        if (mode->bitdepth == 8) {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
               buffer[0] = buffer[1] = buffer[2] = in[i];
            }
        } else if (mode->bitdepth == 16) {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                buffer[0] = buffer[1] = buffer[2] = in[i * 2];
            }
        } else {
            unsigned highest = ((1U << mode->bitdepth) - 1U);
            size_t j = 0;
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                unsigned value = readBitsFromReversedStream(&j, in, mode->bitdepth);
                buffer[0] = buffer[1] = buffer[2] = (value * 255) / highest;
            }
        }
    } else if (mode->colortype == LCT_RGB) {
        if (mode->bitdepth == 8) {
           lodepng_memcpy(buffer, in, numpixels * 3);
        } else {
            for(i = 0; i != numpixels; ++i, buffer += num_channels) {
                buffer[0] = in[i * 6 + 0];
                buffer[1] = in[i * 6 + 2];
                buffer[2] = in[i * 6 + 4];
            }
        }
    } else if (mode->colortype == LCT_PALETTE) {
        if (mode->bitdepth == 8) {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                unsigned index = in[i];
                lodepng_memcpy(buffer, &mode->palette[index * 4], 3);
            }
        } else {
            size_t j = 0;
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                unsigned index = readBitsFromReversedStream(&j, in, mode->bitdepth);
                lodepng_memcpy(buffer, &mode->palette[index * 4], 3);
            }
        }
    } else if (mode->colortype == LCT_GREY_ALPHA) {
        if (mode->bitdepth == 8) {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                buffer[0] = buffer[1] = buffer[2] = in[i * 2 + 0];
            }
        } else {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                buffer[0] = buffer[1] = buffer[2] = in[i * 4 + 0];
            }
        }
    } else if (mode->colortype == LCT_RGBA) {
        if (mode->bitdepth == 8) {
            for(i = 0; i != numpixels; ++i, buffer += num_channels) {
                lodepng_memcpy(buffer, &in[i * 4], 3);
            }
        } else {
            for (i = 0; i != numpixels; ++i, buffer += num_channels) {
                buffer[0] = in[i * 8 + 0];
                buffer[1] = in[i * 8 + 2];
                buffer[2] = in[i * 8 + 4];
            }
        }
    }
}

static void getPixelColorRGBA16(unsigned short* r, unsigned short* g, unsigned short* b, unsigned short* a, const unsigned char* in, size_t i, const LodePNGColorMode* mode)
{
    if (mode->colortype == LCT_GREY) {
        *r = *g = *b = 256 * in[i * 2 + 0] + in[i * 2 + 1];
        if (mode->key_defined && 256U * in[i * 2 + 0] + in[i * 2 + 1] == mode->key_r) *a = 0;
        else *a = 65535;
    } else if (mode->colortype == LCT_RGB) {
        *r = 256u * in[i * 6 + 0] + in[i * 6 + 1];
        *g = 256u * in[i * 6 + 2] + in[i * 6 + 3];
        *b = 256u * in[i * 6 + 4] + in[i * 6 + 5];
        if (mode->key_defined
          && 256u * in[i * 6 + 0] + in[i * 6 + 1] == mode->key_r
          && 256u * in[i * 6 + 2] + in[i * 6 + 3] == mode->key_g
          && 256u * in[i * 6 + 4] + in[i * 6 + 5] == mode->key_b) *a = 0;
        else *a = 65535;
    } else if (mode->colortype == LCT_GREY_ALPHA) {
        *r = *g = *b = 256u * in[i * 4 + 0] + in[i * 4 + 1];
        *a = 256u * in[i * 4 + 2] + in[i * 4 + 3];
    } else if (mode->colortype == LCT_RGBA) {
        *r = 256u * in[i * 8 + 0] + in[i * 8 + 1];
        *g = 256u * in[i * 8 + 2] + in[i * 8 + 3];
        *b = 256u * in[i * 8 + 4] + in[i * 8 + 5];
        *a = 256u * in[i * 8 + 6] + in[i * 8 + 7];
    }
}

static unsigned lodepng_convert(unsigned char* out, const unsigned char* in, const LodePNGColorMode* mode_out, const LodePNGColorMode* mode_in, unsigned w, unsigned h)
{
    size_t i;
    ColorTree tree;
    size_t numpixels = (size_t)w * (size_t)h;
    unsigned error = 0;

    if (mode_in->colortype == LCT_PALETTE && !mode_in->palette) {
        return 107;
    }

    if (lodepng_color_mode_equal(mode_out, mode_in)) {
        size_t numbytes = lodepng_get_raw_size(w, h, mode_in);
        lodepng_memcpy(out, in, numbytes);
        return 0;
    }

    if (mode_out->colortype == LCT_PALETTE) {
        size_t palettesize = mode_out->palettesize;
        const unsigned char* palette = mode_out->palette;
        size_t palsize = (size_t)1u << mode_out->bitdepth;
        if (palettesize == 0) {
            palettesize = mode_in->palettesize;
            palette = mode_in->palette;
            if (mode_in->colortype == LCT_PALETTE && mode_in->bitdepth == mode_out->bitdepth) {
                size_t numbytes = lodepng_get_raw_size(w, h, mode_in);
                lodepng_memcpy(out, in, numbytes);
                return 0;
            }
        }
        if (palettesize < palsize) palsize = palettesize;
        color_tree_init(&tree);
        for (i = 0; i != palsize; ++i) {
            const unsigned char* p = &palette[i * 4];
            error = color_tree_add(&tree, p[0], p[1], p[2], p[3], (unsigned)i);
            if (error) break;
        }
    }

    if (!error) {
        if (mode_in->bitdepth == 16 && mode_out->bitdepth == 16) {
            for (i = 0; i != numpixels; ++i) {
                unsigned short r = 0, g = 0, b = 0, a = 0;
                getPixelColorRGBA16(&r, &g, &b, &a, in, i, mode_in);
                rgba16ToPixel(out, i, mode_out, r, g, b, a);
            }
        } else if (mode_out->bitdepth == 8 && mode_out->colortype == LCT_RGBA) {
            getPixelColorsRGBA8(out, numpixels, in, mode_in);
        } else if(mode_out->bitdepth == 8 && mode_out->colortype == LCT_RGB) {
            getPixelColorsRGB8(out, numpixels, in, mode_in);
        } else {
            unsigned char r = 0, g = 0, b = 0, a = 0;
            for (i = 0; i != numpixels; ++i) {
                getPixelColorRGBA8(&r, &g, &b, &a, in, i, mode_in);
                error = rgba8ToPixel(out, i, mode_out, &tree, r, g, b, a);
                if (error) break;
            }
        }
    }

    if (mode_out->colortype == LCT_PALETTE) {
        color_tree_cleanup(&tree);
    }

    return error;
}

static unsigned char paethPredictor(short a, short b, short c)
{
    short pa = LODEPNG_ABS(b - c);
    short pb = LODEPNG_ABS(a - c);
    short pc = LODEPNG_ABS(a + b - c - c);
    if (pb < pa) { a = b; pa = pb; }
    return (pc < pa) ? c : a;
}

static const unsigned ADAM7_IX[7] = { 0, 4, 0, 2, 0, 1, 0 };
static const unsigned ADAM7_IY[7] = { 0, 0, 4, 0, 2, 0, 1 };
static const unsigned ADAM7_DX[7] = { 8, 8, 4, 4, 2, 2, 1 };
static const unsigned ADAM7_DY[7] = { 8, 8, 8, 4, 4, 2, 2 };

static void Adam7_getpassvalues(unsigned passw[7], unsigned passh[7], size_t filter_passstart[8], size_t padded_passstart[8], size_t passstart[8], unsigned w, unsigned h, unsigned bpp)
{
    unsigned i;

    for (i = 0; i != 7; ++i) {
        passw[i] = (w + ADAM7_DX[i] - ADAM7_IX[i] - 1) / ADAM7_DX[i];
        passh[i] = (h + ADAM7_DY[i] - ADAM7_IY[i] - 1) / ADAM7_DY[i];
        if(passw[i] == 0) passh[i] = 0;
        if(passh[i] == 0) passw[i] = 0;
    }

    filter_passstart[0] = padded_passstart[0] = passstart[0] = 0;
    for (i = 0; i != 7; ++i) {
        filter_passstart[i + 1] = filter_passstart[i]
                                + ((passw[i] && passh[i]) ? passh[i] * (1u + (passw[i] * bpp + 7u) / 8u) : 0);
        padded_passstart[i + 1] = padded_passstart[i] + passh[i] * ((passw[i] * bpp + 7u) / 8u);
        passstart[i + 1] = passstart[i] + (passh[i] * passw[i] * bpp + 7u) / 8u;
    }
}

static unsigned unfilterScanline(unsigned char* recon, const unsigned char* scanline, const unsigned char* precon, size_t bytewidth, unsigned char filterType, size_t length)
{

    size_t i;
    switch (filterType) {
        case 0:
            for (i = 0; i != length; ++i) recon[i] = scanline[i];
            break;
        case 1:
            for (i = 0; i != bytewidth; ++i) recon[i] = scanline[i];
            for (i = bytewidth; i < length; ++i) recon[i] = scanline[i] + recon[i - bytewidth];
            break;
        case 2:
            if (precon) {
                for(i = 0; i != length; ++i) recon[i] = scanline[i] + precon[i];
            } else {
                for(i = 0; i != length; ++i) recon[i] = scanline[i];
            }
            break;
        case 3:
          if (precon) {
              for (i = 0; i != bytewidth; ++i) recon[i] = scanline[i] + (precon[i] >> 1u);
              for (i = bytewidth; i < length; ++i) recon[i] = scanline[i] + ((recon[i - bytewidth] + precon[i]) >> 1u);
          } else {
              for (i = 0; i != bytewidth; ++i) recon[i] = scanline[i];
              for (i = bytewidth; i < length; ++i) recon[i] = scanline[i] + (recon[i - bytewidth] >> 1u);
          }
          break;
        case 4:
            if (precon) {
                for (i = 0; i != bytewidth; ++i) {
                    recon[i] = (scanline[i] + precon[i]);
                }

                if (bytewidth >= 4) {
                    for (; i + 3 < length; i += 4) {
                        size_t j = i - bytewidth;
                        unsigned char s0 = scanline[i + 0], s1 = scanline[i + 1], s2 = scanline[i + 2], s3 = scanline[i + 3];
                        unsigned char r0 = recon[j + 0], r1 = recon[j + 1], r2 = recon[j + 2], r3 = recon[j + 3];
                        unsigned char p0 = precon[i + 0], p1 = precon[i + 1], p2 = precon[i + 2], p3 = precon[i + 3];
                        unsigned char q0 = precon[j + 0], q1 = precon[j + 1], q2 = precon[j + 2], q3 = precon[j + 3];
                        recon[i + 0] = s0 + paethPredictor(r0, p0, q0);
                        recon[i + 1] = s1 + paethPredictor(r1, p1, q1);
                        recon[i + 2] = s2 + paethPredictor(r2, p2, q2);
                        recon[i + 3] = s3 + paethPredictor(r3, p3, q3);
                    }
                } else if (bytewidth >= 3) {
                    for (; i + 2 < length; i += 3) {
                        size_t j = i - bytewidth;
                        unsigned char s0 = scanline[i + 0], s1 = scanline[i + 1], s2 = scanline[i + 2];
                        unsigned char r0 = recon[j + 0], r1 = recon[j + 1], r2 = recon[j + 2];
                        unsigned char p0 = precon[i + 0], p1 = precon[i + 1], p2 = precon[i + 2];
                        unsigned char q0 = precon[j + 0], q1 = precon[j + 1], q2 = precon[j + 2];
                        recon[i + 0] = s0 + paethPredictor(r0, p0, q0);
                        recon[i + 1] = s1 + paethPredictor(r1, p1, q1);
                        recon[i + 2] = s2 + paethPredictor(r2, p2, q2);
                    }
                } else if (bytewidth >= 2) {
                    for (; i + 1 < length; i += 2) {
                        size_t j = i - bytewidth;
                        unsigned char s0 = scanline[i + 0], s1 = scanline[i + 1];
                        unsigned char r0 = recon[j + 0], r1 = recon[j + 1];
                        unsigned char p0 = precon[i + 0], p1 = precon[i + 1];
                        unsigned char q0 = precon[j + 0], q1 = precon[j + 1];
                        recon[i + 0] = s0 + paethPredictor(r0, p0, q0);
                        recon[i + 1] = s1 + paethPredictor(r1, p1, q1);
                    }
                }

                for (; i != length; ++i) {
                    recon[i] = (scanline[i] + paethPredictor(recon[i - bytewidth], precon[i], precon[i - bytewidth]));
                }
            } else {
                for (i = 0; i != bytewidth; ++i) {
                    recon[i] = scanline[i];
                }
                for (i = bytewidth; i < length; ++i) {
                    recon[i] = (scanline[i] + recon[i - bytewidth]);
                }
            }
            break;
        default: return 36;
    }
    return 0;
}

static unsigned unfilter(unsigned char* out, const unsigned char* in, unsigned w, unsigned h, unsigned bpp)
{

    unsigned y;
    unsigned char* prevline = 0;

    size_t bytewidth = (bpp + 7u) / 8u;
    size_t linebytes = lodepng_get_raw_size_idat(w, 1, bpp) - 1u;

    for (y = 0; y < h; ++y) {
        size_t outindex = linebytes * y;
        size_t inindex = (1 + linebytes) * y;
        unsigned char filterType = in[inindex];
        CERROR_TRY_RETURN(unfilterScanline(&out[outindex], &in[inindex + 1], prevline, bytewidth, filterType, linebytes));
        prevline = &out[outindex];
    }

    return 0;
}

static void Adam7_deinterlace(unsigned char* out, const unsigned char* in, unsigned w, unsigned h, unsigned bpp)
{
    unsigned passw[7], passh[7];
    size_t filter_passstart[8], padded_passstart[8], passstart[8];
    unsigned i;

    Adam7_getpassvalues(passw, passh, filter_passstart, padded_passstart, passstart, w, h, bpp);

    if (bpp >= 8) {
        for(i = 0; i != 7; ++i) {
            unsigned x, y, b;
            size_t bytewidth = bpp / 8u;
            for (y = 0; y < passh[i]; ++y)
            for (x = 0; x < passw[i]; ++x) {
                size_t pixelinstart = passstart[i] + (y * passw[i] + x) * bytewidth;
                size_t pixeloutstart = ((ADAM7_IY[i] + (size_t)y * ADAM7_DY[i]) * (size_t)w + ADAM7_IX[i] + (size_t)x * ADAM7_DX[i]) * bytewidth;
                for (b = 0; b < bytewidth; ++b) {
                    out[pixeloutstart + b] = in[pixelinstart + b];
                }
            }
        }
    } else  {
        for (i = 0; i != 7; ++i) {
            unsigned x, y, b;
            unsigned ilinebits = bpp * passw[i];
            unsigned olinebits = bpp * w;
            size_t obp, ibp;
            for (y = 0; y < passh[i]; ++y)
            for (x = 0; x < passw[i]; ++x) {
                ibp = (8 * passstart[i]) + (y * ilinebits + x * bpp);
                obp = (ADAM7_IY[i] + (size_t)y * ADAM7_DY[i]) * olinebits + (ADAM7_IX[i] + (size_t)x * ADAM7_DX[i]) * bpp;
                for (b = 0; b < bpp; ++b) {
                    unsigned char bit = readBitFromReversedStream(&ibp, in);
                    setBitOfReversedStream(&obp, out, bit);
                }
            }
        }
    }
}

static void removePaddingBits(unsigned char* out, const unsigned char* in, size_t olinebits, size_t ilinebits, unsigned h)
{
    unsigned y;
    size_t diff = ilinebits - olinebits;
    size_t ibp = 0, obp = 0;
    for (y = 0; y < h; ++y) {
        size_t x;
        for (x = 0; x < olinebits; ++x) {
            unsigned char bit = readBitFromReversedStream(&ibp, in);
            setBitOfReversedStream(&obp, out, bit);
        }
        ibp += diff;
    }
}

static unsigned postProcessScanlines(unsigned char* out, unsigned char* in, unsigned w, unsigned h, const LodePNGInfo* info_png)
{
    unsigned bpp = lodepng_get_bpp_lct(info_png->color.colortype, info_png->color.bitdepth);
    if (bpp == 0) return 31;

    if (info_png->interlace_method == 0) {
        if (bpp < 8 && w * bpp != ((w * bpp + 7u) / 8u) * 8u) {
            CERROR_TRY_RETURN(unfilter(in, in, w, h, bpp));
            removePaddingBits(out, in, w * bpp, ((w * bpp + 7u) / 8u) * 8u, h);
        }
        else CERROR_TRY_RETURN(unfilter(out, in, w, h, bpp));
    } else  {
        unsigned passw[7], passh[7]; size_t filter_passstart[8], padded_passstart[8], passstart[8];
        unsigned i;

        Adam7_getpassvalues(passw, passh, filter_passstart, padded_passstart, passstart, w, h, bpp);

        for (i = 0; i != 7; ++i) {
            CERROR_TRY_RETURN(unfilter(&in[padded_passstart[i]], &in[filter_passstart[i]], passw[i], passh[i], bpp));
            if (bpp < 8) {
              removePaddingBits(&in[passstart[i]], &in[padded_passstart[i]], passw[i] * bpp, ((passw[i] * bpp + 7u) / 8u) * 8u, passh[i]);
            }
        }
        Adam7_deinterlace(out, in, w, h, bpp);
    }
    return 0;
}

static unsigned readChunk_PLTE(LodePNGColorMode* color, const unsigned char* data, size_t chunkLength)
{
    unsigned pos = 0, i;
    color->palettesize = chunkLength / 3u;
    if (color->palettesize == 0 || color->palettesize > 256) return 38;
    lodepng_color_mode_alloc_palette(color);
    if (!color->palette && color->palettesize) {
        color->palettesize = 0;
        return 83;
    }

    for (i = 0; i != color->palettesize; ++i) {
        color->palette[4 * i + 0] = data[pos++];
        color->palette[4 * i + 1] = data[pos++];
        color->palette[4 * i + 2] = data[pos++];
        color->palette[4 * i + 3] = 255;
    }

    return 0;
}

static unsigned readChunk_tRNS(LodePNGColorMode* color, const unsigned char* data, size_t chunkLength)
{
    unsigned i;
    if (color->colortype == LCT_PALETTE) {
        if (chunkLength > color->palettesize) return 39;

        for (i = 0; i != chunkLength; ++i) color->palette[4 * i + 3] = data[i];
    } else if (color->colortype == LCT_GREY) {
        if (chunkLength != 2) return 30;

        color->key_defined = 1;
        color->key_r = color->key_g = color->key_b = 256u * data[0] + data[1];
    } else if (color->colortype == LCT_RGB) {
        if (chunkLength != 6) return 41;

        color->key_defined = 1;
        color->key_r = 256u * data[0] + data[1];
        color->key_g = 256u * data[2] + data[3];
        color->key_b = 256u * data[4] + data[5];
    }
    else return 42;

    return 0;
}

static unsigned readChunk_iCCP(LodePNGInfo* info, const LodePNGDecompressSettings* zlibsettings,
                               const unsigned char* data, size_t chunkLength)
{
    unsigned error = 0;
    unsigned i;
    size_t size = 0;

    unsigned length, string2_begin;

    if (info->iccp_name) lodepng_clear_icc(info);

    for (length = 0; length < chunkLength && data[length] != 0; ++length) ;
    if (length + 2 >= chunkLength) return 75;
    if (length < 1 || length > 79) return 89;

    info->iccp_name = tvg::malloc<char>(length + 1);
    if (!info->iccp_name) return 83;

    info->iccp_name[length] = 0;
    for (i = 0; i != length; ++i) {
        info->iccp_name[i] = (char)data[i];
    }

    if (data[length + 1] != 0) return 72;

    string2_begin = length + 2;
    if (string2_begin > chunkLength) return 75;

    length = (unsigned)chunkLength - string2_begin;
    error = zlib_decompress(&info->iccp_profile, &size, 0,
                            &data[string2_begin],
                            length, zlibsettings);
    info->iccp_profile_size = size;
    if (!error && !info->iccp_profile_size) error = 100;
    if (!error) info->iccp_defined = 1;
    return error;
}

static void decodeGeneric(unsigned char** out, unsigned* w, unsigned* h, LodePNGState* state, const unsigned char* in, size_t insize)
{
    unsigned char IEND = 0;
    const unsigned char* chunk;
    unsigned char* idat;
    size_t idatsize = 0;
    unsigned char* scanlines = 0;
    size_t scanlines_size = 0, expected_size = 0;
    size_t outsize = 0;

    *out = 0;
    *w = *h = 0;

    state->error = lodepng_inspect(w, h, state, in, insize);
    if (state->error) return;

    if (lodepng_pixel_overflow(*w, *h, &state->info_png.color, &state->info_raw)) {
        CERROR_RETURN(state->error, 92);
    }

    idat = tvg::malloc<unsigned char>(insize);
    if (!idat) CERROR_RETURN(state->error, 83);

    chunk = &in[33];

    while (!IEND && !state->error) {
        unsigned chunkLength;
        const unsigned char* data;

        if ((size_t)((chunk - in) + 12) > insize || chunk < in) {
            if (state->decoder.ignore_end) break;
            CERROR_BREAK(state->error, 30);
        }

        chunkLength = lodepng_chunk_length(chunk);
        if (chunkLength > 2147483647) {
            if (state->decoder.ignore_end) break;
            CERROR_BREAK(state->error, 63);
        }

        if ((size_t)((chunk - in) + chunkLength + 12) > insize || (chunk + chunkLength + 12) < in) {
            CERROR_BREAK(state->error, 64);
        }

        data = lodepng_chunk_data_const(chunk);

        if (lodepng_chunk_type_equals(chunk, "IDAT")) {
            size_t newsize;
            if (lodepng_addofl(idatsize, chunkLength, &newsize)) CERROR_BREAK(state->error, 95);
            if (newsize > insize) CERROR_BREAK(state->error, 95);
            lodepng_memcpy(idat + idatsize, data, chunkLength);
            idatsize += chunkLength;
        } else if (lodepng_chunk_type_equals(chunk, "IEND")) {
            IEND = 1;
        } else if (lodepng_chunk_type_equals(chunk, "PLTE")) {
            state->error = readChunk_PLTE(&state->info_png.color, data, chunkLength);
            if (state->error) break;
        } else if (lodepng_chunk_type_equals(chunk, "tRNS")) {
            state->error = readChunk_tRNS(&state->info_png.color, data, chunkLength);
            if (state->error) break;
        } else if (lodepng_chunk_type_equals(chunk, "iCCP")) {
            state->error = readChunk_iCCP(&state->info_png, &state->decoder.zlibsettings, data, chunkLength);
            if (state->error) break;
        } else  {
            if (!state->decoder.ignore_critical && !lodepng_chunk_ancillary(chunk)) {
                CERROR_BREAK(state->error, 69);
            }
        }

#if 0
        if (!state->decoder.ignore_crc && !unknown)  {
            if (lodepng_chunk_check_crc(chunk)) CERROR_BREAK(state->error, 57);
        }
#endif
        if (!IEND) chunk = lodepng_chunk_next_const(chunk, in + insize);
    }

    if (state->info_png.color.colortype == LCT_PALETTE && !state->info_png.color.palette) {
        state->error = 106;
    }

    if (!state->error) {
        if (state->info_png.interlace_method == 0) {
            size_t bpp = lodepng_get_bpp_lct(state->info_png.color.colortype, state->info_png.color.bitdepth);
            expected_size = lodepng_get_raw_size_idat(*w, *h, bpp);
        } else {
            size_t bpp = lodepng_get_bpp_lct(state->info_png.color.colortype, state->info_png.color.bitdepth);
            expected_size = 0;
            expected_size += lodepng_get_raw_size_idat((*w + 7) >> 3, (*h + 7) >> 3, bpp);
            if (*w > 4) expected_size += lodepng_get_raw_size_idat((*w + 3) >> 3, (*h + 7) >> 3, bpp);
            expected_size += lodepng_get_raw_size_idat((*w + 3) >> 2, (*h + 3) >> 3, bpp);
            if (*w > 2) expected_size += lodepng_get_raw_size_idat((*w + 1) >> 2, (*h + 3) >> 2, bpp);
            expected_size += lodepng_get_raw_size_idat((*w + 1) >> 1, (*h + 1) >> 2, bpp);
            if (*w > 1) expected_size += lodepng_get_raw_size_idat((*w + 0) >> 1, (*h + 1) >> 1, bpp);
            expected_size += lodepng_get_raw_size_idat((*w + 0), (*h + 0) >> 1, bpp);
        }
        state->error = zlib_decompress(&scanlines, &scanlines_size, expected_size, idat, idatsize, &state->decoder.zlibsettings);
    }

    if (!state->error && scanlines_size != expected_size) state->error = 91;
    tvg::free(idat);

    if (!state->error) {
        outsize = lodepng_get_raw_size(*w, *h, &state->info_png.color);
        *out = tvg::malloc<unsigned char>(outsize);
        if (!*out) state->error = 83;
    }
    if (!state->error) {
        lodepng_memset(*out, 0, outsize);
        state->error = postProcessScanlines(*out, scanlines, *w, *h, &state->info_png);
    }
    tvg::free(scanlines);
}

static void lodepng_decoder_settings_init(LodePNGDecoderSettings* settings)
{
    settings->color_convert = 1;
    settings->ignore_crc = 0;
    settings->ignore_critical = 0;
    settings->ignore_end = 0;
    lodepng_decompress_settings_init(&settings->zlibsettings);
}

unsigned lodepng_inspect(unsigned* w, unsigned* h, LodePNGState* state, const unsigned char* in, size_t insize)
{
    unsigned width, height;
    LodePNGInfo* info = &state->info_png;
    if (insize == 0 || in == 0) {
        CERROR_RETURN_ERROR(state->error, 48);
    }
    if (insize < 33) {
        CERROR_RETURN_ERROR(state->error, 27);
    }

    lodepng_info_cleanup(info);
    lodepng_info_init(info);

    if (in[0] != 137 || in[1] != 80 || in[2] != 78 || in[3] != 71 || in[4] != 13 || in[5] != 10 || in[6] != 26 || in[7] != 10) {
        CERROR_RETURN_ERROR(state->error, 28);
    }
    if (lodepng_chunk_length(in + 8) != 13) {
        CERROR_RETURN_ERROR(state->error, 94);
    }
    if (!lodepng_chunk_type_equals(in + 8, "IHDR")) {
        CERROR_RETURN_ERROR(state->error, 29);
    }

    width = lodepng_read32bitInt(&in[16]);
    height = lodepng_read32bitInt(&in[20]);
    if (w) *w = width;
    if (h) *h = height;
    info->color.bitdepth = in[24];
    info->color.colortype = (LodePNGColorType)in[25];
    info->compression_method = in[26];
    info->filter_method = in[27];
    info->interlace_method = in[28];

    if (width == 0 || height == 0) CERROR_RETURN_ERROR(state->error, 93);
    state->error = checkColorValidity(info->color.colortype, info->color.bitdepth);
    if (state->error) return state->error;
    if (info->compression_method != 0) CERROR_RETURN_ERROR(state->error, 32);
    if (info->filter_method != 0) CERROR_RETURN_ERROR(state->error, 33);
    if (info->interlace_method > 1) CERROR_RETURN_ERROR(state->error, 34);

#if 0
    if (!state->decoder.ignore_crc) {
        unsigned CRC = lodepng_read32bitInt(&in[29]);
        unsigned checksum = lodepng_crc32(&in[12], 17);
        if (CRC != checksum) {
          CERROR_RETURN_ERROR(state->error, 57);
        }
    }
#endif
    return state->error;
}

unsigned lodepng_decode(unsigned char** out, unsigned* w, unsigned* h, LodePNGState* state, const unsigned char* in, size_t insize)
{
    *out = 0;
    decodeGeneric(out, w, h, state, in, insize);
    if (state->error) return state->error;
    if (!state->decoder.color_convert || lodepng_color_mode_equal(&state->info_raw, &state->info_png.color)) {
        if (!state->decoder.color_convert) {
            state->error = lodepng_color_mode_copy(&state->info_raw, &state->info_png.color);
            if (state->error) return state->error;
        }
    } else {
        unsigned char* data = *out;
        size_t outsize;

        if (!(state->info_raw.colortype == LCT_RGB || state->info_raw.colortype == LCT_RGBA) && !(state->info_raw.bitdepth == 8)) {
            return 56;
        }

        outsize = lodepng_get_raw_size(*w, *h, &state->info_raw);
        *out = tvg::malloc<unsigned char>(outsize);
        if (!(*out)) {
            state->error = 83;
        }
        else state->error = lodepng_convert(*out, data, &state->info_raw, &state->info_png.color, *w, *h);
        tvg::free(data);
    }
    return state->error;
}

void lodepng_state_init(LodePNGState* state)
{
    lodepng_decoder_settings_init(&state->decoder);
    lodepng_color_mode_init(&state->info_raw);
    lodepng_info_init(&state->info_png);
    state->error = 1;
}

void lodepng_state_cleanup(LodePNGState* state)
{
    lodepng_color_mode_cleanup(&state->info_raw);
    lodepng_info_cleanup(&state->info_png);
}
