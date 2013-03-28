#  email_triggered_by_ga.pl
# email triggert bei GA=1 wenn vorher GA=0
#Plugin zum versenden von Emails beim Empfang eines definierten Werts auf einer definierten GA
#Mehrere Mails an einer GA sind derzeit nicht möglich!
# - benoetigt Paket libnet-smtp-ssl-perl
# Aufbau moeglichst so, dass man unterhalb der Definitionen nichts aendern muss!

my ($sec,$min,$hour,$day,$month,$yr19,@rest) = localtime(time);
my $hostname = `hostname`;

##################
### DEFINITION ###
##################

my $Absender = 'WireGate <xxxx@gmail.com>'; # unbedingt anpassen, die Absenderadresse sollte gültig sein um Probleme zu vermeiden
my $username = 'xxxx@gmail.com'; #Anpassen! Username fuer SMTP-Server
my $password = 'xxxx'; #Anpassen! Passwort fuer SMTP-Server
my $mailserver='smtp.gmail.com:465'; # SMTP-Relay mit SSL: das muss natuerlich angepasst werden!
# my $mailserver='smtp.gmail.com:465'; # SMTP-Relay mit SSL: das muss natuerlich angepasst werden!

my $Msg = $plugin_info{'email.pl.Stoerung'}; # wird von einen anderen Plugin befuellt
#
$plugin_info{$plugname.'_cycle'} = 3600;

my @actionGA;
push @actionGA, { name => "Alarm", email_adress => 'xx1xx@googlemail.com', email_subject => "Test 1", email_text => "Alarm um $hour:$min ausgelöst.", trigger_ga => "2/1/1", value => 1 };
push @actionGA, { name => "test", email_adress => 'xx1xx@googlemail.com', email_subject => "WP Stoerung", email_text => "WP EHeizung EIN", trigger_ga => "1/3/73", value => 0 };
push @actionGA, { name => "test", email_adress => 'xx1xx@googlemail.com', email_subject => "WP Stoerung", email_text => "WP EHeizung AUS", trigger_ga => "1/3/73", value => 1 };
push @actionGA, { name => "test", email_adress => 'xx1xx@googlemail.com', email_subject => "PV Stoerung1", email_text => "PV Anlage gestoert: $Msg", trigger_ga => "5/0/24", value => 01 };
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

    if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $trigger_ga && defined $msg{'value'} && $msg{'value'} == "$value" && $plugin_info{$plugname."_".$trigger_ga} == 0) {        
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
       #
       $plugin_info{$plugname."_".$trigger_ga} = 1; # E-Mail wurde versandt,GA=1
       # return;    # keine Logausgabe
       return "eMail von $Absender an $email_adress\ Betreff $email_subject gesendet: $email_text";    
    }elsif($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $trigger_ga && defined $msg{'value'} && $msg{'value'} == 0){
       $plugin_info{$plugname."_".$trigger_ga} = 0; # GA=0
    }    
}

