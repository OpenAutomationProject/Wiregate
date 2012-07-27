# Abhängigkeiten:
# - Paket libastro-satpass-perl
#   - Astro::Coord::ECI;
#   - Astro::Coord::ECI::Sun;
#   - Astro::Coord::ECI::TLE;
#   - Astro::Coord::ECI::Utils qw{rad2deg deg2rad};
#   - Installation:
#     - Wiregate Web-IF unter Updates Paket installieren libastro-satpass-perl oder
#     - in der Konsole apt-get -install libastro-satpass-perl

# plugin_info-Werte
# - beschattungEin: Beschattung wäre aktuell ein oder aus (ohne Verzögerung)
# - beschattungEinTime: Zeitpunkt zu dem die Beschattung zuletzt ein- oder ausgeschaltet wurde
# - beschattungFreigabe: Nach 5 Minuten ein oder 15 Minuten aus, wird die Freigabe erteilt, oder aufgehoben
# - elevation: Aktueller Elevation-Winkel
# - azimuth: Aktueller Azimuth-Winkel

# Offene Punkte:
# - Im Winter nur auf 90% nach unten fahren (Aneisungsgefahr)
# - Beschattung abhängig von der Raumtemperatur

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
# Konstanten für Nachführung ein/aus
use constant NACHF_AUS => 'AUS';
use constant NACHF_EIN => 'EIN';
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

# Variablendefinitionen
my $gv_lat;
my $gv_lon;
my $gv_elev;
my $gv_gaHelligkeit;
my $gv_gaSperre;
my $gv_helligkeit;
my $gv_azimuth;
my $gv_elevation;
my $gv_beschattungEin;
my $gv_zeitpunkt;
my $gv_zeitdifferenz;
my $gs_raffstore;
my @gt_raffstores;
my $gv_raffstore_dyn;
my @gt_raffstores_dyn;
my $gv_id;
my $gv_aktiv;
my $gv_sperre;
my $gv_automatik;
my $gv_startWinkel;
my $gv_endWinkel;
my $gv_rolloPos;
my $gv_lamellePos;
my $gv_lamellePosNeu;
my $gv_index;
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

#########################################################################################
# Hier folgen nun die Definitionen für die Beschattung
#########################################################################################

# Geografische Lage
($gv_lat, $gv_lon, $gv_elev) = (
 48.43333333333333,		# Breitengrad in Grad
 14.3,					# Längengrad in Grad
 825 / 1000				# Höhe über NN in Kilometer (deswegen geteilt durch 1000)
);

# Gruppenadressen
# GA für die Helligkeit
$gv_gaHelligkeit = '4/2/3';
# GA um die gesamte Beschattungs-Automatik zu sperren
$gv_gaSperre = '';

# Alle Raffstores
# id: ID des Raffstores (evtl. für Variablen, die benötigt werden)
# name: Name, falls irgendwelche Meldungen ausgegeben werden
# ausrichtung: Ausrichtung des Raffstores (z.B.: Süd = 180) Wird zur Berechnung des Start- und Endwinkels der Beschattung verwendet, sofern die Werte nicht direkt vorgegeben werden
# startWinkel: Startwinkel der Beschattung
# endWinkel: Endwinkel der Beschattung
# aktiv: Beschattung aktiv für dieses Fenster
# sperre: Beschattung für diesen Raffstore gesperrt (von außen)
# automatik: Automatik für diesen Raffstore aktiv (von innen, z.B. wenn das Fenster geöffnet wird -> automatik aus, Raffstore ganz nach oben)
# lamellenNachfuehrung: Wird die Lamelle dem Sonnenstand nachgeführt, oder sobald beschattet werden soll einfach ganz zugeklappt
# gaRollo: GA des Rollo-Objekts für den Raffstore
# gaRolloRM: Rückmelde-GA des Rollo-Objekts für den Raffstore
# gaLamellePos: GA des Lamellen-Objekts für den Raffstore
# gaLamellePosRM: Rückmelde-GA des Lamellen-Objekts für den Raffstore
# gaFensterStatus: GA des Reed-Kontakts des Fensters (Wenn das Fenster geöffnet wird, fährt der Raffstore ganz nach oben)
# gaTemperatur: Wird dzt. nicht verwendet! GA des Temperatursensores für das Fenster (kann verwendet werden, damit erst ab einer bestimmten Temperatur beschattet wird)
# gaSperre: GA zum Sperren der Beschattungs-Automatik für desen Raffstore (z.B. wenn eine andere Funktion einen Raffstore fix ganz nach oben oder unten fährt)

#Beispiele
#push @gt_raffstores, { id => "UG_WZ_SUE_FEN", name => "Wohnzimmer Süd Fenster", ausrichtung => 180, startWinkel => 95, endWinkel => 265, aktiv => AKTIV, sperre => SPERRE_INAKTIV, automatik => AUTOMATIK_EIN, lamellenNachfuehrung => NACHF_EIN, gaRolloPos => "3/2/3", gaRolloPosRM => "3/4/3", gaLamellePos => "3/3/3", gaLamellePosRM => "3/5/3", gaFensterStatus => "", gaTemperatur => "4/1/0", gaSperre => "3/6/3" };
#push @gt_raffstores, { id => "UG_KUE_WES_FEN", name => "Küche West Fenster", ausrichtung => 270, aktiv => AKTIV, sperre => SPERRE_INAKTIV, automatik => AUTOMATIK_EIN, lamellenNachfuehrung => NACHF_EIN, gaRolloPos => "3/2/7", gaRolloPosRM => "3/4/7", gaLamellePos => "3/3/7", gaLamellePosRM => "3/5/7", gaFensterStatus => "4/0/27", gaTemperatur => "4/1/0", gaSperre => "3/6/7" };

#########################################################################################
# Ab hier beginnt das Programm -> Sollte im Idealfall nicht mehr verändert werden müssen
#########################################################################################

# Ruf mich alle 60 Sekunden selbst auf, damit ich prüfen kann, ob die Helligkeit über-/unterschritten wurde
$plugin_info{$plugname.'_cycle'} = 60;
# Ruf mich auf, wenn sich die Helligkeit ändert, damit ich meine Helligkeits-Variable setzen kann
if ($gv_gaHelligkeit ne '') {
 $plugin_subscribe{$gv_gaHelligkeit}{$plugname} = 1;
}
# Ruf mich auf, wenn die Automatik gesperre oder freigegeben wird
if ($gv_gaSperre ne '') {
 $plugin_subscribe{$gv_gaSperre}{$plugname} = 1;
}
# Ruf mich auf, wenn sich an der Sperr-GA eines Raffstores etwas ändert
# Ruf mich auf, wenn sich der Fenster-Status ändert
foreach $gs_raffstore (@gt_raffstores) {
 if ($gs_raffstore->{gaSperre} ne "") {
  $plugin_subscribe{$gs_raffstore->{gaSperre}}{$plugname} = 1;
 }
 if ($gs_raffstore->{gaFensterStatus} ne "") {
  $plugin_subscribe{$gs_raffstore->{gaFensterStatus}}{$plugname} = 1;
 }
}

# Dynamische Teile der Raffstore-Definition einlesen
@gt_raffstores_dyn = split(SEPARATOR1, $plugin_info{$plugname.'_gt_raffstores_dyn'});
foreach $gv_raffstore_dyn (@gt_raffstores_dyn) {
 ($gv_id, $gv_aktiv, $gv_sperre, $gv_automatik) = split(SEPARATOR2, $gv_raffstore_dyn);
 
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
 $gv_event = EVENT_RESTART;			# Restart des daemons / Reboot
} elsif ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'}) {
 $gv_event = EVENT_MODIFIED;		# Plugin modifiziert
} elsif (%msg) {
 $gv_event = EVENT_BUS;				# Bustraffic
} elsif ($fh) {
 $gv_event = EVENT_SOCKET;			# Netzwerktraffic
} else {
 $gv_event = EVENT_CYCLE;			# Zyklus
}

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
} elsif ($gv_event eq EVENT_BUS) {
 if ($msg{'apci'} eq "A_GroupValue_Write" and $msg{'dst'} eq $gv_gaHelligkeit) {
  # Aufruf durch Helligkeits-Telegramm
  $gv_helligkeit = $msg{'value'};

  # Helligkeit im RRD mitloggen
  update_rrd("MyHelligkeit","",$gv_helligkeit);

  # Azimuth und Elevation einlesen, damit ich bestimmen kann, ob beschattet werden muss, oder nicht.  
  $gv_elevation = $plugin_info{$plugname.'_elevation'};
  $gv_azimuth = $plugin_info{$plugname.'_azimuth'};

  # Prüfen, ob das Telegramm etwas am aktuellen Status ändert und ggf. merken
  if ($gv_elevation >  0 and $gv_elevation <= 10 and $gv_helligkeit >= 10000) { $gv_beschattungEin = 'J'; }
  if ($gv_elevation > 10 and $gv_elevation <= 20 and $gv_helligkeit >= 20000) { $gv_beschattungEin = 'J'; }
  if ($gv_elevation > 20 and $gv_elevation <= 30 and $gv_helligkeit >= 30000) { $gv_beschattungEin = 'J'; }
  if ($gv_elevation > 30 and $gv_elevation <= 40 and $gv_helligkeit >= 40000) { $gv_beschattungEin = 'J'; }
  if ($gv_elevation > 40 and $gv_elevation <= 50 and $gv_helligkeit >= 50000) { $gv_beschattungEin = 'J'; }
  if ($gv_elevation > 50 and $gv_elevation <= 90 and $gv_helligkeit >= 75000) { $gv_beschattungEin = 'J'; }

  if ($gv_elevation <  0) { $gv_beschattungEin = 0; }
  if ($gv_elevation >  0 and $gv_elevation <= 10 and $gv_helligkeit < 10000) { $gv_beschattungEin = 'N'; }
  if ($gv_elevation > 10 and $gv_elevation <= 20 and $gv_helligkeit < 20000) { $gv_beschattungEin = 'N'; }
  if ($gv_elevation > 20 and $gv_elevation <= 30 and $gv_helligkeit < 30000) { $gv_beschattungEin = 'N'; }
  if ($gv_elevation > 30 and $gv_elevation <= 40 and $gv_helligkeit < 40000) { $gv_beschattungEin = 'N'; }
  if ($gv_elevation > 40 and $gv_elevation <= 50 and $gv_helligkeit < 50000) { $gv_beschattungEin = 'N'; }
  if ($gv_elevation > 50 and $gv_elevation <= 90 and $gv_helligkeit < 75000) { $gv_beschattungEin = 'N'; }

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
    if ($msg{'value'} == 0) {
     # Wird ein Fenster geöffnet, dann Raffstore nach oben und Automatik aus
	 $gs_raffstore->{automatik} = AUTOMATIK_AUS;
	 $gv_rolloPos = knx_read($gs_raffstore->{gaRolloPosRM}, 5.001);
	 $gv_lamellePos = knx_read($gs_raffstore->{gaLamellePosRM}, 5.001);
	 if ($gv_rolloPos != 0) {
	  knx_write($gs_raffstore->{gaRolloPos}, 0, 5.001);
	 }
	 if ($gv_lamellePos != 0) {
	  knx_write($gs_raffstore->{gaLamellePos}, 0, 5.001);
	 }
	} elsif ($msg{'value'} == 1) {
     # Wird ein Fenster geschlossen, dann Automatik aus
	 $gs_raffstore->{automatik} = AUTOMATIK_EIN;
	}
   }
   $gt_raffstores[$gv_index] = $gs_raffstore;
  }
 }
} elsif ($gv_event eq EVENT_SOCKET) {
} elsif ($gv_event eq EVENT_CYCLE) {
 # Aufruf durch Zyklus
 $plugin_info{$plugname.'_beschattungFreigabeOld'} = $plugin_info{$plugname.'_beschattungFreigabe'};

 # Alle 5 Minuten den Sonnenstand neu berechnen
 # Uhrzeit holen
 # Wenn Minuten durch 5 teilbar, dann berechnen
 ($gv_sekunden, $gv_minuten, $gv_stunden, $gv_monatstag, $gv_monat, $gv_jahr, $gv_wochentag, $gv_jahrestag, $gv_sommerzeit) = localtime(time);
 if ($gv_minuten % 5 == 0) {
  ($gv_azimuth, $gv_elevation) = berechneSonnenstand($gv_lat, $gv_lon, $gv_elev);
  $plugin_info{$plugname.'_elevation'} = $gv_elevation;
  $plugin_info{$plugname.'_azimuth'} = $gv_azimuth;
  # Azimuth und Elevation im RRD aufzeichnen (für schöne Kurve auf der Visu)
  update_rrd("MyAzimuth","",$gv_azimuth);
  update_rrd("MyElevation","",$gv_elevation);
 }

 # Prüfen, ob die Beschattung aktiviert oder deaktiviert werden muss
 if ($plugin_info{$plugname.'_beschattungEin'} eq BESCHATTUNG_EIN and $plugin_info{$plugname.'_beschattungFreigabe'} eq FREIGABE_AUS) {
  #($gv_sekunden, $gv_minuten, $gv_stunden, $gv_monatstag, $gv_monat, $gv_jahr, $gv_wochentag, $gv_jahrestag, $gv_sommerzeit) = localtime(time);
  $gv_zeitpunkt = $gv_minuten + ($gv_stunden*60);
  $gv_zeitdifferenz = $gv_zeitpunkt - $plugin_info{$plugname.'_beschattungEinTime'};
  if ($gv_zeitdifferenz > 5) {
   $plugin_info{$plugname.'_beschattungFreigabe'} = FREIGABE_EIN;
  }
 } elsif ($plugin_info{$plugname.'_beschattungEin'} eq BESCHATTUNG_AUS and $plugin_info{$plugname.'_beschattungFreigabe'} eq FREIGABE_EIN) {
  #($gv_sekunden, $gv_minuten, $gv_stunden, $gv_monatstag, $gv_monat, $gv_jahr, $gv_wochentag, $gv_jahrestag, $gv_sommerzeit) = localtime(time);
  $gv_zeitpunkt = $gv_minuten + ($gv_stunden*60);
  $gv_zeitdifferenz = $gv_zeitpunkt - $plugin_info{$plugname.'_beschattungEinTime'};
  if ($gv_zeitdifferenz > 15) {
   $plugin_info{$plugname.'_beschattungFreigabe'} = FREIGABE_AUS;
  }
 }

 # Beschattungs-Automatik
 if ($plugin_info{$plugname.'_sperre'} == SPERRE_INAKTIV) {
  # Automatik läuft grundsätzlich
  foreach $gs_raffstore (@gt_raffstores) {
   if ($gs_raffstore->{aktiv} eq AKTIV and
       $gs_raffstore->{sperre} == SPERRE_INAKTIV and
       $gs_raffstore->{automatik} eq AUTOMATIK_EIN) {

	# Automatik ist aktiv -> also mach nun deine Arbeit
	if ($plugin_info{$plugname.'_beschattungFreigabe'} eq FREIGABE_AUS) {
	 # Freigabe ist aufgrund der Helligkeit nicht notwendig -> Raffstore nach oben!

	 # Aber nur, wenn es sich um den ersten Lauf nach Ende der Freigabe handelt!
	 if ($plugin_info{$plugname.'_beschattungFreigabeOld'} eq FREIGABE_EIN) {
	  # Raffstores hoch
	  $gv_rolloPos = knx_read($gs_raffstore->{gaRolloPosRM}, 5.001);
	  $gv_lamellePos = knx_read($gs_raffstore->{gaLamellePosRM}, 5.001);
	  if ($gv_rolloPos != 0) {
	   knx_write($gs_raffstore->{gaRolloPos}, 0, 5.001);
	  }
	  if ($gv_lamellePos != 0) {
	   knx_write($gs_raffstore->{gaLamellePos}, 0, 5.001);
	  }
	 }
	} else {
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
	 # Aktuelle Sonnenposition verwenden um zu bestimmen, ob der Raffstore gerade beschattet werden muss
	 if ($plugin_info{$plugname.'_azimuth'} >= $gv_startWinkel and
	     $plugin_info{$plugname.'_azimuth'} <= $gv_endWinkel ) {
	
	  # Beschattung aufgrund der Ausrichtung

	  # Raffstore runter
	  $gv_rolloPos = knx_read($gs_raffstore->{gaRolloPosRM}, 5.001);
	  $gv_lamellePos = knx_read($gs_raffstore->{gaLamellePosRM}, 5.001);
	  if ($gv_rolloPos != 100) {
	   knx_write($gs_raffstore->{gaRolloPos}, 100, 5.001);
	  }
	  
	  # Lamellennachführung
	  #$gv_lamellePosNeu = (90 - $plugin_info{$plugname.'_elevation'})/90*100;
	  #if ($gv_lamellePos != $gv_lamellePosNeu) {
	   #knx_write($gs_raffstore->{gaLamellePos}, 100, 5.001);
	  #}
	  
      if ($gv_minuten % 5 == 0) {
	   if ($gs_raffstore->{lamellenNachfuehrung} eq NACHF_AUS) {
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
	   if (abs($gv_lamellePos - $gv_lamellePosNeu) > 2) {
	    knx_write($gs_raffstore->{gaLamellePos},$gv_lamellePosNeu,5.001);
	   }
	  }
	 } else {
	  # Keine Beschattung aufgrund der Ausrichtung

	  # Raffstore hoch
	  $gv_rolloPos = knx_read($gs_raffstore->{gaRolloPosRM}, 5.001);
	  $gv_lamellePos = knx_read($gs_raffstore->{gaLamellePosRM}, 5.001);
	  if ($gv_rolloPos != 0) {
	   knx_write($gs_raffstore->{gaRolloPos}, 0, 5.001);
	  }
	  if ($gv_lamellePos != 0) {
	   knx_write($gs_raffstore->{gaLamellePos}, 0, 5.001);
	  }
	 }
	}
   }
  }
 }
}

# Dynamische Werte der Raffstore-Definition im plugin_info merken
@gt_raffstores_dyn = ();
foreach $gs_raffstore (@gt_raffstores) {
 unshift(@gt_raffstores_dyn, join(SEPARATOR2, $gs_raffstore->{id}, $gs_raffstore->{aktiv}, $gs_raffstore->{sperre}, $gs_raffstore->{automatik}));
}
$gv_raffstore_dyn = join(SEPARATOR1, @gt_raffstores_dyn);
$plugin_info{$plugname.'_gt_raffstores_dyn'} = $gv_raffstore_dyn;


####################################################
# Aufruf mit berechneSonnenstand($lat, $lon, $elev);
####################################################
sub berechneSonnenstand {
 # Aktuelle Zeit
 my $lv_time = time ();
 # Die eigenen Koordinaten
 my $lv_loc = Astro::Coord::ECI->geodetic(deg2rad(shift), deg2rad(shift), shift);
 # Sonne instanzieren
 my $lv_sun = Astro::Coord::ECI::Sun->universal($lv_time);
 # Feststellen wo die Sonne gerade ist
 my ($lv_azimuth, $lv_elevation, $lv_range) = $lv_loc->azel($lv_sun);
 $lv_azimuth = rad2deg($lv_azimuth);
 $lv_elevation = rad2deg($lv_elevation);
 return ($lv_azimuth, $lv_elevation);
}
