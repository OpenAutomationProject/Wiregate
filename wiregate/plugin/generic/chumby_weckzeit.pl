# Plugin zum auslesen der Weckzeit aus dem Chumby
# Version 0.2 BETA 06.08.2011
# Copyright: swiss (http://knx-user-forum.de/members/swiss.html)
# License: GPL (v2)
# Aufbau möglichst so, dass man unterhalb der Einstellungen nichts verändern muss!


####################
###Einstellungen:###
####################

my $chumby_ip = "192.168.1.7"; #Hier die IP-Adresse des Chumby eintragen.


#Pro Weckzeit die als TEXT auf den BUS gesendet werden soll, muss ein entsprechender Eintrag angelegt werden. z.B ('test_1'    => '10/1/2',)
my %weckzeit_ga = ( 
    ''   => '10/1/0', #Hier den genauen Namen der Weckzeit und die GA eintragen (14Byte-Text)
    'test'    => '10/1/1',
    'test_1'    => '10/1/2',
    'test_2'     => '10/1/3',
    
    );


######################
##ENDE Einstellungen##
######################

$plugin_info{$plugname.'_cycle'} = 30; 
# Zyklischer Aufruf nach restart und alle 30 sek.

use XML::Simple;
use Encode qw(encode decode);
# use open ":utf8";

my $command = "ping -c 2 -w 2 ".$chumby_ip;
my $status = `$command`;
if($status =~ /bytes from/) {
	my $url = "http://$chumby_ip/cgi-bin/custom/alarms.pl?page=download";
	my $xml = encode("utf8",get($url));
	die "Fehler beim aufrufen der URL: $url. Bitte mit Anleitung überprüfen." unless defined $xml;
	my $alarms = XMLin($xml)->{alarm};
	
	while ((my $key) = each %{$alarms}) {
		my $zeitdez = $alarms->{$key}->{time} / 60;
		my $minuten = $alarms->{$key}->{time} % 60;
		my $stunde = int $zeitdez;
		my $zeit = $stunde . ":" . $minuten;
		knx_write($weckzeit_ga{$key},$zeit,16);
	}
	return "Status OK";
}elsif($status =~ /0 received/) {
	return "Ein Fehler ist beim Testen der IP $chumby_ip aufgetreten";
}