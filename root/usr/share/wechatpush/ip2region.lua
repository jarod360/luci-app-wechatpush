-- ip2region XDB IPv4 lookup for Lua 5.1 / OpenWrt.
-- Reads only the 512 KiB vector index and the matching segment/data records.
-- IPv6 is intentionally handled by the caller through online providers.
local db_path, ip_text = arg[1], arg[2]
local function fail() os.exit(1) end
if type(db_path) ~= "string" or db_path == "" or type(ip_text) ~= "string" or ip_text == "" then fail() end
local octets = {}
for part in (ip_text .. "."):gmatch("(.-)%.") do
	if part == "" or not part:match("^%d+$") then fail() end
	local value = tonumber(part)
	if not value or value < 0 or value > 255 then fail() end
	octets[#octets + 1] = value
end
if #octets ~= 4 then fail() end
local file = io.open(db_path, "rb")
if not file then fail() end
local function close_and_fail()
	if file then file:close(); file = nil end
	fail()
end
local file_size = file:seek("end", 0)
if not file_size or file_size < 256 + 524288 then close_and_fail() end
local function read_at(offset, length)
	if offset < 0 or length < 0 or offset + length > file_size then return nil end
	if not file:seek("set", offset) then return nil end
	local value = file:read(length)
	if not value or #value ~= length then return nil end
	return value
end
local function uint16_le(data, offset)
	local a, b = data:byte(offset, offset + 1)
	if not a or not b then return nil end
	return a + b * 256
end
local function uint32_le(data, offset)
	local a, b, c, d = data:byte(offset, offset + 3)
	if not a or not b or not c or not d then return nil end
	return a + b * 256 + c * 65536 + d * 16777216
end
local header = read_at(0, 256)
if not header then close_and_fail() end
local structure_version, ip_version = uint16_le(header, 1), uint16_le(header, 17)
if structure_version ~= 2 and (structure_version ~= 3 or ip_version ~= 4) then close_and_fail() end
local vector_index = read_at(256, 524288)
if not vector_index then close_and_fail() end
local vector_offset = (octets[1] * 256 + octets[2]) * 8
local start_ptr = uint32_le(vector_index, vector_offset + 1)
local end_ptr = uint32_le(vector_index, vector_offset + 5)
if not start_ptr or not end_ptr or start_ptr == 0 or end_ptr == 0 or end_ptr < start_ptr or end_ptr + 14 > file_size then close_and_fail() end
local function compare_ip(segment, offset)
	for i = 1, 4 do
		local indexed = segment:byte(offset + 5 - i)
		if octets[i] > indexed then return 1 end
		if octets[i] < indexed then return -1 end
	end
	return 0
end
local low, high = 0, math.floor((end_ptr - start_ptr) / 14)
local data_ptr, data_len
while low <= high do
	local middle = math.floor((low + high) / 2)
	local segment = read_at(start_ptr + middle * 14, 14)
	if not segment then close_and_fail() end
	if compare_ip(segment, 0) < 0 then
		high = middle - 1
	elseif compare_ip(segment, 4) > 0 then
		low = middle + 1
	else
		data_len, data_ptr = uint16_le(segment, 9), uint32_le(segment, 11)
		break
	end
end
if not data_len or data_len == 0 or not data_ptr or data_ptr + data_len > file_size then close_and_fail() end
local region = read_at(data_ptr, data_len)
if not region then close_and_fail() end
file:close()
file = nil
local fields = {}
for field in (region .. "|"):gmatch("(.-)|") do
	field = field:gsub("^%s*(.-)%s*$", "%1")
	local lower = field:lower()
	if field ~= "" and lower ~= "0" and lower ~= "null" and lower ~= "unknown" and lower ~= "n/a"
		and field ~= "未知" and field ~= "保留地址" and field ~= "内网IP" then
		fields[#fields + 1] = field
	end
end
if #fields == 0 then fail() end

-- 统一归一化地理位置：不输出大洲、县区、运营商或 ASN。
-- 中国大陆保留省级 + 市级；香港等地区保留地区 + 市级；其他国家保留国家 + 市级。
local continents = {
	["亚洲"] = true, ["asia"] = true,
	["欧洲"] = true, ["europe"] = true,
	["非洲"] = true, ["africa"] = true,
	["北美洲"] = true, ["north america"] = true,
	["南美洲"] = true, ["south america"] = true,
	["大洋洲"] = true, ["oceania"] = true,
	["南极洲"] = true, ["antarctica"] = true
}
if continents[(fields[1] or ""):lower()] then table.remove(fields, 1) end

local country = fields[1] or ""
local country_lower = country:lower()
local is_mainland_china = country == "中国" or country_lower == "china"
	or country_lower == "cn" or country_lower == "prc" or country == "中国大陆"
if is_mainland_china then
	-- 中国大陆：国家|省|市|县区|运营商。保留省级和市级，兼容缺少省级字段的旧数据。
	local province, city = fields[2], fields[3]
	if province and province ~= "" and city and city ~= "" then
		fields = { province, city }
	elseif city and city ~= "" then
		fields = { city }
	else
		fail()
	end
else
	-- 其他国家/地区：保留国家/地区及市级，丢弃其余行政层级和网络运营商信息。
	local city = (#fields >= 4 and fields[3]) or fields[2]
	if city and city ~= "" then fields = { country, city } else fields = { country } end
end
io.write(table.concat(fields, " "))
