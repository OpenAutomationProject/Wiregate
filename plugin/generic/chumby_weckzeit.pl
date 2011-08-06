# Plugin zum auslesen der Weckzeit aus dem Chumby
# Version 0.4 BETA 06.08.2011
# Copyright: swiss (http://knx-user-forum.de/members/swiss.html)
# License: GPL (v2)
# Aufbau möglichst so, dass man unterhalb der Einstellungen nichts verändern muss!


####################
###Einstellungen:###
####################
my %weckzeit;

my $chumby_ip = "192.168.1.7"; #Hier die IP-Adresse des Chumby eintragen.

#
#Hier die beschreibung der Parameter:
#Nichtbenötigte Parameter einfach auf '' setzen. z.B. text_ga => ''
#
#
# $weckzeit{ '' } Hier muss der genaue Name der Weckzeit aus dem Chumby eingetragen werden
# text_zeit_ga => '10/1/0' Hier kann man eine GA eintragen um die Weckzeit als 14Byte-text an den BUS zu senden.
# text_wann_ga => '10/1/1' Hier kann man eine GA eintragen um die gültigkeit der Weckzeit (wann) als 14Byte-Text an den BUS zu senden.
# ga_aktiv => '10/1/1' ier kann man eine GA eintragen um den Status (inaktiv/aktiv) als 1Bit (0/1) an den BUS zu senden
#


#Pro Weckzeit die auf den BUS gesendet werden soll, muss ein entsprechender Eintrag angelegt werden. z.B $weckzeit_ga{ 'test' } = { text_ga => '10/2/0', ga_aktiv => '10/2/1', ga_alarm => '10/2/2', };
$weckzeit{ '' } = { text_zeit_ga => '10/1/0', text_wann_ga => '10/1/1', ga_aktiv => '10/1/2', };
$weckzeit{ 'test' } = { text_zeit_ga => '10/2/0', text_wann_ga => '10/2/1', ga_aktiv => '10/2/2', };
$weckzeit{ 'test_1' } = { text_zeit_ga => '10/3/0', text_wann_ga => '10/3/1', ga_aktiv => '10/3/2', };


######################
##ENDE Einstellungen##
######################

$plugin_info{$plugname.'_cycle'} = 30; 
# Zyklischer Aufruf nach restart und alle 30 sek.

use XML::Simple;
use LWP::Simple;
use Encode qw(encode decode);
# use open ":utf8";

my %uebersetzungstabelle = ("daily" => "Täglich",
		     "weekend" => "Wochenends",
		     "weekday" => "Mo - Fr",
		     "sunday" => "Sonntags",
		     "monday" => "Montags",
		     "tuesday" => "Dienstags",
		     "wednesday" => "Mittwochs",
		     "thursday" => "Donnerstags",
		     "friday" => "Freitags",
		     "saturday" => "Sammstags",);


my $command = "ping -c 2 -w 2 ".$chumby_ip;
my $status = `$command`;
if($status =~ /bytes from/) {
	my $url = "http://$chumby_ip/cgi-bin/custom/alarms.pl?page=download";
	my $xml = encode("utf8",get($url));
	die "Fehler beim aufrufen der URL: $url. Bitte mit Anleitung überprüfen." unless defined $xml;
	my $alarms = XMLin($xml)->{alarm};
	
	while ((my $key) = each %{$alarms}) {
		if (exists $weckzeit{$key}){
			if ($weckzeit{$key}{text_zeit_ga} ne ''){
				my $zeitdez = $alarms->{$key}->{time} / 60;
				my $minuten = $alarms->{$key}->{time} % 60;
				my $stunde = int $zeitdez;
				my $zeit = $stunde . ":" . $minuten;
				
				knx_write($weckzeit{$key}{text_zeit_ga},$zeit,16);
			}
			if ($weckzeit{$key}{text_wann_ga} ne ''){
				my $text_wann = $uebersetzungstabelle{$alarms->{$key}->{when}} . " um ";
				knx_write($weckzeit{$key}{text_wann_ga},$text_wann,16);
			}
			if ($weckzeit{$key}{ga_aktiv} ne ''){
				knx_write($weckzeit{$key}{ga_aktiv},$alarms->{$key}->{enabled},1.001);
			}
		}
	}
	return "Status OK";
}elsif($status =~ /0 received/) {
	return "Ein Fehler ist beim Testen der IP $chumby_ip aufgetreten";
}
