# Plugin zur Taupunktberechnung
# Details zur Näherungsformel unter http://www.wettermail.de/wetter/feuchte.html
# Das Plugin geht davon aus, das Temperatur&Luftfeuchte zyklisch 
# auf den Bus geschrieben werden und/oder lesbar sind (Lese-Flag gesetzt)
# Der Versand erfolgt zyklisch und beim eintreffen eines neuen Temperaturwertes
# WICHTIG: Falls Werte vom WireGate verwendet werden, muss der Sendezyklus des 
# Wertes < dem Aufrufzyklus dieses Plugins sein.
# Version: 0.1 2010-07-14

##################
### DEFINITION ###
##################

# Eigenen Aufruf-Zyklus / Versand auf 900 Sekunden setzen
$plugin_info{$plugname.'_cycle'} = 900;
my $luftfeuchte_ga = "5/2/79"; # Gruppenadresse Luftfeuchte (DPT5)
my $temperatur_ga = "3/1/46";  # Gruppenadresse Temperatur (DPT9)
my $taupunkt_ga = "14/6/11";   # Gruppenadresse für Ausgabe Taupunkt

#######################
### ENDE DEFINITION ###
#######################

# Plugin an Gruppenadresse "anmelden"
# könnte man sich natürlich auch sparen und einfach zyklisch senden
$plugin_subscribe{$temperatur_ga}{$plugname} = 1;

# Nun kommt es darauf an, ob das Plugin aufgrund eines eintreffenden Telegramms
# oder zyklisch aufgerufen wird! Wir wollen beides..
# Bei eintreffenden Telegrammen reagieren wir gezielt auf "Write" (gibt ja auch Read/Response)
# und die spezifische Gruppenadresse, das Plugin könnte ja bei mehreren "angemeldet" sein.

my $temperatur;
if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $temperatur_ga) {
   #oder nur falls die Gruppenadressen importiert wurden reicht auch:
   #$temperatur = $msg{'value'};
   $temperatur = decode_dpt9($msg{'data'});

} else { # zyklischer Aufruf
   # Wert max. eine Stunde (3600s) im cache
   # "9" (DPT) kann entfallen falls richtig importiert!
   $temperatur = knx_read($temperatur_ga,3600,9);
}

# dito: "5" (DPT) kann entfallen falls richtig importiert!
my $luftfeuchte = knx_read($luftfeuchte_ga,3600,5);

my ($a,$b);
if ($temperatur >= 0) {
  ($a,$b) = (7.5,237.3);
} else { # für T < 0 über Wasser (Taupunkt)
  ($a,$b) = (7.6,240.7);
}

my $SDD = 6.1078 * 10**(($a*$temperatur)/($b+$temperatur));
my $DD = $luftfeuchte/100 * $SDD;
my $v = log($DD/6.1078)/log(10);
my $taupunkt = $b*$v/($a-$v);
knx_write($taupunkt_ga,$taupunkt,9);

#return "T: $temperatur H: $luftfeuchte Taupunkt: $taupunkt a $a b $b v $v DD $DD SDD $SDD ";
return;

