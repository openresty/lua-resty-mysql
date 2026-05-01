# vim:set ft= ts=4 sw=4 et:
#
# MariaDB client_ed25519 authentication tests.
#
# The required users (`ed25519_user` with password `ed25519_pass` and
# `ed25519_nopass` with empty password) and the auth_ed25519 plugin are
# provisioned by .travis/initializedb.sh on supported DB_VERSIONs. The
# whole test file is skipped on databases that don't ship the plugin
# (plain MySQL, MariaDB 5.5, MariaDB 10.0 — the plugin landed in 10.1.22).
#

use t::Test;

# Skip the entire file when DB_VERSION is set and known not to support
# the client_ed25519 setup we need. When DB_VERSION is unset (e.g., local
# dev runs), assume the plugin is present and let individual blocks fail
# loudly otherwise.
#
# Skipped versions and why:
#   mysql:*           — ed25519 is MariaDB-specific.
#   mariadb:5.*       — predates the plugin (added in 10.1.22).
#   mariadb:10.0      — predates the plugin.
#   mariadb:10.1      — official Docker image ships without auth_ed25519.so.
#   mariadb:10.2 and later DO work: initializedb.sh seeds the test users
#   via the explicit `IDENTIFIED VIA ed25519 USING '<base64_pubkey>'` form,
#   which is supported on every MariaDB version that ships the plugin.
my $dbver = $ENV{DB_VERSION};
if (defined $dbver
    && ($dbver =~ /^mysql:/ || $dbver =~ /^mariadb:(5\.|10\.[01]$)/))
{
    plan skip_all => "client_ed25519 unsupported on DB_VERSION=$dbver";
}

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

no_long_string();
no_shuffle();
check_accum_error_log();

run_tests();

__DATA__

=== TEST 1: sign() returns a 64-byte deterministic signature
--- server_config
        content_by_lua_block {
            local ed = require "resty.mysql.auth_ed25519"
            local m = string.rep("\x42", 32)
            local s1, err = ed.sign("password", m)
            if not s1 then ngx.say("sign failed: ", err); return end
            local s2 = ed.sign("password", m)
            ngx.say("len=", #s1)
            ngx.say("deterministic=", tostring(s1 == s2))
        }
--- response_body
len=64
deterministic=true
--- no_error_log
[error]



=== TEST 2: sign() known vector (regression guard)
--- server_config
        content_by_lua_block {
            local ed = require "resty.mysql.auth_ed25519"
            local s = ed.sign("password", string.rep("\x42", 32))
            local hex = (s:sub(1, 8):gsub(".", function(c)
                return string.format("%02x", string.byte(c))
            end))
            ngx.say("prefix=", hex)
        }
--- response_body
prefix=6f25ecb9d36d417d
--- no_error_log
[error]



=== TEST 3: sign() varies with scramble and password
--- server_config
        content_by_lua_block {
            local ed = require "resty.mysql.auth_ed25519"
            local m1 = string.rep("\xab", 32)
            local m2 = string.rep("\xcd", 32)
            local a = ed.sign("pw", m1)
            local b = ed.sign("pw", m2)
            local c = ed.sign("other", m1)
            ngx.say("scramble_diff=", tostring(a ~= b))
            ngx.say("password_diff=", tostring(a ~= c))
        }
--- response_body
scramble_diff=true
password_diff=true
--- no_error_log
[error]



=== TEST 4: sign() handles empty / long / binary passwords
--- server_config
        content_by_lua_block {
            local ed = require "resty.mysql.auth_ed25519"
            local m = string.rep("\x42", 32)
            for _, pw in ipairs({"", string.rep("x", 1024), "\0\0\xff\xab"}) do
                local s = ed.sign(pw, m)
                ngx.say(s and #s or "nil")
            end
        }
--- response_body
64
64
64
--- no_error_log
[error]



=== TEST 5: connect with correct ed25519 password
--- server_config
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local db = mysql:new()
            db:set_timeout(2000)
            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ed25519_user",
                password = "ed25519_pass",
            })
            if not ok then
                ngx.say("connect failed: ", err, ": ", errno, " ", sqlstate)
                return
            end
            local res = db:query("SELECT CURRENT_USER() AS u")
            ngx.say("user=", res[1].u)
            db:close()
        }
--- response_body
user=ed25519_user@%
--- no_error_log
[error]



=== TEST 6: wrong ed25519 password is rejected
--- server_config
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local db = mysql:new()
            db:set_timeout(2000)
            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ed25519_user",
                password = "WRONG_PASSWORD",
            })
            if not ok then
                ngx.say("rejected errno=", errno, " sqlstate=", sqlstate)
                return
            end
            ngx.say("UNEXPECTED: connected with wrong password")
            db:close()
        }
--- response_body
rejected errno=1045 sqlstate=28000
--- no_error_log
[error]



=== TEST 7: ed25519 user with empty password connects
--- server_config
        content_by_lua_block {
            local mysql = require "resty.mysql"
            local db = mysql:new()
            db:set_timeout(2000)
            local ok, err, errno, sqlstate = db:connect({
                host = "$TEST_NGINX_MYSQL_HOST",
                port = $TEST_NGINX_MYSQL_PORT,
                database = "ngx_test",
                user = "ed25519_nopass",
                password = "",
            })
            if not ok then
                ngx.say("connect failed: ", err, ": ", errno, " ", sqlstate)
                return
            end
            local res = db:query("SELECT CURRENT_USER() AS u")
            ngx.say("user=", res[1].u)
            db:close()
        }
--- response_body
user=ed25519_nopass@%
--- no_error_log
[error]



=== TEST 8: repeated connections use fresh scrambles
--- server_config
        content_by_lua_block {
            local mysql = require "resty.mysql"
            for i = 1, 3 do
                local db = mysql:new()
                db:set_timeout(2000)
                local ok, err = db:connect({
                    host = "$TEST_NGINX_MYSQL_HOST",
                    port = $TEST_NGINX_MYSQL_PORT,
                    database = "ngx_test",
                    user = "ed25519_user",
                    password = "ed25519_pass",
                })
                if not ok then
                    ngx.say("connect ", i, " failed: ", err)
                    return
                end
                db:close()
            end
            ngx.say("ok")
        }
--- response_body
ok
--- no_error_log
[error]
