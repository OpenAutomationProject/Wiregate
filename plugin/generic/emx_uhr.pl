# Plugin zum Zeitabhaengigen Schalten von GA's (Schaltuhr)
# License: GPL (v2)
# version von emax

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
#   4  edh  20111010  .....  - Null-Werte wurden falsch verarbeitet
#                            - Zyklusberechnung konnte wg. Rundung 
#                              in underruns (Minuten-Unterschreitung) 
#                              resultieren, wird jetzt durch Addition 
#                              eines Zusatzwertes vermieden. 
#                              Allerdings sind tw. immer noch solche 
#                              Underruns zu beobachten, die anscheinend
#                              wg. unkorrektem timings von 'aussen' 
#                              verursacht werden. Das Script fängt 
#                              diese underruns allerdings ebenfalls ab.                              
#   3  edh  20110910  .....  Zykluszeit wurde nicht korrekt verarbeitet,
#                            Zyklus-Anpassung nun exakt in Sekunden,
#                            -  dadurch keine 1-Sekunden leer-Zyklen mehr,
#                            -  weniger Systemlast.
#                            Alte plugin_info einträge werden bei neuer 
#                             versionsnummer nun bereinigt.
#   2  edh  20110910  -----  Bug im Wertevergleich in 'matches()' gefixt
#   1  edh  20110807  -----  wg. utf-8 Zirkus Umlaute in ae/ue/oe geaendert
#   0  edh  20110708  -----  erste Version

#-----------------------------------------------------------------------------
# Einstellungen
#-----------------------------------------------------------------------------


my @Zeiten = 
    (       
      # Beispiele
       { Name=>'Test',           Aktiv=>'0', Std=>undef, Min=>undef, MTag=>undef, Mon=>undef, WTag=>undef,   Wert=>'1', DPT=>'1', GA=>'1/1/30', Log=>'1' }, 
       { Name=>'Bewaesserung',   Aktiv=>'0', Std=>'7',   Min=> '0',  MTag=>'3',   Mon=>'4-9', WTag=>'1-5',   Wert=>'1', DPT=>'1', GA=>'1/1/30' },
       { Name=>'AussenlichtEin', Aktiv=>'0', Std=>'19',  Min=>'30',  MTag=>'4',   Mon=>undef, WTag=>'1,3,5', Wert=>'1', DPT=>'1', GA=>'1/2/40' }, 
       { Name=>'AussenlichtAus', Aktiv=>'0', Std=>'7',   Min=> '0',  MTag=>undef, Mon=>undef, WTag=>'2,4,6', Wert=>'0', DPT=>'1', GA=>'1/2/40' }
    );

#-----------------------------------------------------------------------------
# ENDE Einstellungen
#-----------------------------------------------------------------------------

use POSIX;

#-----------------------------------------------------------------------------
# Eigenen Aufruf-Zyklus setzen
# Das script verarbeitet keine Sekunden, weshalb die kleinste 
# Granulaitaet ohne zusaetzlioche Statusverarbeitung eine Minute ist. 
#-----------------------------------------------------------------------------
my $cycleTime = 60;

#-----------------------------------------------------------------------------
# definiert die Sekunde, ab der neu synchronisiert wird   
# ACHTUNG: Sollte nicht kleiner als 1 Sekunde sein.
#-----------------------------------------------------------------------------
my $slotEnd = 1; 

#-----------------------------------------------------------------------------
# Die Versionsnummer is Teil des plugin_info hashes und dient
# dazu, dass das script definierte anfangskonditionen findet 
# auch ohne den wiregated neu starten zu muessen. Die Nummer 
# einfach nach einer Aenderung des scripts um eins erhoehen.
#-----------------------------------------------------------------------------
my $version = 8;

#-----------------------------------------------------------------------------
# Numerischen string als Zahl zurückgeben
# - blanks entfernen
# - führende Nullen entfernen
#-----------------------------------------------------------------------------
sub toNumber
{
    my $value = shift;
    (!defined $value) and return 0;

    $value =~ s/\s+//g; # whitespace entfernen
    $value =~ s/^0+(.)$/$1/g; # fuehrende Nullen entfernen
    return $value;
} # toNumber


#-----------------------------------------------------------------------------
# Auswertung von Bereichs und Listenvergleichen
# Prueft, ob ein Wert zu einer Liste oder in einen Bereich passt
#-----------------------------------------------------------------------------
sub matches
{
    my ($value, $def) = @_;  # Zu pruefender Wert, Bereichsdefinition
    (!defined $def)  and return 1;
    $value = &toNumber($value);

    foreach (split(/,/, $def))
    {
        $_ = &toNumber($_);
	# Vergleich auf Alpha-Basis (vermeidet Laufzeit-Fehler)
        (/^$value$/) and return 1;
        (/^([\d]+)-(\d+)/) and return ($value >= $1 && $value <= $2);
    }
    return 0;
} # matches

#-----------------------------------------------------------------------------
# Zykluszeit setzen
#-----------------------------------------------------------------------------
sub setCycle
{
    my ($seconds,$uSec) = gettimeofday();
    my $curSec = $seconds%60;
    if ( $curSec >= $slotEnd)
    {
	$plugin_info{$plugname.'_cycle'} = $cycleTime - $curSec - $uSec/1000000 + 0.1; # avoid rounding underruns
	plugin_log($plugname, "cycle time set to $plugin_info{$plugname.'_cycle'} second");
    }
    else
    {
	$plugin_info{$plugname.'_cycle'} = $cycleTime;
    }
}

#=============================================================================
# main()
#=============================================================================

my ($curSec,$curMin,$curStu,$curMTag,$curMon,$curJahr,$curWTag,$curJTag,$isdst) = localtime(time);
$curJahr += 1900;

# kontrollierte Startkonditionen setzen
if (!defined $plugin_info{"$plugname.$version.firstRun"})
{
    plugin_log($plugname, "Starting plugin version $version, will execute with first time-slot.");
    # obsolete Versionen von $plugin_info bereinigen
    foreach (keys %plugin_info)
    {
	if (/^$plugname\./)
	{
	    delete $plugin_info{$_};
	    plugin_log($plugname, "deleted plugin_info[$_]");
	}
    }
    $plugin_info{"$plugname.$version.firstRun"} = 1;
    &setCycle();
}

# beim ersten mal nur ausfuehren, wenn inmnerhalb des slots
($curSec >= $slotEnd && $plugin_info{"$plugname.$version.firstRun"} == 1) and return;

# pruefen, ob in dieser Minute bereits ausgefuehrt
if (defined $plugin_info{"$plugname.$version.lastMinute"} && $plugin_info{"$plugname.$version.lastMinute"} == $curMin)
{
    &setCycle();
    return;
}

foreach my $Zeit (@Zeiten) 
{
    (defined $Zeit->{Aktiv} && !$Zeit->{Aktiv}) and next;

    (defined $Zeit->{Min}  && !&matches($curMin,  $Zeit->{Min}))  and next;
    (defined $Zeit->{Std}  && !&matches($curStu,  $Zeit->{Std}))  and next;
    (defined $Zeit->{MTag} && !&matches($curMTag, $Zeit->{MTag})) and next;
    (defined $Zeit->{Mon}  && !&matches($curMon,  $Zeit->{Mon}))  and next;
    (defined $Zeit->{WTag} && !&matches($curWTag, $Zeit->{WTag})) and next;
    (defined $Zeit->{Log}  && $Zeit->{Log} eq '1') and 
        plugin_log($plugname, "Sending Value[$Zeit->{Wert}] to GA[$Zeit->{GA}], $Zeit->{Name}"); 

    knx_write($Zeit->{GA},$Zeit->{Wert}, $Zeit->{DPT});   
}

$plugin_info{"$plugname.$version.lastMinute"} = $curMin;

# ggf. Zykluszeit korrigieren
&setCycle();
$plugin_info{"$plugname.$version.firstRun"} = 0;


