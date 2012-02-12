# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    resolver \$TEST_NGINX_RESOLVER;
    lua_package_path "$pwd/lib/?.lua;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;
$ENV{TEST_NGINX_MYSQL_HOST} ||= '127.0.0.1';

no_long_string();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: bad user
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "user_not_found",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            db:close()
        ';
    }
--- request
GET /t
--- response_body
failed to connect: Access denied for user 'user_not_found'@'localhost' (using password: YES): 1045 28000
--- no_error_log
[error]



=== TEST 2: bad host
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "host-not-found",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            db:close()
        ';
    }
--- request
GET /t
--- response_body
failed to connect: failed to connect: host-not-found could not be resolved (3: Host not found): nil nil
--- no_error_log
[error]



=== TEST 3: connected
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            ngx.say("connected to mysql ", db:server_ver())

            db:close()
        ';
    }
--- request
GET /t
--- response_body_like
connected to mysql \d\.\S+
--- no_error_log
[error]



=== TEST 4: send query
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            ngx.say("connected to mysql ", db:server_ver(), ".")

            local bytes, err = db:send_query("drop table if exists cats")
            if not bytes then
                ngx.say("failed to send query: ", err)
            end

            ngx.say("sent ", bytes, " bytes.")

            local res, err, errno, sqlstate = db:read_result()
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
            end

            local cjson = require "cjson"
            ngx.say("result: ", cjson.encode(res))

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body_like chop
^connected to mysql \d\.\S+\.
sent 30 bytes\.
result: {"insert_id":0,"server_status":2,"warning_count":1,"affected_rows":0,"message":""}$
--- no_error_log
[error]

