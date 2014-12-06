local client = nil--require("wirefu.client")
local wirefu = nil--require("wirefu")

local module = {}

local busses= {}

local watch_cache = {}
local watched = {}
local watch_started = false


local function init_buses()
    client = require("wirefu.client")
    wirefu = require("wirefu")
    busses = {
        wirefu.SYSTEM.org.freedesktop.DBus("/org/freedesktop/DBus").org.freedesktop.DBus,
        wirefu.SESSION.org.freedesktop.DBus("/org/freedesktop/DBus").org.freedesktop.DBus,
    }
end

--- Match new services to watch hooks
local function get_callbacks(name)
    local ret = nil
    for k,v in pairs(watched) do
        print(name,k)
        if name:match(k) then
            if not ret then
                ret = v
            else
                -- Ah, no, really?... anyway. And yes, this does create a new table if there is 3
                -- items found, I am lazy and don't do that!
                local old_ret = ret
                ret = {}
                for k2,v2 in ipairs(old_ret) do
                    ret[k2] = v2
                end
                for k2,v2 in ipairs(v) do
                    ret[#ret] = v2
                end
            end
        end
    end
    return ret
end

--- Begin to watch for new services
local function init_watch(bus)
    watch_started = true

    if not client then
        init_buses()
    end
    busses[bus].NameOwnerChanged()  : connect(function(name, new_owner, old_owner)
        -- Drop all :1.99 unamed services, there is no point to watch them anyway
        if name:len() > 7 then
            if new_owner:len() == 0 then --NEW
                local callbacks = get_callbacks(name)
                if callbacks then
                    for k,v in ipairs(callbacks) do
                        local service = client.create_mt_from_name(nil,{
                            __path = name,
                            __bus = bus
                        })
                        v(service, name,true)
                    end
                end
            elseif old_owner:len() == 0 then --OVER
                print("LOST",name)
                --watch_cache[name] = nil
            end
        end
    end) -- This cannot fail
end

--- Watch for a new service
-- @param name a lua matching expression
-- @param callback function to be called when a new service arrive
--
-- The callback function will have a wirefu service as first parameter,
-- the service name as second and a boolean if the service is gained
-- or lost as third.
function module.watch(bus,name,callback)
print("watch",bus,name,callback)
    if not watch_started then
        init_watch(bus.__bus)
    end
    if not watched[name] then
        watched[name] = {}
    end
    local w = watched[name]
    w[#w+1] = callback
end

function module.method()
    
end

function module.property()
    
end

function module.signals()
    
end

function module.annotations()
    
end

return module