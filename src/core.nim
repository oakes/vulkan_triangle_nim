import nimgl/vulkan
import sets

type
  QueueFamilyIndices = object
    graphicsFamily: uint32
    graphicsFamilyFound: bool
    presentFamily: uint32
    presentFamilyFound: bool
  SwapChainSupportDetails = object
    capabilities: VkSurfaceCapabilitiesKHR
    formats: seq[VkSurfaceFormatKHR]
    presentModes: seq[VkPresentModeKHR]

const
  validationLayers = ["VK_LAYER_LUNARG_standard_validation"]
  deviceExtensions = ["VK_KHR_swapchain"]

var
  instance: VkInstance
  physicalDevice: VkPhysicalDevice
  device: VkDevice
  surface: VkSurfaceKHR
  graphicsQueue: VkQueue
  presentQueue: VkQueue

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

type
  CreateSurfaceProc = proc (instance: VkInstance): VkSurfaceKHR

proc init*(glfwExtensions: cstringArray, glfwExtensionCount: uint32, createSurface: CreateSurfaceProc) =
  doAssert vkInit()
  # step 1: instance and physical device selection
  instance = createInstance(glfwExtensions, glfwExtensionCount)
  surface = createSurface(instance) # step 3: window surface and swap chain
  physicalDevice = pickPhysicalDevice()
  # step 2: logical device and queue families
  device = createLogicalDevice()

proc deinit*() =
  vkDestroyDevice(device, nil)
  vkDestroySurfaceKHR(instance, surface, nil)
  vkDestroyInstance(instance, nil)
