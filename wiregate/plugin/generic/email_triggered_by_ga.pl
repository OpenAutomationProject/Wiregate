#Plugin zum versenden von Emails beim Empfang eines definierten Werts auf einer definierten GA
#Mehrere Mails an einer GA sind derzeit nicht möglich!
# - benoetigt Paket libnet-smtp-ssl-perl
# Aufbau moeglichst so, dass man unterhalb der Definitionen nichts aendern muss!

my ($sec,$min,$hour,$day,$month,$yr19,@rest) = localtime(time);
my $hostname = `hostname`;

##################
### DEFINITION ###
##################

my $Absender = 'WireGate <example@googlemail.com>'; # unbedingt anpassen, die Absenderadresse sollte gültig sein um Probleme zu vermeiden
my $username = 'example@googlemail.com'; #Anpassen! Username fuer SMTP-Server
my $password = 'yourPW'; #Anpassen! Passwort fuer SMTP-Server
#my $mailserver='mail.gmx.net:465'; # SMTP-Relay mit SSL: das muss natuerlich angepasst werden!
my $mailserver='smtp.gmail.com:465'; # SMTP-Relay mit SSL: das muss natuerlich angepasst werden!

$plugin_info{$plugname.'_cycle'} = 3600;

my @actionGA;
push @actionGA, { name => "Alarmanlage", email_adress => 'email@t-d1-sms.de', email_subject => "Test 1", email_text => "Alarmanlage hat um $hour:$min ausgelöst.", trigger_ga => "12/1/0", value => 1 };
push @actionGA, { name => "test", email_adress => 'email@gmx.de', email_subject => "test2", email_text => "Test 2", trigger_ga => "1/1/1", value => 0 };
push @actionGA, { name => "test", email_adress => 'email@gmx.de', email_subject => "test3", email_text => "Test 3", trigger_ga => "1/1/2", value => 1 };

#######################
### ENDE DEFINITION ###
#######################

use Net::SMTP::SSL;
use MIME::Base64;

foreach my $element (@actionGA) {
	my $email_adress = $element->{email_adress};
	my $email_subject = $element->{email_subject};
	my $email_text = $element->{email_text};
	my $trigger_ga = $element->{trigger_ga};
	my $value = $element->{value};

	$plugin_subscribe{$trigger_ga}{$plugname} = 1;

	if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $trigger_ga && defined $msg{'value'} && $msg{'value'} == "$value" ) {		
	my $smtp = Net::SMTP::SSL->new($mailserver, Timeout => 10) or return "Fehler beim verbinden zu $mailserver $!; $@";
	$smtp->auth($username,$password) or return "SASL Auth failed $!;$@"; # try SASL
	$smtp->status() < 5 or return "Auth failed: $!; $@ ". $smtp->status();
	$smtp->mail($Absender) or return "Absender $Absender abgelehnt $!";
	$smtp->to($email_adress) or return "Empfaenger $email_adress abgelehnt $!"; 
	$smtp->data() or return "Data failed $!";
	$smtp->datasend("To: $email_adress\n") or return "Empfanger $email_adress (Header-To) abgelehnt $!";
	$smtp->datasend("Subject: $email_subject\n") or return "Subject $email_subject abgelehnt $!";
	$smtp->datasend("\n") or return "Data failed $!";
	$smtp->datasend("$email_text\n") or return "Data failed $!";
	$smtp->dataend() or return "Data failed $!";
	$smtp->quit or return "Quit failed $!";
	
	return;	# keine Logausgabe
	return "eMail von $Absender an $email_adress\ Betreff $email_subject gesendet: $email_text";	
	
	}	
}
