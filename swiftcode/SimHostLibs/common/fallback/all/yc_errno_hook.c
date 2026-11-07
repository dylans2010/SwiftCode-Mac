#include "yc_kernel_api.h"

YC_HIDDEN void __swiftcode_set_errno(int value)
{
    *YC_KFN(__error)() = value;
}

YC_HIDDEN long __swiftcode_stub_enosys(void)
{
    __swiftcode_set_errno(YC_ENOSYS);
    return -1;
}
