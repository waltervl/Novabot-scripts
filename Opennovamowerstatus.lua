return {
    active = true,
    on = {
        timer = { 'every 1 minutes' },
		httpResponses = { "mowerStatusCallback" },
    },

    logging = {
        level = domoticz.LOG_INFO,
        marker = 'mower-status'
    },

    execute = function(domoticz, item)
        local deviceSn = 'LFIN.....'          -- change this
        local textDeviceName = 'Novabot status'     -- change this
        local alertDeviceName = 'Novabot Alert'     -- change this
        local apiUrl = 'http://<Opennovaserver>/api/dashboard/devices/' .. deviceSn -- change this

        local function toNumber(v)
            if v == nil then return nil end
            local n = tonumber(v)
            return n
        end

        local function asUpper(v)
            if v == nil then return '' end
            return tostring(v):upper()
        end

        local function isTruthy(v)
            return v == true or v == 'true' or v == '1' or v == 1
        end

        local function getBatteryPct(s)
            local n = toNumber(s.battery_power)
            if n ~= nil then return math.floor(n + 0.5) end
            n = toNumber(s.battery_capacity)
            if n ~= nil then return math.floor(n + 0.5) end
            return nil
        end

        local function getProgressPct(s)
            local mp = toNumber(s.mowing_progress)
            if mp ~= nil and mp >= 0 and mp <= 100 then
                return math.floor(mp + 0.5)
            end

            local cr = toNumber(s.cov_ratio)
            if cr ~= nil then
                if cr >= 0 and cr <= 1 then
                    return math.floor((cr * 100) + 0.5)
                elseif cr > 1 and cr <= 100 then
                    return math.floor(cr + 0.5)
                end
            end

            return nil
        end

        local function getMapLabel(s)
            local covMap = s.cov_map_path
            if covMap ~= nil and tostring(covMap) ~= '' then
                return tostring(covMap)
            end

            local id = toNumber(s.current_map_ids)
            if id ~= nil and id >= 0 then
                return 'map' .. tostring(math.floor(id))
            end

            return nil
        end

        local function roundToStep(num, step)
             -- Round to nearest multiple of step
            return math.floor((num + step / 2) / step) * step
        end

        local function hasError(s)
            local es = s.error_status
            local ec = s.error_msg

            local errStatus =
                es ~= nil and tostring(es) ~= '' and tostring(es) ~= '0' and tostring(es):upper() ~= 'OK' and tostring(es) ~= 'Error (8)'

            local errCode =
                ec ~= nil and tostring(ec) ~= '' and tostring(ec) ~= '0' and tostring(ec) ~= 'None' and tostring(ec) ~= 'Error_code: 0 Robot work fine'

            -- domoticz.log('hasErrors status: ' .. tostring(errStatus) .. ", code: " .. tostring(errCode), domoticz.LOG_INFO)
            return errStatus
        end

        local function deriveStatus(payload)
            local online = payload.online == true or payload.online == 'true' or payload.online == 1
            local s = payload.sensors or {}

            local rawbatteryPct = getBatteryPct(s)
            local batteryPct = roundToStep(rawbatteryPct, 5)
            local rawprogressPct = getProgressPct(s)
            local progressPct = roundToStep(rawprogressPct, 5)
            local mapLabel = getMapLabel(s)

            local rawWorkStatus = tostring(s.work_status)
            local workStatus = tonumber((rawWorkStatus:gsub('^%s*[Ss]tate%s+', ''))) -- remove state
            local msgstring = s.msg

            local M_Mode      = msgstring:match("Mode:%s*([%w_]+)")
            local M_Work      = msgstring:match("Work:%s*([%w_]+)")
            local M_PrevWork  = msgstring:match("Prev work:%s*([%w_]+)")
            local M_Recharge  = msgstring:match("Recharge:%s*([%w_]+)")
            local statusstring = ' '
            if workStatus ~= nil then
                statusstring = ' Work: ' .. M_Work .. ' Mode: ' .. M_Mode .. ' Workstatus: ' .. workStatus
            else
                statusstring = ' Work: ' .. M_Work .. ' Mode: ' .. M_Mode .. ' rawWorkStatus: ' .. rawWorkStatus
            end
            local rechargeStatus = s.recharge_status
            local batteryState = asUpper(s.battery_state) -- Charging

            local mappingFlag = tostring(s.start_edit_or_assistant_map_flag or '')
            local isMapping =
                mappingFlag == '1' 

            local isCharging = (batteryState == 'CHARGING') or (rechargeStatus == 'Charging (9)')
            local isCharged =
                (rechargeStatus == 'Charging (4)') or
                (batteryState == 'FINISHED') or
                (batteryState == 'FULL')

            if not online then
                return 'Offline' .. statusstring
            end

            if hasError(s) then
                statusstring = statusstring .. ' ES: ' .. s.error_status ..' EC: ' .. s.error_msg
                if isCharging then
                    return batteryPct and ('Error on dock (b' .. batteryPct .. '%)') .. statusstring or 'Error on dock' .. statusstring
                end
                if mapLabel ~= nil then
                    return 'Error on ' .. mapLabel .. ' ' .. s.error_msg
                end    
                return s.error_msg
            end

            -- if isMapping then
            --    return 'Mapping' .. statusstring
            -- end

            if isCharging then
                if batteryPct ~= nil then
                    return 'Docked and charging (b' .. batteryPct .. '%)'  -- .. statusstring
                end
                return 'Docked and charging'  -- .. statusstring
            end

            if isCharged then
                if batteryPct ~= nil then
                    return 'Docked, fully charged (b' .. batteryPct .. '%)'  -- .. statusstring
                end
                return 'Docked, fully charged'  -- .. statusstring
            end

            if rechargeStatus == 'Charging (50)' or rechargeStatus == 'Charging (53)' or rechargeStatus == 'Charging (191)' then
                if mapLabel ~= nil then
                    return 'Returning to dock from mowing ' .. mapLabel  -- .. statusstring .. ' ' .. rechargeStatus
                end
                return 'Returning to dock'  -- .. statusstring .. ' ' .. rechargeStatus
            end
            if rechargeStatus == 'Charging (193)' then
                if mapLabel ~= nil then
                    return 'Final approach to dock from mowing ' .. mapLabel  -- .. statusstring .. ' ' .. rechargeStatus
                end
                return 'Final approach to dock'  -- .. statusstring .. ' ' .. rechargeStatus
            end
            
            -- This section should do all the normal work. The rest is legacy
            if rawWorkStatus ~= nil then
                if mapLabel ~= nil and progressPct ~= nil and batteryPct ~= nil then
                    return rawWorkStatus .. ' ' .. mapLabel .. ' (m' .. progressPct .. '%' .. ' b' .. batteryPct .. '%)' -- .. statusstring
                end
                if mapLabel ~= nil then
                    return rawWorkStatus .. ' ' .. mapLabel -- .. statusstring
                end    
            end
            
            if workStatus == 53 then
                if mapLabel ~= nil and progressPct ~= nil and batteryPct ~= nil then
                    return 'Starting mowing ' .. mapLabel .. ' (m' .. progressPct .. '%' .. ' b' .. batteryPct .. '%)' -- .. statusstring
                end
                if mapLabel ~= nil then
                    return 'Starting mowing  ' .. mapLabel  -- .. statusstring
                end
                return 'Starting mowing'  -- .. statusstring
            end
            
            if workStatus == 51 or workStatus == 52 or rechargeStatus == 2 then
                return 'Docking'  .. statusstring
            end
            
            if workStatus == 56  then
                return 'Backing out of Docking'  -- .. statusstring
            end  
            
            if workStatus == 59  then
                return 'Initiate mowing session'  -- .. statusstring
            end
            
            if workStatus == 101 or workStatus == 93 then
                if mapLabel ~= nil and progressPct ~= nil and batteryPct ~= nil then
                    return 'Boundary mowing ' .. mapLabel .. ' (m' .. progressPct .. '%' .. ' b' .. batteryPct .. '%)'   -- .. statusstring
                end
                if mapLabel ~= nil and progressPct ~= nil then
                    return 'Boundary mowing ' .. mapLabel .. ' (m' .. progressPct .. '%)'   -- .. statusstring
                end
                if mapLabel ~= nil then
                    return 'Boundary mowing ' .. mapLabel  -- .. statusstring
                end
                return 'Boundary mowing'  -- .. statusstring
            end

            if workStatus == 103 or workStatus == 92 then
                if mapLabel ~= nil and progressPct ~= nil and batteryPct ~= nil then
                    return 'Moving to next section of ' .. mapLabel .. ' (m' .. progressPct .. '%' .. ' b' .. batteryPct .. '%)' -- .. statusstring
                end
                if mapLabel ~= nil then
                    return 'Moving to next section of ' .. mapLabel  -- .. statusstring
                end
                return 'Moving to next section'  -- .. statusstring
            end
            
            if workStatus == 91  then
                if mapLabel ~= nil and progressPct ~= nil and batteryPct ~= nil then
                    return 'Avoiding obstacle in ' .. mapLabel .. ' (m' .. progressPct .. '%' .. ' b' .. batteryPct .. '%)' -- .. statusstring
                end
                if mapLabel ~= nil then
                    return 'Avoiding obstacle in ' .. mapLabel -- .. statusstring
                end
                return 'Avoiding obstacle'  -- .. statusstring
            end
            if workStatus == 94  then
                if mapLabel ~= nil then
                    return 'Moving over no grass in ' .. mapLabel -- .. statusstring
                end
                return 'Moving over no grass' -- .. statusstring
            end
            if workStatus == 95  then
                if mapLabel ~= nil then
                    return 'Finished mowing ' .. mapLabel  -- .. statusstring
                end
                return 'Finished mowing'  -- .. statusstring
            end
            if workStatus == 96  then
                if mapLabel ~= nil then
                    return 'Finished mowing once' .. mapLabel  -- .. statusstring
                end
                return 'Finished mowing once'  -- .. statusstring
            end
            if workStatus == 102 then
                if mapLabel ~= nil then
                    return 'Finishing missed spots on ' .. mapLabel  -- .. statusstring
                end
                return 'Finishing missed spots'  -- .. statusstring
            end

            if workStatus == 100 or workStatus == 1 or workStatus == 90 then
                if mapLabel ~= nil and progressPct ~= nil and batteryPct ~= nil then
                    return 'Mowing ' .. mapLabel .. ' (m' .. progressPct .. '%' .. ' b' .. batteryPct .. '%)'  -- .. statusstring
                end
                 if mapLabel ~= nil and progressPct ~= nil then
                    return 'Mowing ' .. mapLabel .. ' (m' .. progressPct .. '%)'  -- .. statusstring
                end
                if mapLabel ~= nil then
                    return 'Mowing ' .. mapLabel  -- .. statusstring
                end
                if progressPct ~= nil then
                    return 'Mowing (m' .. progressPct .. '%)'  -- .. statusstring
                end
                return 'Mowing' .. statusstring
            end

            if workStatus == 72 or workStatus == 84 or workStatus == 85 or workStatus == 86 or workStatus == 87 or workStatus == 88 then
                if mapLabel ~= nil then
                    return 'Paused on ' .. mapLabel  -- .. statusstring
                end
                return 'Paused' .. statusstring
            end
           
            if M_Work == 'USER_STOP' then
                if batteryPct ~= nil then
                    return 'User Paused (b' .. batteryPct .. '%)'  -- .. statusstring
                end
                return 'User Paused'
            end
            if M_Work == 'CANCELLED' then
                if batteryPct ~= nil then
                    return 'Mowing cancelled (b' .. batteryPct .. '%)'  -- .. statusstring
                end
                return 'Mowing cancelled'
            end
            
            if batteryPct ~= nil then
                return 'Unknown (b' .. batteryPct .. '%)'  .. statusstring
            end

            return 'Unknown final' .. statusstring
        end

        local function getMowerData()
            domoticz.openURL({
                url = apiUrl,
             method = 'GET',
                callback = 'mowerStatusCallback'
            })
            -- domoticz.log('get HTTP mower status from: ' .. apiUrl, domoticz.LOG_INFO)
            domoticz.openURL({
                url = apiUrl,
             method = 'GET',
                callback = 'mowerStatusCallback'
            }).afterSec(10)
            domoticz.openURL({
                url = apiUrl,
             method = 'GET',
                callback = 'mowerStatusCallback'
            }).afterSec(20)
            domoticz.openURL({
                url = apiUrl,
             method = 'GET',
                callback = 'mowerStatusCallback'
            }).afterSec(30)
            domoticz.openURL({
                url = apiUrl,
             method = 'GET',
                callback = 'mowerStatusCallback'
            }).afterSec(40)
            domoticz.openURL({
                url = apiUrl,
             method = 'GET',
                callback = 'mowerStatusCallback'
            }).afterSec(50)
        end


        local function processMowerData(response)
            local textDevice = domoticz.devices(textDeviceName)
            local alertDevice = domoticz.devices(alertDeviceName)
            local alertDeviceLevel = alertDevice.color
            if textDevice == nil then
                domoticz.log('Text device not found: ' .. textDeviceName, domoticz.LOG_ERROR)
                return
            end

            if response == nil then
                domoticz.log('No HTTP response received', domoticz.LOG_ERROR)
                textDevice.updateText('API error')
                return
            end

            if response.isJSON == false then
                domoticz.log('Response was not JSON', domoticz.LOG_ERROR)
                textDevice.updateText('API error')
                return
            end

            if response.statusCode ~= 200 then
                domoticz.log('Opennova HTTP API error: ' .. tostring(response.statusCode), domoticz.LOG_ERROR)
                textDevice.updateText('Opennova API error ' .. tostring(response.statusCode))
                return
            end

            local statusText = deriveStatus(response.json)
            textDevice.updateText(statusText)
            domoticz.log('Updated mower status: ' .. statusText, domoticz.LOG_INFO)
            -- Alert sensor
            --color: Number. Color of the alert. See domoticz color constants for possible values.
            -- text: String
            -- updateAlertSensor(level, text): Function. Level can be domoticz.ALERTLEVEL_GREY 0, ALERTLEVEL_GREEN 1, ALERTLEVEL_YELLOW 2 , ALERTLEVEL_ORANGE 3, ALERTLEVEL_RED 4
            -- domoticz.log('current alert level; ' .. alertDeviceLevel, domoticz.LOG_INFO)
            if string.match(statusText, "Error_code:") and alertDeviceLevel ~= 4 then
                alertDevice.updateAlertSensor(domoticz.ALERTLEVEL_RED, statusText)
            elseif string.match(statusText, "Returning to dock") and alertDeviceLevel ~= 2 then 
                alertDevice.updateAlertSensor(domoticz.ALERTLEVEL_YELLOW, 'Mower Finished Mowing')
            elseif  alertDeviceLevel ~= 1 and not string.match(statusText, "Returning to dock") and not string.match(statusText, "Error_code:") then
                alertDevice.updateAlertSensor(domoticz.ALERTLEVEL_GREEN, 'Mower OK')
            else
                -- do nothing
            end    
        end
        
        -- Main
		 if item.isTimer then
            --checkWebpageResponse()
            getMowerData()
        elseif item.ok then -- statusCode == 2xx
            processMowerData(item)
        else
            domoticz.log('Could not get (good) data from ' .. apiUrl,dz.LOG_STATUS)
            domoticz.log(item.data,dz.LOG_DEBUG)
        end
    end
}
