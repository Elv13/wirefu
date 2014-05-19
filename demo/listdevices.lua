local lgi  = require     'lgi'
local wirefu = require("wirefu")
local GLib = lgi.require 'GLib'

wirefu.SESSION.a.b.c.d()

local main_loop = GLib.MainLoop()
main_loop:run()