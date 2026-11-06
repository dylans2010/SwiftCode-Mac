// Runs when the agent library is inserted into a test host (an app or
// tool started with DYLD_INSERT_LIBRARIES naming this library). The
// Swift side does nothing unless SWIFTCODE_TEST_BUNDLE is set.
// See specs/ide/testing.md, "SwiftCode implementation".
#include "cswiftcodetestagentloader.h"

__attribute__((constructor)) static void swiftcode_test_agent_loaded(void) {
    swiftcode_test_agent_start();
}
