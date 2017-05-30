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

=== TEST 1: message in ok packet (github #61)
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua_block {
        local mysql_driver = require "resty.mysql"

        local connect_table = {
            host = "$TEST_NGINX_MYSQL_HOST",
            port = $TEST_NGINX_MYSQL_PORT,
            database = "ngx_test",
            user     = 'ngx_test',
            password = 'ngx_test',
        }

        local connect_timeout = 1000
        local idle_timeout = 10000
        local pool_size = 50

        local function query(statement, compact, rows)
            local db, res, ok, err, errno, sqlstate
            db, err = mysql_driver:new()
            if not db then
                return nil, err
            end
            db:set_timeout(connect_timeout)
            res, err, errno, sqlstate = db:connect(connect_table)
            if not res then
                return nil, err, errno, sqlstate
            end
            db.compact = compact
            res, err, errno, sqlstate =  db:query(statement, rows)
            if res ~= nil then
                ok, err = db:set_keepalive(idle_timeout, pool_size)
                if not ok then
                    return nil, 'fail to set_keepalive:'..err
                end
            end
            return res, err, errno, sqlstate
        end

        local statements = {
            'drop table if exists test_usr',
            'create table test_usr (name varchar(10))',
            'insert into test_usr values ("name1")',
            'update test_usr set name="foo"',
        }

        local res, err
        for i, stm in ipairs(statements) do
            res, err = query(stm)
            if not res then
                return ngx.say(err)
            end
            if res.message then
                ngx.say(res.message)
            end
        end
    }
}
--- request
GET /t

--- response_body
Rows matched: 1  Changed: 1  Warnings: 0
--- no_error_log
[error]
