local lgi  = require     'lgi'
local wirefu = require("wirefu")
local GLib = lgi.require 'GLib'

local list = wirefu.SESSION.org.freedesktop.DBus("/").org.freedesktop.DBus

    list.ListNames():get(function (nameList)
        for i=1,#nameList do
            print(nameList[i])
        end
    end)

local main_loop = GLib.MainLoop()
main_loop:run()