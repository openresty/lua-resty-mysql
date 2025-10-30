# vim:set ft= ts=4 sw=4 et:

use t::Test;

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

#log_level 'warn';

no_long_string();
no_shuffle();
check_accum_error_log();

run_tests();

__DATA__

=== TEST 1: test an old bug in table.new() on i386 in luajit v2.1
--- server_config
        access_log off;
        content_by_lua '
            -- jit.off()
            local mysql = require "resty.mysql"
            local db = mysql:new()

            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "world",
                user = "ngx_test",
                password = "ngx_test"})

            if not ok then
                ngx.log(ngx.ERR, "failed to connect: ", err)
                return ngx.exit(500)
            end

            local res, err, errno, sqlstate
            for j = 1, 10 do
                res, err, errno, sqlstate = db:query("select * from city order by ID limit 50", 50)
                if not res then
                    ngx.log(ngx.ERR, "bad result #1: ", err, ": ", errno, ": ", sqlstate, ".")
                    return ngx.exit(500)
                end
            end

            for _, row in ipairs(res) do
                local ncols = 0
                for k, v in pairs(row) do
                    ncols = ncols + 1
                end
                ngx.say("ncols: ", ncols)
            end

            local ok, err = db:set_keepalive(10000, 50)
            if not ok then
                ngx.log(ngx.ERR, "failed to set keepalive: ", err)
                ngx.exit(500)
            end
        ';
--- response_body eval
"ncols: 5\n" x 50
--- no_error_log
[error]
