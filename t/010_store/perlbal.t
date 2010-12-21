use strict;
use warnings;
use Test::More;
use t::Util;
use Test::Requires 'Perlbal', 'IO::AIO';
use PrettyFS::Server::Store::Perlbal;
use Test::TCP;
use Furl;

my $dir = tempdir();
my $server = Test::TCP->new(
    code => sub {
        my $port = shift;
        PrettyFS::Server::Store::Perlbal->new(docroot => $dir, listen => "127.0.0.1:$port")->run;
    },
);

my $port = $server->port;
subtest 'put' => sub {
    subtest 'ok' => sub {
        my $res = Furl->new->put("http://127.0.0.1:$port/foo", [], "TEST");
        is $res->code, 200;
    };
    subtest 'bad request' => sub {
        my $res = Furl->new->put("http://127.0.0.1:$port/foo/bar", [], "TEST");
        is $res->code, 500;
    };
    subtest 'deep request' => sub {
        my $res = Furl->new->put("http://127.0.0.1:$port/bar/baz", [], "TEST");
        is $res->code, 200;
    };
};

subtest 'get' => sub {
    subtest 'ok' => sub {
        my $res = Furl->new->get("http://127.0.0.1:$port/foo");
        is $res->code, 200;
        is $res->content, 'TEST';
    };
    subtest 'not found' => sub {
        my $res = Furl->new->get("http://127.0.0.1:$port/unknown");
        is $res->code, 404;
    };
};

subtest 'head' => sub {
    subtest 'ok' => sub {
        my $res = Furl->new->head("http://127.0.0.1:$port/foo");
        is $res->code, 200;
        is $res->content, '';
    };
    subtest 'not found' => sub {
        my $res = Furl->new->head("http://127.0.0.1:$port/unknown");
        is $res->code, 404;
    };
};

subtest 'delete' => sub {
    subtest 'ok' => sub {
        my $res = Furl->new->delete("http://127.0.0.1:$port/foo");
        is $res->code, 404; # XXX really?

        my $res2 = Furl->new->get("http://127.0.0.1:$port/foo");
        is $res2->code, 404;
    };
};

subtest 'post' => sub {
    subtest 'ok' => sub {
        my $res = Furl->new->post("http://127.0.0.1:$port/foo", [], 'OK');
        is $res->code, 400, 'bad request';
    };
};

done_testing;

