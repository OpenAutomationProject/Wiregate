# Plugin zur Steuerung eines Handtuchtrockners
# http://knx-user-forum.de/wiregate/16209-plugin-zur-steuerung-eines-handtuchtrockners-2.html
# Sommer > Heizen über E-Patrone
# Winter > Heizen über WW-Heizung
### Definitionen
my $hk_ga = '4/2/100';                # Gruppenadresse zur Steuerung Handtuchtrockner (An/Aus)
my $sommer_ga = '4/0/0';              # Gruppenadresse Sommerbetrieb (An/Aus)
my $patrone_ga = '4/2/110';           # Gruppenadresse E-Heizpatrone (An/Aus)
my $stellantrieb_ga = '4/2/105';      # Gruppenadresse Stellantrieb (%-Wert)
my $stellantrieb_auf = 100;           # Wert für Stellantrieb offen (%-Wert)
my $stellantrieb_zu = 0;              # Wert für Stellantrieb geschlossen (%-Wert)
my $modus_hk = '1';                   # Konnex Betriebsmudus RTR wenn Handtuchtrockner läuft
my $modus_ga = '4/2/91';              # Zwangsbetriebsmodus RTR Bad
my $zwang_fbh_ga = '4/2/97';          # Zwangsmodus für Stellantrieb FBH offen
my $laufzeit = 60*60*2;               # Laufzeit bis Auto Aus in sek.
### Ende Definitionen
# Eigenen Aufruf-Zyklus auf 0 Sekunden setzen
$plugin_info{$plugname.'_cycle'} = 0;
# Plugin an Gruppenadresse "anmelden"
$plugin_subscribe{$hk_ga}{$plugname} = 1;
 
#Prüfung, ob GA durch Schreibtransaktion angesprochen wurde
if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $hk_ga ) { 
   #Wert für Handtuchtrockner lesen
   my $hk_wert = knx_read($hk_ga,300,1);
   #Ausführungszeit setzen
   $plugin_info{$plugname.'_last'} = time();
 
   #Wert für Sommerbetrieb lesen
   my $sommer_wert = knx_read($sommer_ga,300,1);      
   #Kenner Laufzeit gestartet und Aufrufintervall des Plugin setzen
   if ($hk_wert == 1) {
     $plugin_info{$plugname.'_sema'} = 1;
     $plugin_info{$plugname.'_cycle'} = $laufzeit;
     }
   if ($sommer_wert == 1) {
     if ($hk_wert == 1) {
       knx_write($patrone_ga, 1, 1);                           ##Heizpatrone einschalten
       knx_write($stellantrieb_ga, $stellantrieb_zu, 5.001);   ##Stellantrieb für HK schließen
       return "E-Patrone An";
       }
     else {
       knx_write($patrone_ga,0,1);                             ##Heizpatrone ausschalten
       knx_write($stellantrieb_ga, $stellantrieb_auf, 5.001);  ##Stellantrieb für HK öffnen   
       return "E-Patrone Aus";
       }
     }
   else {
     knx_write($patrone_ga,0,1);
     if ($hk_wert == 1) {
       knx_write($stellantrieb_ga, $stellantrieb_auf, 5.001);  ##Stellantrieb für HK öffnen
       knx_write($modus_ga, $modus_hk, 5.010);                 ##Betriebsmodus auf Anwesend zwingen
       knx_write($zwang_fbh_ga, 1, 1);                         ##Stellanrieb zwingen 100% öffnen
       return "WW-Heizung An";
       }
     else {
       knx_write($stellantrieb_ga, $stellantrieb_zu, 5.001);   ##Stellantrieb für HK schließen
       knx_write($modus_ga, 0, 5.010);                         ##Betriebsmodus Zwang zurücksetzen
       knx_write($zwang_fbh_ga, 0, 1);                         ##Stellanrieb Zwang zurücksetzen
       return "WW-Heizung Aus";
       }
     }
   }
#Ausführung wenn Aufrufintervall/Laufzeit abgelaufen ist
elsif ($plugin_info{$plugname.'_sema'} == 1) {
   #Heizkörper ausschalten,Kenner Laufzeit gestartet und Aufrufintervall des Plugin zurücksetzen 
   $plugin_info{$plugname.'_sema'} = 0;
   $plugin_info{$plugname.'_cycle'} = 0; 
   knx_write($hk_ga,0,1);
   }
return "Warte auf Telegramm";
