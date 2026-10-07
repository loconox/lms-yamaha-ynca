package Plugins::YamahaYNCA::Plugin;

# Powers a Yamaha YNCA-compatible amplifier on when any Lyrion player starts
# playing, and switches it back to standby after a configurable period
# during which nothing is playing on any player.
#
# YNCA protocol reference: doc/Yamaha-YNCA-Receivers.pdf
#   - Plain text commands over TCP (default port 50000), terminated by CR/LF
#   - Main zone power: "@MAIN:PWR=On" / "@MAIN:PWR=Standby"
#   - Main zone input select: "@MAIN:INP=<input>"
#   - Renamed input labels: "@SYS:INPNAME=?" replies with one line per
#     renameable jack, e.g. "@SYS:INPNAMEHDMI1=Chromecast"

use strict;
use warnings;

use IO::Socket::INET;
use IO::Select;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Timers;
use Slim::Player::Client;

if ( main::WEBUI ) {
	require Plugins::YamahaYNCA::Settings;
}

use constant POLL_INTERVAL  => 10; # seconds between playback activity checks
use constant SOCKET_TIMEOUT => 3;  # seconds to wait when connecting to / reading from the amp

# Inputs defined by the YNCA protocol for the Main Zone. Models vary in which
# of these actually exist; the renameable jacks (HDMI/AV/AUDIO/DOCK/USB) get
# their real label overlaid at render time via fetchInputNames().
my @KNOWN_INPUTS = qw(
	HDMI1 HDMI2 HDMI3 HDMI4 HDMI5
	AV1 AV2 AV3 AV4 AV5 AV6
	V-AUX AUDIO1 AUDIO2 DOCK USB
	TUNER SIRIUS NET iPod Bluetooth UAW PC Rhapsody Napster Pandora
);

# Maps the suffix used in "@SYS:INPNAMExxxx=" responses to the matching @MAIN:INP value
my %INPNAME_TO_INP = (
	HDMI1 => 'HDMI1', HDMI2 => 'HDMI2', HDMI3 => 'HDMI3', HDMI4 => 'HDMI4', HDMI5 => 'HDMI5',
	AV1   => 'AV1',   AV2   => 'AV2',   AV3   => 'AV3',   AV4   => 'AV4',   AV5 => 'AV5', AV6 => 'AV6',
	VAUX  => 'V-AUX', AUDIO1 => 'AUDIO1', AUDIO2 => 'AUDIO2', DOCK => 'DOCK', USB => 'USB',
);

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.yamahaynca',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_YAMAHAYNCA_NAME',
});

my $prefs = preferences('plugin.yamahaynca');

$prefs->init({
	amphost      => '',
	ampport      => 50000,
	offdelay     => 5,
	startupinput => '',
	inputdelay   => 2,
});

# Host is validated loosely (hostname or IPv4); empty disables the plugin.
$prefs->setValidate( { validator => sub { $_[1] eq '' || $_[1] =~ /^[A-Za-z0-9_.-]+$/ } }, 'amphost' );
$prefs->setValidate( { validator => 'intlimit', low => 1, high => 65535 }, 'ampport' );
$prefs->setValidate( { validator => 'intlimit', low => 1, high => 120 }, 'offdelay' );
$prefs->setValidate( { validator => sub { $_[1] eq '' || $_[1] =~ /^[A-Za-z0-9 \-()]+$/ } }, 'startupinput' );
$prefs->setValidate( { validator => 'intlimit', low => 0, high => 30 }, 'inputdelay' );

# undef = amp power state unknown yet, 1 = believed on, 0 = believed in standby
my $ampIsOn;

# time() of the last moment any player was actively playing
my $lastPlayingTime = time();

sub getDisplayName { return 'PLUGIN_YAMAHAYNCA_NAME'; }

sub initPlugin {
	my $class = shift;

	if ( main::WEBUI ) {
		Plugins::YamahaYNCA::Settings->new;
	}

	$lastPlayingTime = time();

	checkActivity();
}

sub shutdownPlugin {
	Slim::Utils::Timers::killTimers( undef, \&checkActivity );
	Slim::Utils::Timers::killTimers( undef, \&sendStartupInput );
}

sub checkActivity {
	Slim::Utils::Timers::killTimers( undef, \&checkActivity );
	Slim::Utils::Timers::setTimer( undef, time() + POLL_INTERVAL, \&checkActivity );

	my $host = $prefs->get('amphost');
	return unless $host;

	my $anyPlaying = 0;

	for my $client ( Slim::Player::Client::clients() ) {
		if ( $client->isPlaying() ) {
			$anyPlaying = 1;
			last;
		}
	}

	my $now = time();

	if ($anyPlaying) {
		$lastPlayingTime = $now;

		if ( !$ampIsOn ) {
			main::INFOLOG && $log->is_info && $log->info('Playback detected, switching amp on');
			sendPower('On');
			$ampIsOn = 1;

			if ( $prefs->get('startupinput') ) {
				my $delay = $prefs->get('inputdelay');
				$delay = 2 unless defined $delay;

				Slim::Utils::Timers::killTimers( undef, \&sendStartupInput );
				Slim::Utils::Timers::setTimer( undef, time() + $delay, \&sendStartupInput );
			}
		}
	}
	elsif ( !defined $ampIsOn || $ampIsOn ) {
		my $offDelay = ( $prefs->get('offdelay') || 5 ) * 60;

		if ( $now - $lastPlayingTime >= $offDelay ) {
			main::INFOLOG && $log->is_info && $log->info(
				sprintf( 'No playback for %d min, switching amp to standby', ( $now - $lastPlayingTime ) / 60 )
			);
			sendPower('Standby');
			$ampIsOn = 0;
		}
	}
}

sub sendStartupInput {
	# amp may have been switched off again in the meantime (very short offdelay)
	return unless $ampIsOn;

	my $input = $prefs->get('startupinput');
	return unless $input;

	main::INFOLOG && $log->is_info && $log->info("Selecting startup input: $input");
	sendCommand("INP=$input");
}

sub sendPower {
	my $param = shift;
	sendCommand("PWR=$param");
}

sub sendCommand {
	my $command = shift;

	my $host = $prefs->get('amphost');
	my $port = $prefs->get('ampport') || 50000;

	return unless $host;

	my $socket = IO::Socket::INET->new(
		PeerAddr => $host,
		PeerPort => $port,
		Proto    => 'tcp',
		Timeout  => SOCKET_TIMEOUT,
	);

	if ( !$socket ) {
		$log->error("Unable to connect to Yamaha amp at $host:$port: $!");
		return;
	}

	$socket->print("\@MAIN:$command\r\n");
	$socket->close;

	main::DEBUGLOG && $log->is_debug && $log->debug("Sent \@MAIN:$command to $host:$port");
}

# Builds the list of { value, label } options for the startup-input dropdown,
# overlaying real jack names fetched live from the amp (if reachable) onto the
# static list of inputs known to the YNCA protocol.
sub inputOptions {
	my $host = $prefs->get('amphost');
	my $port = $prefs->get('ampport') || 50000;

	my %labels = map { $_ => $_ } @KNOWN_INPUTS;

	if ($host) {
		my $renamed = fetchInputNames( $host, $port );

		for my $suffix ( keys %$renamed ) {
			my $inp  = $INPNAME_TO_INP{$suffix} or next;
			my $name = $renamed->{$suffix};

			$labels{$inp} = "$inp ($name)" if $name && $name ne '';
		}
	}

	return [ map { { value => $_, label => $labels{$_} } } sort keys %labels ];
}

# Queries "@SYS:INPNAME=?" and parses the multi-line reply listing the custom
# name given to each renameable input jack on this particular amp.
sub fetchInputNames {
	my ( $host, $port ) = @_;

	my %names;

	my $socket = IO::Socket::INET->new(
		PeerAddr => $host,
		PeerPort => $port,
		Proto    => 'tcp',
		Timeout  => SOCKET_TIMEOUT,
	);

	return \%names unless $socket;

	$socket->print("\@SYS:INPNAME=?\r\n");

	my $select   = IO::Select->new($socket);
	my $buffer   = '';
	my $deadline = time() + SOCKET_TIMEOUT;

	while ( time() < $deadline && $select->can_read(0.3) ) {
		my $chunk;
		my $bytes = $socket->sysread( $chunk, 1024 );
		last unless $bytes;
		$buffer .= $chunk;
	}

	$socket->close;

	while ( $buffer =~ /\@SYS:INPNAME([A-Z0-9]+)=([^\r\n]*)/g ) {
		$names{$1} = $2;
	}

	if ( main::DEBUGLOG && $log->is_debug ) {
		$log->debug( 'Fetched input names from amp: ' . join( ', ', map { "$_=$names{$_}" } keys %names ) );
	}

	return \%names;
}

1;
