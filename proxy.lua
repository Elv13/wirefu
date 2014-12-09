local print         = print
local lgi           = require     'lgi'
local Gio           = lgi.require 'Gio'
local GLib          = lgi.require 'GLib'
local common        = require "wirefu.common"


local pending,proxies,proxy_connect = { calls = {}, properties = {}, introspect_methods = {} },{},{}

local module = {proxies=proxies,pending=pending}

local function error_handler(err,callback)
    local f = callback or print
    f(err)
end

-- Register a future proxy in the queue
local function init_proxy(bus,service_path,pathname,object_path,error_callback)
    local hash = service_path..pathname..object_path
    local proxy = proxies[hash]

    -- Set a dummy value to avoid the proxy being inited more than once
    if not proxy then
        proxies[hash] = true
    end


    -- This need to be called only once
    if not proxy then
        module.load_proxy(bus,service_path,pathname,object_path,error_callback)
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

-- Add signal or property to the callback queue
function module.register_connect_callback(bus,service_path,pathname,object_path,method_name,callback)
    local hash = service_path..pathname..object_path
    local proxy = proxy or proxies[hash]
    if not proxy then
        init_proxy(bus,service_path,pathname,object_path,error_callback)
    end
    local conn = proxy_connect[hash]
    if not conn then
        conn = {}
        proxy_connect[hash] = conn
        if proxy and type(proxy) ~= "boolean" then
            watch_signals(proxy,hash)
        end
    end
    if not conn[method_name] then
        conn[method_name] = {}
    end
    conn[method_name][#conn[method_name]+1] = callback
end

-- Use the introspection data to extract the method signature
local function get_in_args(info,method_name,error_callback)
    local ret = {}
    local methodinfo = info:lookup_method(method_name)
    if not methodinfo then
        error_handler("Cannot get",method_name,"introspection data",error_callback)
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
        error_handler("WARNING, invalid argument count for ".. method_name ..", expected "..#method_def..", got "..#args.." ffff"..method_def[1],error_callback)
        return GLib.Variant.new_tuple({},0)
    end
    local argsg = {}
    for k,v in ipairs(method_def) do
        argsg[#argsg+1] = GLib.Variant(v,args[k])
    end
    return GLib.Variant.new_tuple(argsg,#argsg)
end

-- Queue calls or properties until proxies are loaded
local function add_pending_call(pending_type,service_path,pathname,object_path,method_name,args,error_callback,callback)
    local hash = service_path..pathname..object_path
    local queue = pending[pending_type][hash]
    if not queue then
       queue = {}
       pending[pending_type][hash] = queue
    end
    queue[#queue+1] = {
        method         = method_name   ,
        args           = args          ,
        callback       = callback      ,
        error_callback = error_callback,
    }
    return queue
end

-- Get a property and call the callback
function module.get_property_with_proxy(bus,service_path,pathname,object_path,property_name,args,proxy,error_callback,callback)
    --TODO use introspection to check if it exist
    local hash  = service_path..pathname..object_path
    local proxy = proxies[hash]
    if not proxy or type(proxy) == "boolean" then
        add_pending_call("properties",service_path,pathname,object_path,property_name,nil,error_callback,callback)

        init_proxy(bus,service_path,pathname,object_path,error_callback)
    else
        local prop = proxy:get_cached_property(property_name)
        if prop then
            callback(prop.value)
        else
            error_handler(property_name.. " not found",error_callback)
        end
    end
end


-- Call a method using a registered proxy
function module.call_with_proxy(bus,service_path,pathname,object_path,method_name,args,proxy,error_callback,callback)
    local hash = service_path..pathname..object_path
    local proxy = proxy or proxies[hash]
    if not proxy or type(proxy) == "boolean" then

        -- The proxy is not ready, add to queue --TODO this leak if there is an error
        add_pending_call("calls",service_path,pathname,object_path,method_name,args,error_callback,callback)

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
                else
                    error_handler(err1,error_callback)
                end
            end
        )

    end
end

-- Get all methods stored in an object_path
function module.get_methods_with_proxy(bus,service_path,pathname,object_path,__,___,proxy,error_callback,callback)

    local hash = service_path..pathname..object_path
    local proxy = proxy or proxies[hash]

    if not proxy or type(proxy) == "boolean" then

        -- The proxy is not ready, add to queue --TODO this leak if there is an error
        add_pending_call("introspect_methods",service_path,pathname,object_path,method_name,args,error_callback,callback)

        -- Start the proxy
        init_proxy(bus,service_path,pathname,object_path,error_callback)
    else
        local introspect = proxy:get_interface_info()
        if not introspect then
            error_handler(object_path.. " not found",error_callback)
        end
        introspect:cache_build()
        local ret = {}

        --TODO store names as keys and an info metatable as value
        for k,v in ipairs(introspect.methods) do
            ret[#ret+1] = v.name
        end
        callback(ret)
    end
end

-- Execute everything in the queue
local function proxy_ready(bus,service_path,pathname,object_path,proxy)
    local hash = service_path..pathname..object_path

    for k2,v2 in pairs {
        calls              = module.call_with_proxy,
        properties         = module.get_property_with_proxy,
        introspect_methods = module.get_methods_with_proxy,
    } do
        local queue = pending[k2][hash]
        if queue then
            for k,v in ipairs(queue) do
                v2(bus,service_path,pathname,object_path,v.method,v.args,proxy,v.error_callback,v.callback)
            end
            pending[k2][hash] = nil
        end
    end
    if proxy_connect[hash] then
        watch_signals(proxy,hash)
    end
end

-- Create a proxy client with all necessary introspection
function module.load_proxy(bus,service_path,pathname,object_path,error_callback)
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
                return error_handler(err,error_callback)
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
                    else
                        error_handler("Cannot get "..object_path.." introspection data, this interface cannot be used",error_callback)
                    end
                end
            )
        end
    )
end

return module