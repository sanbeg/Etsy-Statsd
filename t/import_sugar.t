use warnings;
use strict;

use FindBin;
use lib "$FindBin::Bin";

use Test::More tests => 7;
use Test::MockModule;

use SomeModule;
use Etsy::StatsD '$statsd', host => '1.2.3.4';

my $module = Test::MockModule->new('Etsy::StatsD');
my $data;

$module->mock(
    _send_to_sock => sub ($$) {
        chomp(my $value = $_[1]);
        push(@$data, $value);
    }
);

$data = [];
ok( $statsd->increment('test', 1) );
is( $statsd->{sockets}[0]->peerhost, '1.2.3.4' );
is( $data->[0], 'test:1|c' );

$data = [];
SomeModule->foo( 'metric' );
is( $SomeModule::statsd->{sockets}[0]->peerhost, '1.2.3.4' );
is( $data->[0], 'metric:1|c' );


Etsy::StatsD->configure(host => '4.3.2.1');
is( $statsd->{sockets}[0]->peerhost, '4.3.2.1' );
is( $SomeModule::statsd->{sockets}[0]->peerhost, '4.3.2.1' );

