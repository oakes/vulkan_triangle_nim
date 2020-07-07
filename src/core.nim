import nimgl/vulkan

type
  QueueFamilyIndices = object
    graphicsFamily: uint32
    graphicsFamilyFound: bool

var
  instance: VkInstance
  validationLayers = [ "VK_LAYER_LUNARG_standard_validation" ]
  physicalDevice: VkPhysicalDevice
  device: VkDevice

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

proc findQueueFamilies(pDevice: VkPhysicalDevice): QueueFamilyIndices =
  result.graphicsFamilyFound = false

  var queueFamilyCount: uint32 = 0
  vkGetPhysicalDeviceQueueFamilyProperties(pDevice, queueFamilyCount.addr, nil)
  var queueFamilies = newSeq[VkQueueFamilyProperties](queueFamilyCount)
  vkGetPhysicalDeviceQueueFamilyProperties(pdevice, queueFamilyCount.addr, queueFamilies[0].addr)

  var indice: uint32 = 0
  for queueFamily in queueFamilies:
    if (queueFamily.queueFlags.uint32 and VkQueueGraphicsBit.uint32) > 0'u32:
      result.graphicsFamily = indice
      result.graphicsFamilyFound = true
    indice.inc

proc createLogicalDevice() =
  var
    indices = physicalDevice.findQueueFamilies()
    queuePriority = 1.0
    deviceFeatures = newSeq[VkPhysicalDeviceFeatures](1)

    deviceQueueCreateInfo = newVkDeviceQueueCreateInfo(
      queueFamilyIndex = indices.graphicsFamily,
      queueCount = 1,
      pQueuePriorities = queuePriority.addr
    )
    deviceCreateInfo = newVkDeviceCreateInfo(
      pQueueCreateInfos = deviceQueueCreateInfo.addr,
      queueCreateInfoCount = 1,
      pEnabledFeatures = deviceFeatures[0].addr,
      enabledExtensionCount = 0,
      enabledLayerCount = 0,
      ppEnabledLayerNames = nil,
      ppEnabledExtensionNames = nil
    )

  if vkCreateDevice(physicalDevice, deviceCreateInfo.addr, nil, device.addr) != VKSuccess:
    echo "failed to create logical device"

proc isDeviceSuitable(pDevice: VkPhysicalDevice): bool =
  var deviceProperties: VkPhysicalDeviceProperties
  vkGetPhysicalDeviceProperties(pDevice, deviceProperties.addr)

  #if deviceProperties.deviceType != VkPhysicalDeviceTypeDiscreteGPU:
  #  return false

  let indices: QueueFamilyIndices = pDevice.findQueueFamilies()
  return indices.graphicsFamilyFound

proc createInstance(glfwExtensions: cstringArray, glfwExtensionCount: uint32) =
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

  if vkCreateInstance(instanceCreateInfo.addr, nil, instance.addr) != VKSuccess:
    quit("failed to create instance")

  var extensionCount: uint32 = 0
  discard vkEnumerateInstanceExtensionProperties(nil, extensionCount.addr, nil)
  var extensions = newSeq[VkExtensionProperties](extensionCount)
  discard vkEnumerateInstanceExtensionProperties(nil, extensionCount.addr, extensions[0].addr)

  checkValidationLayers()

proc pickPhysicalDevice() =
  var deviceCount: uint32 = 0
  discard vkEnumeratePhysicalDevices(instance, deviceCount.addr, nil)
  var devices = newSeq[VkPhysicalDevice](deviceCount)
  discard vkEnumeratePhysicalDevices(instance, deviceCount.addr, devices[0].addr)

  for pDevice in devices:
    if pDevice.isDeviceSuitable():
      physicalDevice = pDevice

  if physicalDevice.ord == 0:
    raise newException(Exception, "Suitable physical device not found")

proc init*(glfwExtensions: cstringArray, glfwExtensionCount: uint32) =
  if not vkInit():
    quit("failed to load vulkan")
  createInstance(glfwExtensions, glfwExtensionCount)
  pickPhysicalDevice()
  createLogicalDevice()

proc deinit*() =
  vkDestroyDevice(device, nil)
  vkDestroyInstance(instance, nil)
