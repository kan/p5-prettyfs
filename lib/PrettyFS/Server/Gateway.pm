use strict;
use warnings FATAL => 'all';
use utf8;

package PrettyFS::Server::Gateway;
use Class::Accessor::Lite (
    ro  => [qw/backend_url callback timeout/],
);
use List::Util ();
use AnyEvent::HTTP;
use AE;
use Log::Minimal;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    for (qw/callback/) {
        Carp::croak("missing mandatory parameter: $_") unless exists $args{$_};
    }
    my $self = bless {
        cache   => {},
        timeout => 10,
        %args
    }, $class;
    return $self;
}

sub to_app {
    my $self = shift;

    sub {
        my $env = shift;
        die "This app requires streaming support." unless $env->{'psgi.streaming'};

        my $key = $env->{PATH_INFO};
        $key =~ s!^/!!;

        return sub {
            my $respond = shift;

            my @urls = $self->callback->($key);

            return $respond->([404, [], []]) unless @urls;

            $self->_send_request($respond, @urls);
            return;
        };
    };
}

sub _send_request {
    my ($self, $respond, @url) = @_;

    my $url = shift @url or return $respond->([500, [], ['not found']]); # 500??

    my $writer;
    my $http; $http = http_request(
        'GET'   => $url,
        timeout => $self->timeout,
        on_header => sub {
            my ($headers) = @_;
            if ($headers->{Status} eq '200') {
                $writer = $respond->([200, [%$headers]]);
            } else {
                debugf("FAIL to fetch the content from storage node. try to next node: @url");
                undef $http;
                $self->_send_request($respond, @url); # FAIL. try next node.
            }
        },
        on_body => sub {
            my ($partial_body, $headers) = @_;
            $writer->write($partial_body);
        },
        sub {
            my ($body, $headers) = @_;
            undef $http;
            if ($headers->{Status} =~ /^5/) {
                $self->_send_request($respond, @url); # FAIL. try next node.
                return;
            }
            $writer->close() if defined $writer;
        }
    );
}

# run on twiggy

1;

