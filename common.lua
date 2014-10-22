local lgi    = require     'lgi'
local Gio    = lgi.require 'Gio'
local core   = require     'lgi.core'
local GLib   = lgi.require 'GLib'
local type,unpack = type,unpack

local module = {}


local busses = {}

module.bus_queue = {[Gio.BusType.SESSION]={},[Gio.BusType.SYSTEM]={}}

function module.get_bus(bus_name)
--     local bus_type = ({SESSION=Gio.BusType.SESSION, SYSTEM=Gio.BusType.SYSTEM})[bus_name]
--     if not bus_type then
--         print("Unknown bus",bus_name)
--         return
--     end
    if bus_name ~= 1 and bus_name ~= 2 then
        print("Unknown bus",bus_name)
        return
    end
    if busses[bus_name] then
        return busses[bus_name]
    else
        --I have no idea why this part doesn't work, I will use the sync version for now
--         local bus_get_guard, bus_get_addr = core.marshal.callback(Gio.AsyncReadyCallback ,function(b,a,s)
--             print("got",b,a,s)
--             busses[bus_name] = a
--             for k,v in ipairs( bus_queue[bus_name]) do
--                 v(a)
--             end
--         end)
--         Gio.bus_get(bus_name,nil,bus_get_addr)
        local bus = Gio.bus_get_sync(bus_name) --TODO use get async
--         print("bob",bus,Gio.call)
        busses[bus_name] = bus
        return bus
    end
end


return module