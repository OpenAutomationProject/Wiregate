######################################################################################
#
# Plugin OpenWeatherMapUpload
# Copyright: krumboeck (http://knx-user-forum.de/members/krumboeck.html) 
# License: GPL (v2)
# V0.3 2013-08-24
#
# Ein Wiregate Plugin zum Upload von Wetterdaten für openweathermap.org
# Folgende Funktionen werden unterstützt:
# - Zeitliches Aussetzen wegen Messfehler (z.B.: Sonne scheint auf Tempfühler, etc.)
# - Außentemperatur
#
# TODO:
# - Andere Wetterdaten
#
######################################################################################


#################
### Konfiguration
#################

# Festlegen, dass das Plugin alle 10 Minuten laufen soll
$plugin_info{$plugname.'_cycle'} = 600;


#################################
### Lesen der Konfigurationsdatei
#################################

my ($user, $pass, $name, $lat, $lon, $alt, $GAtemp);
my @TimeExclusions;

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

use LWP::UserAgent;
use HTTP::Request;
use URI::Escape;


######################
### Prüfen von Sperren
######################

my ($Sekunden, $Minuten, $Stunden, $Tag, $Monat, $Jahr, $Wochentag, $Jahrestag, $Sommerzeit) = localtime(time);

$Stunden = ($Stunden < 10) ? "0" . $Stunden : $Stunden;
$Minuten = ($Minuten < 10) ? "0" . $Minuten : $Minuten;

my $currentTime = $Stunden . $Minuten;
print $currentTime;

foreach my $exclusion (@TimeExclusions) {
	my $from = $exclusion->{from};
        $from =~ s/://;
	my $until = $exclusion->{until};
        $until =~ s/://;
	print $from;
	print $until;
        if ($from <= $until) {
		if (($from <= $currentTime) && ($until >= $currentTime)) {
			return "Übertragung ist derzeit gesperrt";
		}
	} else {
		if (($from <= $currentTime) && (2359 >= $currentTime)) {
			return "Übertragung ist derzeit gesperrt";
		}
		if ((0 <= $currentTime) && ($until >= $currentTime)) {
			return "Übertragung ist derzeit gesperrt";
		}
	}
}


#########################
### Wetterdaten ermitteln
#########################

my $ret = "";
my %post_data;
$post_data{name} = $name;
$post_data{lat} = $lat;
$post_data{long} = $lon;
$post_data{alt} = $alt;

if ((defined $GAtemp) && (length($GAtemp) >= 5)) {
	my $temp = knx_read($GAtemp, 300, 9.001);
	if (defined $temp) {
		$post_data{temp} = $temp;
		$ret .= "Temperatur: " . $temp . "; ";
	} else {
		$ret .= "Temperatur: N/A" . "; ";
	}
}


########################
### Übertragen der Daten
########################

my $encoded_data = "";
while ( my ($key, $value) = each(%post_data) ) {
	$encoded_data .= $key . "=" . uri_escape($value) . "&";
}
$encoded_data =~ s/&$//;

my $ua = new LWP::UserAgent;
my $request = new HTTP::Request(POST => 'http://openweathermap.org/data/post');
$request->authorization_basic($user, $pass);
$request->header('Content-Type' => 'application/x-www-form-urlencoded');
$request->content($encoded_data);
my $response = $ua->request($request);

if ($response->is_success) {
        $ret =~ s/; $//;
	return $ret;
} else {
	return "Upload Fehler: " . $response->status_line;
}

