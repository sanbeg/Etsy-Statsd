use strict;
use Test::More tests => 27;
use Test::MockModule;
use Etsy::StatsD;

my $module = Test::MockModule->new('Etsy::StatsD');
my $data;

$module->mock(
    _send_to_sock => sub ($$) {
        chomp(my $value = $_[1]);
        push(@$data, $value);
    }
);

my $bucket = 'test';
my $update = 5;
my $time = 1234;

ok (my $statsd = Etsy::StatsD->new, "create an object" );
is ( $statsd->{sockets}[0]->peerport, 8125, 'used default port');

$data = [];
ok( $statsd->timing($bucket, $time) );
is ( $data->[0], "$bucket:$time|ms");

$data = [];
ok( $statsd->increment($bucket) );
is( $data->[0], "$bucket:1|c");

$data = [];
ok( $statsd->decrement($bucket) );
is( $data->[0], "$bucket:-1|c");

$data = [];
ok( $statsd->update($bucket, $update) );
is( $data->[0], "$bucket:$update|c");

$data = [];
ok( $statsd->update($bucket) );
is( $data->[0], "$bucket:1|c");

$data = [];
ok( $statsd->update(['a','b']) );
is( (sort @$data)[0], "a:1|c" );
is( (sort @$data)[1], "b:1|c" );

$data = [];
ok( $statsd->gauge($bucket, $update) );
is( $data->[0], "$bucket:$update|g" );

$data = [];
ok( $statsd->set($bucket, 'value') );
is( $data->[0], "$bucket:value|s" );

$data = [];
ok( $statsd->prefix('prefix.') );
ok( $statsd->suffix('.suffix') );
ok( $statsd->increment($bucket) );
is( $data->[0], "prefix.$bucket.suffix:1|c" );

ok ( my $remote = Etsy::StatsD->new('localhost', 123), 'created with host, port combo');
is ( $remote->{sockets}[0]->peerport, 123, 'used specified port');


my $err;
eval {
    my $t = Etsy::StatsD->new(['localhost:8126:igmp']);
} or do { $err = $@; };
ok( defined $err && $err =~ /Invalid protocol/, "invalid protocol dies" ) or diag($err);

eval {
    my $t = Etsy::StatsD->new(['localhost', 'localhost:8126:igmp']);
} or do { $err = $@; };
ok( defined $err && $err =~ /Invalid protocol/, "invalid protocol dies in array ref" ) or diag($err);

