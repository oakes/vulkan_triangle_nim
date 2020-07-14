import nimgl/glfw
from nimgl/vulkan import nil
from core import nil

proc keyCallback(window: GLFWWindow, key: int32, scancode: int32, action: int32, mods: int32) {.cdecl.} =
  if action == GLFW_PRESS and key == GLFWKey.Escape:
    window.setWindowShouldClose(true)

if isMainModule:
  doAssert glfwInit()

  glfwWindowHint(GLFWClientApi, GLFWNoApi)
  glfwWindowHint(GLFWResizable, GLFWFalse)

  var w = glfwCreateWindow(800, 600, "Vulkan Triangle")
  if w == nil:
    quit(-1)

  discard w.setKeyCallback(keyCallback)

  proc createSurface(instance: vulkan.VkInstance): vulkan.VkSurfaceKHR =
    if glfwCreateWindowSurface(instance, w, nil, result.addr) != vulkan.VKSuccess:
      quit("failed to create surface")

  var glfwExtensionCount: uint32 = 0
  var glfwExtensions: cstringArray
  glfwExtensions = glfwGetRequiredInstanceExtensions(glfwExtensionCount.addr)
  core.init(glfwExtensions, glfwExtensionCount, createSurface)

  while not w.windowShouldClose():
    glfwPollEvents()

  core.deinit()
  w.destroyWindow()
  glfwTerminate()