#############################################################################
# Plugin: Beschattung mit Raffstores/Rolläden
# V1.0 2013-05-06
# Copyright: Marcus Lichtenberger (marcus@lichtenbergers.at)
# License: GPL (v3)
#
#############################################################################
#
# Plugin zur Beschattung eines Hauses mittels Raffstores oder Rolläden
# - Helligkeitsabhängige Beschattung
# - Beschattung je Sonnenstand
# - Hochfahren der Beschattung, wenn Fenster geöffnet wird
# - Sperre der gesamten Beschattung bzw. jedes einzelnen Fensters mittels Bustelegramm
# - Lamellennachführung bei Raffstores
# - Sommer- und Winter-Modus
#
#############################################################################
#
# Änderungshistorie:
# 20120804 - joda123 - rollo_beschattungsposition eingeführt: Rollos können bei
#            Beschattung jetzt n% geschlossen werden (vorher immer 100%)
# 20120805 - joda123 - Lokale Definitionen in conf Datei ausgelagert: Es sind keine
#            site-spezifischen Definitionen in diesem Script mehr erforderlich.
#            Alle lokalen Anpassungen in /etc/wiregate/plugin/generic/conf.d/beschattung_v2.conf
# 20120808 - mclb - Lamellenbehandlung nur noch, wenn $gs_raffstore->{lamellenNachfuehrung} nicht NACHF_AUS ist
# 20120808 - mclb - Neuen Header eingefügt (nun mit Hinweis auf GPL, damit auch Andere hier weiterentwickeln können
# 20120808 - mclb - Umbenennung von beschattung_v2 auf beschattung
# 20120821 - mclb - Definition einer Konstante hat gefehlt
#            NACHF_100 gefixt
# 20120920 - mclb - Winter-Modus (Aktivierbar über eigene GA; Im Winter-Modus können die Lamellen an eine andere Stelle zur Beschattung gefahren werden)
# 20120925 - mclb - Beschattung temperaturabhängig aktivieren/deaktivieren
# 20130506 - mclb - Aufteilen in 2 Plugins - 1. Freigabe, 2. Ausführung
# 20130620 - mclb - Azimuth und Elevation werden jetzt über GAs empfangen, nicht mehr direkt vom plugin_info gelesen.
#                   Somit erübrigt sich auch der zyklische Aufruf jede Minute.
#
#############################################################################
#
# Offene Punkte:
# - Beschattung abhängig von der Raumtemperatur
#
#############################################################################
#
# Abhängigkeiten:
# - Plugin beschattung_freigabe
#
#############################################################################
#
# plugin_info-Werte
#
#############################################################################

# Konstanten für Aufrufart
use constant EVENT_RESTART => 'restart';
use constant EVENT_MODIFIED => 'modified';
use constant EVENT_BUS => 'bus';
use constant EVENT_SOCKET => 'socket';
use constant EVENT_CYCLE => 'cycle';
# Konstanten für die Freigabe
use constant FREIGABE_AUS => 0;
use constant FREIGABE_EIN => 1;
# Konstanten für Nachführung ein/aus
use constant NACHF_AUS => 'AUS';
use constant NACHF_EIN => 'EIN';
use constant NACHF_100 => '100';
# Konstanten für Raffstore-Attribute
use constant AKTIV => 'A';
use constant INAKTIV => 'I';
use constant SPERRE_AKTIV => 1;
use constant SPERRE_INAKTIV => 0;
use constant AUTOMATIK_EIN => 'EIN';
use constant AUTOMATIK_AUS => 'AUS';
# Konstanten für die Trennung der dynamischen Raffstore-Definitionen
use constant SEPARATOR1 => ';';
use constant SEPARATOR2 => '->';
# Konstanten für Temperaturfreigabe
use constant TEMPFREIGABE_EIN => 'EIN';
use constant TEMPFREIGABE_AUS => 'AUS';

# Variablendefinitionen
my $gv_helligkeit;
my $gv_zeitpunkt;
my $gv_zeitdifferenz;
my $gs_raffstore;
my $gv_raffstore_dyn;
my @gt_raffstores_dyn;
my $gv_id;
my $gv_aktiv;
my $gv_sperre;
my $gv_automatik;
my $gv_startWinkel;
my $gv_endWinkel;
my $gv_rolloPos;
my $gv_rolloBeschattungspos;
my $gv_lamellePos;
my $gv_lamellePosNeu;
my $gv_index;
my $gv_tempFreigabe;
my $gv_temperatur;
my $gv_temperaturFreigabe;
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
my $gv_gaWinter = "";
my $gv_gaFreigabe = "";
my $gv_gaAzimuth = "";
my $gv_gaElevation = "";
my @gt_raffstores;

# Read config file in conf.d
my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
if (! -f $confFile) {
  plugin_log($plugname, "0.1 - no conf file [$confFile] found.") if ($show_debug > 0); 
  return "no conf file [$confFile] found.";
} else {
  plugin_log($plugname, "0.2 - reading conf file [$confFile].") if($show_debug > 0); 
  open(CONF, $confFile);
  my @lines = <CONF>;
  close($confFile);
  my $result = eval("@lines");
  if( $show_debug > 1 )
  {
    ($result) and plugin_log($plugname, "0.3 - conf file [$confFile] returned result[$result]");
  }
  if ($@) 
  {
    plugin_log($plugname, "0.4 - conf file [$confFile] returned:") if($show_debug > 0);
    my @parts = split(/\n/, $@);
    if( $show_debug > 1 )
    {
      plugin_log($plugname, "0.5 - --> $_") foreach (@parts);
    }
  }
}

# Ruf mich garnicht zyklisch auf, nur wenn sich auf einer meiner abbonierten GAs etwas tut
$plugin_info{$plugname.'_cycle'} = 0;
# Ruf mich auf, wenn zwischen Sommer- und Winter-Modus gewechselt wird
if ($gv_gaWinter ne '') { $plugin_subscribe{$gv_gaWinter}{$plugname} = 1; }
# Ruf mich auf, wenn sich die Freigabe ändert
if ($gv_gaFreigabe ne '') { $plugin_subscribe{$gv_gaFreigabe}{$plugname} = 1; }
# Ruf mich auf, wenn sich der Sonnenstand ändert
if ($gv_gaAzimuth ne '') { $plugin_subscribe{$gv_gaAzimuth}{$plugname} = 1; }
if ($gv_gaElevation ne '') { $plugin_subscribe{$gv_gaElevation}{$plugname} = 1; }
# Ruf mich auf, wenn sich an der Sperr-GA eines Raffstores etwas ändert
# Ruf mich auf, wenn sich der Fenster-Status ändert
foreach $gs_raffstore (@gt_raffstores) {
 # Aufruf bei Sperr-GA
 if ($gs_raffstore->{gaSperre} ne "") {
  $plugin_subscribe{$gs_raffstore->{gaSperre}}{$plugname} = 1;
 }
 # Aufruf, wenn sich der Fenster-Status ändert (offen/geschlossen)
 if ($gs_raffstore->{gaFensterStatus} ne "") {
  $plugin_subscribe{$gs_raffstore->{gaFensterStatus}}{$plugname} = 1;
 }
 # Aufruf, wenn eine benötigte Temperatur gesendet wird
 if ($gs_raffstore->{gaTemperatur} ne "") {
  $plugin_subscribe{$gs_raffstore->{gaTemperatur}}{$plugname} = 1;
 }
}

# Dynamische Teile der Raffstore-Definition einlesen
@gt_raffstores_dyn = split(SEPARATOR1, $plugin_info{$plugname.'_gt_raffstores_dyn'});
foreach $gv_raffstore_dyn (@gt_raffstores_dyn) {
 ($gv_id, $gv_aktiv, $gv_sperre, $gv_automatik, $gv_temperatur, $gv_temperaturFreigabe) = split(SEPARATOR2, $gv_raffstore_dyn);
 
 # Wegen Update auf gt_raffstores hier eine for-Schleife
 for ($gv_index=0; $gv_index<@gt_raffstores; $gv_index++) {
  $gs_raffstore = $gt_raffstores[$gv_index];
  if ($gs_raffstore->{id} eq $gv_id) {
   if ($gv_aktiv ne '') {
    $gs_raffstore->{aktiv} = $gv_aktiv;
   }
   if ($gv_sperre ne '') {
    $gs_raffstore->{sperre} = $gv_sperre;
   }
   if ($gv_automatik ne '') {
    $gs_raffstore->{automatik} = $gv_automatik;
   }
   if ($gv_temperatur ne '') {
    $gs_raffstore->{valueTemperatur} = $gv_temperatur;
   }
   if ($gv_temperaturFreigabe ne '') {
    $gs_raffstore->{temperaturFreigabe} = $gv_temperaturFreigabe;
   }
   $gt_raffstores[$gv_index] = $gs_raffstore;
   last();
  }
 }
}

# Module laden
use Astro::Coord::ECI;
use Astro::Coord::ECI::Sun;
use Astro::Coord::ECI::TLE;
use Astro::Coord::ECI::Utils qw{rad2deg deg2rad};

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

if ($gv_event eq EVENT_RESTART) {
 #Default: Sommermodus
 if (!exists $plugin_info{$plugname.'_winterModus'}) {
  $plugin_info{$plugname.'_winterModus'} = 0;
 }
 if (!exists $gs_raffstore->{temperaturFreigabe}) {
  $gs_raffstore->{temperaturFreigabe} = TEMPFREIGABE_AUS;
 }
} elsif ($gv_event eq EVENT_MODIFIED) {
 # Default nicht beschatten, falls der Wert noch nicht existiert
 if (!exists $plugin_info{$plugname.'_freigabe'}) {
  $plugin_info{$plugname.'_freigabe'} = FREIGABE_AUS;
 }
 if (!exists $gs_raffstore->{temperaturFreigabe}) {
  $gs_raffstore->{temperaturFreigabe} = TEMPFREIGABE_AUS;
 }
} elsif ($gv_event eq EVENT_BUS) {
 if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gv_gaFreigabe) {
  plugin_log($plugname, '1 - Freigabe = '.$msg{'value'}) if ($show_debug > 0);
  $plugin_info{$plugname.'_freigabe'} = $msg{'value'};
 } elsif ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gv_gaWinter) {
  # Umschalten zwischen Sommer- und Wintermodus
  plugin_log($plugname, '2 - Write Winter-Modus = '.$msg{'value'}) if ($show_debug > 0);
  $plugin_info{$plugname.'_winterModus'} = $msg{'value'};
 } elsif ($msg{'apci'} eq "A_GroupValue_Read" and $msg{'dst'} eq $gv_gaWinter) {
  # Schreibe den Sommer-Winter-Modus Wert auf den Bus
  plugin_log($plugname, '3 - Read Winter-Modus = '.$msg{'value'}) if ($show_debug > 0);
  knx_write($gv_gaWinter,$plugin_info{$plugname.'_winterModus'});
 } elsif ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gv_gaAzimuth) {
  # Neuer Azimuth-Wert
  plugin_log($plugname, '4 - Azimuth = '.$msg{'value'}) if ($show_debug > 0);
  $plugin_info{$plugname.'_azimuth'} = $msg{'value'};
 } elsif ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gv_gaElevation) {
  # Neuer Elevation-Wert
  plugin_log($plugname, '5 - Elevation = '.$msg{'value'}) if ($show_debug > 0);
  $plugin_info{$plugname.'_elevation'} = $msg{'value'};
 } else {
  for ($gv_index=0; $gv_index < @gt_raffstores; $gv_index++) {
   # Muss mittels for-Schleife (und nicht foreach) gemacht werden, weil ich die Werte in der Schleife updaten muss.
   $gs_raffstore = $gt_raffstores[$gv_index];

   if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gs_raffstore->{gaSperre}) {
    # Sperre wurde gesetzt oder aufgehoben
    $gs_raffstore->{sperre} = $msg{'value'};
   }
   if ($msg{'apci'} eq "A_GroupValue_Read" and $msg{'dst'} eq $gs_raffstore->{gaSperre}) {
    # Sperre wurde abgefragt
    knx_write($gs_raffstore->{gaSperre}, $gs_raffstore->{sperre});
   }
   if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gs_raffstore->{gaFensterStatus}) {
    plugin_log($plugname, '6 - Fenster-Status = '.$msg{'value'}) if ($show_debug > 0);
    if ($msg{'value'} == 0) {
	 plugin_log($plugname, '6a - Fenster-Status AUTOMATIK_AUS') if ($show_debug > 0);
     # Wird ein Fenster geöffnet, dann Raffstore nach oben und Automatik aus
     $gs_raffstore->{automatik} = AUTOMATIK_AUS;
     $gv_rolloPos = knx_read($gs_raffstore->{gaRolloPosRM}, 5.001);
     if ($gv_rolloPos != 0) {
      knx_write($gs_raffstore->{gaRolloPos}, 0, 5.001);
     }
     if ($gs_raffstore->{lamellenNachfuehrung} ne NACHF_AUS) {
      $gv_lamellePos = knx_read($gs_raffstore->{gaLamellePosRM}, 5.001);
      if ($gv_lamellePos != 0) {
       knx_write($gs_raffstore->{gaLamellePos}, 0, 5.001);
      }
	 }
    } elsif ($msg{'value'} == 1) {
	 plugin_log($plugname, '6b - Fenster-Status AUTOMATIK_EIN') if ($show_debug > 0);
     # Wird ein Fenster geschlossen, dann Automatik aus
     $gs_raffstore->{automatik} = AUTOMATIK_EIN;
    }
   }
   if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gs_raffstore->{gaTemperatur}) {
    $gs_raffstore->{valueTemperatur} = $msg{'value'};
   }
   $gt_raffstores[$gv_index] = $gs_raffstore;
  }
 }

 # Beschattungs-Automatik
 plugin_log($plugname,'7 - Cycle-Aufruf, Sperre = '.$plugin_info{$plugname.'_sperre'}.', Freigabe = '.$plugin_info{$plugname.'_freigabe'}) if ($show_debug > 0);
 if ($plugin_info{$plugname.'_sperre'} == SPERRE_INAKTIV) {
  plugin_log($plugname,'8 - Beschattung') if ($show_debug > 0);
  plugin_log($plugname,'9 - Freigabe = '.$plugin_info{$plugname.'_freigabe'}) if ($show_debug > 0);

  # Automatik läuft grundsätzlich
  foreach $gs_raffstore (@gt_raffstores) {
   plugin_log($plugname,'10 - Raffstore = '.$gs_raffstore->{id}.', Aktiv = '.$gs_raffstore->{aktiv}.', Sperre = '.$gs_raffstore->{sperre}.', Automatik = '.$gs_raffstore->{automatik}) if ($show_debug > 0);

   if ($gs_raffstore->{aktiv} eq AKTIV and
       $gs_raffstore->{sperre} == SPERRE_INAKTIV and
       $gs_raffstore->{automatik} eq AUTOMATIK_EIN) {

	plugin_log($plugname,'11 - Beschattung aktiv; Freigabe = '.$plugin_info{$plugname.'_freigabe'}) if ($show_debug > 0);

    # Automatik ist aktiv -> also mach nun deine Arbeit
    if ($plugin_info{$plugname.'_freigabe'} eq FREIGABE_AUS) {
     # Freigabe ist aufgrund der Helligkeit nicht notwendig -> Raffstore nach oben!

	 plugin_log($plugname,'12 - Freigabe AUS -> Raffstores nach oben') if ($show_debug > 0);

     # Raffstores hoch
     $gv_rolloPos = knx_read($gs_raffstore->{gaRolloPosRM}, 5.001);
     if ($gv_rolloPos != 0) {
      knx_write($gs_raffstore->{gaRolloPos}, 0, 5.001);
     }
	 if ($gs_raffstore->{lamellenNachfuehrung} ne NACHF_AUS) {
      $gv_lamellePos = knx_read($gs_raffstore->{gaLamellePosRM}, 5.001);
      if ($gv_lamellePos != 0) {
       knx_write($gs_raffstore->{gaLamellePos}, 0, 5.001);
      }
	 }
    } else {
	 plugin_log($plugname,'13 - Freigabe EIN -> Ausrichtungsabhängig beschatten; Ausrichtung = '.$gs_raffstore->{ausrichtung}) if ($show_debug > 0);

     if (exists($gs_raffstore->{ausrichtung})) {
      #Startwinkel berechnen
      $gv_startWinkel = $gs_raffstore->{ausrichtung} - 85;
      if ($gv_startWinkel < 0) {
       $gv_startWinkel = $gv_startWinkel + 360;
      }
      # Endwinkel berechnen
      $gv_endWinkel = $gs_raffstore->{ausrichtung} + 85;
      if ($gv_endWinkel > 360) {
       $gv_endWinkel = $gv_endWinkel - 360;
      }
     }
     if (exists($gs_raffstore->{startWinkel})) {
      $gv_startWinkel = $gs_raffstore->{startWinkel};
     }
     if (exists($gs_raffstore->{endWinkel})) {
      $gv_endWinkel = $gs_raffstore->{endWinkel};
     }

     # Muss aufgrund der Raumtemperatur beschattet werden?
     if (exists $gs_raffstore->{minTemperatur} and
         exists $gs_raffstore->{maxTemperatur} and
         exists $gs_raffstore->{valueTemperatur} ) {

      plugin_log($plugname,'14 - minTemperatur = '.$gs_raffstore->{minTemperatur}.', maxTemperatur = '.$gs_raffstore->{maxTemperatur}.', valueTemperatur = '.$gs_raffstore->{valueTemperatur}) if ($show_debug > 0);

      if ($gs_raffstore->{valueTemperatur} < $gs_raffstore->{minTemperatur}) {
       $gs_raffstore->{temperaturFreigabe} = TEMPFREIGABE_AUS;
      }
      if ($gs_raffstore->{valueTemperatur} > $gs_raffstore->{maxTemperatur}) {
       $gs_raffstore->{temperaturFreigabe} = TEMPFREIGABE_EIN;
      }
     } else {
      # Wenn keine explizite Temperaturfreigabelogik vorhanden, dann default freigegeben verwenden
	  $gs_raffstore->{temperaturFreigabe} = TEMPFREIGABE_EIN;
	 }

	 plugin_log($plugname,'15 - StartWinkel = '.$gv_startWinkel.', EndWinkel = '.$gv_endWinkel.', Azimuth = '.$plugin_info{$plugname.'_azimuth'}) if ($show_debug > 0);
	 plugin_log($plugname,'16 - TemperaturFreigabe = '.$gs_raffstore->{temperaturFreigabe}) if ($show_debug > 0);

     # Aktuelle Sonnenposition verwenden um zu bestimmen, ob der Raffstore gerade beschattet werden muss
     if ($plugin_info{$plugname.'_azimuth'} >= $gv_startWinkel and
         $plugin_info{$plugname.'_azimuth'} <= $gv_endWinkel   and
         $gs_raffstore->{temperaturFreigabe} eq TEMPFREIGABE_EIN) {

      # Beschattung aufgrund der Ausrichtung und Raumtemperatur

      # Raffstore runter
      $gv_rolloPos = knx_read($gs_raffstore->{gaRolloPosRM}, 5.001);
      if ($plugin_info{$plugname.'_winterModus'} == 1) {
	   plugin_log($plugname,'17 - WinterModus = 1 - rolloBeschattungspos = '.$gs_raffstore->{rolloBeschattungsposWinter}) if ($show_debug > 0);
       $gv_rolloBeschattungspos = $gs_raffstore->{rolloBeschattungsposWinter};
      } else {
	   plugin_log($plugname,'18 - WinterModus = 0 - rolloBeschattungspos = '.$gs_raffstore->{rolloBeschattungspos}) if ($show_debug > 0);
       $gv_rolloBeschattungspos = $gs_raffstore->{rolloBeschattungspos};
      }
	  plugin_log($plugname,'19 - rolloPos = '.$gv_rolloPos.', rolloBeschattungsPos = '.$gv_rolloBeschattungspos) if ($show_debug > 0);
      if ($gv_rolloPos != $gv_rolloBeschattungspos) {
       knx_write($gs_raffstore->{gaRolloPos}, $gv_rolloBeschattungspos, 5.001);
      }
      if ($gs_raffstore->{lamellenNachfuehrung} ne NACHF_AUS) {
       $gv_lamellePos = knx_read($gs_raffstore->{gaLamellePosRM}, 5.001);
      }

      # Lamellennachführung
     
      if ($gv_minuten % 5 == 0) {
       if ($gs_raffstore->{lamellenNachfuehrung} ne NACHF_AUS) {
        if ($gs_raffstore->{lamellenNachfuehrung} eq NACHF_100) {
         # Somit wird auf jeden Fall ganz zu gemacht.
         $gv_lamellePos = 0;
         $gv_lamellePosNeu = 100;
        } else {
         $gv_lamellePosNeu = (90 - $plugin_info{$plugname.'_elevation'})/90*100;
         # Faktor für die Abweichung der Sonne von der Ausrichtung des Fensters miteinbeziehen
         $gv_lamellePosNeu = $gv_lamellePosNeu * (1 - (abs($plugin_info{$plugname.'_azimuth'} - $gs_raffstore->{ausrichtung}) * 0.01));
         # Der Wert für den Lamellenwinkel muss immer zwischen 0 und 100 sein! Alles darüber hinaus wird fix auf 0 bzw. 100 gesetzt.
         if ($gv_lamellePosNeu < 0) { $gv_lamellePosNeu = 0; }
         if ($gv_lamellePosNeu > 100) { $gv_lamellePosNeu = 100; }
        }
        # Nicht wegen jeder Kleinigkeit gleich nachstellen, erst nach einer gewissen Mindeständerung.
        if (abs($gv_lamellePos - $gv_lamellePosNeu) > 5) {
         knx_write($gs_raffstore->{gaLamellePos},$gv_lamellePosNeu,5.001);
        }
       }
      }
     } else {
      # Keine Beschattung aufgrund der Ausrichtung

      # Raffstore hoch
      $gv_rolloPos = knx_read($gs_raffstore->{gaRolloPosRM}, 5.001);
      if ($gv_rolloPos != 0) {
       knx_write($gs_raffstore->{gaRolloPos}, 0, 5.001);
      }
      if ($gs_raffstore->{lamellenNachfuehrung} ne NACHF_AUS) {
       $gv_lamellePos = knx_read($gs_raffstore->{gaLamellePosRM}, 5.001);
       if ($gv_lamellePos != 0) {
        knx_write($gs_raffstore->{gaLamellePos}, 0, 5.001);
       }
      }
     }
    }
   }
  }
 }
} elsif ($gv_event eq EVENT_SOCKET) {
} elsif ($gv_event eq EVENT_CYCLE) {
}

# Dynamische Werte der Raffstore-Definition im plugin_info merken
@gt_raffstores_dyn = ();
foreach $gs_raffstore (@gt_raffstores) {
 unshift(@gt_raffstores_dyn, join(SEPARATOR2, $gs_raffstore->{id}, $gs_raffstore->{aktiv}, $gs_raffstore->{sperre}, $gs_raffstore->{automatik}, $gs_raffstore->{valueTemperatur}, $gs_raffstore->{temperaturFreigabe}));
}
$gv_raffstore_dyn = join(SEPARATOR1, @gt_raffstores_dyn);
$plugin_info{$plugname.'_gt_raffstores_dyn'} = $gv_raffstore_dyn;

if ($show_debug > 0) {
 return $gv_raffstore_dyn;
} else {
 return 'Beschattungslogik erledigt!';
}