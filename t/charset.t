# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    resolver \$TEST_NGINX_RESOLVER;
    lua_package_path "$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    lua_package_cpath "/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;
$ENV{TEST_NGINX_MYSQL_HOST} ||= '127.0.0.1';
$ENV{TEST_NGINX_MYSQL_PATH} ||= '/var/run/mysql/mysql.sock';

#log_level 'warn';

#no_long_string();
no_shuffle();
check_accum_error_log();

run_tests();

__DATA__

=== TEST 1: connect db using charset option (utf8)
--- http_config eval: $::HttpConfig
--- config
    location /t {
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
    }
--- request
GET /t
--- response_body
[{"id":"1","name":"愛麗絲"}]
--- no_error_log
[error]



=== TEST 2: connect db using charset option (big5)
--- http_config eval: $::HttpConfig
--- config
    location /t {
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
    }
--- request
GET /t
--- response_body eval
qq/[{"id":"1","name":"\x{b7}R\x{c4}R\x{b5}\x{b7}"}]\n/
--- no_error_log
[error]



=== TEST 3: connect db using charset option (gbk)
--- http_config eval: $::HttpConfig
--- config
    location /t {
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
    }
--- request
GET /t
--- response_body eval
qq/[{"id":"1","name":"\x{90}\x{db}\x{fb}\x{90}\x{bd}z"}]\n/
--- no_error_log
[error]
