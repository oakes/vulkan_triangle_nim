import nimgl/glfw
from core import nil

proc keyCallback(window: GLFWWindow, key: int32, scancode: int32, action: int32, mods: int32) {.cdecl.} =
  if action == GLFW_PRESS and key == GLFWKey.Escape:
    window.setWindowShouldClose(true)

if isMainModule:
  if not glfwInit():
    quit("failed to init glfw")

  glfwWindowHint(GLFWClientApi, GLFWNoApi)
  glfwWindowHint(GLFWResizable, GLFWFalse)

  var w = glfwCreateWindow(800, 600, "Vulkan")
  if w == nil:
    quit(-1)

  discard w.setKeyCallback(keyCallback)

  var glfwExtensionCount: uint32 = 0
  var glfwExtensions: cstringArray
  glfwExtensions = glfwGetRequiredInstanceExtensions(glfwExtensionCount.addr)
  core.init(glfwExtensions, glfwExtensionCount)

  while not w.windowShouldClose():
    glfwPollEvents()

  core.deinit()
  w.destroyWindow()
  glfwTerminate()
