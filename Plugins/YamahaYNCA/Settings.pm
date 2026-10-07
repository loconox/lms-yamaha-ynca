package Plugins::YamahaYNCA::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.yamahaynca');

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_YAMAHAYNCA_NAME');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/YamahaYNCA/settings/basic.html');
}

sub prefs {
	return ($prefs, qw(amphost ampport offdelay startupinput inputdelay));
}

sub handler {
	my ( $class, $client, $paramRef, @args ) = @_;

	# populate the startup-input dropdown, overlaying live jack names from the amp
	$paramRef->{inputOptions} = Plugins::YamahaYNCA::Plugin::inputOptions();

	return $class->SUPER::handler( $client, $paramRef, @args );
}

1;

__END__
