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

my $smtp = Net::SMTP->new($mailserver, Timeout => 5, Debug =>1) or return "Fehler beim verbinden zu $mailserver $!";
my $ret .= ' auth:'. $smtp->auth($username,$password);
$smtp->status() < 5
or do {
        #        Die smtp->auth Methode schlaegt fehl, also dann so
        $smtp->datasend("AUTH LOGIN\n") or return 'auth login problem';
        $smtp->response();
        $smtp->datasend(encode_base64( $username ) ) or return "username $username cannot be encoded or wrong";
        $smtp->response();
        $smtp->datasend(encode_base64( $password ) ) or return "password $password cannot be encoded or wrong";
        $smtp->response();
};
$ret .= 'status:' . $smtp->status();
$ret .= ' send:'. $smtp->mail($Absender);
$ret .= ' rcpt:'. $smtp->to($Empfaenger); 
$ret .= $smtp->data();
$ret .= $smtp->datasend("To: $Empfaenger\n"); # EmpfÃ¤nger (Header)
$ret .= $smtp->datasend("Subject: $Betreff\n"); # Betreff
$ret .= $smtp->datasend("\n");
$ret .= $smtp->datasend("$text\n");
$ret .= $smtp->dataend();
$ret .= $smtp->quit;

# FIXME: check if we succeeded
return;		

