# Plugin zum versenden von Textmeldungen an XBMC
# Version 0.1 24.06.2011
# erstellt von JuMi2006 (http://knx-user-forum.de/members/JuMi2006.html)
# GPL 
# Erstellt mit Unterstützung des KNX-User-Forums

####################
###Einstellungen:###
####################


my $aufrufende_ga = "1/1/60"; #GA die die Benachrichtigung auslöst
my $xbmc_ip = "192.168.2.30"; #IP des XBMC Rechners
my $xbmc_port = "8080"; #Port des XBMC Webservers
my $user = "media"; #Username XMBC Webserver
my $pwd = "media"; #Password XBMC Webserver
my $text_head = "Licht"; #Überschrift für Benachrichtigung
my $text = "Jetzt wurde das Licht geschalten"; #Inhalt der Benachrichtigung
my $timeout = "5000"; #Zeit in Millisekunden in der die Meldung angezeigt wird
my $img = "http://icons.iconarchive.com/icons/deleket/sleek-xp-basic/256/Lamp-icon.png"; #Bildadresse für Benachrichtigung


######################
##ENDE Einstellungen##
######################

# Plugin an Gruppenadresse anmelden
$plugin_subscribe{$aufrufende_ga}{$plugname} = 1;

# Zusammensetzen der URL aus den Einstellungen
my $url= "http://".$user.":".$pwd."@".$xbmc_ip.":".$xbmc_port."/xbmcCmds/xbmcHttp?command=ExecBuiltIn(Notification(".$text_head.",".$text.",".$timeout.",".$img."))";

# Eigenen Aufruf-Zyklus auf 1 Tag setzen, das Script reagiert auf ankommende Telegramme
$plugin_info{$plugname.'_cycle'} = 86400; 

# Hier wird die Gruppenadresse abgefangen und weiterverarbeitet
if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $aufrufende_ga) {

# Mit Hilfe von LWP wird die entsprechende Website aufgerufen - Die Rückmeldung wird protokolliert.
use LWP::Simple;
my $requestURL = $url;
my $response = get($requestURL)
}