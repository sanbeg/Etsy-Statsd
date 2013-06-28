#! /usr/bin/perl
use IO::Socket;


my $sock = IO::Socket::INET->new(
  Proto      => 'udp',
  LocalHost  => 0,
  LocalPort  => 8125,
  MultiHomed => 1,
);

while (1) {
  my $data;
  my $addr = $sock->recv($data, 1024);

  print "<<$data>>\n";
}
