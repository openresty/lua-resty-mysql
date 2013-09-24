# vim:set ft= ts=4 sw=4 et:

my @skip;
BEGIN {
    if ($ENV{LD_PRELOAD} =~ /\bmockeagain\.so\b/) {
        @skip = (skip_all => 'too slow in mockeagain mode')
    }
}

use Test::Nginx::Socket @skip;
use Cwd qw(cwd);

repeat_each(1);
#repeat_each(10);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    resolver \$TEST_NGINX_RESOLVER;
    lua_package_path "$pwd/lib/?.lua;;";
    lua_package_cpath "/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;
$ENV{TEST_NGINX_MYSQL_HOST} ||= '127.0.0.1';
$ENV{TEST_NGINX_MYSQL_PATH} ||= '/var/run/mysql/mysql.sock';

#log_level 'warn';

#no_long_string();
#no_diff();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: set charset utf8 通过mysql 状态测试
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local cjson = require "cjson"

            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(2000) -- 2 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test",
                charset ="utf8"
             })

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

             res, err, errno, sqlstate =
                      db:query("show variables like \'%%character_set_client%%\'") 
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

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
--- response_body eval
'connected to mysql.
result: [{"Value":"utf8","Variable_name":"character_set_client"}]' . "\n"
--- no_error_log
[error]


=== TEST 2: not set charset 测试向下兼容，即不输入charset ，字符依赖服务端配置
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local cjson = require "cjson"

            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(2000) -- 2 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test",
             })

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

             res, err, errno, sqlstate =
                      db:query("show variables like \'%%character_set_client%%\'") 
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

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
--- response_body eval
'connected to mysql.
result: [{"Value":"latin1","Variable_name":"character_set_client"}]' . "\n"
--- no_error_log
[error]



=== TEST 3: set not supported charset 设置不支持的字符时，预期异常
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local cjson = require "cjson"

            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(2000) -- 2 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test",
                charset ="ut"
             })

            if not ok then
                ngx.say("failed to connect: ", err )
                return
            end

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

             res, err, errno, sqlstate =
                      db:query("show variables like \'%%character_set_client%%\'") 
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

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
--- response_body eval
'failed to connect: charset ut is not supported' . "\n"
--- no_error_log
[error]


=== TEST 4: set utf8 ,insert chainse char 检查输入utf8 中文是否乱码
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local cjson = require "cjson"

            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(2000) -- 2 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test",
                charset ="utf8"
             })

            if not ok then
                ngx.say("failed to connect: ", err )
                return
            end

            -- ngx.say("connected to mysql.")

            local res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.log(ngx.ERROR,"badresult" ,errno)
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end
             res, err, errno, sqlstate =
                db:query("create table cats "
                         .. "(id serial primary key, "
                         .. "name varchar(5)) charset=utf8")
            if not res then
                 ngx.log(ngx.ERROR,"badresult" ,errno)
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end
            res, err, errno, sqlstate =
                db:query("insert into cats (name) "
                         .. "values (\'你好，春哥\')")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end
            res, err, errno, sqlstate =
                db:query("select name from cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end
            ngx.say(res[1].name)

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body eval
'你好，春哥' . "\n"
--- no_error_log
[error]








