#!/usr/bin/lua
-- Credentials, cookies and stok remain outside the LuCI-readable cache.
package.path = '/usr/share/wechatpush/?.lua;' .. package.path
local api = require 'tplink_api'
local json = require 'luci.jsonc'
local fs = require 'nixio.fs'
local nixio = require 'nixio'
local cache = '/tmp/wechatpush/tplink_status.json'
if arg[1] == 'state' or arg[1] == 'ready' then
    io.write((arg[1] == 'ready' and api.ready or api.state)(json.parse(fs.readfile(cache) or ''), arg[2], os.time()))
    return
end
local uci = require('luci.model.uci').cursor()
local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function publish(data)
    data.updated_at = data.updated_at or os.time()
    local temp = cache .. '.' .. nixio.getpid()
    if fs.writefile(temp, json.stringify(data)) then fs.rename(temp, cache) end
end
if uci:get('wechatpush', 'config', 'tplink_enable') ~= '1' then
    fs.unlink(cache)
    return
end
local old = json.parse(fs.readfile(cache) or '')
local interval = type(old) == 'table' and old.state == 'authentication_failed' and 60 or 10
if type(old) == 'table' and type(old.updated_at) == 'number' and
    os.time() >= old.updated_at and os.time() - old.updated_at < interval and
    (old.state ~= 'connected' or old.offline_24h ~= nil and old.wireless ~= nil) then return end

local host = uci:get('wechatpush', 'config', 'tplink_host') or '192.168.0.1'
local username = uci:get('wechatpush', 'config', 'tplink_username') or ''
local password = uci:get('wechatpush', 'config', 'tplink_password') or ''
local valid = host:match('^%d+%.%d+%.%d+%.%d+$')
for part in host:gmatch('%d+') do if tonumber(part) > 255 then valid = false end end
if not valid or username == '' or password == '' then
    publish({state='configuration_error', wireless=type(old)=='table' and old.wireless or nil, clients={}})
    return
end

-- Multiple existing scan/push workers may run concurrently. Never overlap logins.
local lock = '/tmp/wechatpush-tplink-poll.lock'
if not fs.mkdir(lock, '700') then
    local stat = fs.stat(lock)
    if not stat or os.time() - stat.mtime <= 60 then return end
    fs.rmdir(lock) -- recover a lock left by an interrupted worker
    if not fs.mkdir(lock, '700') then return end
end

local private = '/tmp/wechatpush-tplink-' .. nixio.getpid()
if not fs.mkdir(private, '700') then
    publish({state='request_failed', wireless=type(old)=='table' and old.wireless or nil, clients={}})
    fs.rmdir(lock)
    return
end
local observed_at
local function request(path, body)
    -- luci.jsonc's null representation varies; only logout needs JSON null.
    local payload = body.system and body.system.logout ~= nil and '{"method":"do","system":{"logout":null}}' or json.stringify(body)
    assert(fs.writefile(private .. '/request', payload))
    local command = 'curl --silent --fail --noproxy ' .. quote('*') ..
        ' --connect-timeout 2 --max-time 4 --cookie ' .. quote(private .. '/cookies') ..
        ' --cookie-jar ' .. quote(private .. '/cookies') ..
        ' --header ' .. quote('Content-Type: application/json') ..
        ' --header ' .. quote('Referer: http://' .. host .. '/') ..
        ' --data-binary ' .. quote('@' .. private .. '/request') ..
        ' --output ' .. quote(private .. '/response') .. ' ' .. quote('http://' .. host .. path) .. ' 2>/dev/null'
    fs.unlink(private .. '/response')
    local status = os.execute(command)
    if status ~= 0 then error('request_failed', 0) end
    local result = json.parse(fs.readfile(private .. '/response') or '')
    if type(result) ~= 'table' then error('invalid_response', 0) end
    if body.host_management then observed_at = os.time() end
    return result
end
local ok, result = pcall(api.collect, request, username, password, old, os.time())
if ok then result.updated_at = observed_at end
for _, file in ipairs({'request', 'response', 'cookies'}) do fs.unlink(private .. '/' .. file) end
fs.rmdir(private)
if not ok then
    local state = tostring(result)
    if state ~= 'authentication_failed' and state ~= 'invalid_response' then state = 'request_failed' end
    result = {state=state, wireless=type(old)=='table' and old.wireless or nil, clients=type(old)=='table' and old.clients or {},
        offline_since=type(old)=='table' and old.offline_since or {},
        station_events=type(old)=='table' and old.station_events or {},
        log_checked_at=type(old)=='table' and old.log_checked_at or nil}
end
publish(result)
fs.rmdir(lock)
