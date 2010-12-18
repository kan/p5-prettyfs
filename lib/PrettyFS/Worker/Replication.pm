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
use PrettyFS::Constants;

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    $args{furl} ||= Furl::HTTP->new();
    for (qw/dbh/) {
        Carp::croak("missing mandatory parameter: $_") unless exists $args{$_};
    }
    bless {
        %args
    }, $class;
}

sub run {
    my ($self, $uuid) = @_;

    my $file = $self->dbh->selectrow_hashref(q{SELECT * FROM file WHERE uuid=? LIMIT 1}, {}, $uuid) or Carp::croak "Cannot select file: $uuid" . $self->dbh->errstr;
    unless ($file) {
        Carp::croak "unknown file: $uuid";
    }

    my ($host, $port, $status) = $self->dbh->selectrow_array(q{SELECT storage.host, storage.port, storage.status FROM storage WHERE id=?}, {}, $file->{storage_id});
    Carp::croak "Cannot retrieve storage information" unless $host && $port;
    unless ($status == STORAGE_STATUS_ALIVE) {
        critf("Cannot retrieve source. Because the node is currently unavailable.");
        return;
    }

    my $bucket_name;
    if ($file->{bucket_id}) {
        ($bucket_name) = $self->dbh->selectrow_array(q{SELECT bucket.name FROM bucket WHERE id=?}, {}, $file->{bucket_id});
        unless ($bucket_name) {
            critf("Cannot retrieve bucket. uuid: $uuid");
        }
    }

    my $path  = $bucket_name ? "/$bucket_name/$uuid" : "/$uuid";
       $path .= ".$file->{ext}" if $file->{ext};

    my $temp = File::Temp->new();
    my ($minor_version, $code, $msg, $headers, $body) = $self->furl->request(
        method     => 'GET',
        path_query => $path,
        port       => $port,
        host       => $host,
        write_file => $temp,
    );
    unless ($code == 200) {
        die "Cannot get the source data";
    }

    my @storage_nodes = shuffle @{$self->dbh->selectall_arrayref(q{SELECT id, host, port FROM storage WHERE status=? AND id != ?}, {Slice => {}}, STORAGE_STATUS_ALIVE, $file->{storage_id})};
    for my $storage (@storage_nodes) {
        if ($self->copy_file($file, $path, $uuid, $temp, $storage->{id}, $storage->{host}, $storage->{port})) {
            infof("Replication successfully. $host:$port => $storage->{host}:$storage->{port}");
            return;
        }
    }
    die "Cannot replication: $uuid";
}

sub copy_file {
    my ($self, $file, $path, $uuid, $src_fh, $storage_id, $host, $port) = @_;
    seek $src_fh, 0, SEEK_SET;
    my $size = -s $src_fh;

    $self->dbh->do(q{INSERT INTO file (uuid, storage_id, bucket_id, size, ext) VALUES (?, ?, ?, ?, ?)}, {}, $uuid, $storage_id, $file->{bucket_id}, $size, $file->{ext})
            or Carp::croak("Cannot insert to database: " . $self->dbh->errstr);

    my ($minor_version, $code, $msg, $headers, $body) = $self->furl->request(
        method  => 'PUT',
        host    => $host,
        port    => $port,
        path    => $path,
        content => $src_fh,
    );
    return ($code == 200) ? 1 : 0;
}

1;

