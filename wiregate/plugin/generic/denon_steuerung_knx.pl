# Plugin zur Multimediasteuerung über einen 8fach Tastsensor oder eine Visu
# Version 0.3 09.07.2011 BETA
# Copyright: swiss (http://knx-user-forum.de/members/swiss.html)
# Die Vorlage für die Datenübertragung via socat stammt von makki (http://knx-user-forum.de/members/makki.html)
# Aufbau möglichst so, dass man unterhalb der Einstellungen nichts verändern muss!
#
#
#######################
### Wichtige Infos: ###
#######################
#
# Im WG ist eine Socketverbindung mit folgenden Parametern zu erstellen:
# Name: z.B. Denon
# Socket1: tcp-connect, Socket: IP_DES_DENON:23, Optionen: cr
# Socket2: udp-datagram, Socket: localhost:50105, Optionen: bind=localhost:50106,reuseaddr
#
#
# Damit die Steuerung des ON/OFF Tasters korrekt funktioniert, muss die GA die unter $ga_status_einaus angegeben wird auch als höhrende Adresse beim EIN/AUS Taster angegeben werden!
#
#

####################
###Einstellungen:###
####################


my $ga_einaus = '9/5/0'; #Hier die GA für EIN/AUS eintragen (0=AUS, 1=EIN)
my $ga_status_einaus = '9/5/30'; #Hier die Rückmelde-GA für die Statusled EIN/AUS eintragen (0=AUS, 1=EIN)

my $ga_lautstaerke = '9/5/4'; #Hier die GA für MAINZONE leiser/lauter eintragen (0=leiser, 1=lauter)
my $ga_main_lauter = '9/5/5'; #Hier die GA für MAINZONE lauter eintragen (0=NICHTS, 1=lauter)
my $ga_main_leiser = '9/5/6'; #Hier die GA für MAINZONE leiser eintragen (0=NICHTS, 1=leiser)

my $ga_status_mute = '9/5/8'; #Hier die Rückmelde-GA für die Statusled Stummschaltung eintragen (0=AUS, 1=EIN)

my $ga_status_lautstaerke = '9/5/9'; #Hier wird die aktuelle Lautstärke als 14byte TEXT zurückgegeben (z.B. -35.5)


my $ga_umschalttaste = '9/1/5'; #Hier wird die GA für die Umschalttaste eingetragen. Damit lassen sich die MEMORY-Tasten doppelt belegen.
my $ga_status_umschalttaste = '9/1/14'; #Hier wird die GA für die Rückmeldung der Umschalttaste eingetragen.

my $ga_kurzwahltaste1 = '9/1/6'; #Hier die GA für die MEMORY-Taste 1 eintragen (1=abrufen)
my $ga_status_kurzwahltaste1 = '9/1/10'; #Hier die GA für die Status LED der Taste 1 eintragen (1=EIN, 0=Aus)
my $quelle_kurzwahltaste1 = 'SAT';  #Hier kann die aufzurufende Quelle für die Grundbelegung eingetragen. z.B. SAT, DVD, TV, IRADIO (Internet Radio) oder TUNER angegeben werden
my $quelle_kurzwahltaste1u = 'NET'; #Hier kann die aufzurufende Quelle für die Zweitbelegung eingetragen. z.B. SAT, DVD, TV, IRADIO (Internet Radio) oder TUNER angegeben werden


my $ga_kurzwahltaste2 = '9/1/7'; #Hier die GA für die MEMORY-Taste 2 eintragen (1=abrufen)
my $ga_status_kurzwahltaste2 = '9/1/11'; #Hier die GA für die Status LED der Taste 2 eintragen (1=EIN, 0=Aus)
my $quelle_kurzwahltaste2 = 'TV';  #Hier kann die aufzurufende Quelle für die Grundbelegung eingetragen. z.B. SAT, DVD, TV, IRADIO (Internet Radio) oder TUNER angegeben werden
my $quelle_kurzwahltaste2u = 'IRADIO'; #Hier kann die aufzurufende Quelle für die Zweitbelegung eingetragen. z.B. SAT, DVD, TV, IRADIO (Internet Radio) oder TUNER angegeben werden


my $ga_kurzwahltaste3 = '9/1/8'; #Hier die GA für die MEMORY-Taste 3 eintragen (1=abrufen)
my $ga_status_kurzwahltaste3 = '9/1/12'; #Hier die GA für die Status LED der Taste 3 eintragen (1=EIN, 0=Aus)
my $quelle_kurzwahltaste3 = 'DVD';  #Hier kann die aufzurufende Quelle für die Grundbelegung eingetragen. z.B. SAT, DVD, TV, IRADIO (Internet Radio) oder TUNER angegeben werden
my $quelle_kurzwahltaste3u = 'DVR'; #Hier kann die aufzurufende Quelle für die Zweitbelegung eingetragen. z.B. SAT, DVD, TV, IRADIO (Internet Radio) oder TUNER angegeben werden


my $ga_kurzwahltaste4 = '9/1/9'; #Hier die GA für die MEMORY-Taste 4 eintragen (1=abrufen)
my $ga_status_kurzwahltaste4 = '9/1/13'; #Hier die GA für die Status LED der Taste 4 eintragen (1=EIN, 0=Aus)
my $quelle_kurzwahltaste4 = 'CD';  #Hier kann die aufzurufende Quelle für die Grundbelegung eingetragen. z.B. SAT, DVD, TV, IRADIO (Internet Radio) oder TUNER angegeben werden
my $quelle_kurzwahltaste4u = 'TUNER'; #Hier kann die aufzurufende Quelle für die Zweitbelegung eingetragen. z.B. SAT, DVD, TV, IRADIO (Internet Radio) oder TUNER angegeben werden


my $socknum = 118; # Eindeutige Nummer des Sockets +1


#Diese Einstellungen können normalerweise so belassen werden!
my $send_ip = "localhost"; # Sendeport (UDP, siehe in Socket-Einstellungen)
my $send_port = "50106"; # Sendeport (UDP, siehe in Socket-Einstellungen)
my $recv_ip = "localhost"; # Empfangsport (UDP, siehe in Socket-Einstellungen)
my $recv_port = "50105"; # Empfangsport (UDP, siehe in Socket-Einstellungen)


######################
##ENDE Einstellungen##
######################



use Time::HiRes qw(usleep nanosleep);

#Hier werden den Denon-befehle interne Namen zugewiesen
my %denon_befehle = ("PWOFF" => "PWSTANDBY",
		     "PWON" => "PWON",
		     "MVDOWN" => "MVDOWN",
		     "MVUP" => "MVUP",
		     "SAT" => "SISAT/CBL",
		     "DVD" => "SIDVD",
		     "TV" => "SITV",
		     "NET" => "SINET/USB",
		     "CD" => "SICD",
		     "TUNER" => "SITUNER",
		     "IRADIO" => "SIIRADIO",
		     "DVR" => "SIDVR");  


$plugin_info{$plugname.'_cycle'} = 600; 
# Zyklischer Aufruf nach restart und alle 600 sek.

if (!$socket[$socknum]) { # socket erstellen
        $socket[$socknum] = IO::Socket::INET->new(LocalPort => $recv_port,
                                  Proto => "udp",
                                  LocalAddr => $recv_ip,
                                  PeerPort  => $send_port,
                                  PeerAddr  => $send_ip,
                                  ReuseAddr => 1
                                   )
	or return ("open of $recv_ip : $recv_port failed: $!");

	$socksel->add($socket[$socknum]); # add socket to select

	$plugin_socket_subscribe{$socket[$socknum]} = $plugname; # subscribe plugin
	return "opened Socket $socknum";
} 

if ($msg{'apci'} eq "A_GroupValue_Write"){
	if ($msg{'dst'} eq $ga_einaus) {
		if (knx_read($msg{'dst'},0,1) == 1){
			my $return_value2 = command_senden('PWON');
		}elsif (knx_read($msg{'dst'},0,1) == 0){
			knx_write($ga_status_einaus,0,1);
			$plugin_info{$plugname.'_status_quelle'} = 0;
			my $return_value = rueckmeldung_led();
			my $return_value2 = command_senden('PWOFF');
		}
		return;
	} elsif ($msg{'dst'} eq $ga_main_lauter) {
		if (knx_read($msg{'dst'},0,1) == 1){
			do
			{
				my $return_value2 = command_senden('MVUP');
				usleep(150000);
			} until (knx_read($msg{'dst'},0,1) == 0);
			return;
		}
	} elsif ($msg{'dst'} eq $ga_main_leiser) {
		if (knx_read($msg{'dst'},0,1) == 1){
			do
			{
				my $return_value2 = command_senden('MVDOWN').'\r';
				usleep(150000);
			} until (knx_read($msg{'dst'},0,1) == 0);
			return;
		}
	} elsif ($msg{'dst'} eq $ga_lautstaerke) {
		if (knx_read($msg{'dst'},0,1) == 1){
			my $return_value2 = command_senden('MVUP');
		}elsif (knx_read($msg{'dst'},0,1) == 0){
			my $return_value2 = command_senden('MVDOWN');
		}
		return;
	} elsif ($msg{'dst'} eq $ga_umschalttaste) {
		if (knx_read($ga_status_einaus,0,1) == 1){ #Wenn der Verstärker eingeschaltet ist, dann reagiere auf Quellenwahl
			if (knx_read($msg{'dst'},0,1) == 1){
				knx_write($ga_status_umschalttaste,1,1);
				$plugin_info{$plugname.'_status_umschaltung'} = 1;
			}elsif (knx_read($msg{'dst'},0,1) == 0){
				knx_write($ga_status_umschalttaste,0,1);
				$plugin_info{$plugname.'_status_umschaltung'} = 0;
			}
		return;
		}
	} elsif ($msg{'dst'} eq $ga_kurzwahltaste1) {
		if (knx_read($ga_status_einaus,0,1) == 1){ #Wenn der Verstärker eingeschaltet ist, dann reagiere auf Quellenwahl
			if (knx_read($msg{'dst'},0,1) == 1){
				if ($plugin_info{$plugname.'_status_umschaltung'} == 0) {
					$plugin_info{$plugname.'_status_quelle'} = 1;
					my $return_value2 = command_senden($quelle_kurzwahltaste1);
					my $return_value = rueckmeldung_led();
					return;
				} elsif ($plugin_info{$plugname.'_status_umschaltung'} == 1){
					$plugin_info{$plugname.'_status_quelle'} = 5;
					my $return_value2 = command_senden($quelle_kurzwahltaste1u);
					my $return_value = rueckmeldung_led();
					return;
				}
			}
		}
	} elsif ($msg{'dst'} eq $ga_kurzwahltaste2) {
		if (knx_read($ga_status_einaus,0,1) == 1){ #Wenn der Verstärker eingeschaltet ist, dann reagiere auf Quellenwahl
			if (knx_read($msg{'dst'},0,1) == 1){
				if ($plugin_info{$plugname.'_status_umschaltung'} == 0) {
					$plugin_info{$plugname.'_status_quelle'} = 2;
					my $return_value2 = command_senden($quelle_kurzwahltaste2);
					my $return_value = rueckmeldung_led();
					return;
				} elsif ($plugin_info{$plugname.'_status_umschaltung'} == 1){
					$plugin_info{$plugname.'_status_quelle'} = 6;
					my $return_value2 = command_senden($quelle_kurzwahltaste2u);
					my $return_value = rueckmeldung_led();
					return;
				}
			}
		}
	} elsif ($msg{'dst'} eq $ga_kurzwahltaste3) {
		if (knx_read($ga_status_einaus,0,1) == 1){ #Wenn der Verstärker eingeschaltet ist, dann reagiere auf Quellenwahl
			if (knx_read($msg{'dst'},0,1) == 1){
				if ($plugin_info{$plugname.'_status_umschaltung'} == 0) {
					$plugin_info{$plugname.'_status_quelle'} = 3;
					my $return_value2 = command_senden($quelle_kurzwahltaste3);
					my $return_value = rueckmeldung_led();
					return;
				} elsif ($plugin_info{$plugname.'_status_umschaltung'} == 1){
					$plugin_info{$plugname.'_status_quelle'} = 7;
					my $return_value2 = command_senden($quelle_kurzwahltaste3u);
					my $return_value = rueckmeldung_led();
					return;
				}
			}
		}
	} elsif ($msg{'dst'} eq $ga_kurzwahltaste4) {
		if (knx_read($ga_status_einaus,0,1) == 1){ #Wenn der Verstärker eingeschaltet ist, dann reagiere auf Quellenwahl
			if (knx_read($msg{'dst'},0,1) == 1){
				if ($plugin_info{$plugname.'_status_umschaltung'} == 0) {
					$plugin_info{$plugname.'_status_quelle'} = 4;
					my $return_value2 = command_senden($quelle_kurzwahltaste4);
					my $return_value = rueckmeldung_led();
					return;
				} elsif ($plugin_info{$plugname.'_status_umschaltung'} == 1){
					$plugin_info{$plugname.'_status_quelle'} = 8;
					my $return_value2 = command_senden($quelle_kurzwahltaste4u);
					my $return_value = rueckmeldung_led();
					return;
				}
			}
		}
	}
} elsif ($fh) { # Wenn der Denon ein Antworttelegramm sendet, wird ab hier der entsprechende Status ausgelesen.
	my $buf = <$fh>;
	my $bufhex = unpack("H*",$buf);
	chomp $buf;
	my $fn = substr($buf,0,2);
	my $fp = substr($buf,0,4);

	if ($fp eq "PWON") {
		knx_write($ga_status_einaus,1,1);
		syswrite($socket[$socknum],"SI?\r");
		return;
	} elsif ($fp eq "PWST") {
		knx_write($ga_status_einaus,0,1);
		$plugin_info{$plugname.'_status_quelle'} = 0;
		my $return_value = rueckmeldung_led();
		return;
	} elsif ($fp eq "MUON") {
		knx_write($ga_status_mute,1,1);
		return;
	} elsif ($fp eq "MUOF") {
		knx_write($ga_status_mute,0,1);
		return;
	} elsif ($fn eq "SI") {
		if (knx_read($ga_status_einaus,0,1) == 0){
			$plugin_info{$plugname.'_status_quelle'} = 0;
			
		} else {
			SELECT:{
			if ($buf eq $denon_befehle{$quelle_kurzwahltaste1}){ $plugin_info{$plugname.'_status_quelle'} = 1; last SELECT; }
			if ($buf eq $denon_befehle{$quelle_kurzwahltaste2}){ $plugin_info{$plugname.'_status_quelle'} = 2; last SELECT; }
			if ($buf eq $denon_befehle{$quelle_kurzwahltaste3}){ $plugin_info{$plugname.'_status_quelle'} = 3; last SELECT; }
			if ($buf eq $denon_befehle{$quelle_kurzwahltaste4}){ $plugin_info{$plugname.'_status_quelle'} = 4; last SELECT; }
			if ($buf eq $denon_befehle{$quelle_kurzwahltaste1u}){ $plugin_info{$plugname.'_status_quelle'} = 5; last SELECT; }
			if ($buf eq $denon_befehle{$quelle_kurzwahltaste2u}){ $plugin_info{$plugname.'_status_quelle'} = 6; last SELECT; }
			if ($buf eq $denon_befehle{$quelle_kurzwahltaste3u}){ $plugin_info{$plugname.'_status_quelle'} = 7; last SELECT; }
			if ($buf eq $denon_befehle{$quelle_kurzwahltaste4u}){ $plugin_info{$plugname.'_status_quelle'} = 8; last SELECT; }
			}
		}
		my $return_value = rueckmeldung_led();
		return;
	} elsif ($fn eq "MV" and $buf !~ /^MVMAX/) { # MVMAX is undocumented?
		# Hier wird die aktuelle Lautstärke aus der Rückmeldung berechnet
		$plugin_info{$plugname.'_debug_mv'} = $buf;
		my $laenge = length($buf);
		my $wert;
		
		if ($laenge == 4){
			$wert = substr($buf,2,2);
			$wert = $wert."0";	
		}elsif ($laenge == 5){
			$wert = substr($buf,2,3);	
		}
		
		if ($wert ne ""){
			if ($wert <= 800){
				$wert = 800 - $wert;
				$wert = "-".substr($wert,0,2).".".substr($wert,2,1);
			} elsif ($wert == 995){
				$wert = "-80.5";
			} else {
				$wert = "---.-";
			}
			knx_write($ga_status_lautstaerke,$wert,16); #Hier funktioniert etwas noch nicht ganz!
			$plugin_info{$plugname.'_mv_vol'} = $wert;
		}
		return;
	} else {
	        return;
	}
} else { # zyklischer Aufruf
   # Plugin an Gruppenadresse "anmelden", hierdurch wird das Plugin im folgenden bei jedem eintreffen eines Telegramms auf die GA aufgerufen und der obere Teil dieser if-Schleife durchlaufen
   $plugin_subscribe{$ga_einaus}{$plugname} = 1;
   $plugin_subscribe{$ga_lautstaerke}{$plugname} = 1;
   $plugin_subscribe{$ga_main_lauter}{$plugname} = 1;
   $plugin_subscribe{$ga_main_leiser}{$plugname} = 1;
   $plugin_subscribe{$ga_umschalttaste}{$plugname} = 1;
   $plugin_subscribe{$ga_kurzwahltaste1}{$plugname} = 1;
   $plugin_subscribe{$ga_kurzwahltaste2}{$plugname} = 1;
   $plugin_subscribe{$ga_kurzwahltaste3}{$plugname} = 1;
   $plugin_subscribe{$ga_kurzwahltaste4}{$plugname} = 1;
}

# Hier werden diverse Zustände des Denon zyklisch abgefragt um den aktuellen Status auch anzeigen zu können, wenn etwas über z.B. die FB verändert wird:
syswrite($socket[$socknum],"PW?\r");
syswrite($socket[$socknum],"MU?\r");
syswrite($socket[$socknum],"SI?\r");
return;

#Hier werden die Status LED's der Quellenwahltasten angesteuert
sub rueckmeldung_led{
	SELECT:{
	if ($plugin_info{$plugname.'_status_quelle'} == 0){ knx_write($ga_status_umschalttaste,0,1); knx_write($ga_status_kurzwahltaste1,0,1); knx_write($ga_status_kurzwahltaste2,0,1); knx_write($ga_status_kurzwahltaste3,0,1); knx_write($ga_status_kurzwahltaste4,0,1); last SELECT; }
	if ($plugin_info{$plugname.'_status_quelle'} == 1){ knx_write($ga_status_umschalttaste,0,1); knx_write($ga_status_kurzwahltaste1,1,1); knx_write($ga_status_kurzwahltaste2,0,1); knx_write($ga_status_kurzwahltaste3,0,1); knx_write($ga_status_kurzwahltaste4,0,1); last SELECT; }
	if ($plugin_info{$plugname.'_status_quelle'} == 2){ knx_write($ga_status_umschalttaste,0,1); knx_write($ga_status_kurzwahltaste1,0,1); knx_write($ga_status_kurzwahltaste2,1,1); knx_write($ga_status_kurzwahltaste3,0,1); knx_write($ga_status_kurzwahltaste4,0,1); last SELECT; }
	if ($plugin_info{$plugname.'_status_quelle'} == 3){ knx_write($ga_status_umschalttaste,0,1); knx_write($ga_status_kurzwahltaste1,0,1); knx_write($ga_status_kurzwahltaste2,0,1); knx_write($ga_status_kurzwahltaste3,1,1); knx_write($ga_status_kurzwahltaste4,0,1); last SELECT; }
	if ($plugin_info{$plugname.'_status_quelle'} == 4){ knx_write($ga_status_umschalttaste,0,1); knx_write($ga_status_kurzwahltaste1,0,1); knx_write($ga_status_kurzwahltaste2,0,1); knx_write($ga_status_kurzwahltaste3,0,1); knx_write($ga_status_kurzwahltaste4,1,1); last SELECT; }
	if ($plugin_info{$plugname.'_status_quelle'} == 5){ knx_write($ga_status_umschalttaste,1,1); knx_write($ga_status_kurzwahltaste1,1,1); knx_write($ga_status_kurzwahltaste2,0,1); knx_write($ga_status_kurzwahltaste3,0,1); knx_write($ga_status_kurzwahltaste4,0,1); last SELECT; }
	if ($plugin_info{$plugname.'_status_quelle'} == 6){ knx_write($ga_status_umschalttaste,1,1); knx_write($ga_status_kurzwahltaste1,0,1); knx_write($ga_status_kurzwahltaste2,1,1); knx_write($ga_status_kurzwahltaste3,0,1); knx_write($ga_status_kurzwahltaste4,0,1); last SELECT; }
	if ($plugin_info{$plugname.'_status_quelle'} == 7){ knx_write($ga_status_umschalttaste,1,1); knx_write($ga_status_kurzwahltaste1,0,1); knx_write($ga_status_kurzwahltaste2,0,1); knx_write($ga_status_kurzwahltaste3,1,1); knx_write($ga_status_kurzwahltaste4,0,1); last SELECT; }
	if ($plugin_info{$plugname.'_status_quelle'} == 8){ knx_write($ga_status_umschalttaste,1,1); knx_write($ga_status_kurzwahltaste1,0,1); knx_write($ga_status_kurzwahltaste2,0,1); knx_write($ga_status_kurzwahltaste3,0,1); knx_write($ga_status_kurzwahltaste4,1,1); last SELECT; }
	}
}


sub command_senden{
	my $befehl = $_[0];
	my $command = $denon_befehle{$befehl}."\r";
	$plugin_info{$plugname.'_debug'} = $command;
	syswrite($socket[$socknum], $command);
}