######################################################################################
#
# Plugin OpenWeatherMap
# Copyright: krumboeck (http://knx-user-forum.de/members/krumboeck.html)
# License: GPL (v2)
# V0.3 2013-09-07
#
# Ein Wiregate Plugin zum Senden von openweathermap.org Wetterdaten auf den KNX Bus
#
######################################################################################


#################
### Konfiguration
#################

# Festlegen, dass das Plugin alle 20 Minuten laufen soll
$plugin_info{$plugname.'_cycle'} = 1200;


#################################
### Lesen der Konfigurationsdatei
#################################

my ($lat, $lon, $locale);
my $knxGA;

# Read config file in conf.d
my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
if (! -f $confFile) {
	plugin_log($plugname, " no conf file [$confFile] found.");
	return "no conf file [$confFile] found.";
} else {
	open(CONF, $confFile);
	my @lines = <CONF>;
	close($confFile);
	my $result = eval("@lines");
	if ($@) {
		plugin_log($plugname, "conf file [$confFile] returned:");
		my @parts = split(/\n/, $@);
		plugin_log($plugname, "--> $_") foreach (@parts);
	}
}


################
### Definitionen
################

use LWP::UserAgent;
use XML::Simple;

my $units = 'metric';
my $mode = 'xml';


#########################
### Wetterdaten ermitteln
#########################

my $baseurl = 'http://api.openweathermap.org/data/2.5/weather?';
my $url = $baseurl . 'lat=' . $lat . '&lon=' . $lon . '&units=' . $units . '&mode=' . $mode . '&lang=' . $locale;

my $ua = LWP::UserAgent->new;
$ua->timeout(30);
my $response = $ua->get($url);

if (! $response->is_success) {
	return $response->status_line;
}

my $content = $response->decoded_content;

my $xml = new XML::Simple;
my $data = $xml->XMLin($content);


#################################
### Wetterdaten auf Bus schreiben
#################################

if (defined $knxGA->{temperature}) {
	knx_write($knxGA->{temperature}, $data->{temperature}->{value}, 9.001);
}

if (defined $knxGA->{humidity}) {
	knx_write($knxGA->{humidity}, $data->{humidity}->{value}, 9.007);
}

if (defined $knxGA->{pressure}) {
	knx_write($knxGA->{pressure}, $data->{pressure}->{value}, 9.006);
}

if (defined $knxGA->{windSpeed}) {
	var $windSpeed = sprintf("%.1f", $data->{wind}->{speed}->{value} / 3.6);
	knx_write($knxGA->{windSpeed}, $windSpeed, 9.005);
}

if (defined $knxGA->{windDirection}) {
	knx_write($knxGA->{windDirection}, $data->{wind}->{direction}->{value}, 9.003);
}

if (defined $knxGA->{clouds}) {
	knx_write($knxGA->{clouds}, $data->{clouds}->{value}, 5.004);
}

if (defined $knxGA->{city}) {
        my $city = $data->{city}->{name};
        if (length($city) > 14) {
			$city = substr($city, 0, 14);
        }
	knx_write($knxGA->{city}, $city, 16.001);
}

my $ret = "Temperatur: " . $data->{temperature}->{value} . " °C";
$ret .= "; Luftfeuchtigkeit: " . $data->{humidity}->{value} . " %";
$ret .= "; Luftdruck: " . $data->{pressure}->{value} . " hPa";
$ret .= "; Windgeschwindigkeit: " . $data->{wind}->{speed}->{value} . " km/h";

return $ret;
