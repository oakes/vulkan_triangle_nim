# Package

version       = "0.1.0"
author        = "FIXME"
description   = "FIXME"
license       = "FIXME"
srcDir        = "src"
bin           = @["vulkan"]

task dev, "Run dev version":
  exec "nimble run vulkan"

# Dependencies

requires "nim >= 1.0.4"
requires "pararules >= 0.3.0"
requires "stb_image >= 2.5"
requires "nimgl >= 1.1.3"

