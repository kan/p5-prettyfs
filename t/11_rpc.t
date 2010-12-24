use strict;
use warnings;
use Test::More;
use t::Util;
use PrettyFS::Server::RPC;
use Plack::Test;
use JSON;

my $client = get_client();
$client->add_storage(host => '127.0.0.1', port => 1010);

test_psgi
    app => PrettyFS::Server::RPC->new(client => $client)->to_app,
    client => sub {
        my $cb = shift;

        subtest 'list_storage' => sub {
            my $res = $cb->(HTTP::Request->new('GET', 'http://localhost/list_storage'));
            is($res->code, 200) or diag $res->content;
            my $data = decode_json($res->content);
            is_deeply $data, decode_json('{"error":null,"value":[{"status":2,"disk_total":null,"id":1,"port":1010,"disk_used":null,"host":"127.0.0.1"}]}');
        };

        subtest 'add_storage' => sub {
            my $res = $cb->(HTTP::Request->new('POST', 'http://localhost/add_storage', [], 'foo=bar'));
            is($res->code, 500) or diag $res->content;
        };
    };

done_testing;

