# Plugin zum Abfragen und Darstellen von
# WundergroundWeather von jensgulow
# based on
# Plugin zum Abfragen von Google Weather
# Version 0.5 2011-02-15
# Copyright: Bodo (http://knx-user-forum.de/members/bodo.html)
# License: GPL (v2)

##################
### DEFINITION ###
##################

my $city 						= "Leipzig";		# Meine Stadt, hier statt ü,ä,ö einfach u,a,o nehmen oder ue,ae,oe
my $country 					= "Germany";		# Mein Land
my $lang 						= "DL";				# Meine Sprache
my $api 						= "xxxxxxx";		# API, muss man sich bei Wunderground besorgen

my $wunderground_temp_ga							= "10/0/4";		# Gruppenadresse Temperatur (DPT9.001)
my $wunderground_hum_ga								= "10/0/5";		# Gruppenadresse Luftfeuchte (DPT9.007)
my $wunderground_forecast_maxtemp_ga 				= "10/0/6";		# Gruppenadresse Temperatur Maximum (DPT9.001)
my $wunderground_forecast_mintemp_ga 				= "10/0/7";		# Gruppenadresse Temperatur Minimum (DPT9.001)
my $wunderground_clouds_ga							= "10/0/8";		# Gruppenadresse Wolken (DPT16)
my $wunderground_forecast_clouds_ga					= "10/0/9";		# Gruppenadresse Vorhersage Wolken (DPT16)
my $wunderground_wind_ga							= "10/0/10";	# Gruppenadresse Wind (DPT16)

my $wunderground_ip									= "http://api.wunderground.com/api/";
my $symbole											= "/symbole/";						# Pfad zu den Wettersymbolen
my $symbolebg										= "/symbolebg/";					# Pfad zu den Wetterhintergründen
my $htdocs											= "/var/www/";						# Das Webverzeichnis
my $wunderground_xml								= "wunderground_weather.xml";		# Der XML Datensatz
my $weather_html									= "wunderground_weather.html";		# Ausgabe als HTML
my $wunderground_css								= "wunderground_weather.css";		# Das Stylesheet

$plugin_info{$plugname.'_cycle'} = 1800;	# Eigenen Aufruf-Zyklus setzen (Initialisierung/zyklisches prüfen) 
						# nicht zu klein, da die Daten sowieso in längeren Perioden refresht werden
						# und das Plugin auf die CF schreibt.

#######################
### ENDE DEFINITION ###
#######################

# Hauptverarbeitung
use LWP::Simple;
use XML::Simple;
use Data::Dumper;
use Encode qw(encode decode);
# use open ":utf8";

my $url = $wunderground_ip.$api."/conditions/forecast/astronomy/lang:".$lang."/q/".$country."\/".$city."\.xml";
#my $xml = encode("utf8",get($url));
my $xml = get($url);
die "Couldn't get it!" unless defined $xml;

my $xml_w = ">".$htdocs.$wunderground_xml;
open(XML, $xml_w);    # XML Datei zum Schreiben öffnen
print XML $xml;
close(XML);

my $weather = XMLin($xml);

my $wunderground_temp = $weather->{current_observation}->{temp_c};
$wunderground_temp =~ m/(\d{1,3})(\D)(\d{1,3})/; # ($1)($2)($3)
knx_write($wunderground_temp_ga,$1,9);

my $wunderground_hum = $weather->{current_observation}->{relative_humidity};
$wunderground_hum =~ m/(\d{1,3})(\D)/; # ($1)($2)
knx_write($wunderground_hum_ga,$1,9);

my $wunderground_forecast_maxtemp = $weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[0]->{high}->{celcius};
$wunderground_forecast_maxtemp =~ m/(\d{1,3})(\D)(\d{1,3})/; # ($1)($2)($3)
knx_write($wunderground_forecast_maxtemp_ga,$1,9);

my $wunderground_forecast_mintemp = $weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[0]->{low}->{celcius};
$wunderground_forecast_mintemp =~ m/(\d{1,3})(\D)(\d{1,3})/; # ($1)($2)($3)
knx_write($wunderground_forecast_mintemp_ga,$1,9);

my $wunderground_clouds = $weather->{current_observation}->{weather};
if ($wunderground_clouds =~ m/(\D*)(\s)(\D*)/) {  # \s findet Zwischenraum (whitspaces). ($1)($2)($3)
  knx_write($wunderground_clouds_ga,$1." ".$3,16);
} else {
  knx_write($wunderground_clouds_ga,$wunderground_clouds,16);
}

my $wunderground_forecast_clouds = $weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[0]->{conditions};
if ($wunderground_forecast_clouds =~ m/(\D*)(\s)(\D*)/) { # ($1)($2)($3)
  knx_write($wunderground_forecast_clouds_ga,$1." ".$3,16);
} else {
  knx_write($wunderground_forecast_clouds_ga,$wunderground_forecast_clouds,16);
}
my $wunderground_wind = $weather->{current_observation}->{wind_string};
if ($wunderground_wind =~ m/(\D*)(\s)(\D*)/) { # ($1)($2)($3)
knx_write($wunderground_wind_ga,$1." ".$3,"16");
} else {
  knx_write($wunderground_wind_ga,$wunderground_wind,16);
}

my $length = -4;
my $icontoday = substr ($weather->{current_observation}->{icon_url}, 31, $length);
my $location = substr ($weather->{current_observation}->{observation_time}, 5, $length);

my $html = 
"<!DOCTYPE HTML PUBLIC '-//W3C//DTD HTML 4.01 Transitional//EN'>
<html>
<head>
<title>Wetter</title>
<meta name='language' content='de'>
<meta http-equiv='content-type' content='text/html; charset=utf8'>
<link rel='stylesheet' type='text/css' href='".$wunderground_css."'>
<style type='text/css'>
<!--

table
{
	border: 1px;
	border-radius: 10px;
	-moz-border-radius: 10px;
  	-webkit-border-radius: 10px;
  	-o-border-radius: 10px;
	overflow: hidden;
}

td
{ 
  color: white;
  font-family: Dosis, Helvetica, Arial, sans-serif;
  font-size: 16px;
  text-shadow:black 3px 2px;
  border-radius: 10px;
	-moz-border-radius: 10px;
  	-webkit-border-radius: 10px;
  	-o-border-radius: 10px;
  overflow: hidden;
  padding: 10px;
  margin:0;
}

h1
{
  font-size: 1.4em;
  text-shadow:black 3px 2px;

}

h2
{
  font-size: 5.5em;
  color: #FFF799;
  text-shadow:black 4px 3px;
}

h3
{
  font-size: 0.8em;
}



=-->
</style>
</head>
<body>
<table background=\"".$symbolebg.$icontoday."\.png\">".

"<tr height=380px>\n".
"<td width=250px align=left>\n".
"<h2 align=center>".$weather->{current_observation}->{temp_c}."°</h2><h3><br/>\n".
"Gefühlt: ".$weather->{current_observation}->{feelslike_c}."° C<br/>\n".
"Bewölkung: ".$weather->{current_observation}->{weather}."<br/>\n".
"Luftfeuchte: ".$weather->{current_observation}->{relative_humidity}."<br/>\n".
"Niederschlag heute: ".$weather->{current_observation}->{precip_today_metric}." mm"."<br/>\n".
"Windrichtung: ".$weather->{current_observation}->{wind_dir}."<br/>\n".
"Windgeschwindigkeit: ".$weather->{current_observation}->{wind_kph}." km/h"."<br/>\n"."<br/>\n".
$location."</h3><br/>\n".
"</td>\n".
"<td>\n".
"<img width=250px height=250px src=\"".$symbole.$icontoday."\.png\" alt=\"".
$weather->{current_observation}->{icon}."\" /><br/>\n".
"</td>\n";

for(my $j=0;$j<4;$j++) {
$html = $html."<td align=center>\n".
"<strong>".$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{date}->{weekday}."</strong><br/>\n"."<h3>".
$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{conditions}."</h3><br/>\n<h1><font color=\"FFF799\">".
$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{high}->{celsius}."° C</font><br/>\n".
$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{low}->{celsius}."° C</h1><h3><br/>\n".
"Niederschlagsrisiko ".$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{pop}."%<br/>\n</h3>".
"<img width=150px height=150px src=\"".$symbole.$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{icon}."\.png\" alt=\"".
$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{conditions}."\" /><br/>\n".
"</td>\n";
}
$html = $html."</tr>
</table>
</body>";


my $html_datei = $htdocs.$weather_html;

open(HTML, ">:utf8", $html_datei);    # HTML Datei zum Schreiben öffnen
  print HTML $html;
close(HTML);