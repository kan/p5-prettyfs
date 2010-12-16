package PrettyFS::Worker::Replication;
use strict;
use warnings;
use utf8;
use Class::Accessor::Lite (
    new => 0,
    ro => [qw/dbh furl/],
);
use Log::Minimal;
use Furl::HTTP;
use List::Util qw/shuffle/;
use File::Temp;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    $args{furl} ||= Furl::HTTP->new();
    bless {
        %args
    }, $class;
}

sub run {
    my ($self, $file_uuid) = @_;

    my ($host, $port, $status) = $self->dbh->selectrow_array(q{SELECT storage.host, storage.port, storage.status FROM file INNER JOIN storage USING (id) WHERE file.uuid=?}, $file_uuid);
    Carp::croak "Cannot retrieve storage information" unless $host && $port;
    unless ($status == STORAGE_STATUS_ALIVE) {
        critf("Cannot retrieve source. Because the node is currently unavailable.");
        return;
    }

    my ($bucket_name) = $self->dbh->selectrow_array(q{SELECT bucket.name FROM file INNER JOIN bucket USING (id) WHERE file.uuid=?}, $file_uuid);
    unless ($bucket_name) {
        critf("Cannot retrieve bucket. file_uuid: $file_uuid");
    }

    my $temp = File::Temp->new();
    my ($minor_version, $code, $msg, $headers, $body) = $self->furl->request(
        method     => 'GET',
        path_query => "/$bucket_name/$file_uuid",
        port       => $port,
        host       => $host,
        write_file => $temp,
    );
    unless ($code == 200) {
        die "Cannot get the source data";
    }

    my @storage_nodes = shuffle @{$self->dbh->selectall_arrayref(q{SELECT host, port FROM storage WHERE status=?}, {Slice => {}}, STORAGE_STATUS_ALIVE)};
    for my $storage (@storage_nodes) {
        if ($self->copy_file($bucket_name, $file_uuid, $tmp, $storage->{host}, $storage->{port})) {
            infof("Replication successfully. $host:$port => $storage->{host}:$storage->{port}");
            return;
        }
    }
    die "Cannot replication: $file_uuid";
}

sub copy_file {
    my ($bucket_name, $file_uuid, $src_fh, $host, $port) {
    seek $src_fh, 0, SEEK_SET;

    my ($minor_version, $code, $msg, $headers, $body) = $self->furl->request(
        method  => 'PUT',
        host    => $host,
        port    => $port,
        path    => "/$bucket_name/$file_uuid",
        content => $src_fh,
    );
    return ($code == 200) ? 1 : 0;
}

1;

