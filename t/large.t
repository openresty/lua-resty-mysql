# vim:set ft= ts=4 sw=4 et:
# set mysqld: max-allowed-packet=200m

my @skip;
BEGIN {
    if ($ENV{LD_PRELOAD} =~ /\bmockeagain\.so\b/) {
        @skip = (skip_all => 'too slow in mockeagain mode')
    }
}

use Test::Nginx::Socket @skip;
use Cwd qw(cwd);

#repeat_each(50);
#repeat_each(10);

plan tests => repeat_each() * (3 * blocks());

my $pwd = cwd();

our $HttpConfig = qq{
    resolver \$TEST_NGINX_RESOLVER;
    lua_package_path "$pwd/lib/?.lua;;";
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3301;
$ENV{TEST_NGINX_MYSQL_HOST} ||= '127.0.0.1';
$ENV{TEST_NGINX_MYSQL_PATH} ||= '/var/run/mysql/mysql.sock';

#log_level 'warn';

#no_long_string();
#no_diff();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: large insert_id
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local mysql = require("resty.mysql")
            local create_sql = [[
                CREATE TABLE `large_t` (
                    `id` bigint(11) NOT NULL AUTO_INCREMENT,
                    PRIMARY KEY (`id`)
                ) AUTO_INCREMENT=5000000000;
            ]]
            local drop_sql = [[
                DROP TABLE `large_t`;
            ]]
            local insert_sql = [[
                INSERT INTO `large_t` VALUES(NULL);
            ]]
            local db, err = mysql:new()
            if not db then
                ngx.say("failed to instantiate mysql: ", err)
                return
            end
            db:set_timeout(1000)
            local ok, err = db:connect{
                                       host = "$TEST_NGINX_MYSQL_HOST",
                                       port = $TEST_NGINX_MYSQL_PORT,
                                       database="test",
                                       user="root",
                                       password=""}
            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end
            local res, err = db:query(create_sql)
            if not res then
                ngx.say("create table error:" .. err)
                return
            end
            local res, err = db:query(insert_sql)
            if not res then
                ngx.say("insert table error:" .. err)
                return
            else
                ngx.say(res.insert_id)
            end
            local res, err = db:query(drop_sql)
            if not res then
                ngx.say("drop table error:" .. err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body
5000000000
--- no_error_log
[error]

=== TEST 2: large query
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local mysql = require("resty.mysql")
            local db, err = mysql:new()
            if not db then
                ngx.say("failed to instantiate mysql: ", err)
                return
            end
            db:set_timeout(1000)
            local ok, err = db:connect{
                                       host = "$TEST_NGINX_MYSQL_HOST",
                                       port = $TEST_NGINX_MYSQL_PORT,
                                       database="test",
                                       user="root",
                                       password=""}
            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end
            local fix_str = string.format("/* %s       */",string.rep("aaaaaaaaaa",1677721 * 2 - 2))
            local query = fix_str .. "select 123 as ok"
            local res, err = db:query(query)
            if not res then
                ngx.say("select string error:" .. err)
                return
            else
                ngx.say(res[1].ok)
            end
        ';
    }
--- request
GET /t
--- response_body
123
--- no_error_log
[error]

=== TEST 3: large row
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua '
            local mysql = require("resty.mysql")
            local db, err = mysql:new()
            if not db then
                ngx.say("failed to instantiate mysql: ", err)
                return
            end
            db:set_timeout(1000)
            local ok, err = db:connect{
                                       host = "$TEST_NGINX_MYSQL_HOST",
                                       port = $TEST_NGINX_MYSQL_PORT,
                                       database="test",
                                       user="root",
                                       password="",
                                       max_packet_size=16777215}
            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end
            local create_sql = [[
                                   CREATE TABLE `large_row_t`(id int, data1 longtext , data2 longtext);
                               ]]
            local drop_sql = [[
                                 DROP TABLE `large_row_t` 
                             ]]
            local data = string.rep("a", 16777000)
            local insert_sql = "INSERT INTO `large_row_t`(id, data1) VALUES(1, \'".. data .."\')"
            local update_sql = "UPDATE `large_row_t` SET data2=data1"
            local select_sql = "SELECT * FROM `large_row_t`"
            local res, err = db:query(create_sql)
            if not res then
                ngx.say("create table error:" .. err)
                return
            end
            local res, err = db:query(insert_sql)
            if not res then
                ngx.say("insert data error:" .. err)
                return
            end
            local res, err = db:query(update_sql)
            if not res then
                ngx.say("update data error:" .. err)
                return
            end
            local res, err = db:query(select_sql)
            if not res then
                ngx.say("select data error:" .. err)
                return
            else
                ngx.say(#res)
            end
            local res, err = db:query(drop_sql)
            if not res then
                ngx.say("drop table error:" .. err)
                return
            end
        ';
    }
--- request
GET /t
--- response_body
1
--- no_error_log
[error]
