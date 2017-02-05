package SomeModule;

use strict;
use warnings;

use Etsy::StatsD qw($statsd);


sub foo {
    $statsd->increment( $_[1] );
}


1;
