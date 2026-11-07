int demo_plugin_calls = 0;

int demo_plugin_scale(int value) {
    demo_plugin_calls += 1;
    return value * 3 + demo_plugin_calls;
}
