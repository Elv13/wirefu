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

-- This example come from the official DBus spec
local xml = [=[ <!DOCTYPE node PUBLIC '-//freedesktop//DTD D-BUS Object Introspection 1.0//EN'
  'http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd'>
<node name='/com/example/sample_object'>
  <interface name='com.example.SampleInterface'>
    <method name='Frobate'>
      <arg name='foo' type='i' direction='in'/>
      <arg name='bar' type='s' direction='out'/>
      <arg name='baz' type='a{us}' direction='out'/>
      <!--<annotation name='org.freedesktop.DBus.Deprecated' value='true'/>'-->
    </method>
    <method name='Bazify'>
      <arg name='bar' type='(iiu)' direction='in'/>
      <arg name='bar' type='v' direction='out'/>
    </method>
    <method name='Barify'>
      <arg name='bar' type='a{ss}' direction='in'/>
      <arg name='foo' type='i' direction='in'/>
      <arg name='bar' type='i' direction='out'/>
    </method>
    <method name='Mogrify'>
      <arg name='bar' type='(iiav)' direction='in'/>
    </method>
    <signal name='Changed'>
      <arg name='new_value' type='b'/>
    </signal>
    <property name='Bar' type='s' access='readwrite'/>
  </interface>
  <node name='child_of_sample_object'/>
  <node name='another_child_of_sample_object'/>
</node>]=]

--------------
--  LOGIC   --
--------------


-- This table contain all the methods (by name)
local methods = {
  Frobate = function(integer)
    print("Frobate",integer)
    return "123123123",{[12]="234234",[13]="vxcxcvxcv"}
  end,
  Barify = function(dict,int)
    print("Barify",dict.werwer,int)
    return 12
  end,
  Bazify = function()
    print("Bazify")
  end,
  Mogrify = function()
    print("Mogrify")
  end,
}


-- This table contain all peoperties getter


-- This table contain all peoperties setter


--------------
-- GVARIANT --
--------------

-- Having it properly typed would be too easy!
-- We need to do this ourself

-- local gvar_to_lua = {
--     i = function(v) return v:get_int32   () end,
--     b = function(v) return v:get_gboolean() end,
--     y = function(v) return v:get_guchar  () end,
--     n = function(v) return v:get_gint16  () end,
--     q = function(v) return v:get_guint16 () end,
--     u = function(v) return v:get_guint32 () end,
--     x = function(v) return v:get_gint64  () end,
--     t = function(v) return v:get_guint64 () end,
--     h = function(v) return v:get_gint32  () end,
--     d = function(v) return v:get_gdouble () end,
-- }
-- 
-- local function parse_gvariant(gvariant)
--   if gvariant:get_type():is_array() then
--     local ret = {}
--     for i=1,#gvariant do
--         local key,value = gvariant[i][1],gvariant[i][2]
--         if type(value) == "userdata" then
--             value = parse_gvariant(value)
--         end
--         ret[key] = value
--     end
--     return ret
--   elseif gvariant:get_type():is_tuple() then
--     local ret = {}
--     for i = 1,#gvariant do
--       local new_gvar = gvariant:get_child_value(i-1)
--       ret[#ret+1] = parse_gvariant(new_gvar)
--     end
--     return ret
--   elseif gvariant:get_type():is_basic() and gvar_to_lua[gvariant.type] then
--     return gvar_to_lua[gvariant.type](gvariant)
--   end
-- end

local introspection_data = nil

-- Get the interface_info from its name
local ifaces = {}
local function iface_lookup(name)
    if not ifaces[name] then
        local iface = introspection_data:lookup_interface('com.example.SampleInterface')
        ifaces[name] = iface
        return iface
    end
    return ifaces[name]
end

-- Get a method "out" signature
local ret_sigs = {}
local function get_method_info(interface_name,method)
    if not ret_sigs[interface_name] then
        ret_sigs[interface_name] = {}
    end
    local iface_sigs = ret_sigs[interface_name]

    if not iface_sigs[method] then
        local iface = iface_lookup(interface_name)
        if iface then
            local method_info = iface:lookup_method(method)
            if method_info then
                iface_sigs[method] = method_info
            end
        end
    end
    return iface_sigs[method]
end

-- Get a method output signature
local function get_out_signature(interface_name,method)
    local info = get_method_info(interface_name,method)
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

--------------
-- CLOSURES --
--------------


-- Called when a remote method is called
-- This closure dispatch the calls to the right function
local method_call_guard, method_call_addr = core.marshal.callback(Gio.DBusInterfaceMethodCallFunc ,
  function(conn, sender, path, interface_name,method_name,parameters,invok)
  print("A method have been called")
  if methods[method_name] then
    local rets = {methods[method_name](unpack(parameters.value))}
    local out_sig = get_out_signature(interface_name,method_name)

    local gvar = GLib.Variant(out_sig,rets)
    Gio.DBusMethodInvocation.return_value(invok,gvar)
  end
end)

-- Called when there is a property request (get the current value)
local property_get_guard, property_get_addr = core.marshal.callback(Gio.DBusInterfaceMethodCallFunc , 
  function(conn, sender, path, interface_name,method_name,parameters)
  print("Get a property")
end)

-- Called when there is a property request (set the current value)
local property_set_guard, property_set_addr = core.marshal.callback(Gio.DBusInterfaceMethodCallFunc , 
  function(conn, sender, path, interface_name,method_name,parameters)
  print("Set a property")
end)


-- Called when the bus is aquired, it is used to register the
-- XML spec
local bus_aquired = lgi.GObject.Closure(function(conn, name)
  introspection_data = Gio.DBusNodeInfo.new_for_xml(xml)
  print("The bus is aquired!")
  local iface_info = iface_lookup('com.example.SampleInterface')

  --introspection_data
  local registration_id,vat = conn:register_object (
    "/com/example/SampleInterface/Test",
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
end)

-- Called when the name is aquired
local name_aquired = lgi.GObject.Closure(function(conn, name)
  print("The name is aquired!")
end)

-- Called when the name is lost
local name_lost = lgi.GObject.Closure(function(conn, name)
  print("The name is lost!")
end)


-- First, aquire the Session bus
local owner_id = Gio.bus_own_name(Gio.BusType.SESSION,
  "com.example.SampleInterface",           --Interface name
  Gio.BusNameOwnerFlags.ALLOW_REPLACEMENT, --We want to take control of the existing service
  bus_aquired,                             --Called when the bus is aquired
  name_aquired,                            -- Called when the name is aquired
  name_lost                                -- Called when the name is lost
  --Errors handling is not implemented
)

-- This is a test app, so we start the loop directly
local main_loop = GLib.MainLoop()
main_loop.run(main_loop)

