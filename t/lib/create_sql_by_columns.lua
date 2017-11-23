local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local concat = table.concat

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function(narr, nrec) return {} end
end

local _M = {}

function _M.create(num, engine)
    local bits = new_tab(num + 1, 0)
    bits[1] = "CREATE TABLE test" .. num .. " (id int(10) AUTO_INCREMENT, "
    for i = 2, num do
        bits[i] = "t" .. i - 1 .. " int(1) DEFAULT 0, "
    end

    if not engine then
        engine = "InnoDB"
    end
    bits[num + 1] = "PRIMARY KEY (id)) ENGINE=" .. engine

    return concat(bits, "")
end

function _M.drop(num)
    return "drop table if exists test" .. num
end

function _M.insert(num)
    return "insert into test" .. num .. " (t1) values(1)"
end

function _M.query(num)
    return "select * from test" .. num
end

return _M
