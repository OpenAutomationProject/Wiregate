# Demo-Plugin zum eMail-Versand - einfache Version mit Text-only
# das macht nichts sinnvolles, sendet jede Stunde ein eMail,
# soll nur als Vorlage dienen
# - mit SSL (alte Version ohne SSL sieh SVN rev 622)
# - benoetigt Paket libnet-smtp-ssl-perl libauthen-sasl-perl
# (Updates->Pakete installieren oder apt-get install ..)

# Aufbau moeglichst so, dass man unterhalb der Definitionen nichts aendern muss!

my $hostname = `hostname`;

##################
### DEFINITION ###
##################

my $Empfaenger = 'meine@domain.de'; # Anpassen, mehrere mit ,
my $Absender = 'WireGate <abc@gmx.de>'; # unbedingt anpassen, die Absenderadresse sollte gültig sein um Probleme zu vermeiden
my $Betreff = "eMail von $hostname";
my $text = "email-Body";
my $username = 'abc@gmx.de'; #Anpassen! Username fuer SMTP-Server
my $password = 'meinpasswort'; #Anpassen! Passwort fuer SMTP-Server
my $mailserver='mail.gmx.net:465'; # SMTP-Relay mit SSL: das muss natuerlich angepasst werden!
# oder z.B. smtp.gmail.com:465 fuer Gmail; 
$plugin_info{$plugname.'_cycle'} = 3600;

#######################
### ENDE DEFINITION ###
#######################

use Net::SMTP::SSL;
use MIME::Base64;

my $smtp = Net::SMTP::SSL->new($mailserver, Timeout => 10) or return "Fehler beim verbinden zu $mailserver $!; $@";
$smtp->auth($username,$password) or return "SASL Auth failed $!;$@"; # try SASL
$smtp->status() < 5 or return "Auth failed: $!; $@ ". $smtp->status();
$smtp->mail($Absender) or return "Absender $Absender abgelehnt $!";
$smtp->to(split(',',$Empfaenger)) or return "Empfaenger $Empfaenger abgelehnt: $!"; 
$smtp->data() or return "Data failed $!";
$smtp->datasend("To: $Empfaenger\n") or return "Empfanger $Empfaenger (Header-To) abgelehnt $!";
$smtp->datasend("Subject: $Betreff\n") or return "Subject $Betreff abgelehnt $!";
$smtp->datasend("\n") or return "Data failed $!";
$smtp->datasend("$text\n") or return "Data failed $!";
$smtp->dataend() or return "Data failed $!";
$smtp->quit or return "Quit failed $!";

return;	# keine Logausgabe
return "eMail von $Absender an $Empfaenger Betreff $Betreff gesendet: $text";

