use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 2); 

my $pwd = cwd();

$ENV{TEST_LEDGE_REDIS_DATABASE} ||= 1;

our $HttpConfig = qq{
    lua_package_path "$pwd/../lua-resty-redis-connector/lib/?.lua;$pwd/../lua-resty-qless/lib/?.lua;$pwd/../lua-resty-http/lib/?.lua;$pwd/../lua-resty-cookie/lib/?.lua;$pwd/lib/?.lua;;";
	init_by_lua "
		ledge_mod = require 'ledge.ledge'
        ledge = ledge_mod:new()
        ledge:config_set('redis_use_sentinel', true)
        ledge:config_set('redis_sentinel_master_name', '$ENV{TEST_LEDGE_SENTINEL_MASTER_NAME}')
        ledge:config_set('redis_sentinels', {
            { host = '127.0.0.1', port = $ENV{TEST_LEDGE_SENTINEL_PORT} }, 
        })
		ledge:config_set('redis_database', $ENV{TEST_LEDGE_REDIS_DATABASE})
        ledge:config_set('upstream_host', '127.0.0.1')
        ledge:config_set('upstream_port', 1984)
	";
};

no_long_string();
run_tests();

__DATA__
=== TEST 1: Read from cache (primed in previous test file)
--- http_config eval: $::HttpConfig
--- config
	location /sentinel_1_prx {
        rewrite ^(.*)_prx$ $1 break;
        content_by_lua '
            ledge:run()
        ';
    }
    location /sentinel_1 {
        echo "ORIGIN";
    }
--- request
GET /sentinel_1_prx
--- response_body
OK


=== TEST 2: The write will fail, but we'll still get a 200 with our new content.
--- http_config eval: $::HttpConfig
--- config
	location /sentinel_2_prx {
        rewrite ^(.*)_prx$ $1 break;
        content_by_lua '
            ledge:run()
        ';
    }
    location /sentinel_2 {
        content_by_lua '
            ngx.header["Cache-Control"] = "max-age=3600"
            ngx.say("TEST 2")
        ';
    }
--- request
GET /sentinel_2_prx
--- response_body
TEST 2


=== TEST 2b: The write will fail, but we'll still get a 200 with our content.
--- http_config eval: $::HttpConfig
--- config
    location /sentinel_2_prx {
        rewrite ^(.*)_prx$ $1 break;
        content_by_lua '
            ledge:run()
        ';
    }
    location /sentinel_2 {
        content_by_lua '
            ngx.header["Cache-Control"] = "max-age=3600"
            ngx.say("TEST 2b")
        ';
    }
--- request
GET /sentinel_2_prx
--- response_body
TEST 2b
