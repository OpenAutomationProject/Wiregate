######################################################################################
#
# Plugin RollladenAutomatik
# V0.5 2011-06-10
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
#
# TODO: Was teilweise integriert ist aber noch nicht komplett ist:
#	- Nur zufahren, wenn es im Raum warm genug ist
#	- Wetterstation einbinden: Helligkeit, Sonnenschein, Dämmerung
# 	- Bei Fensterdefinition auch Elevation oben bzw. unten angeben
#	- Jalousie Lamellenführung
#	- Vorwarnpositionsfahrten?
#	- Englisch oder Deutsch?
#	- Außentemperaur
######################################################################################


#########################
### BEGINN DEFINITION ###
#########################

# Die Koordinaten des Hauses. Sehr einfach über http://www.getlatlon.com/ zu ermitteln.
# Und die Höhe über NN
my ($lat, $lon, $elev) = (
    49.02917390736781, # Breitengrad in Grad
    8.570709228515625, # Längengrad in Grad
    180 / 1000 # Höhe über NN in Kilometer (dewegen geteilt durch 1000)
    );

# Elevation der Sonne, ab der es abends dunkel ist bzw. morgens hell ist.
# Bürgerliche Dämmerung ist bei -6 Grad.
my $daemmerung = -3;

# Gruppenadresse, über welche die komplette Automatik für alle Rollläden gesperrt werden kann
my $GASperreAlle = "0/0/125";

# Bugfix für KNX-Schnittstellen die sich bei zu schneller Telegrammabfolge
# verschlucken, und denen wir deshalb die Geschwindigkeit der Telegramme drosseln müssen
# 0 = nicht anschalten (Telegramme mit voller Geschwindigkeit abfeuern)
# 1 = anschalten (Telegramme um 20 millisekunden verzögern)
# nur für "Busch-Jäger 6196 USB REG" ist bekannt das dies benötigt wird
my $bugfixSlowInterface = 0;

# Ein Array von Hashes, wobei jeder Hash ein Rollladen/Fenster/Raum ist.
my @AlleRolllaeden;
# Name des Rolladen					
# 	name => "Speisekammer"
# Winkel zum Norden, ab dem das Fenster beschienen wird.
# Echter Osten = 90°, echter Süden = 180°, echter Westen = 270°, echter Norden = 0°
# 	winkel1 => 66	
# Winkel zum Norden, bis zu dem das Fenster beschienen wird
# 	winkel2 => 186
# Richtung bei Beschattung: wenn 1 wird DPT3 angenommen und ganz zugefahren.
# Bei ungleich 1, wird DPT5 angenommen und Position angefahren
# 	wertZuBesch => 1
# Richtung bei keiner Beschattung: wenn 0 wird DPT3 angenommen und ganz aufgefahren.
# Bei ungleich 0, wird DPT5 angenommen und Position angefahren
# 	wertAufBesch => 0
# Richtung bei Nacht: wenn 1 wird DPT3 angenommen und ganz zugefahren.
# Bei ungleich 1, wird DPT5 angenommen und Position angefahren
# 	wertZuNacht => 1
# Richtung bei keiner Nacht: wenn 0 wird DPT3 angenommen und ganz aufgefahren.
# Bei ungleich 0, wird DPT5 angenommen und Position angefahren
# 	wertAufNacht => 0
# Ob der Rollladen in die Automatik für Sonnenauf- und untergang einbezogen werden soll
# 	sonnenAufUnter => 1		
# Raum-Solltemperatur, wenn keine GA angegeben wurde oder kein Wert vom Bus gelesen wurde
# 	raumSollTemp => 22
# GA der Raum-Solltemperatur
# 	GAraumsollTemp => "0/0/127"
# GA der Raum-Isttemperatur
# 	GAraumIstTemp => "0/0/128"
# GA um Rollladen zu fahren TODO:Sollte man hier mehrere GAs angeben können?
# 	GAfahren => "0/0/126"
# GA um die Automatik dieses einen Rollladen zu sperren
# 	GAsperre=> "0/0/129"
push @AlleRolllaeden, { name => "Speisekammer", winkel1 => 66, winkel2 => 186, wertZuBesch => 1, wertAufBesch => 0, 
			wertZuNacht => 1, wertAufNacht => 0, sonnenAufUnter => 1, raumSollTemp => 22, GAraumSollTemp => "0/0/127", 
			GAraumIstTemp => "0/0/128", GAfahren => "2/1/11", GAsperre => "0/0/129" };
push @AlleRolllaeden, { name => "Küche", winkel1 => 194, winkel2 => 294, wertZuBesch => 80, wertAufBesch => 2, 
			wertZuNacht => 100, wertAufNacht => 2, sonnenAufUnter => 1, raumSollTemp => 22, GAraumSollTemp => "0/0/127", 
			GAraumIstTemp => "0/0/128", GAfahren => "2/2/3", GAsperre => "0/0/129" };
push @AlleRolllaeden, { name => "Kind Strasse", winkel1 => 182, winkel2 => 294, wertZuBesch => 86, wertAufBesch => 2, 
			wertZuNacht => 100, wertAufNacht => 2, sonnenAufUnter => 0, raumSollTemp => 22, GAraumSollTemp => "0/0/127", 
			GAraumIstTemp => "0/0/128", GAfahren => "2/3/13", GAsperre => "0/0/129" };
push @AlleRolllaeden, { name => "Kind Friedhof", winkel1 => 182, winkel2 => 294, wertZuBesch => 86, wertAufBesch => 2, 
			wertZuNacht => 100, wertAufNacht => 2, sonnenAufUnter => 0, raumSollTemp => 22, GAraumSollTemp => "0/0/127", 
			GAraumIstTemp => "0/0/128", GAfahren => "2/3/23", GAsperre => "0/0/129" };
push @AlleRolllaeden, { name => "Schlafen", winkel1 => 359, winkel2 => 359, wertZuBesch => 82, wertAufBesch => 2, 
			wertZuNacht => 100, wertAufNacht => 2, sonnenAufUnter => 0, raumSollTemp => 22, GAraumSollTemp => "0/0/127", 
			GAraumIstTemp => "0/0/128", GAfahren => "2/3/3", GAsperre => "0/0/129" };

#######################
### ENDE DEFINITION ###
#######################


# Festlegen, dass das Plugin alle 5 Minuten laufen soll
$plugin_info{$plugname.'_cycle'} = 300;

# Auf die GA der globalen Sperre anmelden
#TODO: muss man sich überhaupt auf die GA anmelden. Sollte doch reichen wenn man den letzten Stand liest...
$plugin_subscribe{$GASperreAlle}{$plugname} = 1;
# Fals global gesperrt, Plugin-Durchgang beenden
if (knx_read($GASperreAlle, 0, 1) == 1) {
	return "Global gesperrt";
}

# Sonnenstands-Berechnungen durchführen
my ($azimuth, $elevation) = berechneSonnenstand($lat, $lon, $elev);
# Auslesen wo die Sonne beim letzten Durchgang war
my $lastAzimuth = $plugin_info{$plugname.'_lastAzimuth'};
my $lastElevation = $plugin_info{$plugname.'_lastElevation'};

# Teste ob es Nacht ist, oder gerade Abend- oder Morgendämmerung ist
my $testAbendDaemmerung = ($elevation < deg2rad($daemmerung) && $lastElevation > deg2rad($daemmerung)) || 0;
my $testMorgenDaemmerung = ($elevation > deg2rad($daemmerung) && $lastElevation < deg2rad($daemmerung)) || 0;
my $testNacht = ($elevation < deg2rad($daemmerung)) || 0;
# Los gehts. Jeden Rolladen/Fenster/Raum abarbeiten.
foreach my $element (@AlleRolllaeden) {
	# Falls gesperrt, mit nächstem Rollladen fortfahren
	if (knx_read($element->{GAsperre}, 0, 1) == 1) {
		next;
	}
	# Die Einfallwinkel in Radians umrechnen
	my $winkel1 = deg2rad($element->{winkel1});
	my $winkel2 = deg2rad($element->{winkel2});

	# Teste ob das Fenster beschienen wird
	my $testAktuellBeschienen = ($azimuth > $winkel1 && $azimuth < $winkel2) || 0;
	my $testVoherBeschienen = ($lastAzimuth > $winkel1 && $lastAzimuth < $winkel2) || 0;
	
	# Fenster war nicht beschienen, ist jetzt beschienen, keine Nacht
	if (!$testVoherBeschienen && $testAktuellBeschienen && !$testNacht) {
		fahreRollladen($element->{wertZuBesch}, $element->{GAfahren});
		plugin_log($plugname,"Name: " . $element->{name} . "; Wegen Sonne zufahren bei: " . round(rad2deg($azimuth)));
	}
	# Fenster ist nicht beschienen, war beschienen, keine Nacht
	if ($testVoherBeschienen && !$testAktuellBeschienen && !$testNacht) {
		fahreRollladen($element->{wertAufBesch}, $element->{GAfahren});
		plugin_log($plugname,"Name: " . $element->{name} . "; Wegen Sonne auffahren bei: " . round(rad2deg($azimuth)));
	}
	# AbendDaemmerung
	if ($testAbendDaemmerung && $element->{sonnenAufUnter}) {
		fahreRollladen($element->{wertZuNacht}, $element->{GAfahren});
		plugin_log($plugname,"Name: " . $element->{name} . "; Wegen Abenddaemmerung zufahren bei: " . round(rad2deg($azimuth)));
	}
	# MorgenDaemmerung
	if ($testMorgenDaemmerung && $element->{sonnenAufUnter}) {
		fahreRollladen($element->{wertAufNacht}, $element->{GAfahren});
		plugin_log($plugname,"Name: " . $element->{name} . "; Wegen Morgendaemmerung auffahren bei: " . round(rad2deg($azimuth)));
	}
}

# Für die nächste Iteration den aktuellen Sonnenstand merken
# TODO: Müsste man sich nicht eigentlich für jedes Element den Zustand merken, ob es auf- oder zugefahren wurde???
#	lastAzimuth ging noch als nur der Sonnenstand entscheidend war, ob gefahren wird. Jetzt aber auch lokale Sperre, 
#	IstTemperatur, Sonnenschein.
$plugin_info{$plugname.'_lastAzimuth'} = $azimuth;
$plugin_info{$plugname.'_lastElevation'} = $elevation;
# Ende
return "Grad gegen Norden: " . round(rad2deg($azimuth)) . "; Grad ueber Horizont: " . round(rad2deg($elevation));


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
	my ($richtung, $GA) = @_;
	if ($richtung == 0 || $richtung == 1) {
		# Auf/Zu fahren
		knx_write($GA,$richtung,3);		
	}
	else {
		# Position anfahren
		knx_write($GA,$richtung,5);
	}
	# kurze Pause, falls das benutzte Interface das braucht...
        if ($bugfixSlowInterface) {
        	usleep(20000);
	}
}

