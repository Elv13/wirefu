local lgi  = require     'lgi'
local wirefu = require("wirefu")
local GLib = lgi.require 'GLib'

wirefu.SYSTEM.a.b.c.d().get(function (work)
    print("It worked:",work)
end)

local main_loop = GLib.MainLoop()
main_loop:run()