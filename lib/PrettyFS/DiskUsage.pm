use strict;
use warnings;
use utf8;

package PrettyFS::DiskUsage;
use Class::Accessor::Lite (
    ro  => [qw/docroot interval/],
);
use Log::Minimal;
use JSON;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    for (qw/docroot/) {
        Carp::croak("missing mandatory parameter: $_") unless exists $args{$_};
    }
    $args{interval} ||= 10;
    bless {%args}, $class;
}

sub run {
    my $self = shift;
    while (1) {
        $self->run_once();

        sleep $self->interval;
    }
}

# code taken from Mogstored::ChildProcess::DiskUsage
sub run_once {
    my $self = shift;
    
    my $path = $self->docroot;
    my $rval = `df -P -l -k $path`;
    my $uperK = ( $rval =~ /512-blocks/i ) ? 2 : 1;    # units per kB
    foreach my $l ( split /\r?\n/, $rval ) {
        next unless $l =~ /^(.+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(.+)\s+(.+)$/;
        my ( $dev, $total, $used, $avail, $useper, $disk ) =
          ( $1, $2, $3, $4, $5, $6 );

        unless ( $disk =~ m{\Q$path\E\/?$} ) {
            $disk = "$path";
        }

        # create string to print
        my $now    = time;
        my $output = {
            time      => time(),
            device    => $dev,                   # /dev/sdh1
            total     => int( $total / $uperK ), # integer: total KiB blocks
            used      => int( $used / $uperK ),  # integer: used KiB blocks
            available => int( $avail / $uperK ), # integer: available KiB blocks
            'use'     => $useper,                # "45%"
            disk      => $disk
            ,  # mount point of disk (/var/mogdata/dev8), or path if not a mount
        };

        # size of old file we'll be overwriting in place (we'll want
        # to pad with newlines/spaces, before we truncate it, for
        # minimizing races)
        my $ufile    = "$path/usage";
        my $old_size = ( -s $ufile ) || 0;
        my $mode     = $old_size ? "+<" : ">";

        # string we'll be writing
        my $new_data = JSON->new->canonical->utf8->encode($output);

        my $new_size = length $new_data;
        my $pad_len = $old_size > $new_size ? ( $old_size - $new_size ) : 0;
        $new_data .= "\n" x $pad_len;

        # write the file, all at once (with padding) then remove padding
        my $rv = open( my $fh, $mode, $ufile );
        unless ($rv) {
            critf("Unable to open '$ufile' for writing: $!");
            next;
        }
        unless ( syswrite( $fh, $new_data ) ) {
            close($fh);
            critf("Error writing to '$ufile': $!");
            next;
        }
        truncate( $fh, $new_size ) if $pad_len;
        close($fh);
    }
}

1;

