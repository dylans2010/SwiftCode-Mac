#include "ycl.h"

__asm__(".globl ___chkstk_darwin\n"
        ".p2align 2\n"
        "___chkstk_darwin:\n"
        "    b ____chkstk_darwin\n");
