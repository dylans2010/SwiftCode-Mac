#include "cswiftcodetestagentloader.h"

__attribute__((constructor)) static void swiftcode_test_agent_loaded(void) {
    swiftcode_test_agent_start();
}
