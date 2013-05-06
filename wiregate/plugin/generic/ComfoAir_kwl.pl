# Plugin zur Ansteuerung einer Zender ComfoAir
# Version 1.6.5 13.04.2013 BETA
# Copyright: swiss (http://knx-user-forum.de/members/swiss.html)
# Aufbau moeglichst so, dass man unterhalb der Einstellungen nichts veraendern muss!
# - Neu mit der Moeglichkeit zur Anbindung über einen Moxa NPort von Fechter65 (http://knx-user-forum.de/members/fechter65.html)
# - Neustrukturierung des Codes von Fechter65 (http://knx-user-forum.de/members/fechter65.html)
# - Besseres Fehlerhandling bei der Verarbeitung der Reuckmeldungen von swiss (http://knx-user-forum.de/members/swiss.html)
# - Neu nun mit direktem abfragen der Stufe nach dem setzen und auswerten der Komforttemperatur von swiss (http://knx-user-forum.de/members/swiss.html)
 

####################
###Einstellungen:###
####################

#BITTE ab sofort die Einstellungen unter conf.d vornemen. Damit bleiben die Einstellungen auch bei einem Update erhalten.
 

######################
##ENDE Einstellungen##
######################


#Ab hier nichts mehr aendern.
#Hauptverarbeitung


#Erzeuge Variablen fuer die Zuordnung der Steuerfunktionen zu den Gruppenadressen:
my $ga_stufeabwesend = ''; #1bit Trigger fuer Stufe "Abwesend". 1=Aktivieren
my $ga_stufe1 = ''; #1bit Trigger fuer Stufe1. 1=Aktivieren
my $ga_stufe2 = ''; #1bit Trigger fuer Stufe2. 1=Aktivieren
my $ga_stufe3 = ''; #1bit Trigger fuer Stufe3. 1=Aktivieren
my $ga_komforttemp = ''; #GA DPT 9.001 zum setzen der Komforttemperatur
my $ga_reset_filter = ''; #1bit Trigger fuer das Zuruecksetzen des Betriebsstundenzaehlers des Filters. 1=Reset
my $ga_reset_error = ''; #1bit Trigger fuer das zuruecksetzen der KWL nach einem Fehler. 1=Reset
 

#Hier werden die Gruppenadressen fuer die Rueckmeldungen vergeben: (Nich vergeben = inaktiv)
my $ga_status_ventilator_zul = ''; #GA DPT5.001 fuer Status Ventilator Zuluft %
my $ga_status_ventilator_abl = ''; #GA DPT5.001 fuer Status Ventilator Abluft %
my $ga_status_bypass_prozent = ''; #GA DPT5.001 fuer Status Bypassklappe %
my $ga_betriebsstunden_filter = ''; #GA DPT16.000 fuer die Rueckmeldung der Betribsstunden des Filters
my $ga_zustand_badschalter = ''; #GA DPT1.001 fuer die Rueckmeldung des Zustandes des Badezimmerschalters
my $ga_fehler_filter = ''; #GA DPT 1.001 fuer den Zustand des Filters. 0=OK, 1=Filter Voll
my $ga_fehlercode = ''; #GA DPT 16.000 fuer die Ausgabe des Fehlercodes als Text
my $ga_aktstufe = ''; #Wert für aktuelle Stufe
 
#Hier werden die Gruppenadressen für die Rückmeldung der Temperaturen vergeben: (Nicht vergeben=inaktiv)
my $ga_aul_temp = ''; #GA DPT 9.001 für die Aussenlufttemperatur
my $ga_zul_temp = ''; #GA DPT 9.001 für die Zulufttemperatur
my $ga_abl_temp = ''; #GA DPT 9.001 für die Ablufttemperatur
my $ga_fol_temp = ''; #GA DPT 9.001 für die Fortlufttemperatur
my $ga_komfort_temp = ''; #GA DPT 9.001 für die Komforttemperatur
 
#Zuordnung der Namen fuer die RRD's:
my $Name_rrd_AUL = 'KWL_Aussenluft'; #Name RRD Aussenluft
my $Name_rrd_ZUL = 'KWL_Zuluft'; #Name RRD Zuluft
my $Name_rrd_ABL = 'KWL_Abluft'; #Name RRD Abluft
my $Name_rrd_FOL = 'KWL_Fortluft'; #Name RRD Fortluft
 
#Pfad zur seriellen Schnittstelle oder dem USB-Seriell-Wandler:
my $schnittstelle = '/dev/ttyUSB-2-4';
 

#Angaben für die Kommunikation über den UDP-Port einer MOXA [diese Einstellungen reichen aus, d.h. auf dem Wiregate muss unter "Seriell/LAN/Socketverbindungen" KEINE Socketverbindung erstellt werden
my $socknum = ""; # Eindeutige Nummer des Sockets
my $send_ip = ""; # SendeIP (UDP)
my $send_port = ""; # Sendeport (UDP)   
my $recv_ip = ""; # EmpfangsIP (UDP)
my $recv_port = ""; # Empfangsport (UDP)
 

# Kommunikationsart
my $Kom_Art = "S"; # "S" = seriell; "M" = Moxa
 

# Dauer einer Abfrage
my $Zaehler = "2500"; #Mit dieser Variable Zaehler wird beeinflusst, wie lange das Plugin auf den Abschluss einer Rückmeldung der KWL wartet; empfohlener Wert für seriell: 2500; für Moxa: 250
 
# Debug level 0 = nur die wichtigsten Infos, 1 = Alle Zustaende, 2 = Rohdaten (nur für Fehlersuche)
my $debug=0;
 
 
#Weitere Variablen die benoetigt werden -> NICHT veraendern!
my $seriel;
my $sin; #Serial Input = Empangener Datenstrom
my $cin; #Counter Input =  Länge des Datenpackets
my $laenge; #Länge des empfangenen Datenstrings nachdem kürzen
 
my $checksum = 0; #Checksumme
my @hex; #Hilfsarray für die Checksummenberechnung
my $x07warschon; #Hilfsvariable für die Checksummenberechnung
 
&readConf(); #conf.d einlesen
 
my $return_value2;
my $daten;
my $reciv;
my $reciv_all;
my $ack = pack("H*","07F3");
my $rcv_checksum;
 
# Zyklischer Aufruf nach restart, empfang GA oder 1/2 der einstellung rrd (typisch 150sek).
$plugin_info{$plugname.'_cycle'}  = 150;

use Device::SerialPort;
use Time::Local;

 
#Einrichten der Seriellen Schnittstelle fuer die Kommunikation mit dem ComfoAir falls Schnittstelle auf "S" steht
if ($Kom_Art eq "S"){
             $seriel = Device::SerialPort->new($schnittstelle) || die "Kann $schnittstelle nicht öffnen! ($!)\n";
             $seriel->baudrate(9600);
             $seriel->parity("none");
             $seriel->databits(8);
             $seriel->stopbits(1);
             if($debug>=1){plugin_log($plugname,'Schnittstelle: ' . $schnittstelle . ' erfolgreich geöffnet')};
}elsif ($Kom_Art eq "M"){
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
        $plugin_socket_subscribe{$socket[$socknum]} = $plugname; # Plugin an Socket "anmelden"
        if($debug>=1){plugin_log($plugname,'Socket: ' . $socknum . ' erfolgreich geöffnet')};
        return "opened Socket $socknum";
    }
}

 
if ($msg{'apci'} eq "A_GroupValue_Write"){ #Wenn ein Telegramm vom KNX empfangen wird, ab hier auswerten
    if ($msg{'dst'} eq $ga_stufeabwesend && knx_read($msg{'dst'},0,1) == 1) {
        $daten = "00990101";
        plugin_log($plugname,'Stufe abwesend setzen');
        $return_value2 = command_senden($daten);
            if($ga_aktstufe){ #Nur wenn die GA vergeben ist, die Ventilationsstufe abfragen
                $daten = "00CD00";
                if($debug>=1){plugin_log($plugname,'Ventilationsstufe abrufen');}
                $return_value2 = command_senden($daten);
            }
    }elsif ($msg{'dst'} eq $ga_stufe1 && knx_read($msg{'dst'},0,1) == 1) {
        $daten = "00990102";
        plugin_log($plugname,'Stufe 1 setzen');
        $return_value2 = command_senden($daten);
            if($ga_aktstufe){ #Nur wenn die GA vergeben ist, die Ventilationsstufe abfragen
                $daten = "00CD00";
                if($debug>=1){plugin_log($plugname,'Ventilationsstufe abrufen');}
                $return_value2 = command_senden($daten);
            }
    }elsif ($msg{'dst'} eq $ga_stufe2 && knx_read($msg{'dst'},0,1) == 1) {
        $daten = "00990103";
        plugin_log($plugname,'Stufe 2 setzen');
        $return_value2 = command_senden($daten);
            if($ga_aktstufe){ #Nur wenn die GA vergeben ist, die Ventilationsstufe abfragen
                $daten = "00CD00";
                if($debug>=1){plugin_log($plugname,'Ventilationsstufe abrufen');}
                $return_value2 = command_senden($daten);
            }
    }elsif ($msg{'dst'} eq $ga_stufe3 && knx_read($msg{'dst'},0,1) == 1) {
        $daten = "00990104";
        plugin_log($plugname,'Stufe 3 setzen');
        $return_value2 = command_senden($daten);
            if($ga_aktstufe){ #Nur wenn die GA vergeben ist, die Ventilationsstufe abfragen
                $daten = "00CD00";
                if($debug>=1){plugin_log($plugname,'Ventilationsstufe abrufen');}
                $return_value2 = command_senden($daten);
            }
    }elsif ($msg{'dst'} eq $ga_komforttemp) {
        my $komforttemp = knx_read($msg{'dst'},0,9.001);
        plugin_log($plugname,'Komforttemp auf: ' . $komforttemp . '°C setzen');
        my $temphex = ($komforttemp + 20)*2; #Rechne die Temperatur fuer die ComfoAir um
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
    if($debug>=2){plugin_log($plugname,'ENDE Aufruf durch GA');}
    return;
            
} else { # zyklischer Aufruf
    if(($plugin_info{$plugname.'_time'}+$plugin_info{$plugname.'_cycle'}) >= $plugin_info{$plugname.'_last'}){
        return;
    }
    $plugin_info{$plugname.'_time'} = time();
   
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
   
    if($ga_status_ventilator_zul && $ga_status_ventilator_abl){ #Nur wenn beide GA's vergeben sind, dann die Zust?nde der Ventilatoren abfragen
        $daten = "000B00";
        if($debug>=1){plugin_log($plugname,'Ventilator Status abrufen');}
        $return_value2 = command_senden($daten);
    }
            
    if($ga_status_bypass_prozent){ #Nur wenn die GA vergeben ist, dann Zustand Bypassklappe abfragen
        $daten = "000D00";
        if($debug>=1){plugin_log($plugname,'Bypass Zustand abrufen');}
        $return_value2 = command_senden($daten);
    }
            
    if($ga_betriebsstunden_filter){ #Nur wenn die GA vergeben ist, die Betriebsstunden abfragen
        $daten = "00DD00";
        if($debug>=1){plugin_log($plugname,'Betriebsstunden abrufen');}
        $return_value2 = command_senden($daten);
    }
            
    if($ga_zustand_badschalter){ #Nur wenn die GA vergeben ist, die Binaereingaenge abfragen
        $daten = "000300";
        if($debug>=1){plugin_log($plugname,'Binäreingänge abrufen');}
        $return_value2 = command_senden($daten);
    }
            
    if($ga_aktstufe){ #Nur wenn die GA vergeben ist, die Ventilationsstufe abfragen
        $daten = "00CD00";
        if($debug>=1){plugin_log($plugname,'Ventilationsstufe abrufen');}
        $return_value2 = command_senden($daten);
    }
            
    #Hier werden die Stoermeldungen abgefragt
    $daten = "00D900";
    if($debug>=1){plugin_log($plugname,'Störungen abrufen');}
    $return_value2 = command_senden($daten);


    if($debug>=2){plugin_log($plugname,'ENDE Zyklische Abfrage');}
    return;
}
 
 
# Ab hier wird das Datenpaket inklusive Checksumme zusammengestellt und an die ComfoAir uebertragen
sub command_senden{
    my $data = $_[0];
    if($debug>=2){plugin_log($plugname,'data: ' . $data);}
    $checksum = checksum_berechnen($data);
    if($debug>=2){plugin_log($plugname,'Checksumme aus der Subroutine: '.$checksum);}
    my $command = pack("H*","07F0" . $data . $checksum . "070F");
    my $commandhex = $command;
   
    $commandhex =~ s/(.)/sprintf("0x%x ",ord($1))/eg;
    if($debug>=2){plugin_log($plugname,'transmit: ' . $commandhex);} #Zeigt im Pluginlog das fertige Datenpaket, dass uebertragen wird
             if ($Kom_Art eq "S"){   
                             $seriel->write($command); #Befehl an die ComfoAir senden
             } elsif ($Kom_Art eq "M"){   
                             $plugin_info{$plugname.'_debug'} = $command;
                             syswrite($socket[$socknum], $command);
             }
    $reciv = '';
    $cin = '';
    $sin = '';
       
    $|=1;
    my $exit=0;
    while($exit < $Zaehler)
    {
        if ($Kom_Art eq "S"){
             ($cin, $sin) = $seriel->read(45);
        }elsif ($Kom_Art eq "M"){
                                 $sin ='';
                                 if ($fh) { # Antwort auslesen
                                                recv($fh,$sin,80,0);
                                 }
                                 $cin = length($sin);
        }
        if($cin > 0){
            $sin = unpack "H*", $sin;
            $reciv .= $sin;
            $exit=0;
        }else{
            $exit++
        }
       
        if($debug>=2){plugin_log($plugname,'reciv-direkt:     ' . $sin);}
    
            if($reciv =~ /070f/i){          
                last;
            }
    }#Ende While  

    if ($Kom_Art eq "S"){
        $seriel->write($ack); #ACK senden
        if($debug>=2){plugin_log($plugname,'ACK senden');}
    } elsif ($Kom_Art eq "M"){
        syswrite($socket[$socknum], $ack); #ACK senden
        if($debug>=2){plugin_log($plugname,'ACK senden');}
    }

    if($reciv eq ""){
        if($debug>=2){plugin_log($plugname,'FEHLER: Keine Daten empfangen!');}
        return;
    }
   
    while ((length($reciv) > 3) && (substr($reciv,(length($reciv)-4),4) ne '070f')) #solange das Ende nicht 0f lautet
    {
                    if($debug>=2){plugin_log($plugname,'String vor Kuerzung Ende: '.$reciv);}
                    $reciv = substr($reciv,0,-2); #String um die letzten zwei Zeichen kürzen
                    if($debug>=2){plugin_log($plugname,'String nach Kuerzung Ende: '.$reciv);}
    }  
   
 
        #Hier wird der empfangene String um Start- und Endbyte gekürzt
        $laenge = length($reciv); #Laenge des Antworttelegramms ermitteln
        $reciv = substr($reciv,0,($laenge-4)); #Entferne 07f0 vom Ende
       
        if(substr($reciv,(length($reciv)-4),4) eq '07f3'){
            $reciv = substr($reciv,0,($laenge-4));
            if($debug>=2){plugin_log($plugname,'String ohne 07f3: '.$reciv);}
        }

        if($debug>=2){plugin_log($plugname,'Erste 4 Byte des Datenpakets: '.(substr($reciv,0,4)));}

                                           
        while ((length($reciv) > 3) && (substr($reciv,0,4)) ne '07f0'){
            $reciv = substr($reciv,2); #falls noch ein falsche Zeichen am Anfang des Strings enthalten sind, werden diese hier entfernt.
            if($debug>=2){plugin_log($plugname,'reciv gekuerzt: '.$reciv);}
        }
       
        $reciv = substr($reciv,4);
        if($debug>=2){plugin_log($plugname,'String ohne 07f0 am Anfang: '.$reciv);}
       
        #Test einer Methode falls aussversehen mehrere Datenpakete auf einmal im Datenstring enthalten sind...
        if($reciv =~ /07f307f0/i){
            my @dataarray=split(/07f307f0/,$reciv);
            $reciv = @dataarray[1];
        }

                            
        #Nun wird die Checksumme gelesen und aus dem Datenstring entfernt
        $checksum = 0;
        $checksum = substr($reciv,-2,2);
        if($debug>=2){plugin_log($plugname,'Checksumme gelesen: '.$checksum);}
        $laenge = length($reciv); #Laenge des Antworttelegramms ermitteln
        $reciv = substr($reciv,0,($laenge-2));
        if($debug>=2){plugin_log($plugname,'Datenpaket ohne Checksumme: '.$reciv);}

        #Hier wird die Subroutine für die Berechnung der Checksumme aufgerufen und das Ergebnis in $rcv_checksum zurück gegeben
        $rcv_checksum = checksum_berechnen($reciv);

                           
        if($rcv_checksum eq $checksum){ #Hier wird geprüft ob die Checksumme korrekt ist
            if($debug>=2){plugin_log($plugname,'Checksumme OK ');}
            if($reciv =~ /00D209/i){ #Wenn die Temperaturen empfangen wurden und die Laenge passt
				my $t1 = substr($reciv,6,2);
                my $t2 = substr($reciv,8,2);
                my $t3 = substr($reciv,10,2);
                my $t4 = substr($reciv,12,2);
                my $t5 = substr($reciv,14,2);
                                                                          
                #Hier werden die Temperaturen "decodiert" damit sie einen Sinn ergeben
                $t1 =  (hex($t1)/2)-20;
                $t2 =  (hex($t2)/2)-20;
                $t3 =  (hex($t3)/2)-20;
                $t4 =  (hex($t4)/2)-20;
				$t5 =  (hex($t5)/2)-20;

                #Wenn die GA's vergeben wurde, die Temperaturen auf die GA's senden
				if($ga_komfort_temp ne ''){knx_write($ga_komfort_temp,$t1,9.001);}
                if($ga_aul_temp ne ''){knx_write($ga_aul_temp,$t2,9.001);}
                if($ga_zul_temp ne ''){knx_write($ga_zul_temp,$t3,9.001);}
                if($ga_abl_temp ne ''){knx_write($ga_abl_temp,$t4,9.001);}
                if($ga_fol_temp ne ''){knx_write($ga_fol_temp,$t5,9.001);}
               
                #Ab hier werden die RRD's mit den aktuellen Temperaturen aktualisiert:
                update_rrd($Name_rrd_AUL,"",$t2);
                update_rrd($Name_rrd_ZUL,"",$t3);
                update_rrd($Name_rrd_ABL,"",$t4);
                update_rrd($Name_rrd_FOL,"",$t5);
               
                plugin_log($plugname,'AUL: ' . $t2 . '°C, ZUL:' . $t3 . '°C, ABL: ' . $t4 . '°C, FOL: ' . $t5 . '°C, Komforttemp: ' . $t1 . '°C');

            }elsif($reciv =~ /000C06/i){ #Wenn der Status fuer die Ventilatoren empfangen wurden
                my $vent_zul = substr($reciv,6,2);
                my $vent_abl = substr($reciv,8,2);
                plugin_log($plugname,'ZUL: ' . hex($vent_zul) . '% ABL: ' . hex($vent_abl) . '%');
                knx_write($ga_status_ventilator_zul,hex($vent_zul),5.001);
                knx_write($ga_status_ventilator_abl,hex($vent_abl),5.001);   
               
            }elsif($reciv =~ /00CE0E/i){ #Wenn Status Ventilatorenstufe empfangen wurden
                my $akt_stufe = substr($reciv,22,2);
                if(hex($akt_stufe) == 1){
                    plugin_log($plugname,'AKT_STUFE: A');
                }else{
                    plugin_log($plugname,'AKT_STUFE: ' . (hex($akt_stufe)-1));
                }
                knx_write($ga_aktstufe,hex($akt_stufe),5.005);                                                                               

            }elsif($reciv =~ /000E04/i){ #Wenn der Status fuer die Bypassklappe empfangen wurden
                my $bypass_prozent = substr($reciv,6,2);
                plugin_log($plugname,'Bypass: ' . hex($bypass_prozent) . '%');               
                knx_write($ga_status_bypass_prozent,hex($bypass_prozent),5.001);

            }elsif($reciv =~ /00DE14/i){ #Wenn die Rueckmeldung der Betriebsstunden empfangen wurden
                my $betriebsstunden_filter = substr($reciv,36,4);
                plugin_log($plugname,'Betriebsstunden: ' . hex($betriebsstunden_filter) . 'h');                
                knx_write($ga_betriebsstunden_filter,hex($betriebsstunden_filter) . 'h',16.000);
               
            }elsif($reciv =~ /000402/i){ #Wenn die Rueckmeldung der Binaereingaenge empfangen wurden
                my $zustand_badschalter = substr($reciv,8,1);
                plugin_log($plugname,'Zustand Badezimmerschalter: ' . $zustand_badschalter);                
                knx_write($ga_zustand_badschalter,$zustand_badschalter,1.001);
               
            }elsif($reciv =~ /00DA11/i){ #Wenn die Rueckmeldung der Stoermeldungen empfangen wurden
                my $fehlerAlo = substr($reciv,6,2);
                my $fehlerAhi = substr($reciv,30,2);
                my $fehlerE = substr($reciv,8,2);
                my $fehlerFilter = substr($reciv,22,2);
                my $fehlerEA = substr($reciv,24,2);
               
                my $numAlo = 'A';
                my $numAhi = 'A';
                my $numE = 'A';
                my $numEA = 'A';
               
                $numAlo .= unpack("B*",pack("H*",$fehlerAlo));
                $numAhi .= unpack("B*",pack("H*",$fehlerAhi));
                $numE .= unpack("B*",pack("H*",$fehlerE));
                $numEA .= unpack("B*",pack("H*",$fehlerEA));
               
               
                $fehlerAlo = reverse($numAlo); #Wandle den Wert in Binaer und drehe die Reihenfolge um. z.B 0x02 = 00000010 = 010000000
                $fehlerAlo = index($fehlerAlo,'1')+1; # Zaehle an welcher Stelle die 1 auftaucht (von links gelesen) z.B. 01000000 = INDEX 2 = Fehler2
               
                if($fehlerAhi ne '00'){
                    $fehlerAhi = index(reverse($numAhi),'1')+9;
                }else{
                    $fehlerAhi = '';
                }
               
                $fehlerE = index(reverse($numE),'1')+1;
                $fehlerEA = index(reverse($numEA),'1')+1;
                                                                           
                if($fehlerAhi == 16){$fehlerAhi = 0;}
                                                                           
                if($ga_fehlercode){ #Wenn die GA fuer das uebertragen den Fehlercodes eingertagen wurde, ab hier auswerten
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
        }else{
            if($debug>=1){plugin_log($plugname,'Checksumme fehlerhaft! Gelesen: '.$checksum.' Berechnet: '.$rcv_checksum);}
        }
} #ENDE Sub command_senden

sub checksum_berechnen {   
    my $chk_datasum = $_[0];
    $rcv_checksum =0;
    my $i;
     $chk_datasum = $chk_datasum . "AD"; #+173 fuer die Checksummenberechnung
        if($debug>=2){plugin_log($plugname,'String für die Berechnung der Checksumme: '.$chk_datasum);}
    $x07warschon = 0;
    $laenge = length($chk_datasum);
        for($i = 0; $i< $laenge; $i++) {
            my $wertstring = substr($chk_datasum,$i,2);
            if($debug>=3){plugin_log($plugname,'Zahl: '.$wertstring);}
            my $wertbetrag = hex($wertstring);
            if ($wertbetrag == 7) {
                if ($x07warschon == 1) {
                    $x07warschon = 0;
                    $i++;
                    next;
                } else {
                    $x07warschon = 1;
                }
            }
        $rcv_checksum += $wertbetrag;
            if($debug>=3){plugin_log($plugname,'Summe: '.$rcv_checksum);}
        $i++;
    }
            if($debug>=3){plugin_log($plugname,'Summe def: '.$rcv_checksum);}

    if($debug>=2){plugin_log($plugname,'Checksumme vor der Umwandlung: '.$rcv_checksum);}
    $rcv_checksum = sprintf "%x\n" , $rcv_checksum; #Mache aus Integer wieder HEX
    if($debug>=2){plugin_log($plugname,'Checksumme vor der Kürzung: '.$rcv_checksum);}
    $rcv_checksum = substr($rcv_checksum,-3,2); #Verwende nur die letzten beiden Stellen
    if($debug>=2){plugin_log($plugname,'Checksumme nach der Kürzung: '.$rcv_checksum);}
    return $rcv_checksum;
} #Ende checksum_berechnen

 

sub readConf
{
    my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
    if (! -f $confFile)
    {
        plugin_log($plugname, " no conf file [$confFile] found!");
    }
    else
    {
        if($debug>=1){plugin_log($plugname, " reading conf file [$confFile].");}
        open(CONF, $confFile);
        my @lines = <CONF>;
        close($confFile);
        my $result = eval("@lines");
#        ($result) and plugin_log($plugname, "conf file [$confFile] returned result[$result]");
        if ($@)
        {
            if($debug>=2){plugin_log($plugname, " conf file [$confFile] returned:");}
            my @parts = split(/\n/, $@);
            if($debug>=2){plugin_log($plugname, " --> $_") foreach (@parts);}
        }
    }
} # readConf