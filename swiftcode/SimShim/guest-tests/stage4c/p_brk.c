int main(void)
{
    static const char message[] = "p_brk: deliberate abort message";
    __asm__ volatile("mov x0, #-105\n\tmov x1, %0\n\tbrk #1" : : "r"(message) : "x0", "x1");
    return 0;
}
