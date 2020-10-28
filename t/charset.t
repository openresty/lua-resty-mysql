# vim:set ft= ts=4 sw=4 et:

use t::Test;

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

#log_level 'warn';

#no_long_string();
no_shuffle();
check_accum_error_log();

run_tests();

__DATA__

=== TEST 1: connect db using charset option (utf8)
--- server_config
        content_by_lua_block {
            local ljson = require "ljson"
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                path     = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user     = "ngx_test",
                password = "ngx_test",
                charset  = "utf8",
                pool     = "my_pool"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            -- generate test data
            local res, err, errno, sqlstate = db:query("DROP TABLE IF EXISTS cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query("CREATE TABLE cats (id serial PRIMARY KEY, name VARCHAR(128)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            -- add new record with '愛麗絲' by utf8 encoded.
            res, err, errno, sqlstate = db:query("INSERT INTO cats(name) VALUES (0xe6849be9ba97e7b5b2)")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query("SELECT * FROM cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            db:close()

            ngx.say(ljson.encode(res))
        }
--- response_body
[{"id":"1","name":"愛麗絲"}]
--- no_error_log
[error]



=== TEST 2: connect db using charset option (big5)
--- server_config
        content_by_lua_block {
            local ljson = require "ljson"
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                path     = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user     = "ngx_test",
                password = "ngx_test",
                charset  = "big5",
                pool     = "my_pool"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            -- generate test data
            local res, err, errno, sqlstate = db:query("DROP TABLE IF EXISTS cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query("CREATE TABLE cats (id serial PRIMARY KEY, name VARCHAR(128)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            -- add new record with '愛麗絲' by utf8 encoded.
            res, err, errno, sqlstate = db:query("INSERT INTO cats(name) VALUES (0xe6849be9ba97e7b5b2)")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query("SELECT * FROM cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            db:close()

            ngx.say(ljson.encode(res))
        }
--- response_body eval
qq/[{"id":"1","name":"\x{b7}R\x{c4}R\x{b5}\x{b7}"}]\n/
--- no_error_log
[error]



=== TEST 3: connect db using charset option (gbk)
--- server_config
        content_by_lua_block {
            local ljson = require "ljson"
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                path     = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user     = "ngx_test",
                password = "ngx_test",
                charset  = "gbk",
                pool     = "my_pool"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            -- generate test data
            local res, err, errno, sqlstate = db:query("DROP TABLE IF EXISTS cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query("CREATE TABLE cats (id serial PRIMARY KEY, name VARCHAR(128)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            -- add new record with '愛麗絲' by utf8 encoded.
            res, err, errno, sqlstate = db:query("INSERT INTO cats(name) VALUES (0xe6849be9ba97e7b5b2)")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query("SELECT * FROM cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            db:close()

            ngx.say(ljson.encode(res))
        }
--- response_body eval
qq/[{"id":"1","name":"\x{90}\x{db}\x{fb}\x{90}\x{bd}z"}]\n/
--- no_error_log
[error]
