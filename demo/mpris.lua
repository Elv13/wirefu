local lgi  = require     'lgi'
local wirefu = require("wirefu")
local GLib = lgi.require 'GLib'

--TODO list all mpris providers

wirefu.SESSION.org.mpris.MediaPlayer2.amarok("/org/mpris/MediaPlayer2").org.mpris.MediaPlayer2.Player.Pause():get(function (work)
    print("It worked:",work)
end)

local alias = wirefu.SESSION.org.mpris.MediaPlayer2.vlc("/org/mpris/MediaPlayer2").org.mpris.MediaPlayer2.TrackList

local player = wirefu.SESSION.org.mpris.MediaPlayer2.amarok("/org/mpris/MediaPlayer2").org.mpris.MediaPlayer2.Player

alias.CanEditTracks:get(function (work)
    print("It worked:",work)
end)

alias.CanEditTracks:get(function (work)
    print("It worked:",work)
end)

player.Metadata:get(function(data)
    print("GOT DATA",data["xesam:title"],#data)
        for k,v in pairs(data) do
            print(k,v)
        end
    player.Metadata:connect(function(data)
        print("DATA changed!",data["xesam:title"],data)
        for k,v in pairs(data) do
            print(k,v)
        end
    end)
end)

wirefu.SESSION.org.mpris.MediaPlayer2.vlc("/org/mpris/MediaPlayer2").org.mpris.MediaPlayer2.TrackList.GetTracksMetadata():get(function (work)
    print("It worked:",work)
end)

wirefu.SESSION:watch(".mpris.",function(service,name)
    print("New mpris service!!",name)

    local timer = GLib.Timer()
    while timer:elapsed() < 3 do
        -- Freeze
    end

    service("/org/mpris/MediaPlayer2").org.mpris.MediaPlayer2.Player.Pause():get(function (work)
        print(name, "Paused")
    end)
end)


local main_loop = GLib.MainLoop()
main_loop:run()