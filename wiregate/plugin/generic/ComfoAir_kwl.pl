# Plugin zur Ansteuerung einer Zender ComfoAir
# Version 1.3 22.06.2012 BETA
# Copyright: swiss (http://knx-user-forum.de/members/swiss.html)
# Aufbau möglichst so, dass man unterhalb der Einstellungen nichts verändern muss!
#
#

####################
###Einstellungen:###
####################

#Zuordnung Steuerfunktionen zu den Gruppenadressen:
my $ga_stufeabwesend = '14/7/0'; #1bit Trigger für Stufe "Abwesend". 1=Aktivieren
my $ga_stufe1 = '14/7/1'; #1bit Trigger für Stufe1. 1=Aktivieren
my $ga_stufe2 = '14/7/2'; #1bit Trigger für Stufe2. 1=Aktivieren
my $ga_stufe3 = '14/7/3'; #1bit Trigger für Stufe3. 1=Aktivieren
my $ga_komforttemp = '4/4/7'; #GA DPT 9.001 zum setzen der Komforttemperatur
my $ga_reset_filter = '14/7/5'; #1bit Trigger für das Zurücksetzen des Betriebsstundenzählers des Filters. 1=Reset
my $ga_reset_error = '14/7/6'; #1bit Trigger für das zurücksetzen der KWL nach einem Fehler. 1=Reset

#Hier werden die Gruppenadressen für die Rückmeldungen vergeben: (Nich vergeben = inaktiv)
my $ga_status_ventilator_zul = '14/4/3'; #GA DPT5.001 für Status Ventilator Zuluft %
my $ga_status_ventilator_abl = '14/4/4'; #GA DPT5.001 für Status Ventilator Abluft %
my $ga_status_bypass_prozent = '14/4/5'; #GA DPT5.001 für Status Bypassklappe %
my $ga_betriebsstunden_filter = '14/4/6'; #GA DPT16.000 für die Rückmeldung der Betribsstunden des Filters
my $ga_zustand_badschalter = ''; #GA DPT1.001 für die Rückmeldung des Zustandes des Badezimmerschalters
my $ga_fehler_filter = '14/0/5'; #GA DPT 1.001 für den Zustand des Filters. 0=OK, 1=Filter Voll
my $ga_fehlercode = '14/0/6'; #GA DPT 16.000 für das augeben des Fehlercodes als Text

#Zuordnung der Namen für die RRD's:
my $Name_rrd_AUL = 'KWL_Aussenluft'; #Name RRD Aussenluft
my $Name_rrd_ZUL = 'KWL_Zuluft'; #Name RRD Zuluft
my $Name_rrd_ABL = 'KWL_Abluft'; #Name RRD Abluft
my $Name_rrd_FOL = 'KWL_Fortluft'; #Name RRD Fortluft

#Pfad zur seriellen Schnittstelle oder dem USB-Seriell-Wandler:
my $schnittstelle = '/dev/ttyUSB-1-1';

######################
##ENDE Einstellungen##
######################

#Ab hier nichts mehr ändern.
#Hauptverarbeitung

use Device::SerialPort;

my $return_value2;
my $daten;
my $reciv;
my $reciv_all;
my $ack = pack("H*","07F3");


# Zyklischer Aufruf nach restart, empfang GA oder nach einstellung rrd (typisch 300sek).
$plugin_info{$plugname.'_cycle'}  = 25; 

#Einrichten der Seriellen Schnittstelle für die Kommunikation mit dem ComfoAir
my $seriel = Device::SerialPort->new($schnittstelle) || die "Kann $schnittstelle nicht öffnen! ($!)\n";
$seriel->baudrate(9600);
$seriel->parity("none");
$seriel->databits(8);
$seriel->stopbits(1);

#plugin_log($plugname,''); 

if ($msg{'apci'} eq "A_GroupValue_Write"){ #Wenn ein Telegramm vom KNX empfangen wird, ab hier auswerten
    if ($msg{'dst'} eq $ga_stufeabwesend && knx_read($msg{'dst'},0,1) == 1) {
        $daten = "00990101";
        plugin_log($plugname,'Stufe abwesend');
        $return_value2 = command_senden($daten);
    }elsif ($msg{'dst'} eq $ga_stufe1 && knx_read($msg{'dst'},0,1) == 1) {
        $daten = "00990102";
        plugin_log($plugname,'Stufe 1');
        $return_value2 = command_senden($daten);
    }elsif ($msg{'dst'} eq $ga_stufe2 && knx_read($msg{'dst'},0,1) == 1) {
        $daten = "00990103";
        plugin_log($plugname,'Stufe 2');
        $return_value2 = command_senden($daten);
    }elsif ($msg{'dst'} eq $ga_stufe3 && knx_read($msg{'dst'},0,1) == 1) {
        $daten = "00990104";
        plugin_log($plugname,'Stufe 3');
        $return_value2 = command_senden($daten);
    }elsif ($msg{'dst'} eq $ga_komforttemp) {
    	my $komforttemp = knx_read($msg{'dst'},0,9.001);
        plugin_log($plugname,'Komforttemp    : ' . $komforttemp . '°C');
        my $temphex = ($komforttemp + 20)*2; #Rechne die Temperatur für die ComfoAir um
        $temphex = sprintf "%x" , $temphex; # Mache aus Integer HEX
        $daten = "00D301" . $temphex;
        $return_value2 = command_senden($daten);
    }elsif ($msg{'dst'} eq $ga_reset_filter && knx_read($msg{'dst'},0,1) == 1) {
        $daten = "00DB0400000001";
        plugin_log($plugname,'Filter zurücksetzen');
        $return_value2 = command_senden($daten);
    }elsif ($msg{'dst'} eq $ga_reset_error && knx_read($msg{'dst'},0,1) == 1) {
        $daten = "00DB0401000000";
        plugin_log($plugname,'Fehler zurücksetzen');
        $return_value2 = command_senden($daten);
    }
    return;
} else { # zyklischer Aufruf

    # Plugin an Gruppenadresse "anmelden", hierdurch wird das Plugin im folgenden bei jedem eintreffen eines Telegramms auf die GA aufgerufen und der obere Teil dieser if-Schleife durchlaufen
    $plugin_subscribe{$ga_stufeabwesend}{$plugname} = 1;
    $plugin_subscribe{$ga_stufe1}{$plugname} = 1;
    $plugin_subscribe{$ga_stufe2}{$plugname} = 1;
    $plugin_subscribe{$ga_stufe3}{$plugname} = 1;
    $plugin_subscribe{$ga_komforttemp}{$plugname} = 1;
    $plugin_subscribe{$ga_reset_filter}{$plugname} = 1;
    $plugin_subscribe{$ga_reset_error}{$plugname} = 1;
    
    $daten = "00D100";
    plugin_log($plugname,'Temperatur abrufen');
    $return_value2 = command_senden($daten);
    
    if($ga_status_ventilator_zul && $ga_status_ventilator_abl){ #Nur wenn beide GA's vergeben sind, dann die Zustände der Ventilatoren abfragen
        $daten = "000B00";
        plugin_log($plugname,'Ventilator Status abrufen');
        $return_value2 = command_senden($daten);
    }
    if($ga_status_bypass_prozent){ #Nur wenn die GA vergeben ist, dann Zustand Bypassklappe abfragen
        $daten = "000D00";
        plugin_log($plugname,'Bypass Zustand abrufen');
        $return_value2 = command_senden($daten);
    }
    if($ga_betriebsstunden_filter){ #Nur wenn die GA vergeben ist, die Betriebsstunden abfragen
        $daten = "00DD00";
        plugin_log($plugname,'Betriebsstunden abrufen');
        $return_value2 = command_senden($daten);
    }
    if($ga_zustand_badschalter){ #Nur wenn die GA vergeben ist, die Binäreingänge abfragen
        $daten = "000300";
        plugin_log($plugname,'Binäreingänge abrufen');
        $return_value2 = command_senden($daten);
    }

    #Hier werden die Störmeldungen abgefragt
    $daten = "00D900";
    plugin_log($plugname,'Störungen abrufen');
    $return_value2 = command_senden($daten);
    
    return;
}

# Ab hier wird das Datenpaket inklusive Checksumme zusammengestellt und an die ComfoAir übertragen
sub command_senden{
    my $checksum = 0;
    my $data = $_[0];
    
    my $datasum = $data . "AD"; #+173 für die Checksummenberechnung
    my @hex  = map { hex($_) } ($datasum =~ /(..)/g);
    
    
    my $x07warschon = 0;
    
    foreach (@hex) {
        $checksum += ($_) unless $x07warschon; # unless ist dasselbe wie if not/!
        if ($_ == 0x07) { $x07warschon = 1; }
    }

    $checksum = sprintf "%x\n" , $checksum; #Mache aus Integer wieder HEX
    $checksum = substr($checksum,-3,2); #Verwede nur die letzten beiden Stellen
    my $command = pack("H*","07F0" . $data . $checksum . "070F");
    my $commandhex = $command;
    
    $commandhex =~ s/(.)/sprintf("0x%x ",ord($1))/eg;
    #plugin_log($plugname,'transmit       : ' . $commandhex); #Zeigt im Pluginlog das fertige Datenpaket, dass übertragen wird
    $seriel->write($command); #Befehl an die ComfoAir senden
    $reciv = '';
        
    $|=1;
    my $exit=0;
    while($exit < 25000)
    {
        my ($cin, $sin) = $seriel->read(45);
        if($cin > 0){
		$sin = unpack "H*", $sin;
		$reciv .= $sin;
		$exit=0;
	}else{
		$exit++
	}

	if($reciv =~ /070f/i){           
           $seriel->write($ack); #ACK senden
            last;
	}
    }    


        my $test = substr($reciv,0,4);
        if($test eq '07f3'){
            $reciv = substr($reciv,4); #falls noch ein 07f3 enthalten ist, wir dieses hier entfernt.
            #plugin_log($plugname,'reciv neu      : ' . $reciv);
        }

	my $laenge = length($reciv); #Länge des Antworttelegramms ermitteln

	if($reciv =~ /07f000D209/i and $laenge == 34){ #Wenn die Temperaturen empfangen wurden und die Länge passt
		
		my $t1 = substr($reciv,12,2);
                my $t2 = substr($reciv,14,2);
                my $t3 = substr($reciv,16,2);
                my $t4 = substr($reciv,18,2);
                
                #Hier werden die Temperaturen "decodiert" damit sie einen Sinn ergeben
                $t1 =  (hex($t1)/2)-20;
                $t2 =  (hex($t2)/2)-20;
                $t3 =  (hex($t3)/2)-20;
                $t4 =  (hex($t4)/2)-20;
                
                #Ab hier werden die RRD's mit den aktuellen Temperaturen aktualisiert:
                update_rrd($Name_rrd_AUL,"",$t1);
                update_rrd($Name_rrd_ZUL,"",$t2);
                update_rrd($Name_rrd_ABL,"",$t3);
                update_rrd($Name_rrd_FOL,"",$t4);
                
                plugin_log($plugname,'AUL: ' . $t1 . '°C, ZUL:' . $t2 . '°C, ABL: ' . $t3 . '°C, FOL: ' . $t4 . '°C');

	}elsif($reciv =~ /07f0000C06/i and $laenge == 28){ #Wenn der Status für die Ventilatoren empfangen wurden
                my $vent_zul = substr($reciv,10,2);
                my $vent_abl = substr($reciv,12,2);
                plugin_log($plugname,'ZUL: ' . hex($vent_zul) . '% ABL: ' . hex($vent_abl) . '%');
                knx_write($ga_status_ventilator_zul,hex($vent_zul),5.001);
                knx_write($ga_status_ventilator_abl,hex($vent_abl),5.001);    
	}elsif($reciv =~ /07f0000E04/i and $laenge == 24){ #Wenn der Status für die Bypassklappe empfangen wurden
                my $bypass_prozent = substr($reciv,10,2);
                plugin_log($plugname,'Bypass: ' . hex($bypass_prozent) . '%');                
                knx_write($ga_status_bypass_prozent,hex($bypass_prozent),5.001);
	}elsif($reciv =~ /07f000DE14/i and $laenge == 56){ #Wenn die Rückmeldung der Betriebsstunden empfangen wurden
                my $betriebsstunden_filter = substr($reciv,40,4);
                plugin_log($plugname,'Betriebsstunden: ' . hex($betriebsstunden_filter) . 'h');                 
                knx_write($ga_betriebsstunden_filter,hex($betriebsstunden_filter) . 'h',16.000);
	}elsif($reciv =~ /07f0000402/i){ #Wenn die Rückmeldung der Binäreingänge empfangen wurden
                my $zustand_badschalter = substr($reciv,12,1);
                plugin_log($plugname,'Zustand Badezimmerschalter: ' . $zustand_badschalter);                 
                knx_write($ga_zustand_badschalter,$zustand_badschalter,1.001);
	}elsif($reciv =~ /07f000DA11/i and $laenge == 50){ #Wenn die Rückmeldung der Störmeldungen empfangen wurden
                my $fehlerAlo = substr($reciv,10,2);
                my $fehlerAhi = substr($reciv,34,2);
                my $fehlerE = substr($reciv,12,2);
                my $fehlerFilter = substr($reciv,26,2);
                my $fehlerEA = substr($reciv,28,2);
                
		my $numAlo = 'A';
		my $numAhi = 'A';
		my $numE = 'A';
		my $numEA = 'A';
		
		$numAlo .= unpack("B*",pack("H*",$fehlerAlo));
		$numAhi .= unpack("B*",pack("H*",$fehlerAhi));
		$numE .= unpack("B*",pack("H*",$fehlerE));
		$numEA .= unpack("B*",pack("H*",$fehlerEA));
		                
                $fehlerAlo = reverse($numAlo); #Wandle den Wert in Binär und drehe die Reihenfolge um. z.B 0x02 = 00000010 = 010000000
                $fehlerAlo = index($fehlerAlo,'1')+1; # Zähle an welcher Stelle die 1 auftaucht (von links gelesen) z.B. 01000000 = INDEX 2 = Feler2

		if($fehlerAhi ne '00'){
			$fehlerAhi = index(reverse($numAhi),'1')+9;
		}else{
			$fehlerAhi = '';
		}
                $fehlerE = index(reverse($numE),'1')+1;
                $fehlerEA = index(reverse($numEA),'1')+1;
                
                if($fehlerAhi == 16){$fehlerAhi = 0;}
                
                if($ga_fehlercode){ #Wenn die GA für das übertragen den Fehlercodes eingertagen wurde, ab hier auswerten

                	if($fehlerAlo > 0){
                		plugin_log($plugname,'Aktueller Fehlercode: A' . $fehlerAlo);
                		knx_write($ga_fehlercode,'A' . $fehlerAlo,16.001);
                	}elsif($fehlerAhi ne ''){
                		plugin_log($plugname,'Aktueller Fehlercode: A' . $fehlerAhi);
                		knx_write($ga_fehlercode,'A' . $fehlerAhi,16.001);                		
                	}elsif($fehlerE > 0){
                		plugin_log($plugname,'Aktueller Fehlercode: E' . $fehlerE);
                		knx_write($ga_fehlercode,'E' . $fehlerE,16.001);
                	}elsif($fehlerEA > 0){
                		plugin_log($plugname,'Aktueller Fehlercode: EA' . $fehlerEA);
                		knx_write($ga_fehlercode,'EA' . $fehlerEA,16.001);
                	}else{
                		plugin_log($plugname,'Aktueller Fehlercode: keiner' );
                		knx_write($ga_fehlercode,'keiner' . $fehlerEA,16.001);
                	}	
                }
                if(hex($fehlerFilter) > 0){
                	plugin_log($plugname,'Aktueller Fehler: Filter Voll');
                	knx_write($ga_fehler_filter,1,1);
                }else{
			knx_write($ga_fehler_filter,0,1);
                }               
	}
}