#! /usr/bin/perl -w

use lib 'lib';
use Etsy::StatsD;

my $bucket = 'test';
my $update = 5;
my $time = 1234;

my $statsd = Etsy::StatsD->new;

$statsd->timing($bucket,$time);

