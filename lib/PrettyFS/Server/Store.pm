use strict;
use warnings;
use utf8;

package PrettyFS::Server::Store;
use Plack::Request;
use Config::Tiny;
use Log::Minimal;
use Class::Accessor::Lite (
    ro => [qw/base/],
);

sub new {
    my $class = shift;

    my $config_path = $ENV{PRETTYFS_CONFIG} || die "missing PRETTYFS_CONFIG";
    my %config = do {
        my $conf = Config::Tiny->read($config_path) or die "cannot load configuration from: $config_path";
        %{$conf->{_}};
    };
    debugf("configuration: %s", ddf(\%config));
    my $base = $config{base} || die "missing configuraion key: base";
    die "'$base' is not a directory" unless -d $base;

    bless {base => $base}, $class;
}

sub to_app {
    my $class = shift;
    my $self = $class->new();

    sub {
        my $env = shift;

        if ($env->{REQUEST_METHOD} =~ /^(PUT|GET|DELETE)$/) {
            my $method = "dispatch_" . lc($env->{REQUEST_METHOD});
            return $self->$method($env);
        } else {
            [405, [], ['Method not allowed']];
        }
    };
}

sub dispatch_put {
    my ($self, $env) = @_;
    my $req = Plack::Request->new($env); # TODO: use $env directly for performance

    # TODO: directory traversal
    my $fname = File::Spec->catfile($self->base, $req->path_info);
    if (-f $fname) {
        [403, [], ["File already exists"]]; # XXX bad status code
    } else {
        open my $fh, '>:raw', $fname or die "cannot open file: $fname";
        print $fh $req->content or die "cannot write file: $fname";
        close $fh;
        [200, [], ["OK"]];
    }
}

sub dispatch_delete {
    my ($self, $env) = @_;
    my $req = Plack::Request->new($env); # TODO: use $env directly for performance

    # TODO: directory traversal
    my $fname = File::Spec->catfile($self->base, $req->path_info);
    if (-f $fname) {
        unlink $fname or die "cannot unlink file: $fname, $!";
        [200, [], ["OK"]];
    } else {
        return [404, [], ['Not Found']];
    }
}

sub dispatch_get {
    my ($self, $env) = @_;
    my $req = Plack::Request->new($env); # TODO: use $env directly for performance

    # TODO: directory traversal
    my $fname = File::Spec->catfile($self->base, $req->path_info);
    if (-f $fname) {
        open my $fh, '<:raw', $fname or die "cannot open file: $fname";
        [200, [], $fh];
    } else {
        return [404, [], ['Not Found']];
    }
}

1;
__END__

=head1 SYNOPSIS

    % plackup -Ilib PrettyFS::Server::Store

