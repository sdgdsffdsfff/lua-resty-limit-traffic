# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4);

#no_diff();
#no_long_string();

my $pwd = cwd();

our $HttpConfig = <<_EOC_;
    lua_package_path "$pwd/lib/?.lua;;";
_EOC_

no_long_string();
run_tests();

__DATA__

=== TEST 1: a single key (always commit, and no leaving)
--- http_config eval
"
$::HttpConfig

    lua_shared_dict store 1m;
"
--- config
    location = /t {
        content_by_lua '
            local limit_conn = require "resty.limit.conn"
            local lim = limit_conn.new("store", 2, 8, 1)
            ngx.shared.store:flush_all()
            local key = "foo"
            for i = 1, 12 do
                local delay, err = lim:incoming(key, true)
                if not delay then
                    ngx.say("failed to limit conn: ", err)
                else
                    local conn = err
                    ngx.say(i, ": ", delay, ", conn: ", conn)
                end
            end
        ';
    }
--- request
    GET /t
--- response_body
1: 0, conn: 1
2: 0, conn: 2
3: 1, conn: 3
4: 1, conn: 4
5: 2, conn: 5
6: 2, conn: 6
7: 3, conn: 7
8: 3, conn: 8
9: 4, conn: 9
10: 4, conn: 10
failed to limit conn: busy
failed to limit conn: busy
--- no_error_log
[error]
[lua]



=== TEST 2: a single key (somtimes not commit, and no leaving)
--- http_config eval
"
$::HttpConfig

    lua_shared_dict store 1m;
"
--- config
    location = /t {
        content_by_lua '
            local limit_conn = require "resty.limit.conn"
            local lim = limit_conn.new("store", 2, 8, 1)
            ngx.shared.store:flush_all()
            local key = "foo"
            for i = 1, 12 do
                local delay, err = lim:incoming(key, i == 3 or i == 5)
                if not delay then
                    ngx.say("failed to limit conn: ", err)
                else
                    local conn = err
                    ngx.say(i, ": ", delay, ", conn: ", conn)
                end
            end
        ';
    }
--- request
    GET /t
--- response_body
1: 0, conn: 1
2: 0, conn: 1
3: 0, conn: 1
4: 0, conn: 2
5: 0, conn: 2
6: 1, conn: 3
7: 1, conn: 3
8: 1, conn: 3
9: 1, conn: 3
10: 1, conn: 3
11: 1, conn: 3
12: 1, conn: 3
--- no_error_log
[error]
[lua]



=== TEST 3: a single key (always commit, and with random leaving)
--- http_config eval
"
$::HttpConfig

    lua_shared_dict store 1m;
"
--- config
    location = /t {
        content_by_lua '
            local limit_conn = require "resty.limit.conn"
            local lim = limit_conn.new("store", 2, 8, 1)
            ngx.shared.store:flush_all()
            local key = "foo"
            for i = 1, 12 do
                local delay, err = lim:incoming(key, true)
                if not delay then
                    ngx.say("failed to limit conn: ", err)
                else
                    local conn = err
                    ngx.say(i, ": ", delay, ", conn: ", conn)
                    if i == 4 or i == 7 then
                        local conn, err = lim:leaving(key)
                        if not conn then
                            ngx.say("leaving failed: ", err)
                        else
                            ngx.say("leaving. conn: ", conn)
                        end
                    end
                end
            end
        ';
    }
--- request
    GET /t
--- response_body
1: 0, conn: 1
2: 0, conn: 2
3: 1, conn: 3
4: 1, conn: 4
leaving. conn: 3
5: 1, conn: 4
6: 2, conn: 5
7: 2, conn: 6
leaving. conn: 5
8: 2, conn: 6
9: 3, conn: 7
10: 3, conn: 8
11: 4, conn: 9
12: 4, conn: 10
--- no_error_log
[error]
[lua]

