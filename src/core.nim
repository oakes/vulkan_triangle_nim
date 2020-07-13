import nimgl/vulkan
import sets
import bitops

type
  CreateSurfaceProc = proc (instance: VkInstance): VkSurfaceKHR
  QueueFamilyIndices = object
    graphicsFamily: uint32
    graphicsFamilyFound: bool
    presentFamily: uint32
    presentFamilyFound: bool
  SwapChain = tuple[
    swapChain: VkSwapchainKHR,
    swapChainImages: seq[VkImage],
    swapChainImageFormat: VkFormat,
    swapChainExtent: VkExtent2D,
  ]
  SwapChainSupportDetails = object
    capabilities: VkSurfaceCapabilitiesKHR
    formats: seq[VkSurfaceFormatKHR]
    presentModes: seq[VkPresentModeKHR]
  GraphicsPipeline = tuple[
    pipelineLayout: VkPipelineLayout,
    pipeline: VkPipeline,
  ]

const
  validationLayers = ["VK_LAYER_LUNARG_standard_validation"]
  deviceExtensions = ["VK_KHR_swapchain"]
  WIDTH = 800
  HEIGHT = 600
  VK_NULL_HANDLE = 0

var
  instance: VkInstance
  physicalDevice: VkPhysicalDevice
  device: VkDevice
  surface: VkSurfaceKHR
  graphicsQueue: VkQueue
  presentQueue: VkQueue
  swapChain: SwapChain
  renderPass: VkRenderPass
  graphicsPipeline: GraphicsPipeline

loadVK_KHR_surface()
loadVK_KHR_swapchain()

proc toString(chars: openArray[char]): string =
  result = ""
  for c in chars:
    if c != '\0':
      result.add(c)

proc checkValidationLayers() =
  var layerCount: uint32 = 0
  discard vkEnumerateInstanceLayerProperties(layerCount.addr, nil)
  var layers = newSeq[VkLayerProperties](layerCount)
  discard vkEnumerateInstanceLayerProperties(layerCount.addr, layers[0].addr)

  for validate in validationLayers:
    var found = false
    for layer in layers:
      if layer.layerName.toString() == validate:
        found = true
    if not found:
      echo validate & " layer is not supported"

proc isComplete(indices: QueueFamilyIndices): bool =
  indices.graphicsFamilyFound and indices.presentFamilyFound

proc findQueueFamilies(pDevice: VkPhysicalDevice): QueueFamilyIndices =
  result.graphicsFamilyFound = false

  var queueFamilyCount: uint32 = 0
  vkGetPhysicalDeviceQueueFamilyProperties(pDevice, queueFamilyCount.addr, nil)
  var queueFamilies = newSeq[VkQueueFamilyProperties](queueFamilyCount)
  vkGetPhysicalDeviceQueueFamilyProperties(pDevice, queueFamilyCount.addr, queueFamilies[0].addr)

  var index: uint32 = 0
  for queueFamily in queueFamilies:
    if (queueFamily.queueFlags.uint32 and VkQueueGraphicsBit.uint32) > 0'u32:
      result.graphicsFamily = index
      result.graphicsFamilyFound = true
    var presentSupport: VkBool32
    discard vkGetPhysicalDeviceSurfaceSupportKHR(pDevice, index, surface, presentSupport.addr)
    if presentSupport.ord == 1:
      result.presentFamily = index
      result.presentFamilyFound = true
    if result.isComplete:
      break
    index.inc

proc createLogicalDevice(): VkDevice =
  let
    indices = physicalDevice.findQueueFamilies()
    uniqueQueueFamilies = [indices.graphicsFamily, indices.presentFamily].toHashSet
  var
    queuePriority = 1.0
    queueCreateInfos = newSeq[VkDeviceQueueCreateInfo]()

  for queueFamily in uniqueQueueFamilies:
    let deviceQueueCreateInfo = newVkDeviceQueueCreateInfo(
      sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      queueFamilyIndex = queueFamily,
      queueCount = 1,
      pQueuePriorities = queuePriority.addr
    )
    queueCreateInfos.add(deviceQueueCreateInfo)

  var
    deviceFeatures = newSeq[VkPhysicalDeviceFeatures](1)
    deviceExts = allocCStringArray(deviceExtensions)
    deviceCreateInfo = newVkDeviceCreateInfo(
      pQueueCreateInfos = queueCreateInfos[0].addr,
      queueCreateInfoCount = queueCreateInfos.len.uint32,
      pEnabledFeatures = deviceFeatures[0].addr,
      enabledExtensionCount = deviceExtensions.len.uint32,
      enabledLayerCount = 0,
      ppEnabledLayerNames = nil,
      ppEnabledExtensionNames = deviceExts
    )

  if vkCreateDevice(physicalDevice, deviceCreateInfo.addr, nil, result.addr) != VKSuccess:
    echo "failed to create logical device"

  deallocCStringArray(deviceExts)

  vkGetDeviceQueue(result, indices.graphicsFamily, 0, graphicsQueue.addr)
  vkGetDeviceQueue(result, indices.presentFamily, 0, presentQueue.addr)

proc checkDeviceExtensionSupport(pDevice: VkPhysicalDevice): bool =
  var extCount: uint32
  discard vkEnumerateDeviceExtensionProperties(pDevice, nil, extCount.addr, nil)
  var availableExts = newSeq[VkExtensionProperties](extCount)
  discard vkEnumerateDeviceExtensionProperties(pDevice, nil, extCount.addr, availableExts[0].addr)

  var requiredExts = deviceExtensions.toHashSet
  for ext in availableExts.mitems:
    requiredExts.excl($ ext.extensionName.addr)
  requiredExts.len == 0

proc querySwapChainSupport(pDevice: VkPhysicalDevice): SwapChainSupportDetails =
  discard vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pDevice, surface, result.capabilities.addr)
  var formatCount: uint32
  discard vkGetPhysicalDeviceSurfaceFormatsKHR(pDevice, surface, formatCount.addr, nil)
  if formatCount != 0:
    result.formats.setLen(formatCount)
    discard vkGetPhysicalDeviceSurfaceFormatsKHR(pDevice, surface, formatCount.addr, result.formats[0].addr)
  var presentModeCount: uint32
  discard vkGetPhysicalDeviceSurfacePresentModesKHR(pDevice, surface, presentModeCount.addr, nil)
  if presentModeCount != 0:
    result.presentModes.setLen(presentModeCount)
    discard vkGetPhysicalDeviceSurfacePresentModesKHR(pDevice, surface, presentModeCount.addr, result.presentModes[0].addr)

proc isDeviceSuitable(pDevice: VkPhysicalDevice): bool =
  var deviceProperties: VkPhysicalDeviceProperties
  vkGetPhysicalDeviceProperties(pDevice, deviceProperties.addr)

  #if deviceProperties.deviceType != VkPhysicalDeviceTypeDiscreteGPU:
  #  return false

  let extsSupported = pDevice.checkDeviceExtensionSupport

  var swapChainAdequate = false
  if extsSupported:
    let swapChainSupport = querySwapChainSupport(pDevice)
    swapChainAdequate =
      swapChainSupport.formats.len != 0 and
      swapChainSupport.presentModes.len != 0

  let indices: QueueFamilyIndices = pDevice.findQueueFamilies
  return indices.isComplete and extsSupported and swapChainAdequate

proc createInstance(glfwExtensions: cstringArray, glfwExtensionCount: uint32): VkInstance =
  var appInfo = newVkApplicationInfo(
    pApplicationName = "NimGL Vulkan Example",
    applicationVersion = vkMakeVersion(1, 0, 0),
    pEngineName = "No Engine",
    engineVersion = vkMakeVersion(1, 0, 0),
    apiVersion = vkApiVersion1_1
  )

  var instanceCreateInfo = newVkInstanceCreateInfo(
    pApplicationInfo = appInfo.addr,
    enabledExtensionCount = glfwExtensionCount,
    ppEnabledExtensionNames = glfwExtensions,
    enabledLayerCount = 0,
    ppEnabledLayerNames = nil,
  )

  if vkCreateInstance(instanceCreateInfo.addr, nil, result.addr) != VKSuccess:
    quit("failed to create instance")

  var extensionCount: uint32 = 0
  discard vkEnumerateInstanceExtensionProperties(nil, extensionCount.addr, nil)
  var extensions = newSeq[VkExtensionProperties](extensionCount)
  discard vkEnumerateInstanceExtensionProperties(nil, extensionCount.addr, extensions[0].addr)

  # disabled for now
  #checkValidationLayers()

proc pickPhysicalDevice(): VkPhysicalDevice =
  var deviceCount: uint32 = 0
  discard vkEnumeratePhysicalDevices(instance, deviceCount.addr, nil)
  var devices = newSeq[VkPhysicalDevice](deviceCount)
  discard vkEnumeratePhysicalDevices(instance, deviceCount.addr, devices[0].addr)

  for pDevice in devices:
    if pDevice.isDeviceSuitable():
      return pDevice

  raise newException(Exception, "Suitable physical device not found")

proc chooseSwapSurfaceFormat(availableFormats: seq[VkSurfaceFormatKHR]): VkSurfaceFormatKHR =
  for availableFormat in availableFormats:
    if availableFormat.format == VK_FORMAT_B8G8R8A8_SRGB and
      availableFormat.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR:
      return availableFormat
  availableFormats[0]

proc chooseSwapPresentMode(availablePresentModes: seq[VkPresentModeKHR]): VkPresentModeKHR =
  for availablePresentMode in availablePresentModes:
    if availablePresentMode == VK_PRESENT_MODE_MAILBOX_KHR:
      return availablePresentMode
  VK_PRESENT_MODE_FIFO_KHR

proc chooseSwapExtent(capabilities: VkSurfaceCapabilitiesKHR): VkExtent2D =
  if capabilities.currentExtent.width != uint32.high:
    return capabilities.currentExtent
  else:
    result = VkExtent2D(width: WIDTH, height: HEIGHT)
    result.width =
      max(
        capabilities.minImageExtent.width,
        min(capabilities.maxImageExtent.width, result.width)
      )
    result.height =
      max(
        capabilities.minImageExtent.height,
        min(capabilities.maxImageExtent.height, result.height)
      )

proc createSwapChain(): SwapChain =
  let
    swapChainSupport = querySwapChainSupport(physicalDevice)
    surfaceFormat = chooseSwapSurfaceFormat(swapChainSupport.formats)
    presentMode = chooseSwapPresentMode(swapChainSupport.presentModes)
    extent = chooseSwapExtent(swapChainSupport.capabilities)
  var imageCount = swapChainSupport.capabilities.minImageCount + 1
  if swapChainSupport.capabilities.maxImageCount > 0 and
    imageCount > swapChainSupport.capabilities.maxImageCount:
    imageCount = swapChainSupport.capabilities.maxImageCount
  var createInfo = VkSwapchainCreateInfoKHR(
    sType: cast[VkStructureType](1000001000), # VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
    surface: surface,
    minImageCount: imageCount,
    imageFormat: surfaceFormat.format,
    imageColorSpace: surfaceFormat.colorSpace,
    imageExtent: extent,
    imageArrayLayers: 1,
    imageUsage: VkImageUsageFlags(0x00000010), # VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
  )
  let indices = physicalDevice.findQueueFamilies()
  var queueFamilyIndices = [indices.graphicsFamily, indices.presentFamily]
  if indices.graphicsFamily != indices.presentFamily:
    createInfo.imageSharingMode = VK_SHARING_MODE_CONCURRENT
    createInfo.queueFamilyIndexCount = queueFamilyIndices.len.uint32
    createInfo.pQueueFamilyIndices = queueFamilyIndices[0].addr
  else:
    createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE
    createInfo.queueFamilyIndexCount = 0 # optional
    createInfo.pQueueFamilyIndices = nil # optional
  createInfo.preTransform = swapChainSupport.capabilities.currentTransform
  createInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR
  createInfo.presentMode = presentMode
  createInfo.clipped = VkBool32(VK_TRUE)
  createInfo.oldSwapChain = VkSwapchainKHR(0)
  if vkCreateSwapChainKHR(device, createInfo.addr, nil, result.swapChain.addr) != VK_SUCCESS:
    quit("failed to create swap chain")
  discard vkGetSwapchainImagesKHR(device, result.swapChain, imageCount.addr, nil)
  result.swapChainImages.setLen(imageCount)
  discard vkGetSwapchainImagesKHR(device, result.swapChain, imageCount.addr, result.swapChainImages[0].addr)
  result.swapChainImageFormat = surfaceFormat.format
  result.swapChainExtent = extent

proc createShaderModule(code: string): VkShaderModule =
  var createInfo = VkShaderModuleCreateInfo(
    sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
    codeSize: code.len.uint32,
    pCode: cast[ptr uint32](code[0].unsafeAddr)
  )
  if vkCreateShaderModule(device, createInfo.addr, nil, result.addr) != VK_SUCCESS:
    quit("failed to create shader module")

proc createGraphicsPipeline(): GraphicsPipeline =
  const
    vertShaderCode = staticRead("shaders/vert.spv")
    fragShaderCode = staticRead("shaders/frag.spv")
  var
    vertShaderModule = createShaderModule(vertShaderCode)
    fragShaderModule = createShaderModule(fragShaderCode)
    vertShaderStageInfo = VkPipelineShaderStageCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
      stage: VK_SHADER_STAGE_VERTEX_BIT,
      module: vertShaderModule,
      pName: "main",
    )
    fragShaderStageInfo = VkPipelineShaderStageCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
      stage: VkShaderStageFlagBits(0x00000010), # VK_SHADER_STAGE_FRAGMENT_BIT
      module: fragShaderModule,
      pName: "main",
    )
    shaderStages = [vertShaderStageInfo, fragShaderStageInfo]
    vertexInputInfo = VkPipelineVertexInputStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
      vertexBindingDescriptionCount: 0,
      pVertexBindingDescriptions: nil, # optional
      vertexAttributeDescriptionCount: 0,
      pVertexAttributeDescriptions: nil, # optional
    )
    inputAssembly = VkPipelineInputAssemblyStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
      topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
      primitiveRestartEnable: VkBool32(VK_FALSE),
    )
    viewport = VkViewport(
      x: 0f,
      y: 0f,
      width: swapChain.swapChainExtent.width.float,
      height: swapChain.swapChainExtent.height.float,
      minDepth: 0f,
      maxDepth: 1f,
    )
    scissor = VkRect2D(
      offset: VkOffset2D(x: 0, y: 0),
      extent: swapChain.swapChainExtent,
    )
    viewportState = VkPipelineViewportStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
      viewportCount: 1,
      pViewports: viewport.addr,
      scissorCount: 1,
      pScissors: scissor.addr,
    )
    rasterizer = VkPipelineRasterizationStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
      depthClampEnable: VkBool32(VK_FALSE),
      rasterizerDiscardEnable: VkBool32(VK_FALSE),
      polygonMode: VK_POLYGON_MODE_FILL,
      lineWidth: 1f,
      cullMode: VkCullModeFlags(0x00000002), # VK_CULL_MODE_BACK_BIT
      frontFace: VK_FRONT_FACE_CLOCKWISE,
      depthBiasEnable: VkBool32(VK_FALSE),
      depthBiasConstantFactor: 0f, # optional
      depthBiasClamp: 0f, # optional
      depthBiasSlopeFactor: 0f, # optional
    )
    multisampling = VkPipelineMultisampleStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
      sampleShadingEnable: VkBool32(VK_FALSE),
      rasterizationSamples: VK_SAMPLE_COUNT_1_BIT,
      minSampleShading: 1f, # optional
      pSampleMask: nil, # optional
      alphaToCoverageEnable: VkBool32(VK_FALSE), # optional
      alphaToOneEnable: VkBool32(VK_FALSE), # optional
    )
    colorBlendAttachment = VkPipelineColorBlendAttachmentState(
      colorWriteMask: VkColorComponentFlags(
        bitor(
        0x00000001, # VK_COLOR_COMPONENT_R_BIT
        bitor(
        0x00000002, # VK_COLOR_COMPONENT_G_BIT
        bitor(
        0x00000004, # VK_COLOR_COMPONENT_B_BIT
        0x00000008, # VK_COLOR_COMPONENT_A_BIT
        )))
      ),
      blendEnable: VkBool32(VK_FALSE),
      srcColorBlendFactor: VK_BLEND_FACTOR_ONE, # optional
      dstColorBlendFactor: VK_BLEND_FACTOR_ZERO, # optional
      colorBlendOp: VK_BLEND_OP_ADD, # optional
      srcAlphaBlendFactor: VK_BLEND_FACTOR_ONE, # optional
      dstAlphaBlendFactor: VK_BLEND_FACTOR_ZERO, # optional
      alphaBlendOp: VK_BLEND_OP_ADD, # optional
    )
    colorBlending = VkPipelineColorBlendStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
      logicOpEnable: VkBool32(VK_FALSE),
      logicOp: VK_LOGIC_OP_COPY, # optional
      attachmentCount: 1,
      pAttachments: colorBlendAttachment.addr,
      blendConstants: [0.0, 0.0, 0.0, 0.0], # optional
    )
    dynamicStates = [VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_LINE_WIDTH]
    dynamicState = VkPipelineDynamicStateCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
      dynamicStateCount: dynamicStates.len.uint32,
      pDynamicStates: dynamicStates[0].addr,
    )
    pipelineLayoutInfo = VkPipelineLayoutCreateInfo(
      sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
      setLayoutCount: 0, # optional
      pSetLayouts: nil, # optional
      pushConstantRangeCount: 0, # optional
      pPushConstantRanges: nil, # optional
    )
  if vkCreatePipelineLayout(device, pipelineLayoutInfo.addr, nil, result.pipelineLayout.addr) != VK_SUCCESS:
    quit("failed to create pipeline layout")
  var
    pipelineInfo = VkGraphicsPipelineCreateInfo(
      sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
      stageCount: shaderStages.len.uint32,
      pStages: shaderStages[0].addr,
      pVertexInputState: vertexInputInfo.addr,
      pInputAssemblyState: inputAssembly.addr,
      pViewportState: viewportState.addr,
      pRasterizationState: rasterizer.addr,
      pMultisampleState: multisampling.addr,
      pDepthStencilState: nil, # optional
      pColorBlendState: colorBlending.addr,
      pDynamicState: nil, # optional
      layout: result.pipelineLayout,
      renderPass: renderPass,
      subpass: 0,
      basePipelineHandle: VkPipeline(VK_NULL_HANDLE), # optional
      basePipelineIndex: -1, # optional
    )
  if vkCreateGraphicsPipelines(device, VkPipelineCache(VK_NULL_HANDLE), 1, pipelineInfo.addr, nil, result.pipeline.addr) != VK_SUCCESS:
    quit("fialed to create graphics pipeline")
  vkDestroyShaderModule(device, vertShaderModule, nil)
  vkDestroyShaderModule(device, fragShaderModule, nil)

proc createRenderPass(): VkRenderPass =
  var
    colorAttachment = VkAttachmentDescription(
      format: swapChain.swapChainImageFormat,
      samples: VK_SAMPLE_COUNT_1_BIT,
      loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,
      storeOp: VK_ATTACHMENT_STORE_OP_STORE,
      stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,
      stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,
      initialLayout: VK_IMAGE_LAYOUT_UNDEFINED,
      finalLayout: cast[VkImageLayout](1000001002), # VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    )
    colorAttachmentRef = VkAttachmentReference(
      attachment: 0,
      layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    )
    subpass = VkSubpassDescription(
      pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,
      colorAttachmentCount: 1,
      pColorAttachments: colorAttachmentRef.addr,
    )
    renderPassInfo = VkRenderPassCreateInfo(
      sType: VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
      attachmentCount: 1,
      pAttachments: colorAttachment.addr,
      subpassCount: 1,
      pSubpasses: subpass.addr,
    )
  if vkCreateRenderPass(device, renderPassInfo.addr, nil, result.addr) != VK_SUCCESS:
    quit("failed to create render pass")

proc init*(glfwExtensions: cstringArray, glfwExtensionCount: uint32, createSurface: CreateSurfaceProc) =
  doAssert vkInit()
  # step 1: instance and physical device selection
  instance = createInstance(glfwExtensions, glfwExtensionCount)
  surface = createSurface(instance) # step 3: window surface
  physicalDevice = pickPhysicalDevice()
  # step 2: logical device and queue families
  device = createLogicalDevice()
  # step 3: swap chain
  swapChain = createSwapChain()
  # step 4: graphics pipeline
  renderPass = createRenderPass()
  graphicsPipeline = createGraphicsPipeline()

proc deinit*() =
  vkDestroyPipeline(device, graphicsPipeline.pipeline, nil)
  vkDestroyPipelineLayout(device, graphicsPipeline.pipelineLayout, nil)
  vkDestroyRenderPass(device, renderPass, nil)
  vkDestroySwapchainKHR(device, swapChain.swapChain, nil)
  vkDestroyDevice(device, nil)
  vkDestroySurfaceKHR(instance, surface, nil)
  vkDestroyInstance(instance, nil)
