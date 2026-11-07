#pragma once

namespace airc::abi {

constexpr unsigned kVersion = 1;

constexpr unsigned kPushSize = 32;
constexpr unsigned kPushTableVertexOrKernel = 0;
constexpr unsigned kPushTableFragment = 8;
constexpr unsigned kPushGrid = 16;

constexpr unsigned kTableBuffer0 = 0;
constexpr unsigned kTableConstantData = 31;
constexpr unsigned kTableTexture0 = 32;
constexpr unsigned kTableSampler0 = 160;
constexpr unsigned kTableConstexprSampler0 = 176;
constexpr unsigned kTableEntries = 192;
constexpr unsigned kMaxBuffers = 31, kMaxTextures = 128, kMaxSamplers = 16, kMaxConstexprSamplers = 16;

constexpr unsigned kSet = 0;
constexpr unsigned kBindingSampledImages = 0;
constexpr unsigned kBindingStorageImages = 1;
constexpr unsigned kBindingSamplers = 2;
constexpr unsigned kTextureSRGBStorageBit = 32;

constexpr unsigned kInputAttachmentSet = 1;

constexpr unsigned kSpecWorkgroupX = 0, kSpecWorkgroupY = 1, kSpecWorkgroupZ = 2;
constexpr unsigned kSpecThreadgroupBytes = 3;
constexpr unsigned kSpecRasterSampleCount = 4;
constexpr unsigned kSpecThreadgroupSlot0 = 100;
constexpr unsigned kSpecFunctionConstant0 = 1u << 20;

}
