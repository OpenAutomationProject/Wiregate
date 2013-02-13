# YAMAHA RX-V773 Steuerung über Wiregate
# http://knx-user-forum.de/wiregate/25205-plugin-fuer-yamaha-reciever.html
# V2.0 12.02.2013 Release

# Die benötigten Gruppenadressen müssen im Wiregate eingetragen sein.

### Definitionen

# Verbindungseinstellungen
my $send_ip = 'xxx.xxx.xxx.xxx'; # IP des Receivers
my $send_port = '50000'; # TCP Port des Receivers (default 50000)

#######################################################################################################################
my %function=(
## YAMAHA Receiver (YNCA Commands), das "@" für jeden Befehl wird in der Sende Routine ergänzt.
# MAIN ZONE
# Name		GA		Command	0		Command 1		Description			DPT
#---------------------------------------------------------------------------------------------------------------------
"MAINPWR"=>	"1/1/1", 	#@MAIN:PWR=Standby	@MAIN:PWR=On		Main Power On/Off		1
"MAINVOL"=>	"1/1/2", 	#@MAIN:VOL=-xx.0 dB				Main Volume Parameter		6.010
"MAINVOLUD"=>	"1/1/3", 	#@MAIN:VOL=DOWN 2dB	@MAIN:VOL=UP 2 dB	Main Volume UP/DOWN		1
"MAINMUTE"=>	"1/1/4",	#@MAIN:MUTE=Off		@MAIN:MUTE=On		Main Volume MUTE		1
"MAINSRC"=>	"1/1/5",	#@MAIN:SRC=1,2,3,4,...				Main Source			5.010
"MAINSLEEP"=>	"1/1/6",	#@MAIN:SLEEP=Off	@MAIN:SLEEP=30		Main Power Sleep 30 Min		1

# ZONE 2
# Name		GA		Command	0		Command 1		Description			DPT
#---------------------------------------------------------------------------------------------------------------------
"ZONE2PWR"=>	"1/1/20", 	#@ZONE2:PWR=Standby	@ZONE2:PWR=On		ZONE2 Power On/Off		1
"ZONE2VOL"=>	"1/1/21", 	#@ZONE2:VOL=DOWN 2dB	@ZONE2:VOL=UP 2 dB	ZONE2 Volume UP/DOWN		1
"ZONE2MUTE"=>	"1/1/22", 	#@ZONE2:MUTE=Off	@ZONE2:MUTE=On		ZONE2 Volume MUTE		1
"MAINSRC"=>	"1/1/23",	#@MAIN:SRC=1,2,3,4,...				Main Source			5.010
"ZONE2SLEEP"=>	"1/1/24",	#@ZONE2:SLEEP=Off	@ZONE2:SLEEP=30		ZONE2 Power Sleep 30 Min	1

# GLOBAL
# Name		GA		Command	0		Command 1		Description			DPT
#---------------------------------------------------------------------------------------------------------------------
"TUNERPRESET"=>	"1/1/30",	#@TUN:PRESET=x					Main Radio Preset		5.010		
"NETRADIOPRE"=>	"1/1/31"	#@NETRADIO:PRESET=X				Net Radio Preset		5.010
);
#######################################################################################################################
### Ende Definitionen


# Eigenen Aufruf-Zyklus setzen
$plugin_info{$plugname.'_cycle'} = 0;

# Anmeldung an den oben eingetragenen Gruppenadressen
while (my($key,$ga) = each %function)
{
  $plugin_subscribe{$function{$key}}{$plugname} = 1;
}
#######################################################################################################################

### Verarbeitung
## MAIN ######################################################################################################
# Main Power ON/OFF
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{MAINPWR} && defined $msg{'value'}) {
    if ($msg{'value'} eq "0") {
	my $command = "MAIN:PWR=Standby";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "1") {
	my $command = "MAIN:PWR=On";
	my $return_val = sendCommand($command);
    }
    return 0;
}

# Main VOL UP/DOWN
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{MAINVOL} && defined $msg{'value'}) {
    my $command = "MAIN:VOL=".$msg{'value'}.".0";
    my $return_val = sendCommand($command);
    return 0;
}

# Main VOL UP/DOWN
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{MAINVOLUD} && defined $msg{'value'}) {
    if ($msg{'value'} eq "0") {
	my $command = "MAIN:VOL=Down 2 dB";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "1") {
	my $command = "MAIN:VOL=Up 2 dB";  
	my $return_val = sendCommand($command);
    }
    return 0;
}

# Main VOL MUTE
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{MAINMUTE} && defined $msg{'value'}) {
    if ($msg{'value'} eq "0") {
	my $command = "MAIN:MUTE=Off";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "1") {
	my $command = "MAIN:MUTE=On";
	my $return_val = sendCommand($command);
    }
    return 0;
}

# Main Source
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{MAINSRC} && defined $msg{'value'}) {
    if ($msg{'value'} eq "1") {
	my $command = "MAIN:INP=TUNER";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "2") {
	my $command = "MAIN:INP=NET RADIO";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "3") {
	my $command = "MAIN:INP=HDMI1";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "4") {
	my $command = "MAIN:INP=HDMI2";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "5") {
	my $command = "MAIN:INP=AUDIO1";
	my $return_val = sendCommand($command);
    }
    return 0;
}

# Main Sleep
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{MAINSLEEP} && defined $msg{'value'}) {
    if ($msg{'value'} eq "0") {
	my $command = "MAIN:SLEEP=Off";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "1") {
	my $command = "MAIN:SLEEP=30 min";
	my $return_val = sendCommand($command);
    }
    return 0;
}

## ZONE 2 ######################################################################################################
# Zone 2 Power ON/OFF
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{MAINPWR} && defined $msg{'value'}) {
    if ($msg{'value'} eq "0") {
	my $command = "ZONE2:PWR=Standby";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "1") {
	my $command = "ZONE2:PWR=On";
	my $return_val = sendCommand($command);
    }
    return 0;
}

# Zone 2 VOL UP/DOWN
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{MAINVOL} && defined $msg{'value'}) {
    my $command = "ZONE2:VOL=".$msg{'value'}.".0";
    my $return_val = sendCommand($command);
    return 0;
}

# Zone 2 VOL UP/DOWN
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{MAINVOLUD} && defined $msg{'value'}) {
    if ($msg{'value'} eq "0") {
	my $command = "ZONE2:VOL=Down 2 dB";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "1") {
	my $command = "ZONE2:VOL=Up 2 dB";  
	my $return_val = sendCommand($command);
    }
    return 0;
}

# Zone 2 VOL MUTE
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{MAINMUTE} && defined $msg{'value'}) {
    if ($msg{'value'} eq "0") {
	my $command = "ZONE2:MUTE=Off";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "1") {
	my $command = "ZONE2:MUTE=On";
	my $return_val = sendCommand($command);
    }
    return 0;
}

# Zone 2 Source
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{MAINSRC} && defined $msg{'value'}) {
    if ($msg{'value'} eq "1") {
	my $command = "ZONE2:INP=TUNER";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "2") {
	my $command = "ZONE2:INP=NET RADIO";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "3") {
	my $command = "ZONE2:INP=HDMI1";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "4") {
	my $command = "ZONE2:INP=HDMI2";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "5") {
	my $command = "ZONE2:INP=AUDIO1";
	my $return_val = sendCommand($command);
    }
    return 0;
}

# Zone2 Sleep
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{MAINSLEEP} && defined $msg{'value'}) {
    if ($msg{'value'} eq "0") {
	my $command = "ZONE2:SLEEP=Off";
	my $return_val = sendCommand($command);
    }
    elsif ($msg{'value'} eq "1") {
	my $command = "ZONE2:SLEEP=30 min";
	my $return_val = sendCommand($command);
    }
    return 0;
}

## GLOBAL ########################################################################################################
# Tuner
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{TUNERPRESET} && defined $msg{'value'}) {
    my $command = "TUN:PRESET=".$msg{'value'};
    my $return_val = sendCommand($command);
    return 0;
}

# NET Radio
elsif ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $function{NETRADIOPRE} && defined $msg{'value'}) {
    my $command = "NETRADIO:PRESET=".$msg{'value'};
    my $return_val = sendCommand($command);
    return 0;
}
#######################################################################################################################

# Sende Routine
sub sendCommand {
use IO::Socket;
my $cmd = $_[0];
my $sock = new IO::Socket::INET (
PeerAddr => $send_ip,
PeerPort => $send_port,
Proto => 'tcp',
);
die "Error: $!\n" unless $sock;
print $sock ("@".$cmd."\r"."\n") ;
plugin_log($plugname, $cmd);
close($sock);
}

