# vim:set ft= ts=4 sw=4 et:

use t::Test;

repeat_each(2);

plan tests => repeat_each() * (3 * blocks());

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: basic
--- server_config
        content_by_lua '
            local mysql = require "resty.mysql"
            ngx.say(mysql._VERSION)
        ';
--- response_body_like chop
^\d+\.\d+$
--- no_error_log
[error]
