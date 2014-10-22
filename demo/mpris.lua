local lgi  = require     'lgi'
local wirefu = require("wirefu")
local GLib = lgi.require 'GLib'

--TODO list all mpris providers

wirefu.SESSION.org.mpris.MediaPlayer2.amarok("/org/mpris/MediaPlayer2").org.mpris.MediaPlayer2.Player.Pause():get(function (work)
    print("It worked:",work)
end)

wirefu.SESSION.org["kate-editor"]["kwrite-12808"]("/Kate/Document/1").org.kde.KTextEditor.Document.lines():get(function (work)
    print("It worked lines:",work)
end)

wirefu.SESSION.org["kate-editor"]["kwrite-12808"]("/Kate/Document/1").org.kde.KTextEditor.Document.insertLine(1,"sdfsdfsdf"):get(function (work)
    print("It worked:",work)
end)
print("async")


local main_loop = GLib.MainLoop()
main_loop:run()