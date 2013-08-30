-- Copyright (C) 2012 Yichun Zhang (agentzh)


local bit = require "bit"
local sub = string.sub
local tcp = ngx.socket.tcp
local insert = table.insert
local strlen = string.len
local strbyte = string.byte
local strchar = string.char
local strfind = string.find
local strrep = string.rep
local null = ngx.null
local band = bit.band
local bxor = bit.bxor
local bor = bit.bor
local lshift = bit.lshift
local rshift = bit.rshift
local tohex = bit.tohex
local sha1 = ngx.sha1_bin
local concat = table.concat
local unpack = unpack
local setmetatable = setmetatable
local error = error
local tonumber = tonumber
local ipairs =ipairs
local strfmt=string.format
module(...)

_VERSION = '0.13'


-- constants

local STATE_CONNECTED = 1
local STATE_COMMAND_SENT = 2

local COM_QUERY = 0x03

local SERVER_MORE_RESULTS_EXISTS = 8

-- 16MB - 1, the default max allowed packet size used by libmysqlclient
local FULL_PACKET_SIZE = 16777215


local mt = { __index = _M }


-- mysql field value type converters
local converters = {}

for i = 0x01, 0x05 do
    -- tiny, short, long, float, double
    converters[i] = tonumber
end
-- converters[0x08] = tonumber  -- long long
converters[0x09] = tonumber  -- int24
converters[0x0d] = tonumber  -- year
converters[0xf6] = tonumber  -- newdecimal


local function _get_byte2(data, i)
    local a, b = strbyte(data, i, i + 1)
    return bor(a, lshift(b, 8)), i + 2
end


local function _get_byte3(data, i)
    local a, b, c = strbyte(data, i, i + 2)
    return bor(a, lshift(b, 8), lshift(c, 16)), i + 3
end


local function _get_byte4(data, i)
    local a, b, c, d = strbyte(data, i, i + 3)
    return bor(a, lshift(b, 8), lshift(c, 16), lshift(d, 24)), i + 4
end


local function _get_byte8(data, i)
    local a, b, c, d, e, f, g, h = strbyte(data, i, i + 7)

    -- XXX workaround for the lack of 64-bit support in bitop:
    local lo = bor(a, lshift(b, 8), lshift(c, 16), lshift(d, 24))
    local hi = bor(e, lshift(f, 8), lshift(g, 16), lshift(h, 24))
    return lo + hi * 4294967296, i + 8

    -- return bor(a, lshift(b, 8), lshift(c, 16), lshift(d, 24), lshift(e, 32),
               -- lshift(f, 40), lshift(g, 48), lshift(h, 56)), i + 8
end


local function _set_byte2(n)
    return strchar(band(n, 0xff), band(rshift(n, 8), 0xff))
end


local function _set_byte3(n)
    return strchar(band(n, 0xff), band(rshift(n, 8), 0xff),
        band(rshift(n, 16), 0xff))
end


local function _set_byte4(n)
    return strchar(band(n, 0xff), band(rshift(n, 8), 0xff),
        band(rshift(n, 16), 0xff), band(rshift(n, 24), 0xff))
end


local function _from_cstring(data, i)
    local last = strfind(data, "\0", i, true)
    if not last then
        return nil, nil
    end

    return sub(data, i, last), last + 1
end


local function _to_cstring(data)
    return {data, "\0"}
end


local function _to_binary_coded_string(data)
    return {strchar(strlen(data)), data}
end


local function _dump(data)
    local bytes = {}
    for i = 1, #data do
        insert(bytes, strbyte(data, i, i))
    end
    return concat(bytes, " ")
end


local function _dumphex(data)
    local bytes = {}
    for i = 1, #data do
        insert(bytes, tohex(strbyte(data, i), 2))
    end
    return concat(bytes, " ")
end


local function _compute_token(password, scramble)
    if password == "" then
        return ""
    end

    local stage1 = sha1(password)
    local stage2 = sha1(stage1)
    local stage3 = sha1(scramble .. stage2)
    local bytes = {}
    for i = 1, #stage1 do
         insert(bytes,
             bxor(strbyte(stage3, i), strbyte(stage1, i)))
    end

    return strchar(unpack(bytes))
end 
--
local mysql={ charset={}};
-- input charset name for get mysqlserver charset id 
-- return id,errormsg
local function _getcharset(charset)
    --local mysql={ charset={}};
    local cid=mysql.charset.utf8
    if not cid then
	    local charsetlist={"armscii8_general_ci","armscii8","32",
		 "ascii_general_ci","ascii","11",
		 "big5_chinese_ci","big5","1",
		 "binary","binary","63",
		 "cp1250_general_ci","cp1250","26",
		 "cp1251_general_ci","cp1251","51",
		 "cp1256_general_ci","cp1256","57",
		 "cp1257_general_ci","cp1257","59",
		 "cp850_general_ci","cp850","4",
		 "cp852_general_ci","cp852","40",
		 "cp866_general_ci","cp866","36",
		 "cp932_japanese_ci","cp932","95",
		 "dec8_swedish_ci","dec8","3",
		 "eucjpms_japanese_ci","eucjpms","97",
		 "euckr_korean_ci","euckr","19",
		 "gb2312_chinese_ci","gb2312","24",
		 "gbk_chinese_ci","gbk","28",
		 "geostd8_general_ci","geostd8","92",
		 "greek_general_ci","greek","25",
		 "hebrew_general_ci","hebrew","16",
		 "hp8_english_ci","hp8","6",
		 "keybcs2_general_ci","keybcs2","37",
		 "koi8r_general_ci","koi8r","7",
		 "koi8u_general_ci","koi8u","22",
		 "latin1_swedish_ci","latin1","8",
		 "latin2_general_ci","latin2","9",
		 "latin5_turkish_ci","latin5","30",
		 "latin7_general_ci","latin7","41",
		 "macce_general_ci","macce","38",
		 "macroman_general_ci","macroman","39",
		 "sjis_japanese_ci","sjis","13",
		 "swe7_swedish_ci","swe7","10",
		 "tis620_thai_ci","tis620","18",
		 "ucs2_general_ci","ucs2","35",
		 "ujis_japanese_ci","ujis","12",
		 "utf16_general_ci","utf16","54",
		 "utf32_general_ci","utf32","60",
		 "utf8_general_ci","utf8","33",
		 "utf8mb4_general_ci","utf8mb4","45"}
	    for i,v in ipairs(charsetlist) do
		if i%3==1 then
			local tab=charsetlist;
			local index =i;
			mysql.charset[tab[i+1]]=tab[index+2]
		end
	    end
    end
    local id=mysql.charset[charset];
    if not id then
        return id, "charset " .. (charset or "nil")  .. "is not supported";
    end
    return id;
end
function _send_packet(self, req, size)
    local sock = self.sock

    self.packet_no = self.packet_no + 1

    --print("packet no: ", self.packet_no)

    local packet = {
        _set_byte3(size),
        strchar(self.packet_no),
        req
    }

    --print("sending packet...")

    return sock:send(packet)
end


local function _recv_packet(self)
    local sock = self.sock

    local data, err = sock:receive(4) -- packet header
    if not data then
        return nil, nil, "failed to receive packet header: " .. err
    end

    --print("packet header: ", _dump(data))

    local len, pos = _get_byte3(data, 1)

    --print("packet length: ", len)

    if len == 0 then
        return nil, nil, "empty packet"
    end

    if len > self._max_packet_size then
        return nil, nil, "packet size too big: " .. len
    end

    local num = strbyte(data, pos)

    --print("recv packet: packet no: ", num)

    self.packet_no = num

    data, err = sock:receive(len)

    --print("receive returned")

    if not data then
        return nil, nil, "failed to read packet content: " .. err
    end

    --print("packet content: ", _dump(data))
    --print("packet content (ascii): ", data)

    local field_count = strbyte(data, 1)

    local typ
    if field_count == 0x00 then
        typ = "OK"
    elseif field_count == 0xff then
        typ = "ERR"
    elseif field_count == 0xfe then
        typ = "EOF"
    elseif field_count <= 250 then
        typ = "DATA"
    end

    return data, typ
end


local function _from_length_coded_bin(data, pos)
    local first = strbyte(data, pos)

    --print("LCB: first: ", first)

    if not first then
        return nil, pos
    end

    if first >= 0 and first <= 250 then
        return first, pos + 1
    end

    if first == 251 then
        return null, pos + 1
    end

    if first == 252 then
        pos = pos + 1
        return _get_byte2(data, pos)
    end

    if first == 253 then
        pos = pos + 1
        return _get_byte3(data, pos)
    end

    if first == 254 then
        pos = pos + 1
        return _get_byte8(data, pos)
    end

    return false, pos + 1
end


local function _from_length_coded_str(data, pos)
    local len
    len, pos = _from_length_coded_bin(data, pos)
    if len == nil or len == null then
        return null, pos
    end

    return sub(data, pos, pos + len - 1), pos + len
end


local function _parse_ok_packet(packet)
    local res = {}
    local pos

    res.affected_rows, pos = _from_length_coded_bin(packet, 2)

    --print("affected rows: ", res.affected_rows, ", pos:", pos)

    res.insert_id, pos = _from_length_coded_bin(packet, pos)

    --print("insert id: ", res.insert_id, ", pos:", pos)

    res.server_status, pos = _get_byte2(packet, pos)

    --print("server status: ", res.server_status, ", pos:", pos)

    res.warning_count, pos = _get_byte2(packet, pos)

    --print("warning count: ", res.warning_count, ", pos: ", pos)

    local message = sub(packet, pos)
    if message and message ~= "" then
        res.message = message
    end

    --print("message: ", res.message, ", pos:", pos)

    return res
end


local function _parse_eof_packet(packet)
    local pos = 2

    local warning_count, pos = _get_byte2(packet, pos)
    local status_flags = _get_byte2(packet, pos)

    return warning_count, status_flags
end


local function _parse_err_packet(packet)
    local errno, pos = _get_byte2(packet, 2)
    local marker = sub(packet, pos, pos)
    local sqlstate
    if marker == '#' then
        -- with sqlstate
        pos = pos + 1
        sqlstate = sub(packet, pos, pos + 5 - 1)
        pos = pos + 5
    end

    local message = sub(packet, pos)
    return errno, message, sqlstate
end


local function _parse_result_set_header_packet(packet)
    local field_count, pos = _from_length_coded_bin(packet, 1)

    local extra
    extra = _from_length_coded_bin(packet, pos)

    return field_count, extra
end


local function _parse_field_packet(data)
    local col = {}
    local catalog, db, table, orig_table, orig_name, charsetnr, length
    local pos
    catalog, pos = _from_length_coded_str(data, 1)

    --print("catalog: ", col.catalog, ", pos:", pos)

    db, pos = _from_length_coded_str(data, pos)
    table, pos = _from_length_coded_str(data, pos)
    orig_table, pos = _from_length_coded_str(data, pos)
    col.name, pos = _from_length_coded_str(data, pos)

    orig_name, pos = _from_length_coded_str(data, pos)

    pos = pos + 1 -- ignore the filler

    charsetnr, pos = _get_byte2(data, pos)

    length, pos = _get_byte4(data, pos)

    col.type = strbyte(data, pos)

    --[[
    pos = pos + 1

    col.flags, pos = _get_byte2(data, pos)

    col.decimals = strbyte(data, pos)
    pos = pos + 1

    local default = sub(data, pos + 2)
    if default and default ~= "" then
        col.default = default
    end
    --]]

    return col
end


local function _parse_row_data_packet(data, cols, compact)
    local row = {}
    local pos = 1
    for i = 1, #cols do
        local value
        value, pos = _from_length_coded_str(data, pos)
        local col = cols[i]
        local typ = col.type
        local name = col.name

        --print("row field value: ", value, ", type: ", typ)

        if value ~= null then
            local conv = converters[typ]
            if conv then
                value = conv(value)
            end
            -- insert(row, value)
        end

        if compact then
            insert(row, value)
        else
            row[name] = value
        end
    end

    return row
end


local function _recv_field_packet(self)
    local packet, typ, err = _recv_packet(self)
    if not packet then
        return nil, err
    end

    if typ == "ERR" then
        local errno, msg, sqlstate = _parse_err_packet(packet)
        return nil, msg, errno, sqlstate
    end

    if typ ~= 'DATA' then
        return nil, "bad field packet type: " .. typ
    end

    -- typ == 'DATA'

    return _parse_field_packet(packet)
end


function new(self)
    local sock, err = tcp()
    if not sock then
        return nil, err
    end
    return setmetatable({ sock = sock }, mt)
end


function set_timeout(self, timeout)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:settimeout(timeout)
end


function connect(self, opts)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local max_packet_size = opts.max_packet_size
    if not max_packet_size then
        max_packet_size = 1024 * 1024 -- default 1 MB
    end
    self._max_packet_size = max_packet_size

    local ok, err

    self.compact = opts.compact_arrays

    local database = opts.database or ""
    local user = opts.user or ""

    local pool = opts.pool

    local host = opts.host
    if host then
        local port = opts.port or 3306
        if not pool then
            pool = concat({user, database, host, port}, ":")
        end

        ok, err = sock:connect(host, port, { pool = pool })

    else
        local path = opts.path
        if not path then
            return nil, 'neither "host" nor "path" options are specified'
        end

        if not pool then
            pool = concat({user, database, path}, ":")
        end

        ok, err = sock:connect("unix:" .. path, { pool = pool })
    end

    if not ok then
        return nil, 'failed to connect: ' .. err
    end

    local reused = sock:getreusedtimes()

    if reused and reused > 0 then
        self.state = STATE_CONNECTED
        return 1
    end

    local packet, typ, err = _recv_packet(self)
    if not packet then
        return nil, err
    end

    if typ == "ERR" then
        local errno, msg, sqlstate = _parse_err_packet(packet)
        return nil, msg, errno, sqlstate
    end

    self.protocol_ver = strbyte(packet)

    --print("protocol version: ", self.protocol_ver)

    local server_ver, pos = _from_cstring(packet, 2)
    if not server_ver then
        return nil, "bad handshake initialization packet: bad server version"
    end

    --print("server version: ", server_ver)

    self._server_ver = server_ver

    local thread_id, pos = _get_byte4(packet, pos)

    --print("thread id: ", thread_id)

    local scramble = sub(packet, pos, pos + 8 - 1)
    if not scramble then
        return nil, "1st part of scramble not found"
    end

    pos = pos + 9 -- skip filler

    -- two lower bytes
    self._server_capabilities, pos = _get_byte2(packet, pos)

    --print("server capabilities: ", self._server_capabilities)

    self._server_lang = strbyte(packet, pos)
    pos = pos + 1

    --print("server lang: ", self._server_lang)

    self._server_status, pos = _get_byte2(packet, pos)

    --print("server status: ", self._server_status)

    local more_capabilities
    more_capabilities, pos = _get_byte2(packet, pos)

    self._server_capabilities = bor(self._server_capabilities,
                                    lshift(more_capabilities, 16))

    --print("server capabilities: ", self._server_capabilities)

    -- local len = strbyte(packet, pos)
    local len = 21 - 8 - 1

    --print("scramble len: ", len)

    pos = pos + 1 + 10

    local scramble_part2 = sub(packet, pos, pos + len - 1)
    if not scramble_part2 then
        return nil, "2nd part of scramble not found"
    end

    scramble = scramble .. scramble_part2
    --print("scramble: ", _dump(scramble))

    local password = opts.password or ""

    local token = _compute_token(password, scramble)

    -- local client_flags = self._server_capabilities
    local client_flags = 260047;

    --print("token: ", _dump(token))
    local _charset=opts.charset or "utf8"
    local _cid,err=_getcharset(_charset)
    if not  _cid then
        return nil, "set charset error" .. err
    end
    local req = {
        _set_byte4(client_flags),
        _set_byte4(self._max_packet_size),
        --"\0", -- TODO: add support for charset encoding,
        strchar(_cid),
        strrep("\0", 23),
        _to_cstring(user),
        _to_binary_coded_string(token),
        _to_cstring(database)
    }

    local packet_len = 4 + 4 + 1 + 23 + strlen(user) + 1
        + strlen(token) + 1 + strlen(database) + 1

    -- print("packet content length: ", packet_len)
    -- print("packet content: ", _dump(concat(req, "")))

    local bytes, err = _send_packet(self, req, packet_len)
    if not bytes then
        return nil, "failed to send client authentication packet: " .. err
    end

    --print("packet sent ", bytes, " bytes")

    local packet, typ, err = _recv_packet(self)
    if not packet then
        return nil, "failed to receive the result packet: " .. err
    end

    if typ == 'ERR' then
        local errno, msg, sqlstate = _parse_err_packet(packet)
        return nil, msg, errno, sqlstate
    end

    if typ == 'EOF' then
        return nil, "old pre-4.1 authentication protocol not supported"
    end

    if typ ~= 'OK' then
        return nil, "bad packet type: " .. typ
    end

    self.state = STATE_CONNECTED

    return 1
end


function set_keepalive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    if self.state ~= STATE_CONNECTED then
        return nil, "cannot be reused in the current connection state: "
                    .. (self.state or "nil")
    end

    self.state = nil
    return sock:setkeepalive(...)
end


function get_reused_times(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:getreusedtimes()
end


function close(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    self.state = nil

    return sock:close()
end


function server_ver(self)
    return self._server_ver
end


local function send_query(self, query)
    if self.state ~= STATE_CONNECTED then
        return nil, "cannot send query in the current context: "
                    .. (self.state or "nil")
    end

    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    self.packet_no = -1

    local cmd_packet = {strchar(COM_QUERY), query}
    local packet_len = 1 + strlen(query)

    local bytes, err = _send_packet(self, cmd_packet, packet_len)
    if not bytes then
        return nil, err
    end

    self.state = STATE_COMMAND_SENT

    --print("packet sent ", bytes, " bytes")

    return bytes
end


local function read_result(self)
    if self.state ~= STATE_COMMAND_SENT then
        return nil, "cannot read result in the current context: " .. self.state
    end

    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    local packet, typ, err = _recv_packet(self)
    if not packet then
        return nil, err
    end

    if typ == "ERR" then
        self.state = STATE_CONNECTED

        local errno, msg, sqlstate = _parse_err_packet(packet)
        return nil, msg, errno, sqlstate
    end

    if typ == 'OK' then
        local res = _parse_ok_packet(packet)
        if res and band(res.server_status, SERVER_MORE_RESULTS_EXISTS) ~= 0 then
            return res, "again"
        end

        self.state = STATE_CONNECTED
        return res
    end

    if typ ~= 'DATA' then
        self.state = STATE_CONNECTED

        return nil, "packet type " .. typ .. " not supported"
    end

    -- typ == 'DATA'

    --print("read the result set header packet")

    local field_count, extra = _parse_result_set_header_packet(packet)

    --print("field count: ", field_count)

    local cols = {}
    for i = 1, field_count do
        local col, err, errno, sqlstate = _recv_field_packet(self)
        if not col then
            return nil, err, errno, sqlstate
        end

        insert(cols, col)
    end

    local packet, typ, err = _recv_packet(self)
    if not packet then
        return nil, err
    end

    if typ ~= 'EOF' then
        return nil, "unexpected packet type " .. typ .. " while eof packet is "
            .. "expected"
    end

    -- typ == 'EOF'

    local compact = self.compact

    local rows = {}
    while true do
        --print("reading a row")

        packet, typ, err = _recv_packet(self)
        if not packet then
            return nil, err
        end

        if typ == 'EOF' then
            local warning_count, status_flags = _parse_eof_packet(packet)

            --print("status flags: ", status_flags)

            if band(status_flags, SERVER_MORE_RESULTS_EXISTS) ~= 0 then
                return rows, "again"
            end

            break
        end

        -- if typ ~= 'DATA' then
            -- return nil, 'bad row packet type: ' .. typ
        -- end

        -- typ == 'DATA'

        local row = _parse_row_data_packet(packet, cols, compact)
        insert(rows, row)
    end

    self.state = STATE_CONNECTED

    return rows
end


function query(self, query)
    local bytes, err = send_query(self, query)
    if not bytes then
        return nil, "failed to send query: " .. err
    end

    return read_result(self)
end


function set_compact_arrays(self, value)
    self.compact = value
end


_M.send_query = send_query
_M.read_result = read_result


local class_mt = {
    -- to prevent use of casual module global variables
    __newindex = function (table, key, val)
        error('attempt to write to undeclared variable "' .. key .. '"')
    end
}

setmetatable(_M, class_mt)

