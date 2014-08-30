# ANPASSUNG an WUNDERGROUND based on
# Plugin zum Abfragen von Google Weather
# Version 0.6 2014-08-29
# Copyright: Bodo (http://knx-user-forum.de/members/bodo.html)
# License: GPL (v2)
# Aufbau möglichst so, dass man unterhalb der Definitionen nichts ändern muss!
OMPILE_PLUGIN

##################
### DEFINITION ###
##################

my $city                        = "xxxxxxx";                            # Meine Stadt, hier statt ü,ä,ö einfach u,a,o nehmen oder ue,ae,oe
my $country                     = "Germany";                            # Mein Land
my $lang                        = "DL";                                 # Meine Sprache
my $api                         = "xxxxxxxxxxxxxxx";                    # API, muss man sich bei Wunderground besorgen

my $wunderground_ip             = "http://api.wunderground.com/api/";
my $symbole                     = "/symbole/";                          # Pfad zu den Wettersymbolen
my $symbolebg                   = "/symbolebg/";                        # Pfad zu den Wetterhintergründen
my $htdocs                      = "/var/www/";                          # Das Webverzeichnis
my $wunderground_xml            = "wunderground_weather.xml";           # Der XML Datensatz
my $weather_div_html            = "wunderground_weather_div.html";      # Ausgabe als HTML mit DIV-Containern
my $wunderground_weather_css	= "wunderground_weather.css";           # Das Stylesheet fur die DIV-Variante

$plugin_info{$plugname.'_cycle'} = 1800;     # Eigenen Aufruf-Zyklus setzen (Initialisierung/zyklisches prüfen) 
                        # nicht zu klein, da die Daten sowieso in laengeren Perioden refresht werden
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
my $xml = get($url);
return "Couldn't get it!" unless defined $xml;

my $xml_w = ">".$htdocs.$wunderground_xml;
open(XML, $xml_w);    # XML Datei zum Schreiben öffnen
print XML $xml;
close(XML);

my $weather = XMLin($xml);

my $length = -4;
my $icontoday = substr ($weather->{current_observation}->{icon_url}, 28, $length);
my $location = substr ($weather->{current_observation}->{observation_time}, 5, $length);

###Version mit div ##############################################
my $htmldiv = 
"<!DOCTYPE HTML PUBLIC '-//W3C//DTD HTML 4.01 Transitional//EN'>
<html>
<head>
<title>Wetter</title>
<meta name='language' content='de'>
<meta http-equiv='content-type' content='text/html; charset=utf8'>
<meta http-equiv='refresh' content='". $plugin_info{$plugname.'_cycle'}/4 ."'>
<meta name='viewport' content='width=device-width,minimumscale=1.0,maximumscale=1.0'>
<link rel='stylesheet' type='text/css' href='".$wunderground_weather_css."'>
<link href='http://fonts.googleapis.com/css?family=Dosis:600' rel='stylesheet' type='text/css'>
<style type='text/css'>
</style>
</head>
<body style=\"background-image:url($symbolebg$icontoday.svg);background-repeat:no-repeat;
background-position:center center;
background-attachment:fixed;
-o-background-size: 100% 100%, auto;
-moz-background-size: 100% 100%, auto;
-webkit-background-size: 100% 100%, auto;
background-size: 100% 100%, auto;\">
<div class=\"wrapper\">\n".

"<div class=\"wetteraktuell\">".
"<h2>".$weather->{current_observation}->{temp_c}."&deg;</h2><br/>\n
<h3>Gef&uuml;hlt: ".$weather->{current_observation}->{feelslike_c}."° C<br/>\n".
"Bew&ouml;lkung: ".$weather->{current_observation}->{weather}."<br/>\n".
"Luftfeuchte: ".$weather->{current_observation}->{relative_humidity}."<br/>\n".
"Windrichtung: ".$weather->{current_observation}->{wind_dir}."<br/>\n".
"Windgeschwindigkeit: ".$weather->{current_observation}->{wind_kph}." km/h"."</h3><br/>\n".
"<nobr><h4>sunrise: ".$weather->{moon_phase}->{sunrise}->{hour}.":".$weather->{moon_phase}->{sunrise}->{minute}." Uhr
sunset: ".$weather->{moon_phase}->{sunset}->{hour}.":".$weather->{moon_phase}->{sunset}->{minute}." Uhr</h4></nobr>
<h3><br/>\n".$location."</h3><br/>\n".
"</div>\n".

"<div class=\"wetteraktuellbild\">
<img width=95% src=\"".$symbole.$icontoday."\.png\" alt=\"".
$weather->{current_observation}->{icon}."\" />".
"</div>\n".

"<div class=\"forecastcontainer\">";

for(my $j=0;$j<4;$j++) {
$htmldiv = $htmldiv."<div class=\"forecast\">".
"<strong>".$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{date}->{weekday}."</strong><br/>\n".
"<h3>".$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{conditions}."</h3><br/>\n
<h1><font color=\"FF8000\">".$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{high}->{celsius}." </font>\/".
$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{low}->{celsius}."° C</h1><br/>
<h3>Niederschlag ".$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{pop}."%<br/>\n".
"<img width=75% src=\"".$symbole.$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{icon}."\.png\" alt=\"".
$weather->{forecast}->{simpleforecast}->{forecastdays}->{forecastday}->[$j]->{conditions}."\" />\n".
"</div>\n";
}

$htmldiv = $htmldiv.
"<p class=\"back\"></p></div></body>";


my $htmldiv_datei = $htdocs.$weather_div_html;

open(HTML, ">:utf8", $htmldiv_datei);    # HTML Datei zum Schreiben öffnen
  print HTML $htmldiv;
close(HTML);

$weather = undef;
