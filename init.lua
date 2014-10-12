-- Links:
-- * DBus spec: http://dbus.freedesktop.org/doc/dbus-specification.html
-- * GVariant API: https://developer.gnome.org/glib/stable/glib-GVariantType.html
-- * More GVariant info: https://developer.gnome.org/glib/stable/gvariant-format-strings.html

--TODO:
-- Create service object, use function myservice:my_method(sdfsdfs,sdfsdf) end
-- function myservice.property:get_foo() return dsfdfg end
-- add way to call methods after getting a service object
-- handle signals myservice:connect_signal("foo",function(43534,345) end)

local lgi  = require     'lgi'
local Gio  = lgi.require 'Gio'
local core = require     'lgi.core'
local GLib = lgi.require 'GLib'
local type,unpack = type,unpack

--------------
--  LOGIC   --
--------------

-- Get the interface_info from its name
local ifaces = {}
local function iface_lookup(service,name)
    if not ifaces[name] then
        local iface = service.introspection_data:lookup_interface(service.iname)
        ifaces[name] = iface
        return iface
    end
    return ifaces[name]
end

-- Get a method information

local function common_get_info(service,cache,interface_name,method,func)
    if not cache[interface_name] then
        cache[interface_name] = {}
    end
    local iface_sigs = cache[interface_name]

    if not iface_sigs[method] then
        local iface = service:iface_lookup(interface_name)
        if iface then
            local info = iface[func](iface,method)
            if info then
                iface_sigs[method] = info
                return info
            end
        end
    end
    return iface_sigs[method]
end

local function get_property_info(service,interface_name,property)
    local prop_info = {}
    return service:common_get_info(prop_info,interface_name,property,"lookup_property")
end

local function get_method_info(service,interface_name,method)
    local method_info = {}
    return service:common_get_info(method_info,interface_name,method,"lookup_method")
end

local function get_signal_info(service,interface_name,signal)
    local sign_info = {}
    return service:common_get_info(sign_info,interface_name,signal,"lookup_signal")
end



-- Get a method output signature
local function get_out_signature(service,interface_name,method)
    local info = service:get_method_info(interface_name,method)
    if info then
        local ret_t = "("
        for k,v in pairs(info.out_args or {}) do
            ret_t = ret_t .. v.signature
        end
        ret_t = ret_t .. ")"
        return ret_t --TODO add a cache for this
    end
    return ""
end

-----------------------
--  Service methods  --
-----------------------

local function register_object(service,name)
    --------------
    -- CLOSURES --
    --------------


    -- Called when a remote method is called
    -- This closure dispatch the calls to the right function
    local method_call_guard, method_call_addr = core.marshal.callback(Gio.DBusInterfaceMethodCallFunc ,
    function(conn, sender, path, interface_name,method_name,parameters,invok)
        -- Only call if the method have been defined
        print("I get here2")
        if service[method_name] then
            local rets = {service[method_name](service,unpack(parameters.value))}
            local out_sig = service:get_out_signature(interface_name,method_name)

            local gvar = GLib.Variant(out_sig,rets)
            Gio.DBusMethodInvocation.return_value(invok,gvar)
        else
            print("Trying to call "..method_name..[=[ but no implementation was found\n
                please implement myService:]=]..method_name.."(arg1,arg2)")
        end
    end)

    -- Called when there is a property request (get the current value)
    local property_get_guard, property_get_addr = core.marshal.callback(Gio.DBusInterfaceGetPropertyFunc , 
    function(conn, sender, path, interface_name,property_name,parameters,error)
        print("I get here")
        local sig = service:get_property_info(interface_name,property_name).signature
        if service.properties["get_"..property_name] then
            return GLib.Variant(sig,service.properties["get_"..property_name](service))
        else
            print("Trying to read "..property_name..[=[ but no getter was found\n
                please implement myService.properties.get_]=]..property_name)
        end
        return GLib.Variant(sig)
    end)

    -- Called when there is a property request (set the current value)
    local property_set_guard, property_set_addr = core.marshal.callback(Gio.DBusInterfaceSetPropertyFunc , 
    function(conn, sender, path, interface_name,method_name,parameters)
        print("Set a property")
    end)

    local function on_conn_aquired(conn,iname)
        service.introspection_data = Gio.DBusNodeInfo.new_for_xml(service.xml)
        print("The bus is aquired!")
        local iface_info = iface_lookup(service,service.iname)

        --introspection_data
        conn:register_object (
            name,
            iface_info,
            Gio.DBusInterfaceVTable({
            method_call   = method_call_addr ,
            get_property  = property_get_addr,
            set_property  = property_get_addr,
            }),
            {},  --/* user_data */
            lgi.GObject.Closure(function()
                print("Closing the object")
            end),  --/* user_data_free_func */
            lgi.GObject.Closure(function()
                print("There was an error")
            end)
        )
    end
    if service.conn then
        on_conn_aquired(service.conn,service.iname)
    else
        service.on_connection_aquired = on_conn_aquired
    end
end


--------------------
--  Module gears  --
--------------------

local module = {}

-- Create a new service
function module.create_service(iname,xml_introspection)

    --Setup object
    local service = {properties = {},iname = iname,introspection_data=nil,
        get_out_signature = get_out_signature,
        get_property_info = get_property_info,
        get_method_info   = get_method_info,
        common_get_info   = common_get_info,
        iface_lookup      = iface_lookup,
        register_object   = register_object,
        xml               = xml_introspection
    }

    print("attempting to create a server")
    -- Called when the bus is aquired, it is used to register the
    -- XML spec
    local bus_aquired = lgi.GObject.Closure(function(conn, name)
        service.connection = conn
        if service.on_connection_aquired then
            service.on_connection_aquired(conn,name)
            service.on_connection_aquired = nil
        end
    end)

    -- Called when the name is aquired
    local name_aquired = lgi.GObject.Closure(function(conn, name,c,d,e)
        print("The name is aquired!",c,d,e)
    end)

    -- Called when the name is lost
    local name_lost = lgi.GObject.Closure(function(conn, name)
        print("The name is lost!",name)
    end)


    -- First, aquire the Session bus
    local owner_id = Gio.bus_own_name(Gio.BusType.SESSION,
    iname,                                   --Interface name
    Gio.BusNameOwnerFlags.REPLACE, --We want to take control of the existing service
    bus_aquired,                             --Called when the bus is aquired
    name_aquired,                            -- Called when the name is aquired
    name_lost                                -- Called when the name is lost
    --Errors handling is not implemented
    )
    return service
end

-------------------------------
--  Name construction gears  --
-------------------------------

local create_mt_from_name = nil

local busses,bus_queue = {},{[Gio.BusType.SESSION]={},[Gio.BusType.SYSTEM]={}}
local function get_bus(bus_name)
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

local function idxf(t,k)
    return create_mt_from_name(k,t)
end

local function callf(t,callback,error_callback)
    local service_path = t.__servicepath
    local pathname     = t.__pathname
    local args         = t.__args
    local object_path  = service_path --TODO extract the right info
    local method_name  = t.__parent.__name
    print("Calling:",service_path,pathname,object_path, method_name)
    local bus = get_bus(t.__bus)
    if not bus then
        bus_queue[t.__bus][#bus_queue[t.__bus]+1] = function(b)
            local o = b:get_object(t.__path)
            --TODO implement bus_queue callback
        end
    else
--         print("alice",bus,bus.call_sync)
--         bus:call_sync("org.freedesktop.UPower","/org/freedesktop/UPower","org.freedesktop.UPower","HibernateAllowed",GLib.Variant(""))
        local ret,err = bus:call(
            service_path,
            pathname,
            object_path,
            method_name,
            nil,
            nil,
            Gio.DBusConnectionFlags.NONE,
            -1, -- Timeout
            nil, -- Cancellable
            function(conn,res,a,b,c)
                local ret, err = bus:call_finish(res)
--                 print("async",conn,Gio.SimpleAsyncResult.get_op_res_gpointer,res:get_op_res_gssize(),
-- 		"sdfsdf ",a,b,c)
                if callback then
                    callback(unpack(ret.value))
                elseif error_callback then
                    error_callback(err)
                end
            end
        )
        if (not ret) and err and error_callback then
            error_callback(err)
        end
--         print("ret",ret and ret.value[1],err)
--         local bus = Gio.bus_get_sync(Gio.BusType.SESSION)
--         local list = bus.list_names()
--         print("start list name",list)
--         local o = bus:get_object(t.__path)
--         print("HERE",o)
        return {
            get = function(f)
                callback = f
            end
        }
    end
end

create_mt_from_name = function(name,parent)
    local ret = {
        __name        = name or "",
        __parent      = parent,
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
                rawset(ret,"__pathname",name)
            else
                rawset(ret,"__objectpath",ret.__path)
                rawset(ret,"__args",{name,...})
            end
--             print("SETTING NAME?",self,aa,ret,ret.__name,ret.__path,ret.__next,bb)
            return self
        end
    end})
end

module.SESSION = create_mt_from_name(  )
rawset(module.SESSION,"__bus",Gio.BusType.SESSION)
module.SYSTEM  = create_mt_from_name(  )
rawset(module.SYSTEM,"__bus",Gio.BusType.SYSTEM)


-- local gio = require("lgi").Gio
-- local bus = get_bus(Gio.BusType.SYSTEM)
-- print("BUS",bus)
-- gio.Async.call(function()
--     print(bus:async_call(
--         'org.freedesktop.UPower',
--         '/org/freedesktop/UPower',
--         'org.freedesktop.UPower',
--         'HibernateAllowed',
--         nil,
--         nil,
--         'NONE',
--         -1))
-- end)()

return module
