# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua::Stream;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $StreamConfig = qq{
    resolver \$TEST_NGINX_RESOLVER;
    lua_package_path "$pwd/lib/?.lua;$pwd/t/lib/?.lua;;";
    lua_package_cpath "/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;
$ENV{TEST_NGINX_MYSQL_HOST} ||= '127.0.0.1';
$ENV{TEST_NGINX_MYSQL_PATH} ||= '/var/run/mysql/mysql.sock';

#log_level 'warn';

no_long_string();
no_shuffle();
check_accum_error_log();

run_tests();

__DATA__

=== TEST 1: connected (support in stream module)
--- stream_config eval: $::StreamConfig
--- stream_server_config
    content_by_lua_block {
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
    }
--- response_body_like
connected to mysql \d\.[^\s\x00]+
--- no_error_log
[error]
