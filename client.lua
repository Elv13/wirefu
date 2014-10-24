local lgi    = require     'lgi'
local Gio    = lgi.require 'Gio'
local core   = require     'lgi.core'
local GLib   = lgi.require 'GLib'
local common = require ("common")
local type,unpack = type,unpack

local module = {}

local pending = { calls = {}, properties = {} }
local proxies = {}
local proxy_connect = {}

local load_proxy -- Declare method

--TODO :alias() to get the object
--properties
--signals
--wildcard service check
--gained/lost
-- xcvxcvxcvx()

-- Use the introspection data to extract the method signature
local function get_in_args(info,method_name,error_callback)
    local ret = {}
    local methodinfo = info:lookup_method(method_name)
    if not methodinfo then
        if error_callback then
            error_callback("Cannot get",method_name,"introspection data")
        else
            print("Cannot get",method_name,"introspection data")
        end
        return ret
    end
    for k,v in ipairs(methodinfo.in_args) do
        ret[#ret+1] = v.signature
    end
    return ret
end

-- GDbus require the arguments to be packet into a gvar-tuple
local function format_arguments(method_name,info,args,error_callback)
    local method_def = get_in_args(info,method_name,error_callback)
    if #method_def ~= #args then
        if error_callback then
            error_callback("WARNING, invalid argument count, expected "..#method_def..", got "..#args)
        else
            print("WARNING, invalid argument count, expected "..#method_def..", got "..#args)
        end
    end
    local argsg = {}
    for k,v in ipairs(method_def) do
        argsg[#argsg+1] = GLib.Variant(v,args[k])
    end
    return GLib.Variant.new_tuple(argsg,#argsg)
end

-- Queue calls until proxies are loaded
local function add_pending_call(service_path,pathname,object_path,method_name,args,error_callback,callback)
    local hash = service_path..pathname..object_path
    local queue = pending.calls[hash]
    if not queue then
       queue = {}
       pending.calls[hash] = queue
    end
    queue[#queue+1] = {
        method         = method_name   ,
        args           = args          ,
        callback       = callback      ,
        error_callback = error_callback,
    }
    return queue
end

--TODO merge with above
local function add_pending_property(service_path,pathname,object_path,property_name,error_callback,callback)
    local hash = service_path..pathname..object_path
    local queue = pending.properties[hash]
        if not queue then
       queue = {}
       pending.properties[hash] = queue
    end
    queue[#queue+1] = {
        method         = property_name ,
        callback       = callback      ,
        error_callback = error_callback,
    }
end

local function init_proxy(bus,service_path,pathname,object_path,error_callback)
    local hash = service_path..pathname..object_path
    local proxy = proxies[hash]

    -- Set a dummy value to avoid the proxy being inited more than once
    proxies[hash] = true -- Don't init twice


    -- This need to be called only once
    if not proxy then
        load_proxy(bus,service_path,pathname,object_path,error_callback)
    end
end

local function call_with_proxy(bus,service_path,pathname,object_path,method_name,args,proxy,error_callback,callback)
    local hash = service_path..pathname..object_path
    local proxy = proxy or proxies[hash]
    if not proxy or type(proxy) == "boolean" then

        -- The proxy is not ready, add to queue --TODO this leak if there is an error
        add_pending_call(service_path,pathname,object_path,method_name,args,error_callback,callback)

        -- Start the proxy
        init_proxy(bus,service_path,pathname,object_path,error_callback)

    else

        -- The proxy is available proceed and call the method
        Gio.DBusProxy.call(
            proxy,
            method_name,
            format_arguments(method_name,proxy:get_interface_info(),args,error_callback),
            Gio.DBusCallFlags.NONE,
            500,
            nil,
            function(conn1,res1)
                local ret1,err1 = proxy:call_finish(res1)
                if not err1 then
                    --Done
                    if callback then
                        callback(unpack(ret1.value))
                    end
                elseif error_callback then
                    error_callback(err1)
                else
                    print(err1)
                end
            end
        )

    end
end

-- Get a property and call the callback
local function get_property_with_proxy(bus,service_path,pathname,object_path,property_name,args,proxy,error_callback,callback)
    --TODO use introspection to check if it exist
    local hash = service_path..pathname..object_path
    local proxy = proxies[hash]
    if not proxy or type(proxy) == "boolean" then
        add_pending_property(service_path,pathname,object_path,property_name,error_callback,callback)

        init_proxy(bus,service_path,pathname,object_path,error_callback)
    else
        local prop = proxy:get_cached_property(property_name)
        if prop then
            callback(prop.value)
        else
            if error_callback then
                error_callback(property_name.. " not found")
            else
                print(property_name.. " not found")
            end
        end
    end
end

-- Watch singals and properties changes
local function watch_signals(proxy,hash)
    local conn = proxy_connect[hash]
    if not conn then
        conn = {}
        proxy_connect[proxy] = conn
    end

    -- Watch generic property change then add filter
    proxy["on_".."g-properties-changed"]:connect(function(p,changed,invalidated)
        if changed and changed:n_children() >= 1 then
            local tuple = changed:get_child_value(0).value
            local prop,value = unpack(tuple)
            local callbacks = conn[prop]
            if callbacks then
                for k,v in ipairs(callbacks) do
                    v(value.value)
                end
            end
        end
    end)

    -- Connect to signals
    proxy["on_".."g-signal"]:connect(function(p,sender_name,signal_name,parameters)
        local callbacks = conn[signal_name]
        if callbacks then
            for k,v in ipairs(callbacks) do
                v(unpack(parameters.value))
            end
        end
    end)
end

-- Execute everything in the queue
local function proxy_ready(bus,service_path,pathname,object_path,proxy)
    local hash = service_path..pathname..object_path
    for k2,v2 in ipairs {"calls","properties"} do
        local queue = pending[v2][hash]
        if queue then
            for k,v in ipairs(queue) do
                print("foo",#queue)
                if v.args then --TODO dont
                    call_with_proxy(bus,service_path,pathname,object_path,v.method,v.args,proxy,v.error_callback,v.callback)
                else
                    get_property_with_proxy(bus,service_path,pathname,object_path,v.method,v.args,proxy,v.error_callback,v.callback)
                end
            end
            pending[v2][hash] = nil
        end
    end
    watch_signals(proxy,hash)
end

-- Create a proxy client with all necessary introspection
load_proxy = function(bus,service_path,pathname,object_path,error_callback)
    Gio.DBusProxy.new(
        bus,--Conn
        Gio.DBusProxyFlags.NONE               ,
        nil                                   ,
        service_path                          ,
        pathname                              ,
        object_path                           ,
        nil                                   ,
        function(conn,res)
            local proxy,err = Gio.DBusProxy.new_finish(res)

            -- There will be an error if the service doesn't exist
            if err then
                if error_callback then
                    error_callback(err)
                else
                    print(err)
                end
                return
            end

            -- Get introspection data, no need for proxies
            bus:call(
                service_path                         ,
                pathname                             ,
                "org.freedesktop.DBus.Introspectable",
                "Introspect"                         ,
                nil                                  ,
                nil                                  ,
                Gio.DBusConnectionFlags.NONE         ,
                -1                                   , -- Timeout
                nil                                  , -- Cancellable
                function(conn,res)
                    local ret1, err1 = bus:call_finish(res)
                    if not err1 then
                        -- Ok, lets load the introspection
                        local ifaceinfo,err2 = Gio.DBusNodeInfo.new_for_xml(ret1.value[1]):lookup_interface(object_path)

                        proxy:set_interface_info(ifaceinfo)
                        proxies[service_path..pathname..object_path] = proxy
                        proxy_ready(bus,service_path,pathname,object_path,proxy)
                    elseif error_callback then
                        error_callback("Cannot get",object_path,"introspection data, this interface cannot be used")
                    else
                        print("Cannot get",object_path,"introspection data, this interface cannot be used")
                    end
                end
            )
        end
    )
end

local function register_connect_callback(service_path,pathname,object_path,method_name,callback)
    local hash = service_path..pathname..object_path
    local conn = proxy_connect[hash]
    if not conn then
        conn = {}
        proxy_connect[hash] = conn
    end
    if not conn[method_name] then
        conn[method_name] = {}
    end
    conn[method_name][#conn[method_name]+1] = callback
end

-- Simple function to get the parameters out of the magic table
local function callf(t,callback,error_callback)
    local service_path = t.__servicepath
    local pathname     = t.__pathname
    local args         = t.__args
    local object_path  = t.__objectpath --TODO extract the right info
    local method_name  = t.__parent.__name
    local bus          = common.get_bus(t.__bus)
    local is_prop      = t.__is_property
    local is_connect   = t.__is_connect

    if is_connect then
        return register_connect_callback(service_path,pathname,object_path,method_name,callback)
    elseif is_prop then
        return get_property_with_proxy(bus,service_path,pathname,object_path,method_name,args,proxy,error_callback,callback)
    else
        return call_with_proxy(bus,service_path,pathname,object_path,method_name,args,proxy,error_callback,callback)
    end

        --TODO this probably wont be that hard to get async
--         print("ret",ret and ret.value[1],err)
--         local bus = Gio.bus_get_sync(Gio.BusType.SESSION)
--         local list = bus.list_names()
--         print("start list name",list)
--         local o = bus:get_object(t.__path)
--         print("HERE",o)

end

-- This recursive method turn a lua table into all required dbus paths
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
    return setmetatable(ret,{__index = function(t,k) return module.create_mt_from_name(k,t) end , __call = function(self,name,...)
        -- When :get() is used, then call
        if ret.__name == "get" or ret.__name == "connect" then

            -- Property calls don't have the extra `()`, so it need to be set here
            if not rawget(ret,"__objectpath") then
                rawset(ret,"__is_property",true)
                rawset(ret,"__objectpath",parent.__prevpath)
            end
            rawset(ret,"__is_connect",ret.__name == "connect")

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
            return self
        end
    end})
end

return module