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

no_long_string();
no_shuffle();
check_accum_error_log();

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
                host = "localhost",
                port = 3306,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            ngx.say("connected to mysql.")


            db:query([[create table prepare_test(id integer)]])
            db:query("insert into prepare_test(id) values(1)")

            local stmt, err = db:prepare([[SELECT id as a, id as b, id as c FROM prepare_test WHERE id = ? OR id = ? OR id = ?]])
            if err then
                ngx.say("prepare failed:", err)
            end

            local ljson = require "ljson"
            ngx.say("prepare success:", ljson.encode(stmt)) 

            local res, err = db:execute(stmt.statement_id, 1, 2, 3)
            if err then
                ngx.say("execute failed.", err)
            end

            ngx.say("execute success:", ljson.encode(res))

            db:query([[drop table prepare_test]])
            
            db:close()
        ';
    }
--- request
GET /t
--- response_body
connected to mysql.
prepare success:{"columns":3,"field_count":0,"parameters":3,"result_set":{"field_count":3,"fields":[{"name":"a","type":3},{"name":"b","type":3},{"name":"c","type":3}]},"statement_id":1,"warnings":0}
execute success:[{"a":1,"b":1,"c":1}]
--- no_error_log
[error]
