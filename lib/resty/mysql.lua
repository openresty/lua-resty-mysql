-- Copyright (C) 2012 Zhang "agentzh" Yichun (章亦春)

module("resty.mysql", package.seeall)


local bit = require "bit"
local mt = { __index = resty.mysql }

local sub = string.sub
local tcp = ngx.socket.tcp
local insert = table.insert
local len = string.len
local null = ngx.null


local function _from_little_endian(data, i, j)
    local res = 0
    local n = 0
    for k = j, i, -1 do
        if n > 0 then
            res = bit.lshift(res, n * 8)
        end
        ngx.say("byte: ", string.byte(data, k))
        res = bit.bor(res, string.byte(data, k))
        n = n + 1
    end
    return res, j + 1
end


local function _to_little_endian(num, size)
    local res = {}
    for i = 0, size - 1 do
        table.insert(res, bit.band(bit.rshift(num, i * 8), 0xff))
    end
    return string.char(unpack(res))
end


local function _from_cstring(data, i)
    local last = string.find(data, "\0", i, true)
    if not last then
        return nil, nil
    end

    return string.sub(data, i, last), last + 1
end


local function _to_cstring(data)
    return data .. "\0"
end


local function _to_binary_coded_string(data)
    return string.char(string.len(data)) .. data
end


local function _dump(data)
    return table.concat({string.byte(data, 1, #data)}, " ")
end


local function _dumphex(data)
    local bytes = {}
    for i = 1, #data do
        table.insert(bytes, bit.tohex(string.byte(data, i), 2))
    end
    return table.concat(bytes, " ")
end


local function _eval_token(password, scramble)
    if password == "" then
        return ""
    end

    local stage1 = ngx.sha1_bin(password)
    local stage2 = ngx.sha1_bin(stage1)
    local stage3 = ngx.sha1_bin(scramble .. stage2)
    local bytes = {}
    for i = 1, #stage1 do
         table.insert(bytes,
             bit.bxor(string.byte(stage3, i), string.byte(stage1, i)))
    end

    return string.char(unpack(bytes))
end


function _send_packet(self, req, size)
    local sock = self.sock

    self.packet_no = self.packet_no + 1

    ngx.say("packet no: ", self.packet_no)

    local packet = {
        _to_little_endian(size, 3),
        string.char(self.packet_no),
        req
    }

    return sock:send(packet)
end


function _recv_packet(self)
    local sock = self.sock

    local data, err = sock:receive(4) -- packet header
    if not data then
        return nil, nil, "failed to receive packet header: " .. err
    end

    ngx.say("packet header: ", _dump(data))

    local len = _from_little_endian(data, 1, 3)

    ngx.say("packet length: ", len)

    if len == 0 then
        return "", "empty"
    end

    local num = string.byte(data, 4)

    ngx.say("packet no: ", num)

    self.packet_no = num

    data, err = sock:receive(len)
    if not data then
        return nil, nil, "failed to read packet content: " .. err
    end

    ngx.say("packet content: ", _dump(data))
    ngx.say("packet content (ascii): ", data)

    local byte = string.byte(data, 1)

    local typ
    if byte == 0x00 then
        typ = "OK"
    elseif byte == 0xff then
        typ = "ERR"
    elseif byte == 0xfe then
        typ = "EOF"
    elseif byte <= 250 then
        typ = "DATA"
    end

    return data, typ
end


function new(self)
    return setmetatable({ sock = tcp() }, mt)
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

    local ok, err

    local host = opts.host
    if host then
        ok, err = sock:connect(host, opts.port or '3306')

    else
        local path = opts.path
        if not path then
            return nil, 'enither "host" nor "path" options are specified'
        end

        ok, err = sock:connect(opts.path)
    end

    if not ok then
        return nil, 'failed to connect: ' .. err
    end

    local packet, typ, err = _recv_packet(self)
    if not packet then
        return nil, err
    end

    if typ == "ERR" then
        local errno, msg = _parse_err_packet(packet)
        return nil, errno .. ": " .. msg
    end

    self.protocol_ver = string.byte(packet)

    ngx.say("protocol version: ", self.protocol_ver)

    local server_ver, pos = _from_cstring(packet, 2)
    if not server_ver then
        return nil, "bad handshake initialization packet: bad server version"
    end

    ngx.say("server version: ", server_ver)

    self.server_ver = server_ver

    local thread_id, pos = _from_little_endian(packet, pos, pos + 4 - 1)

    ngx.say("thread id: ", thread_id)

    local scramble = string.sub(packet, pos, pos + 8 - 1)
    if not scramble then
        return nil, "1st part of scramble not found"
    end

    pos = pos + 9 -- skip filler

    -- two lower bytes
    self.server_capabilities, pos = _from_little_endian(packet, pos, pos + 2 - 1)

    ngx.say("server capabilities: ", self.server_capabilities)

    self.server_lang = string.byte(packet, pos)
    pos = pos + 1

    ngx.say("server lang: ", self.server_lang)

    self.server_status, pos = _from_little_endian(packet, pos, pos + 2 - 1)

    ngx.say("server status: ", self.server_status)

    local more_capabilities
    more_capabilities, pos = _from_little_endian(packet, pos, pos + 2 - 1)

    self.server_capabilities = bit.bor(self.server_capabilities, bit.lshift(more_capabilities, 16))

    ngx.say("server capabilities: ", self.server_capabilities)

    local len = string.byte(packet, pos)
    len = len - 8 - 1

    pos = pos + 1 + 10

    local scramble_part2 = string.sub(packet, pos, pos + len - 1)
    if not scramble_part2 then
        return nil, "2nd part of scramble not found"
    end

    scramble = scramble .. scramble_part2
    ngx.say("scramble: ", _dump(scramble))

    local password = opts.password or ""
    local database = opts.database or ""
    local user = opts.user or ""

    local token = _eval_token(password, scramble)

    -- local client_flags = self.server_capabilities
    local client_flags = 260047;

    ngx.say("token: ", _dump(token))

    local req = {
        _to_little_endian(client_flags, 4),
        _to_little_endian(8192, 4),
        _to_little_endian(0, 1),
        string.rep("\0", 23),
        _to_cstring(user),
        _to_binary_coded_string(token),
        _to_cstring(database)
    }

    local packet_len = 4 + 4 + 1 + 23 + string.len(user) + 1
        + string.len(scramble) + 1 + string.len(database) + 1

    ngx.say("packet content length: ", packet_len)
    ngx.say("packet content: ", _dump(table.concat(req, "")))

    local bytes, err = _send_packet(self, req, packet_len)
    if not bytes then
        return nil, "failed to send client authentication packet: " .. err
    end

    ngx.say("packet sent ", bytes, " bytes")

    local packet, typ, err = _recv_packet(self)
    if not packet then
        return nil, "failed to receive the result packet: " .. err
    end
end


function set_keepalive(self, ...)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end

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

    return sock:close()
end


-- to prevent use of casual module global variables
getmetatable(resty.mysql).__newindex = function (table, key, val)
    error('attempt to write to undeclared variable "' .. key .. '": '
            .. debug.traceback())
end

