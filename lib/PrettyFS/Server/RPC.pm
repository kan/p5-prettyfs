package PrettyFS::Server::RPC;
use strict;
use warnings;
use utf8;
use Class::Accessor::Lite (
    new => 1,
    ro  => [qw/client/],
);
use JSON::XS;
use Plack::Request;

# PSGI app
sub to_app {
    my $self = shift;

    sub {
        my $env = shift;
        my $req = Plack::Request->new($env);
        my $path = $req->path_info;
        $path =~ s!^/!!;
        $path =~ /^[a-z0-9A-Z_-]+$/ or return [404, [], []];
        my $http_method = lc $req->method;
        unless ($http_method eq 'get' or $http_method eq 'post') {
            return [403, [], []];
        }
        my $meth = "${http_method}_$path";
        return $self->$meth($req);
    };
}

sub show_json {
    my ($self, $stuff) = @_;
    my $content = encode_json({error => undef, value => $stuff});
    return [200, ['Content-Type' => 'application/json', 'Content-Length' => length($content)], [$content]];
}

sub show_error {
    my ($self, $msg) = @_;
    my $content = encode_json({error => $msg});
    return [500, ['Content-Type' => 'application/json', 'Content-Length' => length($content)], [$content]];
}

# ------------------------------------------------------------------------- 

sub get_list_storage {
    my $self = shift;
    return $self->show_json(scalar $self->client->list_storage());
}

sub post_add_storage {
    my ($self, $req) = @_;
    my %args = %{$req->parameters};
    for (qw/host port/) {
        return $self->show_error("Missing mandatory parameter: $_") unless defined $args{$_};
    }
    $self->client->add_storage(%args);
    return $self->show_json({error => 0});
}

1;

