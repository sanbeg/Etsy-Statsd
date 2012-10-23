use strict;
use Test::More tests=>9;
use Test::MockModule;
use Etsy::StatsD;

my $module = Test::MockModule->new('Etsy::StatsD');
my $data;

$module->mock(
	send => sub {
		$data = $_[1];
	}
);

my $bucket = 'test';
my $update = 5;
my $time = 1234;

ok (my $statsd = Etsy::StatsD->new );

$data = {};
ok( $statsd->timing($bucket,$time) );
is ( $data->{$bucket}, "$time|ms");

$data = {};
ok( $statsd->increment($bucket) );
is( $data->{$bucket}, '1|c');

$data = {};
ok( $statsd->decrement($bucket) );
is( $data->{$bucket}, '-1|c');

$data = {};
ok( $statsd->update($bucket, $update) );
is( $data->{$bucket}, "$update|c");


