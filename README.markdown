Name
====

lua-resty-mysql - Lua MySQL client driver for the ngx_lua based on the cosocket API

Status
======

This library is considered experimental and still under active development.

The API is still in flux and may change without notice.

Description
===========

This Lua library is a MySQL client driver for the ngx_lua nginx module:

http://wiki.nginx.org/HttpLuaModule

This Lua library takes advantage of ngx_lua's cosocket API, which ensures
100% nonblocking behavior.

Note that at least [ngx_lua 0.5.0rc6](https://github.com/chaoslawful/lua-nginx-module/tags) or [ngx_openresty 1.0.11.9](http://openresty.org/#Download) is required.

Also, the [bit library](http://bitop.luajit.org/) is also required. If you're using LuaJIT 2.0 with ngx_lua, then this library is already available by default.

Synopsis
========

    lua_package_path "/path/to/lua-resty-mysql/lib/?.lua;;";

    server {
        location /test {
            content_by_lua '
                local mysql = require "resty.mysql"
                local db = mysql:new()

                db:set_timeout(1000) -- 1 sec

                -- or connect to a unix domain socket file listened
                -- by a mysql server:
                --     local ok, err, errno, sqlstate =
                --           db:connect{
                --              path = "unix:/path/to/mysql.sock",
                --              database = "ngx_test",
                --              user = "ngx_test",
                --              password = "ngx_test" }

                local ok, err, errno, sqlstate = db:connect{
                    host = "127.0.0.1",
                    port = 3306,
                    database = "ngx_test",
                    user = "ngx_test",
                    password = "ngx_test",
                    max_packet_size = 1024 * 1024 }

                if not ok then
                    ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                    return
                end

                ngx.say("connected to mysql.")

                local res, err, errno, sqlstate =
                    db:query("drop table if exists cats")
                if not res then
                    ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                    return
                end

                res, err, errno, sqlstate =
                    db:query("create table cats "
                             .. "(id serial primary key, "
                             .. "name varchar(5))")
                if not res then
                    ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                    return
                end

                ngx.say("table cats created.")

                res, err, errno, sqlstate =
                    db:query("insert into cats (name) "
                             .. "values (\'Bob\'),(\'\'),(null)")
                if not res then
                    ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                    return
                end

                ngx.say(res.affected_rows, " rows inserted into table cats (last id: ", res.insert_id, ")")

                res, err, errno, sqlstate =
                    db:query("select * from cats order by id asc")
                if not res then
                    ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                    return
                end

                local cjson = require "cjson"
                ngx.say("result: ", cjson.encode(res))

                -- put it into the connection pool of size 100,
                -- with 0 idle timeout
                local ok, err = db:set_keepalive(0, 100)
                if not ok then
                    ngx.say("failed to set keepalive: ", err)
                    return
                end

                -- or just close the connection right away:
                -- local ok, err = db:close()
                -- if not ok then
                --     ngx.say("failed to close: ", err)
                --     return
                -- end
            ';
        }
    }

Methods
=======

new
---
`syntax: db = mysql:new()`

Creates a MySQL connection object. Returns `nil` on error.

connect
-------
`syntax: ok, err = db:connect(options)`

Attempts to connect to the remote MySQL server.

The `options` argument is a Lua table holding the following keys:

* host: the host name for the MySQL server.
* port: the port that the MySQL server is listening on. Default to 3306.
* path: the path of the unix socket file listened by the MySQL server.
* user: MySQL account name for login.
* password: MySQL account password for login (in clear text).
* max_packet_size: the upper limit for the reply packets sent from the MySQL server (default to 100 KB).

Before actually resolving the host name and connecting to the remote backend, this method will always look up the connection pool for matched idle connections created by previous calls of this method.

set_timeout
----------
`syntax: db:set_timeout(time)`

Sets the timeout (in ms) protection for subsequent operations, including the `connect` method.

set_keepalive
------------
`syntax: ok, err = db:set_keepalive(max_idle_timeout, pool_size)`

Keeps the current MySQL connection alive and put it into the ngx_lua cosocket connection pool.

You can specify the max idle timeout (in ms) when the connection is in the pool and the maximal size of the pool every nginx worker process.

In case of success, returns `1`. In case of errors, returns `nil` with a string describing the error.

get_reused_times
----------------
`syntax: db:set_keepalive(max_idle_timeout, pool_size)`

This method returns the (successfully) reused times for the current connection. In case of error, it returns `nil` and a string describing the error.

If the current connection does not come from the built-in connection pool, then this method always returns `0`, that is, the connection has never been reused (yet). If the connection comes from the connection pool, then the return value is always non-zero. So this method can also be used to determine if the current connection comes from the pool.

close
-----
`syntax: ok, err = db:close()`

Closes the current mysql connection and returns the status.

In case of success, returns `1`. In case of errors, returns `nil` with a string describing the error.

Debugging
=========

It is usually convenient to use the [lua-cjson](http://www.kyne.com.au/~mark/software/lua-cjson.php) library to encode the return values of the MySQL query methods to JSON. For example,

    local cjson = require "cjson"
    ...
    local res, err, errcode, sqlstate = db:query("select * from cats")
    if res then
        print("res: ", cjson.encode(res))
    end

TODO
====

* improve the MySQL connection pool support.
* implement the MySQL binary row data packets.
* implement MySQL's old pre-4.0 authentication method.
* implement MySQL server prepare and execute packets.
* implement the data compression support in the protocol.

Author
======

Zhang "agentzh" Yichun (章亦春) <agentzh@gmail.com>

Copyright and License
=====================

This module is licensed under the BSD license.

Copyright (C) 2012, by Zhang "agentzh" Yichun (章亦春) <agentzh@gmail.com>.

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

See Also
========
* the ngx_lua module: http://wiki.nginx.org/HttpLuaModule
* the MySQL wired protocol specification: http://forge.mysql.com/wiki/MySQL_Internals_ClientServer_Protocol
* the lua-resty-memcached library: https://github.com/agentzh/lua-resty-memcached
* the lua-resty-redis library: https://github.com/agentzh/lua-resty-redis

