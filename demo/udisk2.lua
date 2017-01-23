local wirefu = require("wirefu")
local lgi  = require     'lgi'
local GLib = lgi.require 'GLib'

local manager = wirefu.SYSTEM.org.freedesktop.UDisks2("/org/freedesktop/UDisks2/Manager")

manager.org.freedesktop.UDisks2.Manager.Version:get(function (work)
    print("It worked:",work)
end)

local sda = wirefu.SYSTEM.org.freedesktop.UDisks2("/org/freedesktop/UDisks2/block_devices/sda")

sda.org.freedesktop.UDisks2.Block.Id:get(function (work)
    print("The device id is:", work)
end)

print("async")

local main_loop = GLib.MainLoop()
main_loop:run()
