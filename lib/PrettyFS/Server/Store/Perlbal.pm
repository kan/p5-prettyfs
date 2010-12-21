use strict;
use warnings FATAL => 'all';
use utf8;

package PrettyFS::Server::Store::Perlbal;
use Log::Minimal;
use Class::Accessor::Lite (
    ro => [qw/maxconns listen docroot aio_threads/],
);
use List::Util qw/max/;
use Perlbal;

my $OPTMOD_IO_AIO;
BEGIN {
    $OPTMOD_IO_AIO        = eval "use IO::AIO 1.6 (); 1;";
}

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    bless {
        maxconns    => 1024,
        listen      => 1984,
        aio_threads => 10, # 10 to 100 is good(mogstored says)
        %args,
    }, $class;
}

sub run {
    my $self = shift;

    unless ($OPTMOD_IO_AIO) {
        if ($ENV{'PRETTYFS_RUN_WITHOUT_AIO'}) {
            warnf("WARNING:  Running without async IO.  Won't run well with many clients.\n");
        } else {
            die("ERROR: IO::AIO not installed, so async IO not available.  Refusing to run\n".
                "       unless you set the environment variable PRETTYFS_RUN_WITHOUT_AIO=1\n");
        }
    }

    my $xs_conf = "";
    if (eval "use Perlbal::XS::HTTPHeaders (); 1") {
        $xs_conf .= "xs enable headers\n" unless defined $ENV{PERLBAL_XS_HEADERS} && ! $ENV{PERLBAL_XS_HEADERS};
    }

      # this is the perlbal configuration only.  not the mogstored configuration.
      my $pb_conf = "
$xs_conf

SERVER max_connections = $self->{maxconns}

CREATE SERVICE prettyfs
    SET role              = web_server
    SET docroot           = $self->{docroot}
    SET listen            = $self->{listen}
    SET dirindexing       = 0
    SET enable_put        = 1
    SET enable_delete     = 1
    SET min_put_directory = 0
    SET persist_client    = 1
ENABLE prettyfs

SERVER aio_threads = $self->{aio_threads}
";

    Perlbal::run_manage_commands($pb_conf, sub { critf("$_[0]"); });

    unless (Perlbal::Socket->WatchedSockets > 0) {
        die "Invalid configuration.  (shouldn't happen?)  Stopping.\n";
    }

    infof("ready to run the perlbal");
    Perlbal::run();
}

1;

