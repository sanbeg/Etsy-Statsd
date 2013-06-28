use strict;
use Test::More;

eval {
    require Test::TCP;
    plan tests => 5;
};
if ($@) {
    plan skip_all => 'Missing Test::TCP';
}

my $mock_server = Test::TCP->new(
			      listen => 1,
			      code   => sub {  },
			     );

ok ( my $spray = Etsy::StatsD->new(['localhost','localhost:8126',sprintf('localhost:%d:tcp', $mock_server->port)], 8125), "multiple dispatch with tcp" );
is ( $spray->{sockets}[0]->peerport, 8125, 'port works in array of hosts');
is ( $spray->{sockets}[1]->peerport, 8126, 'custom port works in array of hosts');
is ( $spray->{sockets}[2]->protocol, 6, 'TCP protocol  works in array of hosts');
