use Plack::Request;
use Config::Tiny;
use Log::Minimal;

my $config_path = $ENV{PRETTYFS_CONFIG} || die "missing PRETTYFS_CONFIG";
my %config = do {
    my $conf = Config::Tiny->read($config_path) or die "cannot load configuration from: $config_path";
    %{$conf->{_}};
};
debugf("configuration: %s", ddf(\%config));
my $base = $config{base} || die "missing configuraion key: base";
die "'$base' is not a directory" unless -d $base;

sub dispatch_put {
    my ($req) = @_;

    # TODO: directory traversal
    my $fname = File::Spec->catfile($base, $req->path_info);
    if (-f $fname) {
        [403, [], ["File already exists"]]; # XXX bad status code
    } else {
        open my $fh, '>', $fname or die "cannot open file: $fname";
        print $fh $req->content or die "cannot write file: $fname";
        close $fh;
        [200, [], ["OK"]];
    }
}

sub dispatch_delete {
    my ($req) = @_;
    my $fname = File::Spec->catfile($base, $req->path_info);
    if (-f $fname) {
        unlink $fname or die "cannot unlink file: $fname, $!";
        [200, [], ["OK"]];
    } else {
        return [404, [], ['Not Found']];
    }
}

sub dispatch_get {
    my ($req) = @_;
    # TODO: directory traversal
    my $fname = File::Spec->catfile($base, $req->path_info);
    if (-f $fname) {
        open my $fh, '<', $fname or die "cannot open file: $fname";
        [200, [], [$fh]];
    } else {
        return [404, [], ['Not Found']];
    }
}

sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $path_info = $req->path_info;

    my $method = "dispatch_" . lc($req->method);
    my $code = __PACKAGE__->can($method);
    if ($code) {
        return $code->($req);
    } else {
        [405, [], ['Method not allowed']];
    }
};

