#ifndef SWIFTCODE_CVULKAN_H
#define SWIFTCODE_CVULKAN_H

#define VK_NO_PROTOTYPES 1
#include "../vulkan/vulkan_core.h"
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef VK_KHR_dynamic_rendering_local_read
typedef struct YVKDynamicRenderingLocalReadFeatures {
    VkStructureType sType;
    void *pNext;
    VkBool32 dynamicRenderingLocalRead;
} YVKDynamicRenderingLocalReadFeatures;
#define YVK_STRUCTURE_TYPE_DYNAMIC_RENDERING_LOCAL_READ_FEATURES ((VkStructureType)1000232000)
#endif

#define YVK_INSTANCE_FUNCTIONS(X) \
    X(vkDestroyInstance) \
    X(vkEnumeratePhysicalDevices) \
    X(vkGetPhysicalDeviceProperties) \
    X(vkGetPhysicalDeviceProperties2) \
    X(vkGetPhysicalDeviceFeatures2) \
    X(vkGetPhysicalDeviceQueueFamilyProperties) \
    X(vkGetPhysicalDeviceMemoryProperties) \
    X(vkGetPhysicalDeviceFormatProperties) \
    X(vkGetPhysicalDeviceImageFormatProperties) \
    X(vkEnumerateDeviceExtensionProperties) \
    X(vkCreateDevice) \
    X(vkGetDeviceProcAddr)

#define YVK_DEVICE_FUNCTIONS(X) \
    X(vkDestroyDevice) \
    X(vkGetDeviceQueue) \
    X(vkDeviceWaitIdle) \
    X(vkQueueSubmit2) \
    X(vkQueueWaitIdle) \
    X(vkAllocateMemory) \
    X(vkFreeMemory) \
    X(vkMapMemory) \
    X(vkUnmapMemory) \
    X(vkCreateBuffer) \
    X(vkDestroyBuffer) \
    X(vkGetBufferMemoryRequirements) \
    X(vkBindBufferMemory) \
    X(vkGetBufferDeviceAddress) \
    X(vkCreateImage) \
    X(vkDestroyImage) \
    X(vkGetImageMemoryRequirements) \
    X(vkBindImageMemory) \
    X(vkGetImageSubresourceLayout) \
    X(vkCreateImageView) \
    X(vkDestroyImageView) \
    X(vkCreateSampler) \
    X(vkDestroySampler) \
    X(vkCreateShaderModule) \
    X(vkDestroyShaderModule) \
    X(vkCreateDescriptorSetLayout) \
    X(vkDestroyDescriptorSetLayout) \
    X(vkCreateDescriptorPool) \
    X(vkDestroyDescriptorPool) \
    X(vkAllocateDescriptorSets) \
    X(vkUpdateDescriptorSets) \
    X(vkCreatePipelineLayout) \
    X(vkDestroyPipelineLayout) \
    X(vkCreateComputePipelines) \
    X(vkCreatePipelineCache) \
    X(vkDestroyPipelineCache) \
    X(vkGetPipelineCacheData) \
    X(vkCreateGraphicsPipelines) \
    X(vkDestroyPipeline) \
    X(vkCreateCommandPool) \
    X(vkDestroyCommandPool) \
    X(vkAllocateCommandBuffers) \
    X(vkFreeCommandBuffers) \
    X(vkBeginCommandBuffer) \
    X(vkEndCommandBuffer) \
    X(vkResetCommandBuffer) \
    X(vkCreateSemaphore) \
    X(vkDestroySemaphore) \
    X(vkWaitSemaphores) \
    X(vkSignalSemaphore) \
    X(vkGetSemaphoreCounterValue) \
    X(vkCmdPipelineBarrier2) \
    X(vkCmdBeginRendering) \
    X(vkCmdEndRendering) \
    X(vkCmdBindPipeline) \
    X(vkCmdBindDescriptorSets) \
    X(vkCmdPushConstants) \
    X(vkCmdBindVertexBuffers) \
    X(vkCmdBindIndexBuffer) \
    X(vkCmdDraw) \
    X(vkCmdDrawIndexed) \
    X(vkCmdDrawIndirect) \
    X(vkCmdDrawIndexedIndirect) \
    X(vkCmdDispatch) \
    X(vkCmdDispatchIndirect) \
    X(vkCmdSetViewport) \
    X(vkCmdSetScissor) \
    X(vkCmdSetCullMode) \
    X(vkCmdSetFrontFace) \
    X(vkCmdSetPrimitiveTopology) \
    X(vkCmdSetPrimitiveRestartEnable) \
    X(vkCmdSetDepthBias) \
    X(vkCmdSetDepthBiasEnable) \
    X(vkCmdSetBlendConstants) \
    X(vkCmdSetStencilReference) \
    X(vkCmdSetStencilCompareMask) \
    X(vkCmdSetStencilWriteMask) \
    X(vkCmdSetStencilTestEnable) \
    X(vkCmdSetStencilOp) \
    X(vkCmdSetDepthTestEnable) \
    X(vkCmdSetDepthWriteEnable) \
    X(vkCmdSetDepthCompareOp) \
    X(vkCmdCopyBuffer) \
    X(vkCmdCopyBufferToImage) \
    X(vkCmdCopyImageToBuffer) \
    X(vkCmdCopyImage) \
    X(vkCmdBlitImage) \
    X(vkCmdFillBuffer) \
    X(vkCmdUpdateBuffer) \
    X(vkCmdClearColorImage) \
    X(vkCreateQueryPool) \
    X(vkDestroyQueryPool) \
    X(vkCmdResetQueryPool) \
    X(vkCmdWriteTimestamp2) \
    X(vkGetQueryPoolResults) \
    X(vkCmdBeginQuery) \
    X(vkCmdEndQuery) \
    X(vkCmdCopyQueryPoolResults)

#define YVK_OPTIONAL_DEVICE_FUNCTIONS(X) \
    X(vkGetMemoryHostPointerPropertiesEXT) \
    X(vkCmdSetPolygonModeEXT) \
    X(vkCmdSetDepthClampEnableEXT) \
    X(vkCmdSetCheckpointNV) \
    X(vkGetQueueCheckpointDataNV) \
    X(vkGetQueueCheckpointData2NV) \
    X(vkGetDeviceMemoryOpaqueCaptureAddress)

typedef struct yvk_dispatch {
    PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr;
    PFN_vkCreateInstance vkCreateInstance;
    PFN_vkEnumerateInstanceVersion vkEnumerateInstanceVersion;
    PFN_vkEnumerateInstanceExtensionProperties vkEnumerateInstanceExtensionProperties;
#define YVK_DECL(name) PFN_##name name;
    YVK_INSTANCE_FUNCTIONS(YVK_DECL)
    YVK_DEVICE_FUNCTIONS(YVK_DECL)
    YVK_OPTIONAL_DEVICE_FUNCTIONS(YVK_DECL)
#undef YVK_DECL
} yvk_dispatch;

const yvk_dispatch *yvk_fns(void);

int yvk_load(char *err, size_t errlen);

typedef struct yvk_features {
    VkBool32 bufferDeviceAddress, descriptorIndexing, dynamicRendering, synchronization2,
             timelineSemaphore, maintenance4, subgroupSizeControl, computeFullSubgroups,
             externalMemoryHost;
    VkBool32 shaderFloat16, shaderInt8, shaderInt16, shaderInt64, shaderFloat64,
             storageBuffer8BitAccess, storageBuffer16BitAccess, storagePushConstant16,
             storageInputOutput16, scalarBlockLayout, vulkanMemoryModel,
             samplerAnisotropy, samplerMirrorClampToEdge, dualSrcBlend, logicOp,
             independentBlend, depthClamp, depthBiasClamp, fillModeNonSolid, wideLines,
             largePoints, shaderClipDistance, multiDrawIndirect, drawIndirectFirstInstance,
             fragmentStoresAndAtomics, vertexPipelineStoresAndAtomics, imageCubeArray,
             textureCompressionBC, textureCompressionETC2, textureCompressionASTC_LDR,
             shaderStorageImageReadWithoutFormat, shaderStorageImageWriteWithoutFormat,
             customBorderColors, extendedDynamicState3PolygonMode, extendedDynamicState3DepthClamp,
             vertexAttributeInstanceRateDivisor, vertexAttributeInstanceRateZeroDivisor,
             fragmentShaderPixelInterlock, workgroupMemoryExplicitLayout, formatA8,
             dynamicRenderingLocalRead, fragmentShaderBarycentric, shaderDemoteToHelperInvocation,
             externalMemoryFd,
             occlusionQueryPrecise,
             graphicsPipelineLibrary,
             diagnosticCheckpoints,
             bufferCaptureReplay;
} yvk_features;

#define YVK_MAX_QUEUES 16u

typedef struct yvk_context {
    VkInstance instance;
    VkPhysicalDevice physical;
    VkDevice device;
    VkQueue queue;
    uint32_t queueFamily;
    VkQueue queues[YVK_MAX_QUEUES];
    uint32_t queueCount;
    VkPhysicalDeviceProperties properties;
    VkPhysicalDeviceMemoryProperties memory;
    VkDeviceSize hostPointerAlignment;
    uint32_t subgroupSize;
    yvk_features features;
    VkDescriptorSetLayout heapLayout;
    VkDescriptorPool heapPool;
    VkDescriptorSet heapSet;
    uint32_t heapSampledImages;
    uint32_t heapStorageImages;
    uint32_t heapSamplers;
    VkPipelineLayout pipelineLayout;
    VkCommandPool commandPool;
    VkPipelineCache pipelineCache;
} yvk_context;

#define YVK_PUSH_CONSTANT_SIZE 128u

typedef struct yvk_context_options {
    uint32_t maxSampledImages;
    uint32_t maxSamplers;
    uint32_t maxStorageImages;
    int validation;
    uint32_t queues;
    int second;
} yvk_context_options;

int yvk_context_create(yvk_context *ctx, const yvk_context_options *opts, char *err, size_t errlen);
void yvk_context_destroy(yvk_context *ctx);

int yvk_pipeline_cache_create(yvk_context *ctx, const void *data, size_t size);
VkResult yvk_pipeline_cache_data(yvk_context *ctx, void *data, size_t *size);

VkFormatFeatureFlags yvk_format_features(const yvk_context *ctx, VkFormat format);
VkFormatFeatureFlags yvk_format_buffer_features(const yvk_context *ctx, VkFormat format);

typedef enum yvk_memory_kind {
    YVK_MEMORY_DEVICE = 0,
    YVK_MEMORY_HOST = 1,
    YVK_MEMORY_IMPORT_HOST = 2,
} yvk_memory_kind;

typedef struct yvk_buffer {
    VkBuffer buffer;
    VkDeviceMemory memory;
    void *mapped;
    VkDeviceSize size;
    VkDeviceAddress address;
    uint64_t captureAddress;
} yvk_buffer;

int yvk_buffer_create(yvk_context *ctx, VkDeviceSize size, yvk_memory_kind kind, void *hostPointer,
                      yvk_buffer *out, char *err, size_t errlen);
int yvk_buffer_recreate(yvk_context *ctx, VkDeviceSize size, yvk_memory_kind kind, void *hostPointer,
                        uint64_t captureAddress, yvk_buffer *out, char *err, size_t errlen);
void yvk_buffer_destroy(yvk_context *ctx, yvk_buffer *buffer);

typedef struct yvk_image_info {
    VkImageType type;
    VkFormat format;
    uint32_t width, height, depth;
    uint32_t mipLevels, arrayLayers;
    VkSampleCountFlagBits samples;
    VkImageUsageFlags usage;
    VkImageCreateFlags flags;
} yvk_image_info;

typedef struct yvk_image {
    VkImage image;
    VkDeviceMemory memory;
} yvk_image;

int yvk_image_create(yvk_context *ctx, const yvk_image_info *info, yvk_image *out, char *err, size_t errlen);
void yvk_image_destroy(yvk_context *ctx, yvk_image *image);

typedef struct yvk_view_info {
    VkImage image;
    VkImageViewType viewType;
    VkFormat format;
    VkImageAspectFlags aspect;
    uint32_t baseLevel, levelCount, baseLayer, layerCount;
    VkComponentMapping components;
    VkImageUsageFlags usage;
} yvk_view_info;

VkImageView yvk_view_create(yvk_context *ctx, const yvk_view_info *info, char *err, size_t errlen);

void yvk_heap_write_sampled(yvk_context *ctx, uint32_t index, VkImageView view);
void yvk_heap_write_storage(yvk_context *ctx, uint32_t index, VkImageView view);
void yvk_heap_write_sampler(yvk_context *ctx, uint32_t index, VkSampler sampler);

typedef struct yvk_sampler_info {
    VkFilter magFilter, minFilter;
    VkSamplerMipmapMode mipmapMode;
    VkSamplerAddressMode addressU, addressV, addressW;
    float mipLodBias, maxAnisotropy, minLod, maxLod;
    VkBool32 anisotropyEnable, compareEnable, unnormalizedCoordinates;
    VkCompareOp compareOp;
    VkBorderColor borderColor;
} yvk_sampler_info;

VkSampler yvk_sampler_create(yvk_context *ctx, const yvk_sampler_info *info, char *err, size_t errlen);

typedef struct yvk_spec_constant {
    uint32_t id;
    uint32_t value;
} yvk_spec_constant;

typedef struct yvk_shader_stage {
    const uint32_t *code;
    size_t wordCount;
    const char *entry;
    const yvk_spec_constant *constants;
    uint32_t constantCount;
    VkPipelineShaderStageCreateFlags flags;
} yvk_shader_stage;

VkPipeline yvk_compute_pipeline_create(yvk_context *ctx, const yvk_shader_stage *stage, char *err, size_t errlen);

#define YVK_MAX_COLOR_ATTACHMENTS 8
#define YVK_MAX_VERTEX_BINDINGS 32
#define YVK_MAX_VERTEX_ATTRIBUTES 32

typedef struct yvk_vertex_binding {
    uint32_t binding, stride;
    VkVertexInputRate inputRate;
    uint32_t divisor;
} yvk_vertex_binding;

typedef struct yvk_graphics_info {
    yvk_shader_stage vertex;
    yvk_shader_stage fragment;
    uint32_t bindingCount;
    yvk_vertex_binding bindings[YVK_MAX_VERTEX_BINDINGS];
    uint32_t attributeCount;
    VkVertexInputAttributeDescription attributes[YVK_MAX_VERTEX_ATTRIBUTES];
    VkPrimitiveTopology topology;
    VkSampleCountFlagBits samples;
    VkBool32 alphaToCoverage;
    uint32_t colorCount;
    VkFormat colorFormats[YVK_MAX_COLOR_ATTACHMENTS];
    VkPipelineColorBlendAttachmentState blend[YVK_MAX_COLOR_ATTACHMENTS];
    VkFormat depthFormat, stencilFormat;
    int rasterizerDiscard;
} yvk_graphics_info;

VkPipeline yvk_library_vertex_input(yvk_context *ctx, const yvk_graphics_info *info, char *err, size_t errlen);
VkPipeline yvk_library_pre_raster(yvk_context *ctx, const yvk_shader_stage *vertex, int rasterizerDiscard,
                                  char *err, size_t errlen);
VkPipeline yvk_library_fragment_shader(yvk_context *ctx, const yvk_shader_stage *fragment, VkSampleCountFlagBits samples,
                                       char *err, size_t errlen);
VkPipeline yvk_library_fragment_output(yvk_context *ctx, const yvk_graphics_info *info, char *err, size_t errlen);
VkPipeline yvk_library_link(yvk_context *ctx, const VkPipeline *libraries, uint32_t count, int optimize,
                            char *err, size_t errlen);

VkPipeline yvk_graphics_pipeline_create(yvk_context *ctx, const yvk_graphics_info *info, char *err, size_t errlen);

VkCommandBuffer yvk_command_buffer_begin(yvk_context *ctx, char *err, size_t errlen);
int yvk_command_buffer_restart(yvk_context *ctx, VkCommandBuffer cb);
void yvk_command_buffer_free(yvk_context *ctx, VkCommandBuffer cb);

typedef struct yvk_attachment {
    VkImageView view;
    VkImageView resolveView;
    VkResolveModeFlagBits resolveMode;
    VkAttachmentLoadOp load;
    VkAttachmentStoreOp store;
    VkClearValue clear;
} yvk_attachment;

typedef struct yvk_rendering_info {
    uint32_t x, y, width, height;
    uint32_t layerCount;
    uint32_t colorCount;
    yvk_attachment color[YVK_MAX_COLOR_ATTACHMENTS];
    yvk_attachment depth;
    yvk_attachment stencil;
} yvk_rendering_info;

void yvk_cmd_begin_rendering(VkCommandBuffer cb, const yvk_rendering_info *info);

void yvk_cmd_memory_barrier(VkCommandBuffer cb, VkPipelineStageFlags2 srcStages, VkAccessFlags2 srcAccess,
                            VkPipelineStageFlags2 dstStages, VkAccessFlags2 dstAccess);
void yvk_cmd_image_layout(VkCommandBuffer cb, VkImage image, VkImageAspectFlags aspect,
                          VkImageLayout from, VkImageLayout to);

VkResult yvk_submit(yvk_context *ctx, VkCommandBuffer cb, VkSemaphore signal, uint64_t value,
                    VkSemaphore waitSemaphore, uint64_t waitValue);
VkResult yvk_submit_on(yvk_context *ctx, uint32_t queue, VkCommandBuffer cb, VkSemaphore signal, uint64_t value,
                       const VkSemaphore *waits, const uint64_t *waitValues, uint32_t waitCount);
VkSemaphore yvk_timeline_create(yvk_context *ctx, uint64_t initial);
VkResult yvk_kick(yvk_context *ctx, uint64_t timeoutNs);
int yvk_presents_to_session(const char *deviceName);
void yvk_cmd_checkpoint(VkCommandBuffer cb, uint64_t marker);
uint32_t yvk_queue_checkpoints(yvk_context *ctx, uint64_t *markers, uint64_t *stages, uint32_t max);
uint32_t yvk_queue_checkpoints_on(yvk_context *ctx, uint32_t queue, uint64_t *markers, uint64_t *stages, uint32_t max);
VkResult yvk_timeline_wait(yvk_context *ctx, VkSemaphore semaphore, uint64_t value, uint64_t timeoutNs);
uint64_t yvk_timeline_value(yvk_context *ctx, VkSemaphore semaphore);
VkResult yvk_timeline_query(yvk_context *ctx, VkSemaphore semaphore, uint64_t *value);
VkResult yvk_timeline_signal(yvk_context *ctx, VkSemaphore semaphore, uint64_t value);

int yvk_spawn_piped(const char *path, char *const argv[], int *pid, int *toChild, int *fromChild);
int yvk_write_all(int fd, const void *bytes, size_t length);
int yvk_read_exactly(int fd, void *bytes, size_t length);
void yvk_end_child(int pid);

#ifdef __cplusplus
}
#endif
#endif
