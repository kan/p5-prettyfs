use strict;
use warnings;
use Test::More;
use PrettyFS::Server::Store;
use Plack::Test;
use File::Temp qw/tempdir/;

my $app = PrettyFS::Server::Store->new(base => tempdir())->to_app();

test_psgi
    app => $app,
    client => sub {
        my $cb = shift;

        subtest 'put' => sub {
            subtest 'normal' => sub {
                my $res = $cb->(HTTP::Request->new(PUT => 'http://localhost/foo', ['Content-Length' => 4], "TEST"));
                is $res->code, 200;
                is $res->content, 'OK';
            };

            subtest "Don't overwrite" => sub {
                my $res = $cb->(HTTP::Request->new(PUT => 'http://localhost/foo', [], "TEST"));
                is $res->code, 403;
            };
        };

        subtest 'get' => sub {
            subtest 'not found: 404' => sub {
                my $res = $cb->(HTTP::Request->new(GET => 'http://localhost/unknown'));
                is $res->code, 404;
            };
            subtest 'ok' => sub {
                my $res = $cb->(HTTP::Request->new(GET => 'http://localhost/foo'));
                is $res->code, 200;
                is $res->content, 'TEST';
            };
        };

        subtest 'head' => sub {
            subtest 'ok' => sub {
                my $res = $cb->(HTTP::Request->new(HEAD => 'http://localhost/foo'));
                is $res->code, 200;
            };
            subtest 'not found' => sub {
                my $res = $cb->(HTTP::Request->new(HEAD => 'http://localhost/unknown'));
                is $res->code, 404;
            };
        };

        subtest 'delete' => sub {
            subtest 'ok' => sub {
                my $res = $cb->(HTTP::Request->new(DELETE => 'http://localhost/foo'));
                is $res->code, 200;

                my $res2 = $cb->(HTTP::Request->new(GET => 'http://localhost/foo'));
                is $res2->code, 404, 'removed';
            };
            subtest 'not found' => sub {
                my $res = $cb->(HTTP::Request->new(DELETE => 'http://localhost/foo'));
                is $res->code, 404;
            };
        };

        subtest 'post' => sub {
            subtest 'not allowed' => sub {
                my $res = $cb->(HTTP::Request->new(POST => 'http://localhost/foo'));
                is $res->code, 405;
            };
        };

    };

done_testing;

