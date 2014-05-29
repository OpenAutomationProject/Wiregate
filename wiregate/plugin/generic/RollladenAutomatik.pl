######################################################################################
# Plugin RollladenAutomatik
# V0.9 2014-05-29
# Lizenz: GPLv2
# Autoren: kleinklausi (http://knx-user-forum.de/members/kleinklausi.html)
#          krumboeck (http://knx-user-forum.de/members/krumboeck.html)
# Benötigt: libastro-satpass-perl -> 'apt-get install libastro-satpass-perl'
#
# Ein Wiregate Plugin zum automatischen Fahren der Rollläden. Es berechnet unter Anderem 
# den Stand der Sonne und fährt je nach Winkel der Sonne zum Fenster, den Rollladen in 
# eine Beschattungsposition. Folgende Funktionen werden unterstützt:
#	- Sonnenstand (Azimuth)
#	- Anfangs- und Endwinkel (Azimuth) ab dem das Fenster beschienen wird
#	- Globale Sperre duch eine Gruppenadresse
#	- Sperre eines einzelnen Rollladens durch eine Gruppenadresse
#	- Fahren des Rollladen zu (1) oder auf (0) oder Positionsfahren mit Prozentwert
#	- Zufahren bei Dunkelheit am Abend und Hell am Morgen
#	- Bugfix für Busch-Jäger USB Schnittstelle (muss eingeschaltet werden)
#	- Vorlagen um die Konfiguration zu vereinfachen (krumboeck)
#	- Rolladenschutz vor hohen Windgeschwindigkeiten (krumboeck)
#	- Zufahren bei sehr niedgrigen Außentemperaturen um die Isolationswirkung zu erhöhen (krumboeck)
#	- Öffnen bei sehr starker Bewölkung um die Helligkeit im Raum zu erhöhen (krumboeck)
#	- Seperate Konfigurationsdatei (krumboeck)
#	- Steuerung aufgrund der Raumtemperatur (krumboeck)
#	- Hysteresewerte für Temperatur, Wind und Bewölkung (krumboeck)
#	- Speichern der Rolladenposition und aktuellen Zuständen (krumboeck)
#	- Fahren auf Positionen welche im Aktor (z.B. Siemens 523/03) gespeichert sind (krumboeck)
#	- Überprüfen von Positionen vor Sonnenauf bzw. -untergang (krumboeck)
#	- Nach Aufhebung der Sperre auf Position fahren (krumboeck)
#
# TODO: Was teilweise integriert ist aber noch nicht komplett ist:
# 	- Bei Fensterdefinition auch Elevation oben bzw. unten angeben
#	- Jalousie Lamellenführung
#	- Vorwarnpositionsfahrten?
#	- Englisch oder Deutsch?
######################################################################################


#########################
### BEGINN DEFINITION ###
#########################

use constant HIGHER => 1;
use constant EQUAL => 0;
use constant LOWER => -1;

# Die Koordinaten des Hauses. Sehr einfach über http://www.getlatlon.com/ zu ermitteln.
# Und die Höhe über NN
my ($lat, $lon, $elev);

# Elevation der Sonne, ab der es abends dunkel ist bzw. morgens hell ist.
# Bürgerliche Dämmerung ist bei -6 Grad.
my $daemmerung = -3;

# Gruppenadresse, über welche die komplette Automatik für alle Rollläden gesperrt werden kann
my $GASperreAlle;

# Bugfix für KNX-Schnittstellen die sich bei zu schneller Telegrammabfolge
# verschlucken, und denen wir deshalb die Geschwindigkeit der Telegramme drosseln müssen
my $bugfixSlowInterface = 0;

# Ein Array von Hashes, wobei jeder Hash ein Rollladen/Fenster/Raum ist.
my @AlleRolllaeden;

# Gruppenadresse für die Windgeschwindigkeit
my $GAWindSpeed;

# Gruppenadresse für die Windgrichtung
my $GAWindDirection;

# Gruppenadresse für die Bewölkung
my $GACloudiness;

# Gruppenadresse für die Außentemperatur
my $GATemperature;


#################################
### Lesen der Konfigurationsdatei
#################################

my ($user, $pass, $name, $lat, $lon, $alt, $GAtemp);
my @TimeExclusions;

# Read config file in conf.d
my $confFile = '/etc/wiregate/plugin/generic/conf.d/'.basename($plugname,'.pl').'.conf';
if (! -f $confFile) {
	plugin_log($plugname, " no conf file [$confFile] found.");
	return "no conf file [$confFile] found.";
} else {
	open(CONF, $confFile);
	my @lines = <CONF>;
	close($confFile);
	my $result = eval("@lines");
	if ($@) {
		plugin_log($plugname, "conf file [$confFile] returned:");
		my @parts = split(/\n/, $@);
		plugin_log($plugname, "--> $_") foreach (@parts);
	}
}

# Festlegen, dass das Plugin alle 5 Minuten laufen soll
$plugin_info{$plugname.'_cycle'} = 300;

my $debug = 0;

#######################
### ENDE DEFINITION ###
#######################

if (defined $GASperreAlle) {
	# Auf die GA der globalen Sperre anmelden
	# TODO: muss man sich überhaupt auf die GA anmelden. Sollte doch reichen wenn man den letzten Stand liest...
	$plugin_subscribe{$GASperreAlle}{$plugname} = 1;
	# Fals global gesperrt, Plugin-Durchgang beenden
	if (knx_read($GASperreAlle, 0, 1) == 1) {
		return "Global gesperrt";
	}
}

my $weather = {};
if (defined $GAWindSpeed) {
	$weather->{windSpeed} = knx_read($GAWindSpeed, 1800, 9.005);
}
if (defined $GAWindDirection) {
	my $windDirection = knx_read($GAWindDirection, 1800, 5.003);
	if (defined $windDirection) {
		$weather->{windFromDirection} = ($windDirection + 180) % 360;
	}
}
if (defined $GACloudiness) {
	$weather->{cloudiness} = knx_read($GACloudiness, 1800, 5.004);
}
if (defined $GATemperature) {
	$weather->{temperature} = knx_read($GATemperature, 1800, 9.001);
}

# Sonnenstands-Berechnungen durchführen
my ($azimuth, $elevation) = berechneSonnenstand($lat, $lon, $elev);

# Auslesen wo die Sonne beim letzten Durchgang war
my $lastAzimuth = $plugin_info{$plugname.'_lastAzimuth'};
my $lastElevation = $plugin_info{$plugname.'_lastElevation'};

my %rolllaeden;
foreach my $element (@AlleRolllaeden) {
	$rolllaeden{$element->{name}} = $element;
}

# Los gehts. Jeden Rolladen/Fenster/Raum abarbeiten.
foreach my $element (@AlleRolllaeden) {

	if (defined $element->{istVorlage} && $element->{istVorlage}) {
		next;
	}

	my $rolladen = berechneRolladenParameter($element, 0);

	if (defined $rolladen->{GAsperre}) {
		$plugin_subscribe{$rolladen->{GAsperre}}{$plugname} = 1;
		# Falls gesperrt, mit nächstem Rollladen fortfahren
		if (knx_read($rolladen->{GAsperre}, 0, 1) == 1) {
			speichereRolladenParameter($rolladen, "locked", 1);
			plugin_log($plugname,"Name: " . $rolladen->{name} . "; Sperre für Rolladen wurde empfangen");
			next;
		}
	}

	# Ermittle gewünschte Position und Grund des Fahrens für den Rollladen
	my ($position, $bemerkung) = berechneRolladenposition($rolladen, $azimuth, $elevation, $lastAzimuth, $lastElevation, $daemmerung, $weather);

	# Fahre den Rollladen wenn es einen Positionswunsch gibt
	if (defined $position) {

		if ($position =~ m/((\d+|\*));Position:(\d+)/) {
			if (positionChanged($rolladen, $position)) {
				ladeRollladenPosition($rolladen, $position, $3);
				plugin_log($plugname,"Name: " . $rolladen->{name} . " (Lade Pos); " . $bemerkung);
			}
		} else {
			if (positionChanged($rolladen, $position)) {
				fahreRollladen($rolladen, $position);
				plugin_log($plugname,"Name: " . $rolladen->{name} . "; " . $bemerkung);
			}
		}
	} elsif (defined $rolladen->{debug} && $rolladen->{debug}) {
		plugin_log($plugname,"Name: " . $rolladen->{name} . "; Fahren wird fuer diesen Zyklus ausgesetzt");
	}

}

# Für die nächste Iteration den aktuellen Sonnenstand merken
$plugin_info{$plugname.'_lastAzimuth'} = $azimuth;
$plugin_info{$plugname.'_lastElevation'} = $elevation;

return "Grad gegen Norden: " . round(rad2deg($azimuth)) . "; Grad ueber Horizont: " . round(rad2deg($elevation));


############################################
# Prüft ob der Rolladen gefahren werden muss
############################################
sub positionChanged {
	my ($rolladen, $newPosition) = @_;

	# Ermittle die aktuelle Position
	my $lastPosition = ladeRolladenParameter($rolladen, "position");

	my $testAbendDaemmerung = ($elevation < deg2rad($daemmerung) && $lastElevation > deg2rad($daemmerung)) || 0;
	my $testMorgenDaemmerung = ($elevation > deg2rad($daemmerung) && $lastElevation < deg2rad($daemmerung)) || 0;

	my $testLockChanged = 0;
	if (defined $rolladen->{GAsperre}) {
		my $parameterLocked = ladeRolladenParameter($rolladen, "locked");
		if (defined $parameterLocked && $parameterLocked && knx_read($rolladen->{GAsperre}, 0, 1) == 0) {
			speichereRolladenParameter($rolladen, "locked", 0);
			if (defined $rolladen->{pruefePositionNachSperre} && $rolladen->{pruefePositionNachSperre}) {
				$testLockChanged = 1;
			}
		}
	}

	my $newPositionValue = $newPosition;
	if ($newPosition =~ m/((\d+|\*));Position:(\d+)/) {
		$newPositionValue = $1;
	}
	my $lastPositionValue = $lastPosition;
	if ($lastPosition =~ m/((\d+|\*));Position:(\d+)/) {
		$lastPositionValue = $1;
	}

	if ((defined $rolladen->{pruefePositionSonnenAufUnter} && $rolladen->{pruefePositionSonnenAufUnter} == 1
			&& ($testAbendDaemmerung || $testMorgenDaemmerung))
		|| $testLockChanged
		|| (($lastPosition ne $newPosition) && ($lastPositionValue eq "*"))) {
		if (defined $rolladen->{GAistPos}) {
			$lastPositionValue = knx_read($rolladen->{GAistPos}, 0, 5.001);
			$lastPositionValue = sprintf("%d", $lastPositionValue);
			if (defined $rolladen->{debug} && $rolladen->{debug}) {
				plugin_log($plugname,"Name: " . $rolladen->{name} . "; Rollladen meldete Position: " . $lastPosition);
			}
		} elsif ($testLockChanged) {
			$lastPositionValue = -1;
		} else {
			plugin_log($plugname,"Name: " . $rolladen->{name} . "; Konfiguration benötigt GAistPos für diesen Rollladen");
		}
	}

	if ($newPosition == 1) {
		$newPosition = 100;
	}
	if ($newPositionValue == 1) {
		$newPositionValue = 100;
	}
	if (defined $rolladen->{debug} && $rolladen->{debug}) {
		plugin_log($plugname,"Name: " . $rolladen->{name} . "; Last-Pos: " . $lastPosition . "; Pos: " . $newPosition);
		plugin_log($plugname,"Name: " . $rolladen->{name} . "; Last-Pos-Value: " . $lastPositionValue . "; Pos-Value: " . $newPositionValue);
	}
	if (($lastPosition ne $newPosition) || ($newPositionValue <= ($lastPositionValue - 1)) || ($newPositionValue >= ($lastPositionValue + 1))) {
		return 1;
	} else {
		return 0;
	}
}

###################################
# Berechne Parameter eines Rolladen
###################################
sub berechneRolladenParameter {
	my ($rolladen, $counter) = @_;
	if ($counter > 20) {
		die $plugname . "Name: " . $rolladen->{name} . "; Endlosschleife bei Templates";
	}
	if (defined $rolladen->{vorlage}) {
		my $template = berechneRolladenParameter($rolllaeden{$rolladen->{vorlage}}, $counter + 1);
		foreach my $key (keys (%$template)) {
			if (!defined $rolladen->{$key}) {
				if ($debug) {
					plugin_log($plugname,"Name: " . $rolladen->{name} . "; Uebernehme Parameter " . $key . " aus Template " . $template->{name});
				}
				$rolladen->{$key} = $template->{$key};
			}
		}
	}
	return $rolladen;
}


####################################################
# Aufruf mit berechneSonnenstand($lat, $lon, $elev);
####################################################
sub berechneSonnenstand {
	# Module laden
	use Astro::Coord::ECI;
	use Astro::Coord::ECI::Sun;
	use Astro::Coord::ECI::TLE;
	use Astro::Coord::ECI::Utils qw{rad2deg deg2rad};
	# Aktuelle Zeit
	my $time = time ();
	# Die eigenen Koordinaten
	my $loc = Astro::Coord::ECI->geodetic(deg2rad(shift), deg2rad(shift), shift);
	# Sonne instanzieren
	my $sun = Astro::Coord::ECI::Sun->universal($time);
	# Feststellen wo die Sonne gerade ist
	my ($azimuth, $elevation, $range) = $loc->azel($sun);
	return ($azimuth, $elevation);
}


##################################
# Berechne Position eines Rolladen
##################################
sub berechneRolladenposition {
	my ($element, $azimuth, $elevation, $lastAzimuth, $lastElevation, $daemmerung, $weather) = @_;

	# Die Einfallwinkel in Radians umrechnen
	my $winkel1 = deg2rad($element->{winkel1});
	my $winkel2 = deg2rad($element->{winkel2});

        # Teste ob das Fenster beschienen wird
        my $testAktuellBeschienen = ($azimuth > $winkel1 && $azimuth < $winkel2) || 0;
        my $testVoherBeschienen = ($lastAzimuth > $winkel1 && $lastAzimuth < $winkel2) || 0;

	# Test ob Nacht oder Daemmerung
	my $testAbendDaemmerung = ($elevation < deg2rad($daemmerung) && $lastElevation > deg2rad($daemmerung)) || 0;
	my $testMorgenDaemmerung = ($elevation > deg2rad($daemmerung) && $lastElevation < deg2rad($daemmerung)) || 0;
	my $testNacht = ($elevation < deg2rad($daemmerung)) || 0;

	my ($position, $bemerkung);

	if (defined $element->{maxWindGeschw}) {
		if (defined $weather->{windSpeed}) {
			my $compare = vergleicheWert($weather->{windSpeed}, $element->{maxWindGeschw}, $element->{windGeschwHysterese});
			if ($compare == HIGHER) {
				speichereRolladenParameter($element, "windProtection", 1);
			}
			if ($compare == LOWER) {
				speichereRolladenParameter($element, "windProtection", 0);
			}
		}
		my $windProtection = ladeRolladenParameter($element, "windProtection");
		if (defined $windProtection && $windProtection) {
			$position = $element->{wertAufSchutz} || 0;
			$bemerkung = "Wegen zu hoher Windgeschwindigkeit auffahren bei " + $weather->{windSpeed} . " km/h";
			return ($position, $bemerkung);
		}
	}

	if ($element->{sonnenAufUnter}) {
		if ($testNacht) {
			$position = $element->{wertZuNacht};
			$bemerkung = "Wegen Abenddaemmerung zufahren bei: " . round(rad2deg($azimuth));
			return ($position, $bemerkung);
		} elsif ($testMorgenDaemmerung) {
			$position = $element->{wertAufNacht};
			$bemerkung = "Wegen Morgendaemmerung auffahren bei: " . round(rad2deg($azimuth));
		}
	}

	# Fenster wird von der Sonne beschienen
	if (!$testVoherBeschienen && $testAktuellBeschienen) {
		$position = $element->{wertZuBesch};
		$bemerkung = "Wegen Sonne zufahren bei: " . round(rad2deg($azimuth));
	} elsif ($testVoherBeschienen && !$testAktuellBeschienen) {
		$position = $element->{wertAufBesch};
		$bemerkung = "Wegen Sonne auffahren bei: " . round(rad2deg($azimuth));
	}

	my $testTempNiedrig = 0;
	my $testTempHoch = 0;
	if (!$testNacht && $testAktuellBeschienen && $element->{tempGesteuert}) {
		# Solltemperatur für den Raum feststellen
		my $sollTemp;
		if (defined $element->{GAraumSollTemp}) {
			$sollTemp = knx_read($element->{GAraumSollTemp}, 300, 9);
		}
	        if (!defined $sollTemp) {
	        	$sollTemp = $element->{raumSollTemp};
	        }

		# Aktuelle Temperatur für den Raum feststellen
		my $istTemp = knx_read($element->{GAraumIstTemp}, 300, 9);

		if (defined $sollTemp && defined $istTemp) {
			my $tempHysterese = $element->{tempHysterese};
			if (!defined $tempHysterese) {
				$tempHysterese = 1;
			}
	 		$testTempNiedrig = ($istTemp < ($sollTemp - $tempHysterese));
		 	$testTempHoch = ($istTemp > ($sollTemp + $tempHysterese));

			# Fenster ist beschienen, Rolladen ist zu und Temperatur ist zu niedrig
			if ($testTempNiedrig) {
				$position = $element->{wertAufBesch};
				$bemerkung = "Wegen Temperatur auffahren bei: " . $istTemp . ' °C';
			}

			# Fenster ist beschienen, Rolladen ist offen und Temperatur ist zu hoch
			if ($testTempHoch) {
				$position = $element->{wertZuBesch};
				$bemerkung = "Wegen Temperatur zufahren bei: " . $istTemp . ' °C';
			}
		} else {
			plugin_log($plugname,"Name: " . $element->{name} . "; Temperatur konnte nicht festgestellt werden");
			return (undef, undef);
		}
	}

	if (!$testNacht
		&& $testAktuellBeschienen
		&& defined $element->{maxBewoelkung}) {
		if (defined $weather->{cloudiness}) {
			my $compare = vergleicheWert($weather->{cloudiness}, $element->{maxBewoelkung}, $element->{bewoelkungHysterese});
			if ($compare == HIGHER) {
				speichereRolladenParameter($element, "overclouded", 1);
			}
			if ($compare == LOWER) {
				speichereRolladenParameter($element, "overclouded", 0);
			}
		}
		my $overclouded = ladeRolladenParameter($element, "overclouded");
		if (defined $overclouded && $overclouded) {
			$position = $element->{wertAufBesch};
			$bemerkung = "Wegen Bewoelkung auffahren bei: " . $weather->{cloudiness} . ' %';
		}
	}

	if (defined $element->{minAussenTemp}) {
		if (defined $weather->{temperature}) {
			my $compare = vergleicheWert($weather->{temperature}, $element->{minAussenTemp}, $element->{aussenTempHysterese});
			if ($compare == LOWER) {
				speichereRolladenParameter($element, "tempProtection", 1);
			}
			if ($compare == HIGHER) {
				speichereRolladenParameter($element, "tempProtection", 0);
			}
		}
		my $tempProtection = ladeRolladenParameter($element, "tempProtection");
		if (defined $tempProtection && $tempProtection) {
			$position = $element->{wertZuSchutz} || 1;
			$bemerkung = "Wegen zu niedriger Temperatur zufahren bei " + $weather->{temperature} . ' °C';
		}
	}

	return ($position, $bemerkung);
}


######################################################################
# Prüfen ob der aktuelle Wert eine Grenze über bzw. unterschritten hat
######################################################################
sub vergleicheWert {
	my ($currentValue, $reference, $hysterese) = @_;
	my $current = EQUAL;
	my $last = EQUAL;
	if (!defined $hysterese) {
		$hysterese = 0;
	}
	if ($currentValue < ($reference - $hysterese)) {
		$current = LOWER;
	}
	if ($currentValue > ($reference + $hysterese)) {
		$current = HIGHER;
	}
	return $current;
}


####################################################
# Aufruf mit fahreRollladen($richtung, $GA);
####################################################
sub fahreRollladen {
	# Falls $richtung 0 oder 1 ist, wird angenommen, dass der Rollladen
	# komplett zu- bzw. aufgefahren werden soll (DPT3).
	# Bei $richtung>1 wird angenommen, dass eine Positionsfahrt
	# durchgeführt werden soll (DPT5).
	# TODO: man muss bei Positionsfahrt für den Offen-Zustand mindestens 2% angeben...
	#	hm, wenn man die GAs ins Wiregate importiert hat, bräuchte man keinerlei 
	#	Unterscheidung mehr! Und man kann auch 0% bzw 1% benutzen
	my ($rolladen, $richtung) = @_;
	my $GA = $rolladen->{GAfahren};

	if (defined $rolladen->{debug} && $rolladen->{debug}) {
		plugin_log($plugname, "Name: " . $rolladen->{name} . "; Fahre Rolladen Position: " . $richtung);
	}

	if ($richtung == 0 || $richtung == 1) {
		# Auf/Zu fahren
		knx_write($GA,$richtung,3);		
	} else {
		# Position anfahren
		knx_write($GA,$richtung,5);
	}

	# Position speichern
	if ($richtung == 1) {
		$richtung = 100;
	}
	speichereRolladenParameter($rolladen, "position", $richtung);

	# kurze Pause, falls das benutzte Interface das braucht...
        if ($bugfixSlowInterface) {
        	usleep(20000);
	}
}

####################################################
# Aufruf mit fahreRollladen($richtung, $GA);
####################################################
sub ladeRollladenPosition {
	my ($rolladen, $wert, $position) = @_;

	if (! defined $rolladen->{GAladePos}) {
		plugin_log($plugname,"Name: " . $rolladen->{name} . "; Wert für GAladePos ist nicht definiert!");
		return;
	}

	if (defined $rolladen->{debug} && $rolladen->{debug}) {
		plugin_log($plugname, "Name: " . $rolladen->{name} . "; Fahre zur gespeicherten Position: " . $position);
	}

	knx_write($rolladen->{GAladePos}, $position, 1.001);

	speichereRolladenParameter($rolladen, "position", $wert);

	# kurze Pause, falls das benutzte Interface das braucht...
        if ($bugfixSlowInterface) {
        	usleep(20000);
	}
}

########################################
# Parameter für einen Rolladen speichern
########################################
sub speichereRolladenParameter {
	my ($rolladen, $parameter, $value) = @_;
	$plugin_info{$plugname . '_Rolladen_' . $rolladen->{GAfahren} . "_" . $parameter} = $value;
}


####################################
# Parameter für einen Rolladen laden
####################################
sub ladeRolladenParameter {
	my ($rolladen, $parameter) = @_;
	return $plugin_info{$plugname . '_Rolladen_' . $rolladen->{GAfahren} . "_" . $parameter};
}

