#############################################################################
# Plugin: Beschattung freigeben / einschalten
# V1.0 2013-05-06
# Copyright: Marcus Lichtenberger (marcus@lichtenbergers.at)
# License: GPL (v3)
#
#############################################################################
#
# Änderungshistorie:
# 20130506 - mclb - Erstellung
# 20130617 - mclb - Sonnenstand wird nun mittels GAs erhalten
#                   Somit können nun die Werte z.B. einer Wetterstation verwendet werden.
#
#############################################################################
#
# Offene Punkte:
# - Dzt. keine bekannt
#
#############################################################################
#
# Abhängigkeiten:
# - Plugin berechne_sonnenstand
#
#############################################################################
#
# plugin_info-Werte
# - 
#
#############################################################################

# Konstanten für Aufrufart
use constant EVENT_RESTART => 'restart';
use constant EVENT_MODIFIED => 'modified';
use constant EVENT_BUS => 'bus';
use constant EVENT_SOCKET => 'socket';
use constant EVENT_CYCLE => 'cycle';
# Konstanten für Beschattung ein/aus
use constant BESCHATTUNG_AUS => 'AUS';
use constant BESCHATTUNG_EIN => 'EIN';
# Konstanten für Beschattung Freigabe ein/aus
use constant FREIGABE_AUS => 'AUS';
use constant FREIGABE_EIN => 'EIN';

# Variablendefinitionen
my $gv_helligkeit;
my $gv_azimuth;
my $gv_elevation;
my $gv_beschattungEin;
my $gv_zeitpunkt;
my $gv_zeitdifferenz;
# Zeitpunkt auslesen
my $gv_sekunden;
my $gv_minuten;
my $gv_stunden;
my $gv_monatstag;
my $gv_monat;
my $gv_jahr;
my $gv_wochentag;
my $gv_jahrestag;
my $gv_sommerzeit;

# Definition und Initialisierung der konfigurierbaren Werte
my $show_debug = 0; # switches debug information that will be shown in the log
my $gv_gaHelligkeit = "";
my $gv_gaSperre = "";
my $gv_gaFreigabe = "";
my $gv_gaAzimuth = "";
my $gv_gaElevation = "";

# Read config file in conf.d
my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
if (! -f $confFile)
{
  plugin_log($plugname, "0.1 - no conf file [$confFile] found.") if ($show_debug > 0); 
  return "no conf file [$confFile] found.";
}
else
{
  plugin_log($plugname, "0.2 - reading conf file [$confFile].") if ($show_debug > 0); 
  open(CONF, $confFile);
  my @lines = <CONF>;
  close($confFile);
  my $result = eval("@lines");
  if( $show_debug > 0 )
  {
    ($result) and plugin_log($plugname, "0.3 - conf file [$confFile] returned result[$result]");
  }
  if ($@) 
  {
    plugin_log($plugname, "0.4 - conf file [$confFile] returned:") if ($show_debug > 0);
    my @parts = split(/\n/, $@);
    if( $show_debug > 0 )
    {
      plugin_log($plugname, "0.5 - --> $_") foreach (@parts);
    }
  }
}

# Ruf mich alle 60 Sekunden selbst auf, damit ich prüfen kann, ob die Helligkeit über-/unterschritten wurde
$plugin_info{$plugname.'_cycle'} = 60;
# Ruf mich auf, wenn sich die Helligkeit ändert, damit ich meine Helligkeits-Variable setzen kann
if ($gv_gaHelligkeit ne '') { $plugin_subscribe{$gv_gaHelligkeit}{$plugname} = 1; }
# Ruf mich auf, wenn die Automatik gesperre oder freigegeben wird
if ($gv_gaSperre ne '') { $plugin_subscribe{$gv_gaSperre}{$plugname} = 1; }
# Ruf mich auf, wenn sich der Sonnenstand ändert
if ($gv_gaAzimuth ne '') { $plugin_subscribe{$gv_gaAzimuth}{$plugname} = 1; }
if ($gv_gaElevation ne '') { $plugin_subscribe{$gv_gaElevation}{$plugname} = 1; }

# Aus welchem Grund läuft das Plugin gerade
my $gv_event=undef;
if (!$plugin_initflag) {
 $gv_event = EVENT_RESTART;            # Restart des daemons / Reboot
} elsif ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'}) {
 $gv_event = EVENT_MODIFIED;        # Plugin modifiziert
} elsif (%msg) {
 $gv_event = EVENT_BUS;                # Bustraffic
} elsif ($fh) {
 $gv_event = EVENT_SOCKET;            # Netzwerktraffic
} else {
 $gv_event = EVENT_CYCLE;            # Zyklus
}

plugin_log($plugname, "1 - Event: ".$gv_event) if ($show_debug > 0);

if ($gv_event eq EVENT_RESTART) {
 # Default nicht beschatten, falls der Wert noch nicht existiert
 if (!exists $plugin_info{$plugname.'_beschattungFreigabe'}) {
  $plugin_info{$plugname.'_beschattungFreigabe'} = FREIGABE_AUS;
 }
 # Evtl. Sperre setzen, falls noch nicht existent
 if (!exists $plugin_info{$plugname.'_sperre'}) {
  $plugin_info{$plugname.'_sperre'} = SPERRE_INAKTIV;
 }
 # Evtl. Werte initialisieren, falls es sie noch nicht gibt.
 if (!exists $plugin_info{$plugname.'_beschattungEin'}) {
  $plugin_info{$plugname.'_beschattungEin'} = BESCHATTUNG_AUS;
 }
 if (!exists $plugin_info{$plugname.'_beschattungEinTime'}) {
  ($gv_sekunden, $gv_minuten, $gv_stunden, $gv_monatstag, $gv_monat, $gv_jahr, $gv_wochentag, $gv_jahrestag, $gv_sommerzeit) = localtime(time);
  $gv_zeitpunkt = $gv_minuten + ($gv_stunden*60);
  $plugin_info{$plugname.'_beschattungEinTime'} = $gv_zeitpunkt;
 }
} elsif ($gv_event eq EVENT_MODIFIED) {
 # Default nicht beschatten, falls der Wert noch nicht existiert
 if (!exists $plugin_info{$plugname.'_beschattungFreigabe'}) {
  $plugin_info{$plugname.'_beschattungFreigabe'} = FREIGABE_AUS;
 }
 # Evtl. Sperre setzen, falls noch nicht existent
 if (!exists $plugin_info{$plugname.'_sperre'}) {
 }
  $plugin_info{$plugname.'_sperre'} = SPERRE_INAKTIV;
 # Evtl. Werte initialisieren, falls es sie noch nicht gibt.
 if (!exists $plugin_info{$plugname.'_beschattungEin'}) {
  $plugin_info{$plugname.'_beschattungEin'} = BESCHATTUNG_AUS;
 }
 if (!exists $plugin_info{$plugname.'_beschattungEinTime'}) {
  ($gv_sekunden, $gv_minuten, $gv_stunden, $gv_monatstag, $gv_monat, $gv_jahr, $gv_wochentag, $gv_jahrestag, $gv_sommerzeit) = localtime(time);
  $gv_zeitpunkt = $gv_minuten + ($gv_stunden*60);
  $plugin_info{$plugname.'_beschattungEinTime'} = $gv_zeitpunkt;
 }
} elsif ($gv_event eq EVENT_BUS) {
 if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gv_gaAzimuth) {
  $plugin_info{$plugname.'_azimuth'} = $msg{'value'};
 } elsif ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gv_gaElevation) {
  $plugin_info{$plugname.'_elevation'} = $msg{'value'};
 } elsif ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gv_gaHelligkeit) {
  # Aufruf durch Helligkeits-Telegramm
  $gv_helligkeit = $msg{'value'};

  # Azimuth und Elevation einlesen, damit ich bestimmen kann, ob beschattet werden muss, oder nicht.  
  $gv_azimuth = $plugin_info{$plugname.'_azimuth'};
  $gv_elevation = $plugin_info{$plugname.'_elevation'};

  plugin_log($plugname, "2 - Elevation: ".$gv_elevation." , Helligkeit: ".$gv_helligkeit) if ($show_debug > 0);

  # Prüfen, ob das Telegramm etwas am aktuellen Status ändert und ggf. merken
  if ($gv_elevation >  0 and $gv_elevation <= 10 and $gv_helligkeit >= 10000) { $gv_beschattungEin = 'J'; }
  if ($gv_elevation > 10 and $gv_elevation <= 20 and $gv_helligkeit >= 20000) { $gv_beschattungEin = 'J'; }
  if ($gv_elevation > 20 and $gv_elevation <= 30 and $gv_helligkeit >= 30000) { $gv_beschattungEin = 'J'; }
  if ($gv_elevation > 30 and $gv_elevation <= 40 and $gv_helligkeit >= 40000) { $gv_beschattungEin = 'J'; }
  if ($gv_elevation > 40 and $gv_elevation <= 50 and $gv_helligkeit >= 50000) { $gv_beschattungEin = 'J'; }
  if ($gv_elevation > 50 and $gv_elevation <= 90 and $gv_helligkeit >= 75000) { $gv_beschattungEin = 'J'; }

  if ($gv_elevation <  0) { $gv_beschattungEin = 'N'; }
  if ($gv_elevation >  0 and $gv_elevation <= 10 and $gv_helligkeit < 10000) { $gv_beschattungEin = 'N'; }
  if ($gv_elevation > 10 and $gv_elevation <= 20 and $gv_helligkeit < 20000) { $gv_beschattungEin = 'N'; }
  if ($gv_elevation > 20 and $gv_elevation <= 30 and $gv_helligkeit < 30000) { $gv_beschattungEin = 'N'; }
  if ($gv_elevation > 30 and $gv_elevation <= 40 and $gv_helligkeit < 40000) { $gv_beschattungEin = 'N'; }
  if ($gv_elevation > 40 and $gv_elevation <= 50 and $gv_helligkeit < 50000) { $gv_beschattungEin = 'N'; }
  if ($gv_elevation > 50 and $gv_elevation <= 90 and $gv_helligkeit < 75000) { $gv_beschattungEin = 'N'; }

  plugin_log($plugname, "3 - Beschattung ein: ".$gv_beschattungEin) if ($show_debug > 0);

  # Abhängig vom letzten gültigen Wert den neuen beschattungEin setzen
  if ($gv_beschattungEin eq 'J' and $plugin_info{$plugname.'_beschattungEin'} eq BESCHATTUNG_AUS) {
   ($gv_sekunden, $gv_minuten, $gv_stunden, $gv_monatstag, $gv_monat, $gv_jahr, $gv_wochentag, $gv_jahrestag, $gv_sommerzeit) = localtime(time);
   $gv_zeitpunkt = $gv_minuten + ($gv_stunden*60);
   $plugin_info{$plugname.'_beschattungEin'} = BESCHATTUNG_EIN;
   $plugin_info{$plugname.'_beschattungEinTime'} = $gv_zeitpunkt;
  } elsif ($gv_beschattungEin eq 'N' and $plugin_info{$plugname.'_beschattungEin'} eq BESCHATTUNG_EIN) {
   ($gv_sekunden, $gv_minuten, $gv_stunden, $gv_monatstag, $gv_monat, $gv_jahr, $gv_wochentag, $gv_jahrestag, $gv_sommerzeit) = localtime(time);
   $gv_zeitpunkt = $gv_minuten + ($gv_stunden*60);
   $plugin_info{$plugname.'_beschattungEin'} = BESCHATTUNG_AUS;
   $plugin_info{$plugname.'_beschattungEinTime'} = $gv_zeitpunkt;
  }
 } elsif ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gv_gaSperre) {
  $plugin_info{$plugname.'_sperre'} = $msg{'value'};
 }
} elsif ($gv_event eq EVENT_SOCKET) {
} elsif ($gv_event eq EVENT_CYCLE) {
 # Aufruf durch Zyklus
 $plugin_info{$plugname.'_beschattungFreigabeOld'} = $plugin_info{$plugname.'_beschattungFreigabe'};

 $gv_azimuth = $plugin_info{$plugname.'_azimuth'};
 $gv_elevation = $plugin_info{$plugname.'_elevation'};
 
 # Prüfen, ob die Beschattung aktiviert oder deaktiviert werden muss
 if ($plugin_info{$plugname.'_beschattungEin'} eq BESCHATTUNG_EIN and
     $plugin_info{$plugname.'_sperre'} == 0 and
	 $plugin_info{$plugname.'_beschattungFreigabe'} eq FREIGABE_AUS) {

  ($gv_sekunden, $gv_minuten, $gv_stunden, $gv_monatstag, $gv_monat, $gv_jahr, $gv_wochentag, $gv_jahrestag, $gv_sommerzeit) = localtime(time);
  $gv_zeitpunkt = $gv_minuten + ($gv_stunden*60);
  $gv_zeitdifferenz = $gv_zeitpunkt - $plugin_info{$plugname.'_beschattungEinTime'};
  plugin_log($plugname, "4 - Zeit neu: ".$gv_zeitpunkt.", Zeit alt: ".$plugin_info{$plugname.'_beschattungEinTime'}.", Differenz: ".$gv_zeitdifferenz) if ($show_debug > 0);
  if ($gv_zeitdifferenz > 5) {
   $plugin_info{$plugname.'_beschattungFreigabe'} = FREIGABE_EIN;
   knx_write($gv_gaFreigabe, 1);
  }
 } elsif ( ($plugin_info{$plugname.'_beschattungEin'} eq BESCHATTUNG_AUS or
            $plugin_info{$plugname.'_sperre'} == 1) and
          $plugin_info{$plugname.'_beschattungFreigabe'} eq FREIGABE_EIN) {

  ($gv_sekunden, $gv_minuten, $gv_stunden, $gv_monatstag, $gv_monat, $gv_jahr, $gv_wochentag, $gv_jahrestag, $gv_sommerzeit) = localtime(time);
  $gv_zeitpunkt = $gv_minuten + ($gv_stunden*60);
  $gv_zeitdifferenz = $gv_zeitpunkt - $plugin_info{$plugname.'_beschattungEinTime'};
  plugin_log($plugname, "5 - Zeit neu: ".$gv_zeitpunkt.", Zeit alt: ".$plugin_info{$plugname.'_beschattungEinTime'}.", Differenz: ".$gv_zeitdifferenz) if ($show_debug > 0);
  if ($gv_zeitdifferenz > 15) {
   $plugin_info{$plugname.'_beschattungFreigabe'} = FREIGABE_AUS;
   knx_write($gv_gaFreigabe, 0);
  }
 }
}

return 'Freigabe: '.$plugin_info{$plugname.'_beschattungFreigabe'};