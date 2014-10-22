local lgi    = require     'lgi'
local Gio    = lgi.require 'Gio'
local core   = require     'lgi.core'
local GLib   = lgi.require 'GLib'
local common = require ("common")
local type,unpack = type,unpack

local module = {}

local pending_calls = {}
local proxies       = {}

local load_proxy

local function idxf(t,k)
    return module.create_mt_from_name(k,t)
end

local function get_in_args(info,method_name)
    local ret = {}
    local methodinfo = ifaceinfo:lookup_method("OpenUri")
    for k,v in ipairs(methodinfo.in_args) do
        --mmmm.in_args[1].name
        ret[#ret+1] = v.signature
    end
    return ret
end

-- Queue calls until proxies are loaded
local function add_pending_call(service_path,pathname,object_path,method_name,args)
    local hash = service_path..pathname..object_path
    local queue = pending_calls[hash]
    if not queue then
       queue = {}
       pending_calls[hash] = queue
    end
    queue[#queue+1] = {
        method      = method_name,
        args        = args       ,
    }
end

local function call_with_proxy(bus,service_path,pathname,object_path,method_name,args,proxy)
    local hash = service_path..pathname..object_path
    local proxy = proxies[hash]
    if not proxy or type(proxy) == "boolean" then
        add_pending_call(service_path,pathname,object_path,method_name,args)
        proxies[hash] = true
        load_proxy(bus,service_path,pathname,object_path)
    else

        local callback = nil

        Gio.DBusProxy.call(
            proxy,
            method_name,
            nil,
            Gio.DBusCallFlags.NONE,
            500,
            nil,
            function(conn1,res1)
                local ret1,err1 = proxy:call_finish(res1)
                print("got called",callback)
                if not err1 then
                    --Done
                    if callback then
                        callback(unpack(ret1.value))
                    end
                end
            end,
            nil
        )
    end

    return {
        get = function(f)
            print("executed")
            callback = f
        end
    }
end

-- Execute everything in the queue
local function proxy_ready(bus,service_path,pathname,object_path,proxy)
    local hash = service_path..pathname..object_path
    local queue = pending_calls[hash]
    if queue then
        for k,v in ipairs(queue) do
            print("KV",k,v)
            call_with_proxy(bus,service_path,pathname,object_path,v.method,v.args,proxy)
        end
        queue = {}
    end
end

-- Create a proxy client with all necessary introspection
load_proxy = function(bus,service_path,pathname,object_path)
    print("getting proxy",service_path)
    Gio.DBusProxy.new(
        bus,--Conn
        Gio.DBusProxyFlags.NONE               ,
        nil                                   ,
        service_path                          ,
        pathname                              ,
        object_path                           ,
        nil,
        function(conn,res)
            local proxy,err = Gio.DBusProxy.new_finish(res)
            print("got foo")

--             Gio.DBusProxy.call(
--                 proxy,
--                 "Introspect",
--                 nil,
--                 Gio.DBusCallFlags.NONE,
--                 500,
--                 nil,
--                 function(conn1,res1)
--                     local ret1,err1 = proxy:call_finish(res1)
--                     if not err1 then
--                         -- Ok, lets load the introspection
--                         local ifaceinfo = Gio.DBusNodeInfo.new_for_xml(ret1.value[1]):lookup_interface(object_path)
-- 
--                         proxy:set_interface_info(ifaceinfo)
--                         proxy_ready(service_path,pathname,object_path,proxy)
--                     else
--                         --TODO
--                     end
--                 end,
--                 nil
--             )

            -- Get introspection data, no need for proxies
            bus:call(
                service_path,
                pathname,
                "org.freedesktop.DBus.Introspectable",
                "Introspect",
                nil,
                nil,
                Gio.DBusConnectionFlags.NONE,
                -1, -- Timeout
                nil, -- Cancellable
                function(conn,res,a,b,c)
                    print("got intro")
                    local ret1, err1 = bus:call_finish(res)
                    if not err1 then
                        -- Ok, lets load the introspection
                        local ifaceinfo = Gio.DBusNodeInfo.new_for_xml(ret1.value[1]):lookup_interface(object_path)

                        proxy:set_interface_info(ifaceinfo)
                        print("\n\n\nHERE")
                        proxies[service_path..pathname..object_path] = proxy
                        proxy_ready(bus,service_path,pathname,object_path,proxy)
                    else
                        --TODO
                    end
                end
            )
        end,
        nil --userdata
    )
end

local function callf(t,callback,error_callback)
    local service_path = t.__servicepath
    local pathname     = t.__pathname
    local args         = t.__args
    local object_path  = t.__objectpath --TODO extract the right info
    local method_name  = t.__parent.__name
    local bus          = common.get_bus(t.__bus)

    print("calling",method_name)

    return call_with_proxy(bus,service_path,pathname,object_path,method_name,args,proxy,error_callback)

        --TODO this probably wont be that hard to get async
--         print("ret",ret and ret.value[1],err)
--         local bus = Gio.bus_get_sync(Gio.BusType.SESSION)
--         local list = bus.list_names()
--         print("start list name",list)
--         local o = bus:get_object(t.__path)
--         print("HERE",o)

--     end
end

module.create_mt_from_name = function(name,parent)
    local ret = {
        __name        = name or "",
        __parent      = parent,
        __prevpath    = parent and rawget(parent,"__path"),
        __path        = (parent and parent.__path ~= "" and (parent.__path..".") or "") .. (name or ""),
        __bus         = parent and parent.__bus or nil,
        __pathname    = parent and rawget(parent,"__pathname"),
        __args        = parent and rawget(parent,"__args"),
        __objectpath  = parent and rawget(parent,"__objectpath"),
        __servicepath = parent and rawget(parent,"__servicepath"),
    }
    if parent then
        rawset(parent,"__next",ret)
    end
    return setmetatable(ret,{__index = idxf , __call = function(self,name,...)
        -- When :get() is used, then call
        if ret.__name == "get" then
            return callf(self,...)
        else
            -- Set a pathname
            if (not rawget(ret,"__pathname")) and type(name) == "string" then
                rawset(ret,"__servicepath",ret.__path)
                rawset(ret,"__path","")
                rawset(ret,"__pathname",name)
            else
                rawset(ret,"__objectpath",ret.__prevpath)
                rawset(ret,"__args",{name,...})
            end
--             print("SETTING NAME?",self,aa,ret,ret.__name,ret.__path,ret.__next,bb)
            return self
        end
    end})
end

return module