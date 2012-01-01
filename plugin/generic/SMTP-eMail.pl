# Demo-Plugin zum eMail-Versand - einfache Version mit Text-only
# das macht nichts sinnvolles, sendet jede Stunde ein eMail,
# soll nur als Vorlage dienen

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
my $password = "meinpasswort"; #Anpassen! Passwort fuer SMTP-Server
my $mailserver='mail.gmx.net'; # SMTP-Relay: das muss natuerlich angepasst werden!
$plugin_info{$plugname.'_cycle'} = 3600;

#######################
### ENDE DEFINITION ###
#######################

use Net::SMTP;
use MIME::Base64;

my $smtp = Net::SMTP->new($mailserver, Timeout => 20, Debug =>1) or return "Fehler beim verbinden zu $mailserver $!; $@";
$smtp->auth($username,$password);
$smtp->status() < 5
or do {
        #Die smtp->auth Methode schlaegt fehl, also dann so
        $smtp->datasend("AUTH LOGIN\n") or return 'auth login problem $!';
        $smtp->response();
        $smtp->datasend(encode_base64( $username ) ) or return "username $username cannot be encoded or wrong $!";
        $smtp->response();
        $smtp->datasend(encode_base64( $password ) ) or return "password $password cannot be encoded or wrong $!";
        $smtp->response();
};
$smtp->status() < 5 or return "Auth failed: $! ". $smtp->status();
$smtp->mail($Absender) or return "Absender $Absender abgelehnt $!";
$smtp->to($Empfaenger) or return "Empfaenger $Empfaenger abgelehnt $!"; 
$smtp->data() or return "Data failed $!";
$smtp->datasend("To: $Empfaenger\n") or return "Empfanger $Empfaenger (Header-To) abgelehnt $!";
$smtp->datasend("Subject: $Betreff\n") or return "Subject $Betreff abgelehnt $!";
$smtp->datasend("\n") or return "Data failed $!";
$smtp->datasend("$text\n") or return "Data failed $!";
$smtp->dataend() or return "Data failed $!";
$smtp->quit or return "Quit failed $!";

return;	# keine Logausgabe
return "eMail von $Absender an $Empfaenger Betreff $Betreff gesendet: $text";

