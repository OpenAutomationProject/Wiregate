# Plugin zum Zeitabhaengigen Schalten von GA's (Schaltuhr)
# License: GPL (v2)
# version von emax
#
# $Id$
#
# Copyright: Edgar (emax) Hermanns, emax at berlios Punkt de
#--------------------------------------------------------------------
#  CHANGE LOG:
#  ##  who  yyyymmdd   bug#  description
#  --  ---  --------  -----  ----------------------------------------
#   .  ...  ........  .....  vorlage 
#   2  edh  20110910  -----  Bug im Wertevergleich in 'matches()' gefixt
#   1  edh  20110807  -----  wg. utf-8 Zirkus Umlaute in ae/ue/oe geaendert
#   0  edh  20110708  -----  erste Version
 

#---------------
# Einstellungen:
#---------------

my @Zeiten = 
    ( 
      { Name=>'Test',           Aktiv=>'1', Std=>undef, Min=>undef, MTag=>undef, Mon=>undef, WTag=>undef,   Wert=>'1', DPT=>'1', GA=>'1/1/30', Log=>'1' }, 
      { Name=>'Bewaesserung',   Aktiv=>'1', Std=>'7',   Min=> '0',  MTag=>'3',   Mon=>'4-9', WTag=>'1-5',   Wert=>'1', DPT=>'1', GA=>'1/1/30' },
      { Name=>'AussenlichtEin', Aktiv=>'1', Std=>'19',  Min=>'30',  MTag=>'4',   Mon=>undef, WTag=>'1,3,5', Wert=>'1', DPT=>'1', GA=>'1/2/40' },
      { Name=>'AussenlichtAus', Aktiv=>'1', Std=>'7',   Min=> '0',  MTag=>undef, Mon=>undef, WTag=>'2,4,6', Wert=>'0', DPT=>'1', GA=>'1/2/40' }
    );

#-------------------  
# ENDE Einstellungen  
#-------------------  

use POSIX;

#--------------------------------------------------------------------
# Eigenen Aufruf-Zyklus setzen
# Das script verarbeitet keine Sekunden, weshalb die kleinste 
# Granulaitaet ohne zusaetzlioche Statusverarbeitung eine Minute ist. 
#--------------------------------------------------------------------
my $cycleTime = 60;

#--------------------------------------------------------------------
# definiert die Sekunde, ab der neu synchronisiert wird
#--------------------------------------------------------------------
my $slotEnd = 10; 

#--------------------------------------------------------------------
# Die Versionsnummer ist Teil des plugin_info hashes und dient
# dazu, dass das script definierte Anfangskonditionen findet 
# auch ohne alles neu starten zu muessen. Die Nummer 
# einfach nach einer AEnderung des scripts um eins erhoehen.
#--------------------------------------------------------------------
my $version = 1;

#--------------------------------------------------------------------
# Auswertung von Bereichs und Listenvergleichen 
# Prueft, ob ein Wert zu einer Liste oder in einen Bereich passt
#--------------------------------------------------------------------
sub matches
{
    my ($value, $def) = @_;        # Zu pruefender Wert, Bereichsdefinition
    (!$def) and return 1;
    foreach (split(/,/, $def))
    {        
        s/\s+//g;                  # Blanks entfernen
        s/^0+//g;                  # fuehrende Nullen entfernen
        (/^$value$/) and return 1; # Alpha-Vergleich (vermeidet Laufzeitfehler)
        (/^([\d]+)-(\d+)/) and return ($value >= $1 && $value <= $2);
    }
    return 0;
}

#====================================================================
# main()
#====================================================================

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

#--------------------------------------------------------------------  
# Es ist sinnvoll, dafuer zu sorgen, dass die Startzeit dieses Plugins 
# mit der Zeit nicht "abdriftet", da sonst ueber lange Laufzeiten ein 
# Minutenueberlauf entstehen koennte, und so Ereignisse verloren gingen.
# Aus diesem Grund prueft das script, ob es innerhalb der ersten 10 Sekunden 
# einer Minute laeuft, Wenn das nicht der Fall ist, wird so lange eine 
# verkuerzte Zykluszeit verwendet, bis die Ausfuehrung wieder im vorgesehenen 
# Zeitraum ablaeuft.
#
# Bei der Erstausfuehrung des Plugins nimmt dieses erst nach Erreichen 
# des vorgesehenen Zeitfensters die eigentliche Arbeit auf, weil der 
# Abstand zwischen zwei Triggern sonst zu klein werden koennte.
#--------------------------------------------------------------------

if ($curSec >= $slotEnd)
{
    if ($plugin_info{$plugname.'_cycle'} != 1)
    {
        plugin_log($plugname, "lost time-slot due to time drift, reducing cycle time to 1 second");
            $plugin_info{$plugname.'_cycle'} = 1;
    }
    
    # bei Erstausfuehrung auf Zeitfenster warten
    ($plugin_info{$plugname.$version.'firstRun'} == 1) and return;
}

# pruefen, ob in dieser Minute bereits ausgefuehrt
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
