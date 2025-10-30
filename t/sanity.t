# vim:set ft= ts=4 sw=4 et:

use t::Test;

repeat_each(2);

plan tests => repeat_each() * (3 * blocks() + 4);

#log_level 'warn';

no_long_string();
no_shuffle();
check_accum_error_log();

run_tests();

__DATA__

=== TEST 1: bad user
--- server_config
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
--- response_body_like
failed to connect: Access denied for user 'user_not_found'@'[^\s]+' \(using password: YES\): 1045 28000
--- no_error_log
[error]



=== TEST 2: bad host
--- server_config
        content_by_lua '
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "host-not-found.org",
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
--- response_body_like chop
^failed to connect: failed to connect: host-not-found.org could not be resolved(?: \(3: Host not found\))?: nil nil$
--- no_error_log
[error]
--- timeout: 7



=== TEST 3: connected
--- server_config
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
--- response_body_like
connected to mysql \d\.[^\s\x00]+
--- no_error_log
[error]



=== TEST 4: send query w/o result set
--- server_config
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

            local ljson = require "ljson"
            ngx.say("result: ", ljson.encode(res))

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
--- response_body_like chop
^connected to mysql \d\.[^\s\x00]+\.
sent 30 bytes\.
result: \{"affected_rows":0,"insert_id":0,"server_status":2,"warning_count":[01]\}$
--- no_error_log
[error]



=== TEST 5: send bad query
--- server_config
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

            local bytes, err = db:send_query("bad SQL")
            if not bytes then
                ngx.say("failed to send query: ", err)
            end

            ngx.say("sent ", bytes, " bytes.")

            local res, err, errno, sqlstate = db:read_result()
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            local ljson = require "ljson"
            ngx.say("result: ", ljson.encode(res))

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
--- response_body_like chop
^connected to mysql \d\.[^\s\x00]+\.
sent 12 bytes\.
bad result: You have an error in your SQL syntax; check the manual that corresponds to your (?:MySQL|MariaDB) server version for the right syntax to use near 'bad SQL' at line 1: 1064: 42000\.$
--- no_error_log
[error]



=== TEST 6: select query with an non-empty result set
--- server_config
        content_by_lua '
            local ljson = require "ljson"

            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(2000) -- 2 sec

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

            res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name varchar(5))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errno, sqlstate = db:query("insert into cats (name) value (\'Bob\'),(\'\'),(null)")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows, " rows inserted into table cats (last id: ", res.insert_id, ")")

            res, err, errno, sqlstate = db:query("select * from cats order by id asc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res))

            res, err, errno, sqlstate = db:query("select * from cats order by id desc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res))

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
--- response_body
connected to mysql.
table cats dropped.
table cats created.
3 rows inserted into table cats (last id: 1)
result: [{"id":"1","name":"Bob"},{"id":"2","name":""},{"id":"3","name":null}]
result: [{"id":"3","name":null},{"id":"2","name":""},{"id":"1","name":"Bob"}]
--- no_error_log
[error]



=== TEST 7: select query with an empty result set
--- server_config
        content_by_lua '
            local ljson = require "ljson"

            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(2000) -- 2 sec

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

            res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name varchar(5))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errno, sqlstate = db:query("select * from cats order by id asc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res))

            res, err, errno, sqlstate = db:query("select * from cats order by id desc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res))

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
--- response_body
connected to mysql.
table cats dropped.
table cats created.
result: []
result: []
--- no_error_log
[error]



=== TEST 8: numerical types
--- server_config
        content_by_lua '
            local ljson = require "ljson"

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

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate = db:query("drop table if exists foo")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table foo dropped.")

            res, err, errno, sqlstate = db:query("create table foo (id serial primary key, bar tinyint, baz smallint, bah float, blah double, kah bigint, hah mediumint, haha year, lah int)")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table foo created.")

            res, err, errno, sqlstate = db:query("insert into foo (bar, baz, bah, blah, kah, hah, haha, lah) value (3, 4, 3.14, 5.16, 65535, 256, 1998, 579),(null, null, null, null, null, null, null, null)")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows, " rows inserted into table foo (last id: ", res.insert_id, ")")

            res, err, errno, sqlstate = db:query("select * from foo order by id asc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res))

            res, err, errno, sqlstate = db:query("select * from foo order by id desc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res))

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
--- response_body
connected to mysql.
table foo dropped.
table foo created.
2 rows inserted into table foo (last id: 1)
result: [{"bah":3.14,"bar":3,"baz":4,"blah":5.16,"hah":256,"haha":1998,"id":"1","kah":"65535","lah":579},{"bah":null,"bar":null,"baz":null,"blah":null,"hah":null,"haha":null,"id":"2","kah":null,"lah":null}]
result: [{"bah":null,"bar":null,"baz":null,"blah":null,"hah":null,"haha":null,"id":"2","kah":null,"lah":null},{"bah":3.14,"bar":3,"baz":4,"blah":5.16,"hah":256,"haha":1998,"id":"1","kah":"65535","lah":579}]
--- no_error_log
[error]
--- timeout: 5



=== TEST 9: multiple DDL statements
--- server_config
        content_by_lua '
            local ljson = require "ljson"

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

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate =
                db:query("drop table if exists foo; "
                         .. "create table foo (id serial primary key, name text);")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res), ", err:", err)

            res, err, errno, sqlstate =
                db:query("select * from foo order by id asc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            else
                ngx.say("result: ", ljson.encode(res), ", err:", err)
            end

            res, err, errno, sqlstate = db:read_result()
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            else
                ngx.say("result: ", ljson.encode(res), ", err:", err)
            end

            res, err, errno, sqlstate =
                db:query("select * from foo order by id asc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            else
                ngx.say("result: ", ljson.encode(res), ", err:", err)
            end

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
--- response_body
connected to mysql.
result: {"affected_rows":0,"insert_id":0,"server_status":10,"warning_count":0}, err:again
bad result: failed to send query: cannot send query in the current context: 2: nil: nil.
--- no_error_log
[error]



=== TEST 10: multiple select queries
--- server_config
        content_by_lua '
            local ljson = require "ljson"

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

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate =
                db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats dropped.")

            res, err, errno, sqlstate =
                db:query("create table cats "
                         .. "(id serial primary key, name varchar(5))")
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

            ngx.say(res.affected_rows .. " rows inserted into table cats (last id: ", res.insert_id, ")")

            res, err, errno, sqlstate =
                db:query("select * from cats order by id asc; "
                         .. "select * from cats order by id desc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res), ", err:", err)

            res, err, errno, sqlstate = db:read_result()
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res), ", err:", err)

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
--- response_body
connected to mysql.
table cats dropped.
table cats created.
3 rows inserted into table cats (last id: 1)
result: [{"id":"1","name":"Bob"},{"id":"2","name":""},{"id":"3","name":null}], err:again
result: [{"id":"3","name":null},{"id":"2","name":""},{"id":"1","name":"Bob"}], err:nil
--- no_error_log
[error]



=== TEST 11: set_keepalive in the wrong state
--- server_config
        content_by_lua '
            local ljson = require "ljson"

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

            ngx.say("connected to mysql.")

            local res, err, errno, sqlstate =
                db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats dropped.")

            res, err, errno, sqlstate =
                db:query("create table cats "
                         .. "(id serial primary key, name varchar(5))")
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

            ngx.say(res.affected_rows .. " rows inserted into table cats (last id: ", res.insert_id, ")")

            res, err, errno, sqlstate =
                db:query("select * from cats order by id asc; "
                         .. "select * from cats order by id desc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res), ", err:", err)

            local ok, err = db:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end
        ';
--- response_body
connected to mysql.
table cats dropped.
table cats created.
3 rows inserted into table cats (last id: 1)
result: [{"id":"1","name":"Bob"},{"id":"2","name":""},{"id":"3","name":null}], err:again
failed to set keepalive: cannot be reused in the current connection state: 2
--- no_error_log
[error]



=== TEST 12: set keepalive (tcp)
--- server_config
        content_by_lua '
            local ljson = require "ljson"

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

            ngx.say("connected to mysql: ", db:get_reused_times())

            local ok, err = db:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end

            ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            ngx.say("connected to mysql: ", db:get_reused_times())

            local res, err, errno, sqlstate =
                db:query("select * from cats order by id asc;")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res), ", err:", err)

            local ok, err = db:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end
        ';
--- response_body_like chop
^connected to mysql: [02]
connected to mysql: [13]
result: \[\{"id":"1","name":"Bob"\},\{"id":"2","name":""\},\{"id":"3","name":null\}\], err:nil$
--- no_error_log
[error]
--- error_log eval
qr/lua tcp socket keepalive create connection pool for key "ngx_test:ngx_test:[^\s:]+:\d+"/
--- log_level: debug
--- wait: 0.3



=== TEST 13: send query w/o result set (unix domain socket)
--- server_config
        content_by_lua '
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                path = "$TEST_NGINX_MYSQL_PATH",
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

            local ljson = require "ljson"
            ngx.say("result: ", ljson.encode(res))

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
--- response_body_like chop
^connected to mysql \d\.[^\s\x00]+\.
sent 30 bytes\.
result: (?:\{"insert_id":0,"server_status":2,"warning_count":1,"affected_rows":0}|{"affected_rows":0,"insert_id":0,"server_status":2,"warning_count":[01]\})$
--- no_error_log
[error]



=== TEST 14: null at the beginning of a row
--- server_config
        content_by_lua '
            local ljson = require "ljson"

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

            ngx.say("connected to mysql.")

            local res
            res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats dropped.")

            res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name varchar(5))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errno, sqlstate = db:query("insert into cats (name) value (\'Bob\'),(\'\'),(null)")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows, " rows inserted into table cats (last id: ", res.insert_id, ")")

            res, err, errno, sqlstate = db:query("select name from cats order by id asc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res))

            res, err, errno, sqlstate = db:query("select name from cats order by id desc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res))

            local ok, err = db:close()
            if not ok then
                ngx.say("failed to close: ", err)
                return
            end
        ';
--- response_body
connected to mysql.
table cats dropped.
table cats created.
3 rows inserted into table cats (last id: 1)
result: [{"name":"Bob"},{"name":""},{"name":null}]
result: [{"name":null},{"name":""},{"name":"Bob"}]
--- no_error_log
[error]



=== TEST 15: set keepalive (uds)
--- server_config
        content_by_lua '
            local ljson = require "ljson"

            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                path = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            ngx.say("connected to mysql: ", db:get_reused_times())

            local ok, err = db:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end

            ok, err, errno, sqlstate = db:connect({
                path = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            ngx.say("connected to mysql: ", db:get_reused_times())

            local res
            res, err, errno, sqlstate =
                db:query("select * from cats order by id asc;")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res), ", err:", err)

            local ok, err = db:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end
        ';
--- response_body_like chop
^connected to mysql: [02]
connected to mysql: [13]
result: \[\{"id":"1","name":"Bob"\},\{"id":"2","name":""\},\{"id":"3","name":null\}\], err:nil$
--- no_error_log
[error]
--- error_log eval
qr/lua tcp socket keepalive create connection pool for key "ngx_test:ngx_test:[^\s:]+"/
--- log_level: debug
--- wait: 0.3



=== TEST 16: set keepalive (explicit pool name)
--- server_config
        content_by_lua '
            local ljson = require "ljson"

            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                path = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test",
                pool = "my_pool"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            ngx.say("connected to mysql: ", db:get_reused_times())

            local ok, err = db:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end

            ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test",
                pool = "my_pool"})

            ngx.say("connected to mysql: ", db:get_reused_times())

            local res
            res, err, errno, sqlstate =
                db:query("select * from cats order by id asc;")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res), ", err:", err)

            local ok, err = db:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end
        ';
--- response_body_like chop
^connected to mysql: [02]
connected to mysql: [13]
result: \[\{"id":"1","name":"Bob"\},\{"id":"2","name":""\},\{"id":"3","name":null\}\], err:nil$
--- no_error_log
[error]
--- error_log eval
qr/lua tcp socket keepalive create connection pool for key "my_pool"/
--- log_level: debug
--- wait: 0.3



=== TEST 17: the mysql newdecimal type
--- server_config
        content_by_lua '
            local ljson = require "ljson"

            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                path = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test",
                pool = "my_pool"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            ngx.say("connected to mysql: ", db:get_reused_times())

            ok, err = db:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end

            ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test",
                pool = "my_pool"})

            ngx.say("connected to mysql: ", db:get_reused_times())

            local res
            res, err, errno, sqlstate =
                db:query("select sum(id) from cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res), ", err:", err)

            local ok, err = db:set_keepalive()
            if not ok then
                ngx.say("failed to set keepalive: ", err)
                return
            end
        ';
--- response_body_like chop
^connected to mysql: [02]
connected to mysql: [13]
result: \[\{"sum\(id\)":6\}\], err:nil$
--- no_error_log
[error]
--- error_log eval
qr/lua tcp socket keepalive create connection pool for key "my_pool"/
--- log_level: debug
--- wait: 0.3



=== TEST 18: large insert_id exceeding a 32-bit integer value
--- server_config
        content_by_lua '
            local mysql = require("resty.mysql")
            local create_sql = [[
                CREATE TABLE `large_t` (
                    `id` bigint(11) NOT NULL AUTO_INCREMENT,
                    PRIMARY KEY (`id`)
                ) AUTO_INCREMENT=5000000312;
            ]]
            local drop_sql = [[
                DROP TABLE IF EXISTS `large_t`;
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
                                       database="ngx_test",
                                       user="ngx_test",
                                       password="ngx_test"}
            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end
            local res, err = db:query(drop_sql)
            if not res then
                ngx.say("drop table error:" .. err)
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
        ';
--- response_body
5000000312
--- no_error_log
[error]



=== TEST 19: fix packet number overflow
--- server_config
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(2000) -- 2 sec

            local ok, err, errno, sqlstate = db:connect({
                path = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test",
                pool = "my_pool"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            -- generate test data
            local res, err, errno, sqlstate = db:query("drop table if exists cats")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name varchar(5))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            for i = 1, 260 do
                res, err, errno, sqlstate = db:query("insert into cats(name) values (\'abc\')")
                if not res then
                    ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                    return
                end
            end

            -- according to the MySQL protocol, make packet number be equal to 255
            -- packet number = header(1) + field(M) + eof(1) + row(N) + eof(1)
            -- the following sql packet number is: 1 + 1 + 1 + 251 + 1 = 255
            local res, err, errno, sqlstate = db:query("select id from cats limit 251")
            db:close()

            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            if #res ~= 251 then
                ngx.say("bad result, not got 251 rows")
                return
            end

            ngx.say("success")
        }
--- response_body
success
--- no_error_log
[error]
--- timeout: 20



=== TEST 20: 251 columns
--- server_config
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local sql = require "create_sql_by_columns"

            local db = mysql:new()

            db:set_timeout(2000) -- 2 sec

            local ok, err, errno, sqlstate = db:connect({
                path = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            local columns = 251

            -- generate test data
            local res, err, errno, sqlstate = db:query(sql.drop(columns))
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query(sql.create(columns))
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query(sql.insert(columns))
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            local res, err, errno, sqlstate = db:query(sql.query(columns))
            db:close()

            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            if #res ~= 1 then
                ngx.say("bad result, not got 1 rows")
                return
            end

            local row = res[1]
            local count = 0
            for _ in pairs(row) do
                count = count + 1
            end
            if count ~= columns then
                ngx.say("bad result, got ", count, " columns")
                return
            end

            ngx.say("success")
        }
--- response_body
success
--- no_error_log
[error]
--- timeout: 20



=== TEST 21: MySQL has hard limit of 4096 columns per table
--- server_config
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local sql = require "create_sql_by_columns"

            local db = mysql:new()

            db:set_timeout(2000) -- 2 sec

            local ok, err, errno, sqlstate = db:connect({
                path = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            local columns = 4097

            -- generate test data
            local res, err, errno, sqlstate = db:query(sql.drop(columns))
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query(sql.create(columns))
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query(sql.insert(columns))
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            local res, err, errno, sqlstate = db:query(sql.query(columns))
            db:close()

            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            if #res ~= 1 then
                ngx.say("bad result, not got 1 rows")
                return
            end

            local row = res[1]
            local count = 0
            for _ in pairs(row) do
                count = count + 1
            end
            if count ~= columns then
                ngx.say("bad result, got ", count, " columns")
                return
            end

            ngx.say("success")
        }
--- response_body_like
bad result: .*Too many columns.*.

--- no_error_log
[error]
--- timeout: 20



=== TEST 22: InnoDB has a limit of 1017 columns per table
--- server_config
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local sql = require "create_sql_by_columns"

            local db = mysql:new()

            db:set_timeout(2000) -- 2 sec

            local ok, err, errno, sqlstate = db:connect({
                path = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            local columns = 1018

            -- generate test data
            local res, err, errno, sqlstate = db:query(sql.drop(columns))
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query(sql.create(columns))
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query(sql.insert(columns))
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            local res, err, errno, sqlstate = db:query(sql.query(columns))
            db:close()

            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            if #res ~= 1 then
                ngx.say("bad result, not got 1 rows")
                return
            end

            local row = res[1]
            local count = 0
            for _ in pairs(row) do
                count = count + 1
            end
            if count ~= columns then
                ngx.say("bad result, got ", count, " columns")
                return
            end

            ngx.say("success")
        }
--- response_body_like chomp
bad result: .*?(?:Too many columns|Can't create table 'ngx_test\.test1018' \(errno: 139\))

--- no_error_log
[error]
--- timeout: 20



=== TEST 23: MyISAM columns per table > 1017
--- server_config
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local sql = require "create_sql_by_columns"

            local db = mysql:new()

            db:set_timeout(2000) -- 2 sec

            local ok, err, errno, sqlstate = db:connect({
                path = "$TEST_NGINX_MYSQL_PATH",
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            local columns = 1018

            -- generate test data
            local res, err, errno, sqlstate = db:query(sql.drop(columns))
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query(sql.create(columns, "MyISAM"))
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            res, err, errno, sqlstate = db:query(sql.insert(columns))
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            local res, err, errno, sqlstate = db:query(sql.query(columns))
            db:close()

            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            if #res ~= 1 then
                ngx.say("bad result, not got 1 rows")
                return
            end

            local row = res[1]
            local count = 0
            for _ in pairs(row) do
                count = count + 1
            end
            if count ~= columns then
                ngx.say("bad result, got ", count, " columns")
                return
            end

            ngx.say("success")
        }
--- response_body
success
--- no_error_log
[error]
--- timeout: 20



=== TEST 24: connected with no error when pool opts are provided
--- server_config
        content_by_lua '
            local mysql = require "resty.mysql"
            local db = mysql:new()

            db:set_timeout(1000) -- 1 sec

            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ngx_test",
                password = "ngx_test",
                pool = "my_pool",
                pool_size = 10,
                backlog = 5
                })

            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end

            ngx.say("connected to mysql ", db:server_ver())

            db:close()
        ';
--- response_body_like
connected to mysql \d\.[^\s\x00]+
--- no_error_log
[error]



=== TEST 25: set pool_size option no backlog option
--- server_config
        content_by_lua_block {
            local mysql = require "resty.mysql"

            local function mysql_conn()
                local db = mysql:new()
                db:set_timeout(1000) -- 1 sec

                local ok, err, errno, sqlstate = db:connect({
                    host = "$TEST_NGINX_MYSQL_HOST",
                    port = $TEST_NGINX_MYSQL_PORT,
                    database = "ngx_test",
                    user = "ngx_test",
                    password = "ngx_test",
                    pool = "my_pool",
                    pool_size = 5
                })
                if not ok then
                    return err
                end
                return nil
            end

            for i = 1,10 do
                local err = mysql_conn()
                if err ~= nil then
                    ngx.say(err)
                    return
                end
            end
            ngx.say("connected to mysql")
        }
--- response_body_like
connected to mysql
--- no_error_log
[error]



=== TEST 26: set the pool_size and backlog options at the same time
--- server_config
        content_by_lua_block {
            local mysql = require "resty.mysql"

            local function mysql_conn()
                local db = mysql:new()
                db:set_timeout(1000) -- 1 sec

                local ok, err, errno, sqlstate = db:connect({
                    host = "$TEST_NGINX_MYSQL_HOST",
                    port = $TEST_NGINX_MYSQL_PORT,
                    database = "ngx_test",
                    user = "ngx_test",
                    password = "ngx_test",
                    pool = "my_pool",
                    pool_size = 5,
                    backlog = 5
                })
                if not ok then
                    ngx.say(err)
                    return err
                end
                return nil
            end
            for i = 1,15 do
                ngx.thread.spawn(mysql_conn)
            end
        }
--- response_body_like
failed to connect: too many waiting connect operations
failed to connect: too many waiting connect operations
failed to connect: too many waiting connect operations
failed to connect: too many waiting connect operations
failed to connect: too many waiting connect operations
failed to connect: timeout
failed to connect: timeout
failed to connect: timeout
failed to connect: timeout
failed to connect: timeout
--- error_log
lua tcp socket queued connect timed out



=== TEST 27: large insert_id exceeding a 32-bit signed integer value
--- http_config eval: $::HttpConfig
--- server_config
        content_by_lua_block {
            local mysql = require("resty.mysql")
            local create_sql = [[
                CREATE TABLE `large_t` (
                    `id` bigint(11) NOT NULL AUTO_INCREMENT,
                    PRIMARY KEY (`id`)
                ) AUTO_INCREMENT=
            ]] .. (math.pow(2, 32) - 1)
            local drop_sql = [[
                DROP TABLE IF EXISTS `large_t`;
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
                                       database="ngx_test",
                                       user="ngx_test",
                                       password="ngx_test"}
            if not ok then
                ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
                return
            end
            local res, err = db:query(drop_sql)
            if not res then
                ngx.say("drop table error:" .. err)
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
        }
--- response_body
4294967295
--- no_error_log
[error]
