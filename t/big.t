# vim:set ft= ts=4 sw=4 et:

my @skip;
BEGIN {
    if ($ENV{LD_PRELOAD} =~ /\bmockeagain\.so\b/) {
        @skip = (skip_all => 'too slow in mockeagain mode')
    }
}

use t::Test @skip;

repeat_each(50);
#repeat_each(10);

plan tests => repeat_each() * (3 * blocks());

log_level 'warn';

#no_long_string();
#no_diff();
no_shuffle();

run_tests();

__DATA__

=== TEST 1: big field value exceeding 256
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

            res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name varchar(1024))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errno, sqlstate = db:query("insert into cats (name) value (\'"
                   .. string.rep("B", 1024)
                   .. "\')")

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
--- response_body eval
'connected to mysql.
table cats dropped.
table cats created.
1 rows inserted into table cats (last id: 1)
result: [{"id":"1","name":"' . ('B' x 1024)
   . '"}]' . "\n" .
'result: [{"id":"1","name":"' . ('B' x 1024)
   . '"}]' . "\n"
--- no_error_log
[error]



=== TEST 2: big field value exceeding max packet size
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
                password = "ngx_test",
                max_packet_size = 1024 })

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

            res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name varchar(1024))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errno, sqlstate = db:query("insert into cats (name) value (\'"
                   .. string.rep("B", 1024)
                   .. "\')")

            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say(res.affected_rows, " rows inserted into table cats (last id: ", res.insert_id, ")")

            res, err, errno, sqlstate =
                db:query("select * from cats order by id asc")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("result: ", ljson.encode(res))

            res, err, errno, sqlstate =
                db:query("select * from cats order by id desc")
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
--- response_body eval
'connected to mysql.
table cats dropped.
table cats created.
1 rows inserted into table cats (last id: 1)
bad result: packet size too big: 1029: nil: nil.
'
--- no_error_log
[error]



=== TEST 3: big field value exceeding 256 (first field in rows)
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

            res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name varchar(1024))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errno, sqlstate = db:query("insert into cats (name) value (\'"
                   .. string.rep("B", 1024)
                   .. "\')")

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
--- response_body eval
'connected to mysql.
table cats dropped.
table cats created.
1 rows inserted into table cats (last id: 1)
result: [{"name":"' . ('B' x 1024)
   . '"}]' . "\n" .
'result: [{"name":"' . ('B' x 1024)
   . '"}]' . "\n"
--- no_error_log
[error]



=== TEST 4: big field value exceeding 65536 (first field in rows)
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

            res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name text(65540))")
            if not res then
                ngx.say("bad result: ", err, ": ", errno, ": ", sqlstate, ".")
                return
            end

            ngx.say("table cats created.")

            res, err, errno, sqlstate = db:query("insert into cats (name) value (\'"
                   .. string.rep("B", 65540)
                   .. "\')")

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
--- response_body eval
'connected to mysql.
table cats dropped.
table cats created.
1 rows inserted into table cats (last id: 1)
result: [{"name":"' . ('B' x 65540)
   . '"}]' . "\n" .
'result: [{"name":"' . ('B' x 65540)
   . '"}]' . "\n"
--- no_error_log
[error]
--- timeout: 10
