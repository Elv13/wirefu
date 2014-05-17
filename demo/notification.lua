local service = module.create_service("org.freedesktop.Notifications",[=[<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object
    Introspection 1.0//EN"
    "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
    <node>
      <interface name="org.freedesktop.DBus.Introspectable">
        <method name="Introspect">
          <arg name="data" direction="out" type="s"/>
        </method>
      </interface>
      <interface name="org.freedesktop.Notifications">
        <method name="GetCapabilities">
          <arg name="caps" type="as" direction="out"/>
        </method>
        <method name="CloseNotification">
          <arg name="id" type="u" direction="in"/>
        </method>
        <method name="Notify">
          <arg name="app_name" type="s" direction="in"/>
          <arg name="id" type="u" direction="in"/>
          <arg name="icon" type="s" direction="in"/>
          <arg name="summary" type="s" direction="in"/>
          <arg name="body" type="s" direction="in"/>
          <arg name="actions" type="as" direction="in"/>
          <arg name="hints" type="a{sv}" direction="in"/>
          <arg name="timeout" type="i" direction="in"/>
          <arg name="return_id" type="u" direction="out"/>
        </method>
        <method name="GetServerInformation">
          <arg name="return_name" type="s" direction="out"/>
          <arg name="return_vendor" type="s" direction="out"/>
          <arg name="return_version" type="s" direction="out"/>
          <arg name="return_spec_version" type="s" direction="out"/>
        </method>
        <method name="GetServerInfo">
          <arg name="return_name" type="s" direction="out"/>
          <arg name="return_vendor" type="s" direction="out"/>
          <arg name="return_version" type="s" direction="out"/>
       </method>
      </interface>
    </node>]=])


function service:GetCapabilities()
    return { "s", "body", "s", "body-markup", "s", "icon-static" }
end

function service:Notify(app_name, type, id, icon, summary, body, actions, hints, timeout, return_id)
    print("NEW NOTIF",app_name,summary,body)
    return 12
end

function service:CloseNotification()
    return --TODO
end

function service:GetServerInfo()
    return "naughty", "awesome", awesome.version:match("%d.%d")
end


function service:GetServerInformation()
    local a,b,c = service:GetServerInfo()
    return a,b,c, "1.0"
end

function service.properties.get_Bar(service)
    print("property getter!")
    return "foo"
end

service:register_object("/org/freedesktop/Notifications")
-- service:register_object("/com/example/SampleInterface/Test2")


--TODO check if a mainloop and running or start one

-- This is a test app, so we start the loop directly
local main_loop = GLib.MainLoop()
main_loop:run()