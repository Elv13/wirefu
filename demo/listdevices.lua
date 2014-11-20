local lgi  = require     'lgi'
local GLib = lgi.require 'GLib'

local wirefuLookup = require('wirefu.lookup')

-- Demo of wirefu/lookup module
-- USAGE: wirefu/demo/listdevices.lua [pattern]


-- Create lookup instance
wirefuLookup()

-- Print function
local printNames = function (nameList)
        for i=1,#nameList do
                print(nameList[i])
        end
        os.exit()
end


wirefuLookup.getServices(printNames,arg[1])

local main_loop = GLib.MainLoop()
main_loop:run()