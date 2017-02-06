package Etsy::StatsD;
use strict;
use warnings;
use IO::Socket;
use Carp;

our $VERSION = 1.002002;

# The CPAN verion at https://github.com/sanbeg/Etsy-Statsd should be kept in
# sync with the version distributed with StatsD, at
# https://github.com/etsy/statsd (in the exmaples directory), so you can get
# it from either location.

sub import {
    my $class = shift;

    return unless @_;

    my $varname;
    my $config = {};

    while ( $_ = shift @_) {
        if (/^\$(statsd?)/) {
            $varname = $1;
        }
        else {
            $config->{$_} = shift @_; # pairwise
        }
    }

    if (%$config) {
        $class->configure($config);
    }

    if ($varname) {
        my $caller  = caller();

        no strict 'refs';
        my $full_varname = "${caller}::$varname";

        # my $statsd  = $class->get_statsd;
        # *$full_varname = \$statsd;

        # Defer object creation because we need config that will be availabe at run time
        my $deferred = Etsy::StatsD::_Deferred->new;
        *$full_varname = \$deferred;
    }
}

sub new {
    my ( $class, $host, $port, $sample_rate, $prefix, $suffix ) = @_;

    if ( ref($host) eq 'HASH' ) {
        my $args = $host;

        $host = $args->{host};
        $port = $args->{port};

        $sample_rate = $args->{sample_rate};
        $prefix      = $args->{prefix};
        $suffix      = $args->{suffix};
    }

    $host = 'localhost' unless defined $host;
    $port = 8125        unless defined $port;

    # Handle multiple connections and
    #  allow different ports to be specified
    #  in the form of "<host>:<port>:<proto>"
    my %protos = map { $_ => 1 } qw(tcp udp);
    my @connections = ();

    if( ref $host eq 'ARRAY' ) {
        foreach my $addr ( @{ $host } ) {
            my ($addr_host,$addr_port,$addr_proto) = split /:/, $addr;
            $addr_port  ||= $port;
            # Validate the protocol
            if( defined $addr_proto ) {
                $addr_proto = lc $addr_proto;  # Normalize to lowercase
                # Check validity
                if( !exists $protos{$addr_proto} ) {
                    croak sprintf("Invalid protocol  '%s', valid: %s", $addr_proto, join(', ', sort keys %protos));
                }
            }
            else {
                $addr_proto = 'udp';
            }
            push @connections, [ $addr_host, $addr_port, $addr_proto ];
        }
    }
    else {
        push @connections, [ $host, $port, 'udp' ];
    }

    my @sockets = ();
    foreach my $conn ( @connections ) {
        my $sock = IO::Socket::INET->new(
            PeerAddr => $conn->[0],
            PeerPort => $conn->[1],
            Proto    => $conn->[2],
        ) or carp "Failed to initialize socket: $!";

        push @sockets, $sock if defined $sock;
    }
    # Check that we have at least 1 socket to send to
    croak "Failed to initialize any sockets." unless @sockets;

    bless {
        sockets     => \@sockets,
        sample_rate => $sample_rate,
        prefix      => $prefix // '',
        suffix      => $suffix // '',
    }, $class;
}

sub prefix {
    my ( $self ) = @_;
    @_ > 1 ? $self->{prefix} = $_[1] : $self->{prefix};
}

sub suffix {
    my ( $self ) = @_;
    @_ > 1 ? $self->{suffix} = $_[1] : $self->{suffix};
}

sub timing {
    my ( $self, $stat, $time, $sample_rate ) = @_;
    $self->send( { $stat => "$time|ms" }, $sample_rate );
}

sub increment {
    my ( $self, $stats, $sample_rate ) = @_;
    $self->update( $stats, 1, $sample_rate );
}

sub decrement {
    my ( $self, $stats, $sample_rate ) = @_;
    $self->update( $stats, -1, $sample_rate );
}

sub update {
    my ( $self, $stats, $delta, $sample_rate ) = @_;
    $delta = 1 unless defined $delta;
    my %data;
    if ( ref($stats) eq 'ARRAY' ) {
        %data = map { $_ => "$delta|c" } @$stats;
    }
    else {
        %data = ( $stats => "$delta|c" );
    }
    $self->send( \%data, $sample_rate );
}

sub gauge {
    my ( $self, $stats, $value, $sample_rate ) = @_;
    $self->send( { $stats => "$value|g" }, $sample_rate );
}

sub set {
    my ( $self, $stats, $value, $sample_rate ) = @_;
    $self->send( { $stats => "$value|s" }, $sample_rate );
}

sub timer {
    my ( $self, $stats, $sample_rate ) = @_;
    return Etsy::StatsD::Timer->new( $self, $stats, $sample_rate );
}

sub send {
    my ( $self, $data, $sample_rate ) = @_;
    $sample_rate = $self->{sample_rate} unless defined $sample_rate;

    my $sampled_data;
    if ( defined($sample_rate) and $sample_rate < 1 ) {
        while ( my ( $stat, $value ) = each %$data ) {
            $sampled_data->{$stat} = "$value|\@$sample_rate" if rand() <= $sample_rate;
        }
    }
    else {
        $sampled_data = $data;
    }

    return '0 but true' unless keys %$sampled_data;

    #failures in any of this can be silently ignored
    my $count  = 0;
    foreach my $socket ( @{ $self->{sockets} } ) {
        # calling keys() resets the each() iterator
        keys %$sampled_data;
        while ( my ( $stat, $value ) = each %$sampled_data ) {
            _send_to_sock($socket, $self->_metric_name($stat).":$value\n", 0);
            ++$count;
        }
    }
    return $count;
}

{
    my $config    = {};
    my $instances = [];

    sub configure {
        my ( $class, @args ) = @_;
        $config = ref($args[0]) eq 'HASH' ? $args[0] : { @args };

        # clean out destroyed objects
        # maybee it will be better to do in DESTROY
        @$instances = grep { defined } @$instances;

        for (@$instances) {
            $_->_update_options($config);
        }
    }

    sub get_statsd {
        my ($class) = @_;
        my $statsd = $class->new($config);
        push( @$instances, $statsd );
        return $statsd;
    }

    sub _update_options {
        my ( $self, $options ) = @_;
        my $new_statsd = ref($_[0])->new($_[1]);
        %{ $self } = %{ $new_statsd };
    }
}

sub _send_to_sock( $$ ) {
    my ( $sock, $msg ) = @_;
    CORE::send( $sock, $msg, 0 );
}

sub _metric_name {
    my ($self, $name) = @_;
    join('', $self->{prefix}, $name, $self->{suffix});
}


package Etsy::StatsD::Timer;

use Time::HiRes;

sub new {
    my ( $class, $statsd, $metric, $sample_rate ) = @_;

    my ( undef, $file, $line ) = caller(1);

    return bless {
        statsd      => $statsd,
        metric      => $metric,
        sample_rate => $sample_rate,
        start       => Time::HiRes::time,
        file        => $file,
        line        => $line,
        is_finished => 0,
    }, $class;
}

sub finish {
    my ($self) = @_;

    $self->{statsd}->timing( $self->{metric}, ( Time::HiRes::time - $self->{start} ) * 1000, $self->{sample_rate} );

    $self->{is_finished} = 1;
}

sub cancel {
    my ($self) = @_;
    $self->{is_finished} = 1;
}

sub DESTROY {
    my ($self) = @_;
    warn sprintf(
        "Destroy unfinished timer for metric %s started at %s line %s.\n",
        $self->{statsd} ? $self->{statsd}->_metric_name( $self->{metric} ) : $self->{metric},
        $self->{file},
        $self->{line}
    ) unless $_[0]->{is_finished};
}


package Etsy::StatsD::_Deferred;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub AUTOLOAD {
    my ($self, @args) = @_;

    my ($sub) = our $AUTOLOAD =~ /.*::(.+)$/;

    $_[0] = Etsy::StatsD->get_statsd;

    return $_[0]->$sub(@args);
}

sub DESTROY { }


1;


__END__

=pod

=encoding UTF-8

=head1 NAME

Etsy::StatsD - Object-Oriented Client for Etsy's StatsD Server

=head1 SYNOPSIS

    use Etsy::StatsD;

    # Increment a counter
    my $statsd = Etsy::StatsD->new();
    $statsd->increment( 'app.method.success' );


    # Time something
    use Time::HiRes;

    my $start_time = time;
    $app->do_stuff;
    my $done_time = time;

    # Timers are expected in milliseconds
    $statsd->timing( 'app.method', ($done_time - $start_time) * 1000 );

    # Send to two StatsD Endpoints simultaneously
    my $repl_statsd = Etsy::StatsD->new(["statsd1","statsd2"]);

    # On two different ports:
    my $repl_statsd = Etsy::StatsD->new(["statsd1","statsd1:8126"]);

    # Use TCP to a collector (you must specify a port)
    my $important_stats = Etsy::StatsD->new(["bizstats1:8125:tcp"]);


=head1 METHODS

=head2 new(HOST, PORT, SAMPLE_RATE, PREFIX, SUFFIX)

Create a new instance.

=over

=item HOST


If the argument is a string, it must be a hostname or IP only. The default is
'localhost'. The argument may also be an array reference of strings in the
form of "<host>", "<host>:<port>", or "<host>:<port>:<proto>". If the port is
not specified, the default port specified by the PORT argument will be used.
If the protocol is not specified, or is not "tcp" or "udp", "udp" will be set.
The only way to change the protocol, is to specify the host, port and protocol.

=item PORT

Default is 8125. Will be used as the default port for any HOST argument not explicitly defining port.

=item SAMPLE_RATE

Default is undefined, or no sampling performed. Specify a rate as a decimal between 0 and 1 to enable
sampling. e.g. 0.5 for 50%.

=item PREFIX

Optional. Default is ''. Specify prefix for metric names.

=item SUFFIX

Optional. Default is ''. Specify suffix for metric names.

=back

=head2 prefix(STRING)

A prefix to be prepended to all metric names.

=head2 suffix(STRING)

A suffix to be appended to all metric names.

=head2 timing(STAT, TIME, SAMPLE_RATE)

Log timing information

=head2 increment(STATS, SAMPLE_RATE)

Increment one of more stats counters.

=head2 decrement(STATS, SAMPLE_RATE)

Decrement one of more stats counters.

=head2 update(STATS, DELTA, SAMPLE_RATE)

Update one of more stats counters by arbitrary amounts.

=head2 gauge(STATS, VALUE, SAMPLE_RATE)

Send a value for the named gauge metric.

=head2 set(STATS, VALUE, SAMPLE_RATE)

Add a value to the unique set metric.

=head2 timer(STATS, SAMPLE_RATE)

Start timer for metric STATS. Return Etsy::StatsD::Timer object with C<finish()> and C<cancel()> methods.

    my $timer = $statsd->timer('foo');
    ...
    $timer->finish;

=head2 send(DATA, SAMPLE_RATE)

Sending logging data; implicitly called by most of the other methods.

=head1 IMPORT SYNTACTIC SUGAR (EXPERIMENTAL)

You can use L<Etsy::Statsd> in well known L<Log::Any> manner

In a CPAN or other module:

    package Foo;
    use Etsy::Statsd qw($statsd);

    # send a metric
    $statsd->incemenet('foo.metrict');

In your application:

    use Foo;
    use Etsy::StatsD '$statsd', host => '1.2.3.4';

    $statsd->increment('main.metric');

    # reconfigure Statsd options
    # will affect all created $statsd objects
    Etsy::StatsD->configure(host => '4.3.2.1');

=head1 SEE ALSO

L<http://codeascraft.etsy.com/2011/02/15/measure-anything-measure-everything/>

=head1 AUTHOR

Steve Sanbeg L<http://www.buzzfeed.com/stv>

=head1 LICENSE

Same as perl.

=cut

1;
