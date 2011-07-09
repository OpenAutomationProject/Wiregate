# Plugin zum Zeitabhängigen Schalten von GA's (Schaltuhr)
# License: GPL (v2)
# version von emax
# Version 1, 8.7.2011
# Copyright: Edgar (emax) Hermanns, emax at berlios Punkt de

####################
###Einstellungen:###
####################

my @Zeiten = 
    ( 
      { Name=>'Test',           Aktiv=>'1', Std=>undef, Min=>undef, MTag=>undef, Mon=>undef, WTag=>undef,   Wert=>'1', DPT=>'1', GA=>'1/1/30', Log=>'1' }, 
      { Name=>'Bewaesserung',   Aktiv=>'1', Std=>'7',   Min=> '0',  MTag=>'3',   Mon=>'4-9', WTag=>'1-5',   Wert=>'1', DPT=>'1', GA=>'1/1/30' },
      { Name=>'AussenlichtEin', Aktiv=>'1', Std=>'19',  Min=>'30',  MTag=>'4',   Mon=>undef, WTag=>'1,3,5', Wert=>'1', DPT=>'1', GA=>'1/2/40' },
      { Name=>'AussenlichtAus', Aktiv=>'1', Std=>'7',   Min=> '0',  MTag=>undef, Mon=>undef, WTag=>'2,4,6', Wert=>'0', DPT=>'1', GA=>'1/2/40' }
    );

######################
##ENDE Einstellungen##
######################

use POSIX;

############################################################
# Eigenen Aufruf-Zyklus setzen
# Das script verarbeitet keine Sekunden, weshalb die kleinste 
# Granulaität ohne zusätzlioche Statusverarbeitung eine Minute ist. 
############################################################
my $cycleTime = 60;

############################################################
# definiert die Sekunde, ab der neu synchronisiert wird    #
############################################################
my $slotEnd = 10; 

############################################################
# Die Versionsnummer ist Teil des plugin_info hashes und dient
# dazu, dass das script definierte Anfangskonditionen findet 
# auch ohne alles neu starten zu müssen. Die Nummer 
# einfach nach einer Änderung des scripts um eins erhöhen.
############################################################
my $version = 1;

###################################################################
# Auswertung von Bereichs und Listenvergleichen                   #
# Prüft, ob ein Wert zu einer Liste oder in einen Bereich passt   #
###################################################################
sub matches
{
    my ($value, $def) = @_;  # Zu prüfender Wert, Bereichsdefinition
    (!$def) and return 1;
    foreach (split(/,/, $def))
    {        
        s/\s+//g;
        (/^$value$/) and return 1;
        (/^([\d]+)-(\d+)/) and return ($value >= $1 && $value <= $2);
    }
    return 0;
}

##########
# main() #
##########

# kontrollierte Startkonditionen setzen
if (!defined $plugin_info{$plugname.$version.'firstRun'}) 
{
    $plugin_info{$plugname.$version.'firstRun'} = 1;
    plugin_log($plugname, "Started plugin version $version, first have to sync with time slot.");
    # die Anpassungs der Zyklyzweit erfolgt dynamisch, s.u.
    $plugin_info{$plugname.'_cycle'} = 1;
}

my ($curSec,$curMin,$curStu,$curMTag,$curMon,$curJahr,$curWTag,$curJTag,$isdst) = localtime(time);
$curJahr += 1900;

#######################################################################
# Es ist sinnvoll, dafür zu sorgen, dass die Startzeit dieses Plugins 
# mit der Zeit nicht "abdriftet", da sonst über lange Laufzeiten ein 
# Minutenüberlauf entstehen könnte, und so Ereignisse verloren gingen.
# Aus diesem Grund prüft das script, ob es innerhalb der ersten 10 Sekunden 
# einer Minute läuft, Wenn das nicht der Fall ist, wird so lange eine 
# verkürzte Zykluszeit verwendet, bis die Ausführung wieder im vorgesehenen 
# Zeitraum abläuft.
#
# Bei der Erstausführung des Plugins nimmt dieses erst nach Erreichen 
# des vorgesehenen Zeitfensters die eigentliche Arbeit auf, weil der 
# Abstand zwischen zwei sonst zu klein werden könnte.
#######################################################################

if ($curSec >= $slotEnd)
{
    if ($plugin_info{$plugname.'_cycle'} != 1)
    {
        plugin_log($plugname, "lost time-slot due to time drift, reducing cycle time to 1 second");
            $plugin_info{$plugname.'_cycle'} = 1;
    }
    
    # bei Erstausführung auf Zeitfenster warten
    ($plugin_info{$plugname.$version.'firstRun'} == 1) and return;
}

# prüfen, ob in dieser Minute bereits ausgeführt
(defined $plugin_info{$plugname.$version.'lastMinute'} && $plugin_info{$plugname.$version.'lastMinute'} == $curMin) and return;

foreach my $Zeit (@Zeiten) 
{
    (defined $Zeit->{Aktiv} && !$Zeit->{Aktiv}) and next;

    (defined $Zeit->{Min}  && !&matches($curMin,  $Zeit->{Min}))  and next;
    (defined $Zeit->{Std}  && !&matches($curStu,  $Zeit->{Std}))  and next;
    (defined $Zeit->{MTag} && !&matches($curMTag, $Zeit->{MTag})) and next;
    (defined $Zeit->{Mon}  && !&matches($curMon,  $Zeit->{Mon}))  and next;
    (defined $Zeit->{WTag} && !&matches($curWTag, $Zeit->{WTag})) and next;
    (defined $Zeit->{Log}  && $Zeit->{Log} eq '1') and 
        plugin_log($plugname, "Sending $Zeit->{Name}, GA[$Zeit->{GA}], Value[$Zeit->{Wert}]"); 

    knx_write($Zeit->{GA},$Zeit->{Wert}, $Zeit->{DPT});   
}

$plugin_info{$plugname.$version.'lastMinute'} = $curMin;
$plugin_info{$plugname.$version.'firstRun'} = 0;
