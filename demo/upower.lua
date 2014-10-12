local lgi  = require     'lgi'
local wirefu = require("wirefu")
local GLib = lgi.require 'GLib'

wirefu.SYSTEM.org.freedesktop.UPower("/org/freedesktop/UPower").HibernateAllowed():get(function (work)
    print("It worked:",work)
end)

local main_loop = GLib.MainLoop()
main_loop:run()