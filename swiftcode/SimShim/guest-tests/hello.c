#include <unistd.h>

int main(void)
{
    static const char line[] = "hello from the iOS simulator runtime on Linux\n";
    write(1, line, sizeof line - 1);
    return 0;
}
