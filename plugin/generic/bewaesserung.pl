#############################################################################
# Plugin: bewaesserung.pl (Gartenberegnung steuern)
# V0.5 20140309
# Autor: Mathias Gindler (mathias@gindler.de)
# License: GPL (v3)
#
#############################################################################
#
# Beschreibung:
# Ansteuerung mehrerer Beregnungstränge hintereinander für eine bestimmte Dauer
# (je Strang), ausgelöst/gestoppt über eine einzige GA.
# Dabei wird der Strang innerhalb der Dauer zyklisch neu angetriggert,
# somit kann die Treppenlichtfunktion eines Aktors für eine Sicherheits-
# abschaltung verwendet werden.
#
#############################################################################
#
# Änderungshistorie:
#
#############################################################################
#
# Offene Punkte:
#
#############################################################################
#
# Abhängigkeiten:
#
#############################################################################
#
# plugin_info-Werte
# - aktKreisNr: Index (0-n) des aktuellen Kreises
# - Startzeit: Start des aktuellen Kreises
# - Status: Bewässerung aktiv (1) oder inaktiv (0)
#
#############################################################################

use POSIX;
use Time::Local;

# Konstanten für Aufrufart
use constant EVENT_RESTART => 'restart';
use constant EVENT_MODIFIED => 'modified';
use constant EVENT_BUS => 'bus';
use constant EVENT_SOCKET => 'socket';
use constant EVENT_CYCLE => 'cycle';

my $show_debug = 1;
my $debugindex = 1;
my $gv_event=undef;

my $startzeit;
my $pluginstatus;

my $ga_plugintrigger = "12/6/100";    # Start/Stop der Beregnungs-Sequenz
my $ga_pluginstatus  = "12/6/102";    # Status, ob Sequenz aktiv/inaktiv (1/0)
my $triggercycle = 10;                # Re-Trigger-Intervall  (entspricht max. Über-Bewässerung), 
                                      # muss kleiner als Treppenlicht-Einstellung des Aktors sein


my @Kreise;    # Array für Regnerkreise
push @Kreise, {name => "Rasen West", dauer => 100, ga_schalten => '12/6/10', ga_status => '12/6/12'};
push @Kreise, {name => "Rasen Ost",  dauer => 110, ga_schalten => '12/6/20', ga_status => '12/6/22'};
push @Kreise, {name => "Hecke",      dauer => 120, ga_schalten => '12/6/30', ga_status => '12/6/32'};

plugin_log($plugname, "------------------------------------") if ($show_debug > 5);

# Aufruf per Bus-Telegramm
$plugin_subscribe{$ga_plugintrigger}{$plugname} = 1;

# aktuellen Status lesen
if ($plugin_info{$plugname.'_Status'} ne '') {$pluginstatus = $plugin_info{$plugname.'_Status'}};

# Aus welchem Grund läuft das Plugin gerade
if (!$plugin_initflag) {$gv_event = EVENT_RESTART;} # Restart des daemons / Reboot
elsif ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'}) {$gv_event = EVENT_MODIFIED;} # Plugin modifiziert
elsif (%msg) {$gv_event = EVENT_BUS;}               # Bustraffic
elsif ($fh) {$gv_event = EVENT_SOCKET;}             # Netzwerktraffic
else {$gv_event = EVENT_CYCLE;}                     # Zyklus

plugin_log($plugname, $debugindex++." (MAIN) Aufrufgrund: $gv_event") if ($show_debug > 5);
plugin_log($plugname, $debugindex++." (MAIN) aktueller Status: $pluginstatus") if ($show_debug > 5);

if ($gv_event eq EVENT_RESTART) {
    ende();
} 
elsif ($gv_event eq EVENT_MODIFIED) {
    ende();
}  
elsif ($gv_event eq EVENT_SOCKET) {
} 
elsif ($gv_event eq EVENT_CYCLE) {
    beregnung();
}
elsif ($gv_event eq EVENT_BUS) {
    plugin_log($plugname, $debugindex++." (BUS) aktueller Status: $pluginstatus") if ($show_debug > 1);
    if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $ga_plugintrigger) {
        if ($msg{'value'} == 1){
            plugin_log($plugname, $debugindex++." (BUS) EIN-Telegramm empfangen") if ($show_debug > 1);
            $plugin_info{$plugname.'_cycle'} = $triggercycle;
            if ($pluginstatus == 1){
                plugin_log($plugname, $debugindex++." (BUS) Beregnungsprogramm läuft bereits - keine Aktion ausgeführt") if ($show_debug > 0);
            }
            else{
                plugin_log($plugname, $debugindex++." (BUS) Beregnungsprogramm gestartet") if ($show_debug > 0);
                $startzeit = time();
                $plugin_info{$plugname.'_Startzeit'} = $startzeit;
                $plugin_info{$plugname.'_aktKreisNr'} = 0;
                $pluginstatus = 1;
                $plugin_info{$plugname.'_Status'} = $pluginstatus;
                beregnung();
            }
        }
        else{
            plugin_log($plugname, $debugindex++." (BUS) AUS-Telegramm empfangen") if ($show_debug > 1);
            $plugin_info{$plugname.'_cycle'} = 0;
            if ($pluginstatus == 0){
                plugin_log($plugname, $debugindex++." (BUS) Beregnungsprogramm läuft nicht - keine Aktion ausgeführt") if ($show_debug > 0);
            }
            else{
                plugin_log($plugname, $debugindex++." (BUS) Beregnungsprogramm beendet") if ($show_debug > 0);
                ende();
            }
        }
    } 
} 

knx_write($ga_pluginstatus, $pluginstatus);  # aktuellen Status an Bus zurückmelden


sub beregnung{
    my $x;
    my $kreisname;
    my $kreisdauer;
    my $ga_schalten;
    my $ga_status;
    my $istdauer;
    
# Parameter für aktuellen Kreis setzen    
    $x = $plugin_info{$plugname.'_aktKreisNr'};
    $kreisname     = $Kreise[$x]->{name};
    $ga_schalten   = $Kreise[$x]->{ga_schalten};
    $ga_status     = $Kreise[$x]->{ga_status};
    $kreisdauer    = $Kreise[$x]->{dauer};
    
    plugin_log($plugname, $debugindex++." (SUB beregnung) Beregnung: Index $x ('$kreisname'), Trigger $ga_schalten, Status $ga_status") if ($show_debug > 5);
    
    if ($plugin_info{$plugname.'_Startzeit'} + $kreisdauer < time()){
        plugin_log($plugname, $debugindex++." (SUB beregnung) Kreis '$kreisname' abgeschlossen") if ($show_debug > 0);
        $istdauer = sprintf("%2.0f", time() - $plugin_info{$plugname.'_Startzeit'});
        plugin_log($plugname, $debugindex++." (SUB beregnung) Kreis '$kreisname' Dauer: $istdauer sek. (ist)/$kreisdauer sek. (soll)") if ($show_debug > 0);
        knx_write($ga_schalten, 0);
        if ($x < $#Kreise){
            plugin_log($plugname, $debugindex++." (SUB beregnung) Umschalten auf nächsten Kreis") if ($show_debug > 0);
            $x++;
            $plugin_info{$plugname.'_aktKreisNr'} = $x;
            $plugin_info{$plugname.'_Startzeit'} = time();

# nächste Zeile aktivieren, um sofort umzuschalten; 
# wenn deaktiviert, wird nächster Kreis erst im nächsten Zyklus eingeschaltet ($triggercycle)
            beregnung();   
        }
        else{
            plugin_log($plugname, $debugindex++." (SUB beregnung) keine weiteren Kreise, Beregnung beendet.") if ($show_debug > 0);
            ende();
        }
    }
    else{
        plugin_log($plugname, $debugindex++." (SUB beregnung) Beregnung für Kreis '$kreisname' (re-)triggert") if ($show_debug > 0);
        knx_write($ga_schalten, 1);
    }
}

sub ende{
    foreach (@Kreise){
        plugin_log($plugname, $debugindex++." (SUB ende) Ventil für '$_->{name}' geschlossen") if ($show_debug > 0);
        knx_write($_->{ga_schalten},0);
    }
    $pluginstatus = 0;
    $plugin_info{$plugname.'_Status'} = $pluginstatus;
    $plugin_info{$plugname.'_cycle'} = 0;
}

