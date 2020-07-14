# Package

version       = "0.1.0"
author        = "oakes"
description   = "FIXME"
license       = "Public Domain"
srcDir        = "src"
bin           = @["vulkan_triangle"]

task dev, "Run dev version":
  exec "nimble run vulkan_triangle"

# Dependencies

requires "nim >= 1.2.0"
requires "nimgl >= 1.1.3"

