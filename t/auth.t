# vim:set ft= ts=4 sw=4 et:

use t::Test;

repeat_each(5);

plan tests => repeat_each() * (2 * blocks());

#log_level 'warn';

no_long_string();
no_shuffle();
check_accum_error_log();

add_block_preprocessor(sub {
    my $block = shift;

    if (!defined $block->user_files) {
        $block->set_value("user_files", <<'_EOC_');
>>> test_suit.lua
local _M = {}

local ljson = require "ljson"
local mysql = require "resty.mysql"

function _M.prepare()
    local db = mysql:new()
    db:set_timeout(2000) -- 2 sec

    local ok, err, errno, sqlstate = db:connect({
        host = "$TEST_NGINX_MYSQL_HOST",
        port = $TEST_NGINX_MYSQL_PORT,
        database = "ngx_test",
        user = "ngx_test",
        password = "ngx_test"})

    if not ok then
        ngx.log(ngx.ERR, "failed to connect: ", err, ": ", errno, " ", sqlstate)
        return
    end

    ngx.say("connected to mysql.")

    local res, err, errno, sqlstate = db:query("drop table if exists cats")
    if not res then
        ngx.log(ngx.ERR, "bad result: ", err, ": ", errno, ": ", sqlstate, ".")
        return
    end

    ngx.say("table cats dropped.")

    res, err, errno, sqlstate = db:query("create table cats (id serial primary key, name varchar(5))")
    if not res then
        ngx.log(ngx.ERR, "bad result: ", err, ": ", errno, ": ", sqlstate, ".")
        return
    end

    ngx.say("table cats created.")

    res, err, errno, sqlstate = db:query("insert into cats (name) value (\'Bob\'),(\'\'),(null)")
    if not res then
        ngx.log(ngx.ERR, "bad result: ", err, ": ", errno, ": ", sqlstate, ".")
        return
    end

    ngx.say(res.affected_rows, " rows inserted into table cats (last id: ", res.insert_id, ")")

    local ok, err = db:close()
    if not ok then
        ngx.log(ngx.ERR, "failed to close: ", err)
        return
    end
end

function _M.run(user, password, ssl)
    local db = mysql:new()
    db:set_timeout(2000) -- 2 sec

    local ok, err, errno, sqlstate = db:connect({
        host = "$TEST_NGINX_MYSQL_HOST",
        port = $TEST_NGINX_MYSQL_PORT,
        database = "ngx_test",
        user = user,
        password = password,
        ssl = ssl,
    })

    if not ok then
        ngx.log(ngx.ERR, "failed to connect: ", err, ": ", errno, " ", sqlstate)
        return
    end

    ngx.say("mysql auth successful.")

    local res, err, errno, sqlstate = db:query("select * from cats order by id asc")
    if not res then
        ngx.log(ngx.ERR, "bad result: ", err, ": ", errno, ": ", sqlstate, ".")
        return
    end

    ngx.say("result: ", ljson.encode(res))

    res, err, errno, sqlstate = db:query("select * from cats order by id desc")
    if not res then
        ngx.log(ngx.ERR, "bad result: ", err, ": ", errno, ": ", sqlstate, ".")
        return
    end

    ngx.say("result: ", ljson.encode(res))

    local ok, err = db:close()
    if not ok then
        ngx.log(ngx.ERR, "failed to close: ", err)
        return
    end

    return true
end

return _M
_EOC_
    }
});

run_tests();

__DATA__

=== TEST 1: test different auth plugin
--- main_config
    env DB_VERSION;
--- server_config
        content_by_lua_block {
            local test_suit = require "test_suit"
            test_suit.prepare()
            local version = os.getenv("DB_VERSION")
            if not version then
                ngx.log(ngx.ERR, "please add the environment value \"DB_VERSION\"")
            end

            local version_plugin_mapping = {
                ["mysql:5.5"] = {
                    "mysql_native_password",
                    "mysql_old_password",
                },
                ["mysql:5.6"] = {
                    "mysql_native_password",
                    "mysql_old_password",
                    "sha256_password",
                },
                ["mysql:5.7"] = {
                    "mysql_native_password",
                    "sha256_password",
                },
                ["mysql:8.0"] = {
                    "mysql_native_password",
                    "sha256_password",
                    "caching_sha2_password",
                },
                ["mariadb:5.5"] = {
                    "mysql_native_password",
                    "mysql_old_password",
                },
                ["mariadb:10.0"] = {
                    "mysql_native_password",
                    "mysql_old_password",
                },
                ["mariadb:10.1"] = {
                    "mysql_native_password",
                    "mysql_old_password",
                },
                ["mariadb:10.2"] = {
                    "mysql_native_password",
                    "mysql_old_password",
                },
                ["mariadb:10.3"] = {
                    "mysql_native_password",
                    "mysql_old_password",
                },
            }

            local plugin_user_mapping = {
                ["mysql_native_password"] = {
                    {
                        user = "user_native",
                        password = "pass_native",
                    },
                    {
                        user = "nopass_native",
                    },
                },
                ["mysql_old_password"] = {
                    {
                        user = "user_old",
                        password = "pass_old",
                    },
                    {
                        user = "nopass_old",
                    },
                },
                ["sha256_password"] = {
                    {
                        user = "user_sha256",
                        password = "pass_sha256",
                    },
                    {
                        user = "nopass_sha256",
                    },
                },
                ["caching_sha2_password"] = {
                    {
                        user = "user_caching_sha2",
                        password = "pass_caching_sha2",
                    },
                    {
                        user = "nopass_caching_sha2",
                    },
                },
            }

            local plugin_list = version_plugin_mapping[version]
            if not plugin_list then
                ngx.log(ngx.ERR, "unknown version: ", version)
            end

            for _, p in ipairs(plugin_list) do
                local user_infos = plugin_user_mapping[p]
                for _, u in ipairs(user_infos) do
                    if not test_suit.run(u.user, u.password) then
                        ngx.log(ngx.ERR, "testing with plugin ", p,
                                " failed, and the user is ", u.user,
                                ", password is ", u.password or "null")
                    end

                    if not test_suit.run(u.user, u.password, true) then -- tls
                        ngx.log(ngx.ERR, "testing(by tls) with plugin ", p,
                                " failed, and the user is ", u.user,
                                ", password is ", u.password or "null")
                    end
                end
            end
        }
--- no_error_log
[error]
