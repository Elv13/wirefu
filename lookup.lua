local wirefu = require("wirefu")

local capi = { timer  = timer  }

local module = {}

local function new()

        local dbusWirefu = wirefu.SESSION.org.freedesktop.DBus("/").org.freedesktop.DBus
        
        
        --Functions------------------------------
        
        -- Asynchronus getter for service name list
        -- callback = function  (namelist:)
        -- error_callback =
        -- match = patter to match
        module.getServices = function(callback,match,error_callback)
                if callback then
                        --Async call
                        dbusWirefu.ListNames():get(function (nameList)
                                        --If no pattern set just call callback
                                        if not match then callback(nameList)
                                        else
                                                local filtered = {}
                                                for i=1,#nameList do
                                                        if string.match(nameList[i],match) then
                                                                table.insert(filtered,nameList[i])
                                                        end
                                                end
                                                callback(filtered)
                                        end
                                end,error_callback)

                end
        end

end

return setmetatable(module, { __call = function(_, ...) return new(...) end })