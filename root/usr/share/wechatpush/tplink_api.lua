-- Read-only TP-LINK R-series protocol. No router configuration actions.
local M = {}

local function units(s)
    local out, i = {}, 1
    while i <= #s do
        local a, n, cp = s:byte(i), 1, s:byte(i)
        if a >= 240 then n, cp = 4, a - 240
        elseif a >= 224 then n, cp = 3, a - 224
        elseif a >= 192 then n, cp = 2, a - 192 end
        for j = 1, n - 1 do cp = cp * 64 + ((s:byte(i+j) or 128) - 128) end
        if cp > 65535 then
            cp = cp - 65536
            out[#out+1] = 55296 + math.floor(cp / 1024)
            out[#out+1] = 56320 + cp % 1024
        else out[#out+1] = cp end
        i = i + n
    end
    return out
end

function M.encode(password)
    local key = units('RDpbLfCPsJZ7fiv')
    local dict = 'yLwVl0zKqws7LgKPRQ84Mdt708T1qQ3Ha7xv3H7NyU84p21BriUWBU43odz3iP4rBL3cD' ..
        '02KZciXTysVXiV8ngg6vL48rPJyAUw0HurW20xqxv9aYb4M9wK1Ae0wlro510qXeU07kV57fQMc8L6aLg' ..
        'MLwygtc0F10a0Dg70TOoouyFhdysuRMO51yY5ZlOZZLEal1h0t9YQW0Ko7oBwmCAHoic4HYbUyVeU3sfQ' ..
        '1xtXcPcf1aT303wAQhv66qzW'
    local pwd, out = units(password), {}
    for i = 1, math.max(#pwd, #key) do
        local a, b, x, bit = pwd[i] or 187, key[i] or 187, 0, 1
        while a > 0 or b > 0 do
            if a % 2 ~= b % 2 then x = x + bit end
            a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
        end
        local index = x % #dict + 1
        out[#out+1] = dict:sub(index, index)
    end
    return table.concat(out)
end

function M.mac(value)
    if type(value) ~= 'string' then return nil end
    value = value:lower():gsub('-', ':')
    if value:match('^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$') then return value end
end

function M.state(cache, mac, now)
    local key = M.mac(mac) or ''
    if type(cache) ~= 'table' or type(cache.wireless) ~= 'table' or not cache.wireless[key] then return 'unmanaged' end
    if type(cache) ~= 'table' or cache.state ~= 'connected' or
        type(cache.updated_at) ~= 'number' or now < cache.updated_at or
        now - cache.updated_at > 30 or type(cache.clients) ~= 'table' then return 'unknown' end
    local value = cache.clients[key]
    if value == 'offline' and cache.logs_ok == false then return 'unknown' end
    return (value == 'online' or value == 'offline') and value or 'unknown'
end

-- Require a successful observation after the 30-second disconnect window.
function M.ready(cache, mac, now)
    local state = M.state(cache, mac, now)
    if state ~= 'offline' then return state end
    local since = type(cache.offline_since) == 'table' and tonumber(cache.offline_since[M.mac(mac) or '']) or nil
    if not since or since > now or now - since < 30 or cache.updated_at < since + 30 then return 'pending' end
    return 'offline'
end

function M.disconnects(request, path, now, previous)
    local times, events = {}, {}
    previous = type(previous) == 'table' and previous or {}
    for mac, event in pairs(previous.station_events or {}) do
        if type(event) == 'table' and type(event.time)=='number' and event.time <= now and event.time >= now - 86400 then events[mac] = event end
    end
    local checked = type(previous.station_events) == 'table' and tonumber(previous.log_checked_at) or nil
    if checked and checked > now then checked = nil end
    local cutoff = math.max(now - 86400, (checked or 0) - 2)
    local page_size = checked and 100 or 500
    for page = 1, 10 do
        local data = request(path, {method='do',system={read_logs={page=tostring(page),num_per_page=tostring(page_size)}}})
        if type(data) ~= 'table' or data.error_code ~= 0 or type(data.syslog) ~= 'table' then
            error('log_query_failed', 0)
        end
        local older = false
        for _, entry in ipairs(data.syslog) do
            for _, value in pairs(entry) do
                if type(value) == 'string' then
                    local line = value:gsub('%%(%x%x)',function(v) return string.char(tonumber(v,16)) end)
                    local y,m,d,h,min,s = line:match('>(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)')
                    if y then
                        local stamp = os.time({year=tonumber(y),month=tonumber(m),day=tonumber(d),hour=tonumber(h),min=tonumber(min),sec=tonumber(s)})
                        if stamp and stamp < cutoff then older = true end
                        if stamp and stamp <= now and stamp >= now - 86400 and line:find('[WSTATION]',1,true) then
                            local mac = M.mac(line:match('STA%(MAC%s+([%x:%-]+)%)'))
                            local state = line:find('断开连接',1,true) and 'offline' or
                                ((line:find('成功连接到AP',1,true) or line:find('成功漫游到AP',1,true)) and 'online' or nil)
                            if mac and state then
                                local old = events[mac]
                                if not old or stamp > old.time or stamp == old.time and state == 'online' then
                                    events[mac] = {state=state,time=stamp}
                                end
                            end
                        end
                    end
                end
            end
        end
        if older or #data.syslog < page_size or page * page_size >= (tonumber(data.total) or math.huge) then break end
    end
    for mac, event in pairs(events) do if event.state == 'offline' then times[mac] = event.time end end
    return times, events
end

function M.recent_count(result, previous, now, logs)
    previous = type(previous) == 'table' and previous or {}
    local since, count = {}, 0
    for mac, state in pairs(result.clients) do
        if state == 'offline' then
            local stamp = type(previous.offline_since) == 'table' and tonumber(previous.offline_since[mac]) or nil
            if type(previous.clients) == 'table' and previous.clients[mac] == 'online' then stamp = now end
            if logs and logs[mac] then stamp = math.max(stamp or 0, logs[mac]) end
            if stamp and stamp <= now and stamp >= now - 86400 then since[mac] = stamp; count = count + 1 end
        end
    end
    result.offline_since, result.offline_24h = since, count
end

function M.collect(request, username, password, previous, now)
    local login = request('/', {method='do', login={username=username, password=M.encode(password)}})
    if type(login) ~= 'table' or (login.error_code == 0 and type(login.stok) ~= 'string') then
        error('invalid_response', 0)
    end
    if type(login) ~= 'table' or (login.error_code and login.error_code ~= 0) or
        type(login.stok) ~= 'string' or not login.stok:match('^%x+$') then
        error('authentication_failed', 0)
    end
    local path = '/stok=' .. login.stok .. '/ds'
    local ok, result = pcall(request, path, {method='get', host_management={table={'host_info'}}})
    local logs, station_events, log_checked_at
    if ok and now then
        local log_ok, history, events = pcall(M.disconnects, request, path, now, previous)
        if log_ok then logs, station_events, log_checked_at = history, events, now end
    end
    -- Always release the authenticated session, including query failures.
    pcall(request, path, {method='do', system={logout=false}})
    if not ok then error('query_failed', 0) end
    if type(result) ~= 'table' or result.error_code ~= 0 or
        type(result.host_management) ~= 'table' or type(result.host_management.host_info) ~= 'table' then
        error('invalid_response', 0)
    end
    local clients, online, offline = {}, 0, 0
    local wireless, wired, details = {}, {}, {}
    for mac, value in pairs(type(previous)=='table' and previous.wireless or {}) do if value then wireless[mac] = true end end
    local function add(row)
        if type(row) ~= 'table' then error('invalid_response', 0) end
        local mac = M.mac(row.mac)
        if not mac then return end
        if row.type == 'wireless' then wireless[mac] = true elseif row.type == 'wired' then wired[mac] = true end
        local function text(value)
            return type(value)=='string' and value:gsub('%%(%x%x)',function(v) return string.char(tonumber(v,16)) end) or ''
        end
        if row.state == 'online' then
            details[mac] = {mac=mac,name=text(type(row.hostname)=='string' and row.hostname ~= '' and row.hostname or row.origin_hostname),
                ip=text(row.ip),ap=text(row.ap_name),ssid=text(row.ssid),interface=text(row.interface),connected_at=text(row.connect_date)}
        end
        local state = (row.state == 'online' or row.state == 'offline') and row.state or 'unknown'
        -- Conflicting records must never produce an offline confirmation.
        local previous = clients[mac]
        if previous and previous ~= state then
            state = (previous == 'online' or state == 'online') and 'online' or 'unknown'
        end
        clients[mac] = state
    end
    for _, entry in ipairs(result.host_management.host_info) do
        if type(entry) ~= 'table' then error('invalid_response', 0) end
        if entry.mac then add(entry) else for _, row in pairs(entry) do add(row) end end
    end
    -- Unsaved wireless clients disappear from host_info on disconnect. Only an
    -- explicit latest disconnect event may confirm these missing MACs offline.
    if station_events then
        for mac, event in pairs(station_events) do
            wireless[mac] = true
            local observed_online = type(previous)=='table' and type(previous.clients)=='table' and previous.clients[mac]=='online' and tonumber(previous.updated_at) or nil
            if clients[mac] == nil and event.state == 'offline' and (not observed_online or event.time > observed_online) then clients[mac] = 'offline' end
            -- A newer connection/roam cancels an old offline host-table entry too.
            if clients[mac] == 'offline' and event.state == 'online' then clients[mac] = 'unknown' end
        end
    end
    for mac in pairs(wired) do wireless[mac] = nil end
    for mac in pairs(clients) do if not wireless[mac] then clients[mac] = nil end end
    for _, state in pairs(clients) do
        if state == 'online' then online = online + 1 elseif state == 'offline' then offline = offline + 1 end
    end
    local online_clients = {}
    for mac, detail in pairs(details) do
        if wireless[mac] and clients[mac] == 'online' then online_clients[#online_clients+1] = detail end
    end
    table.sort(online_clients,function(a,b) return a.mac < b.mac end)
    local output = {logs_ok=station_events ~= nil, online_clients=online_clients, state='connected', clients=clients, wireless=wireless, online=online, offline=offline}
    if now then
        M.recent_count(output, previous, now, logs)
        output.log_checked_at = log_checked_at or (previous and previous.log_checked_at)
        output.station_events = station_events or (previous and previous.station_events)
    end
    return output
end

return M
