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

=== TEST 1: prepare
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local ljson = require "ljson"
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

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats dropped.")
            
            local res, err, errcode, sqlstate =
                db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
                return
            end

            res, err, errcode, sqlstate =
                db:query("create table cats "
                         .. "(id serial primary key, "
                         .. "name varchar(5))")
            if not res then
                ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errcode, sqlstate =
                db:query("insert into cats (name) "
                         .. "values ('Bob'),(''),(null)")
            if not res then
                ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows, " rows inserted into table cats ",
                    "(last insert id: ", res.insert_id, ")")

            local statement_id, err = db:prepare([[SELECT id
                                     FROM cats WHERE id = ? OR id = ?]])
            if err then
                ngx.say("prepare failed:", err)
                return
            end

            ngx.say("prepare success:", statement_id)

            local res, err = db:execute(statement_id, 1, 2)
            if err then
                ngx.say("execute failed.", err)
                return
            end

            ngx.say("execute success:", ljson.encode(res))

            -- put it into the connection pool of size 100,
            -- with 10 seconds max idle timeout
            -- local ok, err = db:set_keepalive(10000, 100)
            -- if not ok then
            --     ngx.say("failed to set keepalive: ", err)
            --     return
            -- end

            -- or just close the connection right away:
            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        }
    }
--- request
GET /t
--- response_body
connected to mysql.
table cats dropped.
table cats created.
3 rows inserted into table cats (last insert id: 1)
prepare success:1
execute success:[{"id":1},{"id":2}]
--- no_error_log
[error]


=== TEST 2: prepare number type
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local ljson = require "ljson"
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

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.say("drop table bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats dropped.")
            

            res, err, errcode, sqlstate =
                db:query("create table cats "
                         .. "(u_tiny TINYINT, "
                         .. "u_bit   BIT(64),"
                         .. "bool    BOOL,"
                         .. "u_small SMALLINT,"     -- 4
                         .. "u_int   INT,"     
                         .. "u_integer INTEGER,"
                         .. "u_bigint  BIGINT,"
                         .. "u_float   FLOAT,"      -- 8
                         .. "u_double  DOUBLE,"
                         .. "u_real    REAL,"
                         .. "u_decimal DECIMAL,"
                         .. "u_dec     DEC,"        -- 12
                         .. "u_num     NUMERIC)")
            if not res then
                ngx.say("create table bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errcode, sqlstate =
                db:query("insert into cats "
                         .. "values (1, 2, true, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13)")
            if not res then
                ngx.say("insert values bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows, " rows inserted into table cats ",
                    "(last insert id: ", res.insert_id, ")")

            local statement_id, err = db:prepare([[SELECT *
                                     FROM cats WHERE u_tiny = ?]])
            if err then
                ngx.say("prepare failed:", err)
                return
            end

            ngx.say("prepare success:", statement_id)

            local res, err = db:execute(statement_id, 1)
            if err then
                ngx.say("execute failed.", err)
                return
            end

            ngx.say("execute success:", ljson.encode(res))

            -- put it into the connection pool of size 100,
            -- with 10 seconds max idle timeout
            -- local ok, err = db:set_keepalive(10000, 100)
            -- if not ok then
            --     ngx.say("failed to set keepalive: ", err)
            --     return
            -- end

            -- or just close the connection right away:
            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        }
    }
--- request
GET /t
--- response_body
connected to mysql.
table cats dropped.
table cats created.
1 rows inserted into table cats (last insert id: 0)
prepare success:1
execute success:[{"bool":1,"u_bigint":7,"u_bit":2,"u_dec":"12","u_decimal":"11","u_double":9,"u_float":8,"u_int":5,"u_integer":6,"u_num":"13","u_real":10,"u_small":4,"u_tiny":1}]
--- no_error_log
[error]




=== TEST 3: prepare string type except ENUM, SET
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local ljson = require "ljson"
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

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.say("drop table bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats dropped.")
            

            res, err, errcode, sqlstate =
                db:query("create table cats "
                         .. "(u_char        CHAR, "
                         .. "u_varchar      VARCHAR(12),"
                         .. "u_tinyblob     TINYBLOB,"
                         .. "u_tinytext     TINYTEXT,"     -- 4
                         .. "u_blob         BLOB,"     
                         .. "u_text         TEXT,"
                         .. "u_mblob        MEDIUMBLOB,"
                         .. "u_mtext        MEDIUMTEXT,"      -- 8
                         .. "u_lblob        LONGBLOB,"
                         .. "u_ltext        LONGTEXT"
                         .. ")")
            if not res then
                ngx.say("create table bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errcode, sqlstate =
                db:query("insert into cats "
                         .. "values ('c', 'varchar', 'tinyblob', 'u_tinytext', "
                         .. " 'u_blob', 'u_text', 'u_mblob', 'u_mtext', 'u_lblob',"
                         .. " 'u_ltext')")
            if not res then
                ngx.say("insert values bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows, " rows inserted into table cats ",
                    "(last insert id: ", res.insert_id, ")")

            local statement_id, err = db:prepare([[SELECT *
                                     FROM cats WHERE u_char = ?]])
            if err then
                ngx.say("prepare failed:", err)
                return
            end

            ngx.say("prepare success:", statement_id)

            local res, err = db:execute(statement_id, 'c')
            if err then
                ngx.say("execute failed.", err)
                return
            end

            ngx.say("execute success:", ljson.encode(res))

            -- put it into the connection pool of size 100,
            -- with 10 seconds max idle timeout
            -- local ok, err = db:set_keepalive(10000, 100)
            -- if not ok then
            --     ngx.say("failed to set keepalive: ", err)
            --     return
            -- end

            -- or just close the connection right away:
            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        }
    }
--- request
GET /t
--- response_body
connected to mysql.
table cats dropped.
table cats created.
1 rows inserted into table cats (last insert id: 0)
prepare success:1
execute success:[{"u_blob":"u_blob","u_char":"c","u_lblob":"u_lblob","u_ltext":"u_ltext","u_mblob":"u_mblob","u_mtext":"u_mtext","u_text":"u_text","u_tinyblob":"tinyblob","u_tinytext":"u_tinytext","u_varchar":"varchar"}]
--- no_error_log
[error]



=== TEST 4: prepare type: ENUM, SET
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local ljson = require "ljson"
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

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.say("drop table bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats dropped.")
            

            res, err, errcode, sqlstate =
                db:query("create table cats "
                         .. "(id        integer, "
                         .. "u_enum     ENUM('e_1','e_2','e_3'),"
                         .. "u_set      SET('a', 'b', 'c')"
                         .. ")")
            if not res then
                ngx.say("create table bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errcode, sqlstate =
                db:query("insert into cats "
                         .. "values (1, "
                         .. "2, "
                         .. " ('a,c'))")
            if not res then
                ngx.say("insert values bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows, " rows inserted into table cats ",
                    "(last insert id: ", res.insert_id, ")")

            local statement_id, err = db:prepare([[SELECT *
                                     FROM cats WHERE id = ?]])
            if err then
                ngx.say("prepare failed:", err)
                return
            end

            ngx.say("prepare success:", statement_id)

            local res, err = db:execute(statement_id, 1)
            if err then
                ngx.say("execute failed.", err)
                return
            end

            ngx.say("execute success:", ljson.encode(res))

            -- put it into the connection pool of size 100,
            -- with 10 seconds max idle timeout
            -- local ok, err = db:set_keepalive(10000, 100)
            -- if not ok then
            --     ngx.say("failed to set keepalive: ", err)
            --     return
            -- end

            -- or just close the connection right away:
            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        }
    }
--- request
GET /t
--- response_body
connected to mysql.
table cats dropped.
table cats created.
1 rows inserted into table cats (last insert id: 0)
prepare success:1
execute success:[{"id":1,"u_enum":"e_2","u_set":"a,c"}]
--- no_error_log
[error]



=== TEST 5: prepare type: datetime
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local ljson = require "ljson"
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

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.say("drop table bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats dropped.")
            

            res, err, errcode, sqlstate =
                db:query("create table cats "
                         .. "(id      integer, "
                         .. "u_dt     DATETIME,"
                         .. "u_d      DATE,"
                         .. "u_ts     TIMESTAMP,"
                         .. "u_t      TIME,"
                         .. "u_y      YEAR"
                         .. ")")
            if not res then
                ngx.say("create table bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errcode, sqlstate =
                db:query("insert into cats "
                         .. "values (1, "
                         .. "'2016-08-23 07:09:51', "
                         .. "'2016-08-23 07:09:51', "
                         .. "'2016-08-23 07:09:51', "
                         .. "'2016-08-23 07:09:51', "
                         .. "'2016')")
            if not res then
                ngx.say("insert values bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows, " rows inserted into table cats ",
                    "(last insert id: ", res.insert_id, ")")

            local statement_id, err = db:prepare([[SELECT *
                                     FROM cats WHERE id = ?]])
            if err then
                ngx.say("prepare failed:", err)
                return
            end

            ngx.say("prepare success:", statement_id)

            local res, err = db:execute(statement_id, 1)
            if err then
                ngx.say("execute failed.", err)
                return
            end

            ngx.say("execute success:", ljson.encode(res))

            -- put it into the connection pool of size 100,
            -- with 10 seconds max idle timeout
            -- local ok, err = db:set_keepalive(10000, 100)
            -- if not ok then
            --     ngx.say("failed to set keepalive: ", err)
            --     return
            -- end

            -- or just close the connection right away:
            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        }
    }
--- request
GET /t
--- response_body
connected to mysql.
table cats dropped.
table cats created.
1 rows inserted into table cats (last insert id: 0)
prepare success:1
execute success:[{"id":1,"u_d":"2016-08-23","u_dt":"2016-08-23 07:09:51","u_t":"07:09:51","u_ts":"2016-08-23 07:09:51","u_y":2016}]
--- no_error_log
[error]

