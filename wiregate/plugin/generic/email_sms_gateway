#Plugin zum versenden von Emails und SMS beim Empfang eines definierten Wertes auf einer definierten GA
#
#Mehrere Email und SMS Emfpänger sind möglich!
#Beispiel: email_adress => 'test@test.com, test1@test.com'
#          sms_number => '4917xxxxxx,4917xxxxxx'	
# - benoetigt Paket libnet-smtp-ssl-perl
# - benoetigt smstools mit eingerichtetem Device

#return "disabled!";

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
my $hostname = `hostname`;


##################
### DEFINITION ###
##################
my $Absender = 'Smarthome - Automatische Nachricht <test@test.com>'; # unbedingt anpassen, die Absenderadresse sollte gültig sein um Probleme zu vermeiden
my $username = 'test@test.com'; #Anpassen! Username fuer SMTP-Server
my $password = 'xxxx'; #Anpassen! Passwort fuer SMTP-Server
#my $mailserver='mail.gmx.net:465'; # SMTP-Relay mit SSL: das muss natuerlich angepasst werden!
my $mailserver='smtp.gmail.com:465'; # SMTP-Relay mit SSL: das muss natuerlich angepasst werden!


my @actionGA; #name: Einfacher Name, hat keine Funktion, email_adress: Empfänger-Adresse (wenn leer wird keine E-Mail versendet), email_subject: E-Mail Betreff, 
#email_text: Text der E-Mail, sms_number: SMS-Empfänger (wenn leer wird keine SMS gesendet), sms_text: Text der SMS, trigger_ga: GA auf die ragiert weird, value: Wert der GA auf den reagiert wird
push @actionGA, { name => 'Alarmanlage', email_adress => 'test@test.com, test1@test.com', email_subject => 'Alarmanlage', email_text => 'Alarmanlage hat um '. $hour .':'. $min .' ausgelöst.', sms_number => '4917xxxxxx,4917xxxxxx', sms_text => 'Alarmanlage hat um '. $hour .':'. $min .' ausgelöst.', trigger_ga => '8/2/0', value => 1 };

#######################
### ENDE DEFINITION ###
#######################
use Net::SMTP::SSL;
use MIME::Base64;

$plugin_info{$plugname.'_cycle'} = 3600;

foreach my $element (@actionGA) {
	my $email_adress = $element->{email_adress};
	my $email_subject = $element->{email_subject};
	my $email_text = $element->{email_text};
	my $sms_number = $element->{sms_number};
	my $sms_text = $element->{sms_text};
	my $trigger_ga = $element->{trigger_ga};
	my $value = $element->{value};

	$plugin_subscribe{$trigger_ga}{$plugname} = 1;

	if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $trigger_ga && defined $msg{'value'} && $msg{'value'} == "$value" ) {

		if(defined $sms_number ) {
			my @numberList = split(/,/, $sms_number);
			 
			foreach (@numberList){

 				my $file = "/var/spool/sms/outgoing/".$plugname."-".($year+1900)."-".$mon."-".$mday."-".$hour."-".$min."-".$sec."-".$_;
				my $mes_val = "To: ".$_."\n"."\n".$sms_text;			
				
				open (SMS,">$file") || die "Fehler $!";
				print SMS $mes_val;
				close SMS;
				#return "SMS an $_\ gesendet: $sms_text";	
			}		
		}
		
		
		if(defined $email_adress ) {
			my $smtp = Net::SMTP::SSL->new($mailserver, Timeout => 10) or return "Fehler beim verbinden zu $mailserver $!; $@";
			$smtp->auth($username,$password) or return "SASL Auth failed $!;$@"; # try SASL
			$smtp->status() < 5 or return "Auth failed: $!; $@ ". $smtp->status();
			$smtp->mail($Absender) or return "Absender $Absender abgelehnt $!";
			$smtp->to(split(',',$email_adress)) or return "Empfaenger $email_adress abgelehnt $!"; 
			$smtp->data() or return "Data failed $!";
			$smtp->datasend("To: $email_adress\n") or return "Empfanger $email_adress (Header-To) abgelehnt $!";
			$smtp->datasend("Subject: $email_subject\n") or return "Subject $email_subject abgelehnt $!";
			$smtp->datasend("\n") or return "Data failed $!";
			$smtp->datasend("$email_text\n") or return "Data failed $!";
			$smtp->dataend() or return "Data failed $!";
			$smtp->quit or return "Quit failed $!";
			#return "eMail von $Absender an $email_adress\ Betreff $email_subject gesendet: $email_text";		
		}
	}	
}
