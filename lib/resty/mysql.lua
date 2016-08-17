-- Copyright (C) 2012 Yichun Zhang (agentzh)


local bit = require "bit"
local ffi = require("ffi")
local sub = string.sub
local tcp = ngx.socket.tcp
local strbyte = string.byte
local strchar = string.char
local strfind = string.find
local format = string.format
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
local setmetatable = setmetatable
local error = error
local tonumber = tonumber


if not ngx.config
   or not ngx.config.ngx_lua_version
   or ngx.config.ngx_lua_version < 9011
then
    error("ngx_lua 0.9.11+ required")
end


ffi.cdef[[
    typedef union { 
        char buf[4];
        float f;
    } point_f;

    typedef union { 
        char buf[8];
        double d;
    } point_d;
]]


local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec) return {} end
end


local _M = { _VERSION = '0.16' }


-- constants

local STATE_CONNECTED = 1
local STATE_COMMAND_SENT = 2

local COM_QUIT = 0x01
local COM_QUERY = 0x03
local CLIENT_SSL = 0x0800
local COM_STMT_PREPARE = 0x16
local COM_STMT_EXECUTE = 0x17

local SERVER_MORE_RESULTS_EXISTS = 8
local MYSQL_TYPE_STRING      = 254

-- 16MB - 1, the default max allowed packet size used by libmysqlclient
local FULL_PACKET_SIZE = 16777215


local mt = { __index = _M }


-- mysql field value type converters
local converters = new_tab(0, 8)

for i = 0x01, 0x05 do
    -- tiny, short, long, float, double
    converters[i] = tonumber
end
-- converters[0x08] = tonumber  -- long long
converters[0x09] = tonumber  -- int24
converters[0x0d] = tonumber  -- year
converters[0xf6] = tonumber  -- newdecimal

-- mysql data type
local mysql_data_type = {
    MYSQL_TYPE_DECIMAL  = 0,
    MYSQL_TYPE_TINY     = 1,
    MYSQL_TYPE_SHORT    = 2,
    MYSQL_TYPE_LONG     = 3,
    MYSQL_TYPE_FLOAT    = 4,
    MYSQL_TYPE_DOUBLE   = 5,
    MYSQL_TYPE_NULL     = 6,
    MYSQL_TYPE_TIMESTAMP= 7,
    MYSQL_TYPE_LONGLONG = 8,
    MYSQL_TYPE_INT24    = 9,
    MYSQL_TYPE_DATE     = 10,
    MYSQL_TYPE_TIME     = 11,
    MYSQL_TYPE_DATETIME = 12,
    MYSQL_TYPE_YEAR     = 13,
    MYSQL_TYPE_NEWDATE  = 14,
    MYSQL_TYPE_VARCHAR  = 15,
    MYSQL_TYPE_BIT      = 16,
    MYSQL_TYPE_NEWDECIMAL  = 246,
    MYSQL_TYPE_ENUM        = 247,
    MYSQL_TYPE_SET         = 248,
    MYSQL_TYPE_TINY_BLOB   = 249,
    MYSQL_TYPE_MEDIUM_BLOB = 250,
    MYSQL_TYPE_LONG_BLOB   = 251,
    MYSQL_TYPE_BLOB        = 252,
    MYSQL_TYPE_VAR_STRING  = 253,
    MYSQL_TYPE_STRING      = 254,
    MYSQL_TYPE_GEOMETRY    = 255
}


local function _get_byte1(data, i)
    local a = strbyte(data, i)
    return a, i + 1
end


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
    return strchar(band(n, 0xff),
                   band(rshift(n, 8), 0xff),
                   band(rshift(n, 16), 0xff))
end


local function _set_byte4(n)
    return strchar(band(n, 0xff),
                   band(rshift(n, 8), 0xff),
                   band(rshift(n, 16), 0xff),
                   band(rshift(n, 24), 0xff))
end


local function _from_cstring(data, i)
    local last = strfind(data, "\0", i, true)
    if not last then
        return nil, nil
    end

    return sub(data, i, last), last + 1
end


local function _to_cstring(data)
    return data .. "\0"
end


local function _to_binary_coded_string(data)
    return strchar(#data) .. data
end


local function _dump(data)
    local len = #data
    local bytes = new_tab(len, 0)
    for i = 1, len do
        bytes[i] = format("%x", strbyte(data, i))
    end
    return concat(bytes, " ")
end


local function _dumphex(data)
    local len = #data
    local bytes = new_tab(len, 0)
    for i = 1, len do
        bytes[i] = tohex(strbyte(data, i), 2)
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
    local n = #stage1
    local bytes = new_tab(n, 0)
    for i = 1, n do
         bytes[i] = strchar(bxor(strbyte(stage3, i), strbyte(stage1, i)))
    end

    return concat(bytes)
end


local function _send_packet(self, req, size)
    local sock = self.sock

    self.packet_no = self.packet_no + 1

    -- print("packet no: ", self.packet_no)

    local packet = _set_byte3(size) .. strchar(self.packet_no) .. req

    -- print("sending packet: ", _dump(packet))

    -- print("sending packet... of size " .. #packet)

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
    local res = new_tab(0, 5)
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
    local col = new_tab(0, 2)
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
    local pos = 1
    local ncols = #cols
    local row
    if compact then
        row = new_tab(ncols, 0)
    else
        row = new_tab(0, ncols)
    end
    for i = 1, ncols do
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
        end

        if compact then
            row[i] = value

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


function _M.new(self)
    local sock, err = tcp()
    if not sock then
        return nil, err
    end
    return setmetatable({ sock = sock }, mt)
end


function _M.set_timeout(self, timeout)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:settimeout(timeout)
end


function _M.connect(self, opts, only_record)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end
    self.opts = opts
    if only_record then
        return true
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
            pool = user .. ":" .. database .. ":" .. host .. ":" .. port
        end

        ok, err = sock:connect(host, port, { pool = pool })

    else
        local path = opts.path
        if not path then
            return nil, 'neither "host" nor "path" options are specified'
        end

        if not pool then
            pool = user .. ":" .. database .. ":" .. path
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
    local capabilities  -- server capabilities
    capabilities, pos = _get_byte2(packet, pos)

    -- print(format("server capabilities: %#x", capabilities))

    self._server_lang = strbyte(packet, pos)
    pos = pos + 1

    --print("server lang: ", self._server_lang)

    self._server_status, pos = _get_byte2(packet, pos)

    --print("server status: ", self._server_status)

    local more_capabilities
    more_capabilities, pos = _get_byte2(packet, pos)

    capabilities = bor(capabilities, lshift(more_capabilities, 16))

    --print("server capabilities: ", capabilities)

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

    local client_flags = 0x3f7cf;

    local ssl_verify = opts.ssl_verify
    local use_ssl = opts.ssl or ssl_verify

    if use_ssl then
        if band(capabilities, CLIENT_SSL) == 0 then
            return nil, "ssl disabled on server"
        end

        -- send a SSL Request Packet
        local req = _set_byte4(bor(client_flags, CLIENT_SSL))
                    .. _set_byte4(self._max_packet_size)
                    .. "\0" -- TODO: add support for charset encoding
                    .. strrep("\0", 23)

        local packet_len = 4 + 4 + 1 + 23
        local bytes, err = _send_packet(self, req, packet_len)
        if not bytes then
            return nil, "failed to send client authentication packet: " .. err
        end

        local ok, err = sock:sslhandshake(false, nil, ssl_verify)
        if not ok then
            return nil, "failed to do ssl handshake: " .. (err or "")
        end
    end

    local password = opts.password or ""

    local token = _compute_token(password, scramble)

    --print("token: ", _dump(token))

    local req = _set_byte4(client_flags)
                .. _set_byte4(self._max_packet_size)
                .. "\0" -- TODO: add support for charset encoding
                .. strrep("\0", 23)
                .. _to_cstring(user)
                .. _to_binary_coded_string(token)
                .. _to_cstring(database)

    local packet_len = 4 + 4 + 1 + 23 + #user + 1
        + #token + 1 + #database + 1

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


function _M.set_keepalive(self, ...)
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


function _M.get_reused_times(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    return sock:getreusedtimes()
end


function _M.close(self)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    self.state = nil

    local bytes, err = _send_packet(self, strchar(COM_QUIT), 1)
    if not bytes then
        return nil, err
    end

    return sock:close()
end


function _M.server_ver(self)
    return self._server_ver
end


local function _send_com_package(self, com_package, packet_type)
    if self.state ~= STATE_CONNECTED then
        return nil, "cannot send query in the current context: "
                    .. (self.state or "nil")
    end

    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

    self.packet_no = -1

    local cmd_packet = strchar(packet_type) .. com_package
    local packet_len = 1 + #com_package

    local bytes, err = _send_packet(self, cmd_packet, packet_len)
    if not bytes then
        return nil, err
    end

    self.state = STATE_COMMAND_SENT

    --print("package sent ", bytes, " bytes")

    return bytes
end


function _M.send_query(self, query)
    local bytes, err = _send_com_package(self, query)
    return bytes, err
end


local function read_result(self, est_nrows)
    if self.state ~= STATE_COMMAND_SENT then
        return nil, "cannot read result in the current context: "
                    .. (self.state or "nil")
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

    local cols = new_tab(field_count, 0)
    for i = 1, field_count do
        local col, err, errno, sqlstate = _recv_field_packet(self)
        if not col then
            return nil, err, errno, sqlstate
        end

        cols[i] = col
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

    local rows = new_tab(est_nrows or 4, 0)
    local i = 0
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
        i = i + 1
        rows[i] = row
    end

    self.state = STATE_CONNECTED

    return rows
end
_M.read_result = read_result


function _M.query(self, query, est_nrows)
    local bytes, err = _send_com_package(self, query, COM_QUERY)
    if not bytes then
        return nil, "failed to send query: " .. err
    end

    return read_result(self, est_nrows)
end


local function _read_prepare_init(self)
    local packet, typ, err = _recv_packet(self)
    if not packet then
        return nil, err
    end

    if typ == "ERR" then
        local errno, msg, sqlstate = _parse_err_packet(packet)
        return nil, msg, errno, sqlstate
    end

    if typ ~= 'OK' then
        return nil, "bad read prepare init packet type: " .. typ
    end

    -- typ == 'OK'
    local stmt = new_tab(0, 5)
    local pos
    stmt.field_count, pos = _get_byte1(packet, 1)
    stmt.statement_id, pos= _get_byte4(packet, pos)
    stmt.columns, pos     = _get_byte2(packet, pos)
    stmt.parameters, pos  = _get_byte2(packet, pos)
    if #packet >= 12 then
        pos = pos + 1
        stmt.warnings, pos = _get_byte2(packet, pos)
    end

    return stmt
end


local function _read_prepare_parameters(self, stmt)
    local para_count = stmt.parameters
    for _ = 1, para_count do
        local packet, typ, err = _recv_packet(self)
        if not packet then
            return nil, err
        end

        if typ ~= 'DATA' then
            return nil, "bad prepare parameters response type: " .. typ
        end
    end

    return true
end


local function _read_eof_packet(self)
    local packet, typ, err = _recv_packet(self)
    if not packet then
        return err
    end

    if typ ~= 'EOF' then
        return "unexpected packet type " .. typ .. " while eof packet is "
            .. "expected"
    end

    return 
end


local function _read_result_set(self, field_count)
    local result_set = new_tab(0, 2)
    local packet, typ, err

    result_set.field_count = field_count
    result_set.fields      = new_tab(field_count, 0)

    for i = 1, field_count do
        packet, typ, err = _recv_packet(self)
        if not packet then
            return nil, err
        end

        if typ ~= 'DATA' then
            return nil, "_readresult_set type: " .. typ
        end

        result_set.fields[i] = _parse_field_packet(packet)
    end

    return result_set
end


local function _read_prepare_reponse(self)
    if self.state ~= STATE_COMMAND_SENT then
        return nil, "cannot read result in the current context: "
                    .. (self.state or "nil")
    end

    local stmt, err = _read_prepare_init(self)
    if err then
        self.state = STATE_CONNECTED
        return nil, err
    end

    if stmt.parameters > 0 then
        local ok
        ok, err = _read_prepare_parameters(self, stmt)
        if not ok then
            self.state = STATE_CONNECTED
            return nil, err
        end

        err = _read_eof_packet(self)
        if err ~= nil then
            self.state = STATE_CONNECTED
            return nil, err
        end
    end

    if stmt.columns > 0 then
        stmt.result_set, err = _read_result_set(self, stmt.columns)
        if err then
            self.state = STATE_CONNECTED
            return nil, err
        end

        err = _read_eof_packet(self)
        if err ~= nil then
            self.state = STATE_CONNECTED
            return nil, err
        end
    end

    self.state = STATE_CONNECTED

    return stmt, err
end


function _M.prepare(self, sql)
    local _, err = _send_com_package(self, sql, COM_STMT_PREPARE)
    if err then
        return nil, err
    end

    local statement
    statement, err = _read_prepare_reponse(self)

    return statement, err
end


local function _encode_param_types(args)
    local buf = new_tab(#args, 0)

    for i, _ in ipairs(args) do
        buf[i] = _set_byte2(MYSQL_TYPE_STRING)
    end

    return concat(buf, "")
end


local function _encode_param_values(args)
    local buf = new_tab(#args, 0)

    for i, v in ipairs(args) do
        buf[i] = _to_binary_coded_string(tostring(v))
    end

    return concat(buf, "")
end


local function _read_result(self)
    if self.state ~= STATE_COMMAND_SENT then
        return nil, "cannot read result in the current context: "
                    .. (self.state or "nil")
    end

    local response = new_tab(0, 2)
    local packet, typ, err = _recv_packet(self)
    if not packet then
        return nil, err
    end

    if typ == "ERR" then
        local errno, msg, sqlstate = _parse_err_packet(packet)
        return nil, msg, errno, sqlstate
    end

    if typ ~= 'DATA' then
        return nil, "cannot read result with unexpected packet:" .. typ
    end

    response.field_count = strbyte(packet)

    response.result_set, err = _read_result_set(self, response.field_count)
    if err then
        return nil, err
    end

    err = _read_eof_packet(self)
    if err ~= nil then
        return nil, err
    end

    return response
end


local function _parse_result_data_packet(data, pos, cols, compact)
    local ncols = #cols
    local row
    if compact then
        row = new_tab(ncols, 0)
        
    else
        row = new_tab(0, ncols)
    end

    for i = 1, ncols do
        local col = cols[i]
        local value

        local typ = col.type
        local name = col.name

        if     typ == mysql_data_type.MYSQL_TYPE_TINY then
            value, pos = _get_byte1(data, pos)

        elseif typ == mysql_data_type.MYSQL_TYPE_SHORT then
            value, pos = _get_byte2(data, pos)

        elseif typ == mysql_data_type.MYSQL_TYPE_LONG then
            value, pos = _get_byte4(data, pos)

        elseif typ == mysql_data_type.MYSQL_TYPE_LONGLONG then
            value, pos = _get_byte8(data, pos)

        elseif typ == mysql_data_type.MYSQL_TYPE_FLOAT then
            value = data:sub(pos, pos + 3)
            pos = pos + 4
            
            local v = ffi.new("point_f", value)
            value = v.f

        elseif typ == mysql_data_type.MYSQL_TYPE_DOUBLE then
            value = data:sub(pos, pos + 7)
            pos = pos + 8
            
            local v = ffi.new("point_d", value)
            value = v.d

        else
            value, pos = _from_length_coded_str(data, pos)
        end
        
        -- print("row field value: ", value, ", type: ", typ)

        if compact then
            row[i] = value
            
        else
            row[name] = value
        end
    end

    return row
end


local function _fetch_all_rows(self, res)
    if self.state ~= STATE_COMMAND_SENT then
        return nil, "cannot read result in the current context: "
                    .. (self.state or "nil")
    end

    local field_count = res.result_set.field_count
    local fields = res.result_set.fields

    local rows = new_tab(4, 0)
    local i = 0
    while true do
        local packet, typ, err = _recv_packet(self)
        if not packet then
            return nil, err
        end

        if typ == 'EOF' then
            local _, status_flags = _parse_eof_packet(packet)
            --print("status flags: ", status_flags)

            if band(status_flags, SERVER_MORE_RESULTS_EXISTS) ~= 0 then
                return rows, "again"
            end

            break
        end

        if typ ~= 'OK' then
            return nil, "cannot fetch rows with unexpected packet:" .. typ
        end

        local pos = 1 + math.floor((field_count+9)/8) + 1

        local row = _parse_result_data_packet(packet, pos, fields)
        i = i + 1
        rows[i] = row
    end

    return rows
end


function _M.execute(self, statement_id, ...)
    local args = {...}
    local type_parm  = _encode_param_types(args)
    local value_parm = _encode_param_values(args)
    
    local packet = new_tab(8, 0)
    packet[1] = _set_byte4(statement_id)
    packet[2] = strchar(0)        -- flag
    packet[3] = _set_byte4(1)     -- iteration-count
    
    local bitmap_len =  (#args + 7) / 8 
    local i
    for j = 4, 3 + bitmap_len do
        -- NULL-bitmap, length: (num-params+7)/8
        packet[j] = strchar(0)
        i = j
    end
    packet[i+1] = strchar(1)
    packet[i+2] = type_parm
    packet[i+3] = value_parm
    packet = concat(packet, "")
    -- print("execute pkg: ", _dumphex(packet))

    local _, err = _send_com_package(self, packet, COM_STMT_EXECUTE)
    if err ~= nil then
        return nil, err
    end

    local result, err = _read_result(self)
    if err then
        self.state = STATE_CONNECTED
        return nil, err
    end

    local rows, err = _fetch_all_rows(self, result)
    if err then
        self.state = STATE_CONNECTED
        return nil, err
    end

    self.state = STATE_CONNECTED
    return rows
end


function _M.set_compact_arrays(self, value)
    self.compact = value
end


local function _shallow_copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
        
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end


function _M.run(self, prepare_sql, ...)
    local opts = _shallow_copy(self.opts)
    local db, err, res, errcode, sqlstate, used_times, _

    db, err = _M:new()
    if not db then
        return nil, err
    end

    local database = opts.database or ""
    local user = opts.user or ""
    local host = opts.host
    local pool = user .. ":" .. database .. ":"
    if host then
        local port = opts.port or 3306
        pool = pool .. host .. ":" .. port .. ":" .. prepare_sql
        
    else
        local path = opts.path
        if not path then
            return nil, 'neither "host" nor "path" options are specified'
        end

        pool = pool .. path .. ":" .. prepare_sql
    end
    opts.pool = pool

    ok, err, errcode, sqlstate = db:connect(opts)
    if not ok then
        return nil, "failed to connect: " .. err .. ": " .. errcode .. " " .. sqlstate
    end

    used_times, err = db:get_reused_times()
    if err then
        return nil, err
    end

    if used_times == 0 then
        _, err = db:prepare(prepare_sql)
        if err then
            return nil, err
        end
    end

    -- print("prepare success: ", json.encode(stmt))

    res, err = db:execute(1, ...)
    if err then
        return nil, err
    end

    db:set_keepalive(1000 * 60 * 5, 10)

    return res
end


return _M
