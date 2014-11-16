local lgi           = require     'lgi'
local Gio           = lgi.require 'Gio'
local GLib          = lgi.require 'GLib'
local common        = require "wirefu.common"
local introspection = require "wirefu.introspection"
local proxy2        = require "wirefu.proxy"
local type,unpack = type,unpack

local module = {}


--TODO :alias() to get the object
--wildcard service check
--gained/lost

local function error_handler(err,callback)
    local f = callback or print
    f(err)
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

    --print("BAR",method_name,"connect:",is_connect,"property:",is_prop)
    if is_connect then
        return proxy2.register_connect_callback(bus,service_path,pathname,object_path,method_name,callback)
    elseif is_prop then
        return proxy2.get_property_with_proxy(bus,service_path,pathname,object_path,method_name,args,proxy,error_callback,callback)
    else
        return proxy2.call_with_proxy(bus,service_path,pathname,object_path,method_name,args,proxy,error_callback,callback)
    end
end

local reserved_names = {
    get                    = callf                    ,
    connect                = callf                    ,
    introspect_methods     = introspection.method     ,
    introspect_properties  = introspection.properties ,
    introspect_signals     = introspection.signals    ,
    introspect_annotations = introspection.annotations,
}

-- This recursive method turn a lua table into all required dbus paths
module.create_mt_from_name = function(name,parent)
    local ret = {
        __name        = name or ""                                                                     ,
        __parent      = parent                                                                         ,
        __prevpath    = parent and rawget(parent,"__path")                                             ,
        __path        = (parent and parent.__path ~= "" and (parent.__path..".") or "") .. (name or ""),
        __bus         = parent and parent.__bus or nil                                                 ,
        __pathname    = parent and rawget(parent,"__pathname")                                         ,
        __args        = parent and rawget(parent,"__args")                                             ,
        __objectpath  = parent and rawget(parent,"__objectpath")                                       ,
        __servicepath = parent and rawget(parent,"__servicepath")                                      ,
        __is_property = parent and rawget(parent,"__is_property") or false                             ,
    }
    if parent then
        rawset(parent,"__next",ret)
    end
    return setmetatable(ret,{__index = function(t,k) return module.create_mt_from_name(k,t) end , __call = function(self,name,...)
        -- When :get() is used, then call
        if reserved_names[ret.__name] then

            -- Property calls don't have the extra `()`, so it need to be set here
            if not rawget(ret,"__objectpath") then
                rawset(ret,"__is_property",true)
                rawset(ret,"__objectpath",parent.__prevpath)
            end
            rawset(ret,"__is_connect",ret.__name == "connect")

            return reserved_names[ret.__name](self,...)
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