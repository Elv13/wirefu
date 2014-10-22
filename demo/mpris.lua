local lgi  = require     'lgi'
local wirefu = require("wirefu")
local GLib = lgi.require 'GLib'

--TODO list all mpris providers

wirefu.SESSION.org.mpris.MediaPlayer2.amarok("/org/mpris/MediaPlayer2").org.mpris.MediaPlayer2.Player.Pause():get(function (work)
    print("It worked:",work)
end)
print("async")

local main_loop = GLib.MainLoop()
main_loop:run()