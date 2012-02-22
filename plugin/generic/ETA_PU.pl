# Plugin: Schnittstelle zum Pelletskessel ETA-PU
# Version 1.0
# License: GPL (v3)

# Dieses Plugin dient als Schnittstelle zwischen KNX und dem ETA Heizkessel PU (Pellets Unit).
# Verwendet wird hierbei die ETAtouch RESTful Webservices Schnittstelle, die mit der Anbindung
# des Kessels an www.meineta.at zur Verfügung steht.
#
# Eine Beschreibung der Schnittstelle ist unter diesem Link verfügbar:
# https://www.meineta.at/user/download.action?contentType=application%2Fpdf&file=ETA-RESTful-v1.pdf
# CAN-BUS-URI können in der XML-Datei für die Menüstruktur entnommen werden:
# http://ip:port/user/menu


# Aktuell werden folgende Features unterstützt:
# 1.	Lesen von festgelegten Kesseldaten in einem festgelegten Intervall (aktuell 1 Minute):
#		- Schreiben der Kesselwerte auf KNX-Gruppenadressen 
#		  > DPT wird über ein Mapping der Einheiten bestimmt)
#		- Schreiben von Statustexten auf KNX-Gruppenadressen(DPT wird über ein Mapping der Einheiten bestimmt)
#		  > DPT wird über Import der Gruppenadressen ins Wiregate bestimmt
#       - Aufzeichnen der Kesselwerte in RRD für Messwerte (GAUGE)
#		  > RRD wird mit Standardparametern automatisch angelegt
#		- Aufzeichnen von Tageswerten auf Basis von Zählerständen des Kessel in RRD für Zähler (COUNTER)
#		  > RRD wird mit den entsprechenden Parametern automatisch angelegt, falls noch vorhanden
# 2.	Lesen der Meldungen der Kesselsteuerung in einem festgelegten Intervall (aktuell 1 Minute)
#		- Schreiben einer Status Grupenadresse: Meldung Ja/Nein
#		- Schreiben der Anzahl der Meldungen auf eine Gruppenadresse
# 3. 	Empfangen von KNX-Schreibtelegrammen von festgelegten KNX-Gruppenadressen 
#    	und Schreiben in die Steuerung des Kessels. 
#    	Achtung: Es dürfen nicht die selben Gruppenadressen wie beim Lesen der Kesseldaten verwendet werden!!!


# Folgende Features werden aktuell durch das Plugin noch nicht unterstützt:
# -	Empfangen von KNX-Lesetelegrammen von festgelegten KNX-Gruppenadressen,
#	Lesen der entsprechenden Kesseldaten und Schreiben der Kesselwerte auf KNX-Gruppenadressen
# -	Schreiben der Fehlermeldungen in einen RSS-Feed
#
# Folgende Features werden aktuell durch die ETAtouch RESTful Webservices Schnittstelle noch nicht unterstützt:
# -	Lesen und Schreiben auf Werte der Schaltuhren
# -	Lesen der aktuellen Pumpenleistung in %
# - Lesen und Schreiben auf Werte die mit der Service Anmeldung in der Kesselsteuerung zur Verfügung stehen
# -	Ein-/Ausschalten der Schaltuhren


# Die Fachliche Diskussion zu dem Plugin findet im knx-user-forum.de statt:
# http://knx-user-forum.de/knx-eib-forum/16767-plugin-pelletskessel-eta-pu-new-post.html 
#
# Mitwirkende bei der Entwicklung des Plugins:
# Matthias Lemke	greentux
# Sascha Bank		haegar80
# Kontaktaufnahme bitte über das knx-user-forum.de



## Beginn Definitionen ##
my $IP_PU = 			"192.168.10.11:8080";
my $ResVariables = 		"/user/vars";
my $ResSingleVariable =	"/user/var";
my $ResErrors = 		"/user/errors";
my $set =				"basic";
my $DirRrd =			"/var/www/rrd/";

my $GA_Fehler = 			"10/0/3";
my $DPT_GA_Fehler = 		"1.001";
my $GA_AnzahlFehler = 		"10/0/4";
my $DPT_GA_AnzahlFehler =	"5.010";


# Mapping ETA can-bus-uri zu Gruppenadressen für Werte aus string Rückgaben
my %string_GA_URI_mapping = (
	'10/0/0' 	=> '112/10021/0/0/12000', 	# Kessel - Kesselstatus (Text)
	'10/0/48' 	=> '112/10021/0/0/12078', 	# Kessel - UV-Speicher (Text)
	'10/0/80' 	=> '112/10101/0/0/12090', 	# Kessel - Entaschung Status (Text)
	'10/0/90' 	=> '112/10021/0/0/12248', 	# Kessel - Beginn Ruhezeit
	'10/0/95' 	=> '112/10021/0/0/12249', 	# Kessel - Dauer Ruhezeit
	'10/0/185' 	=> '112/10021/0/0/12152', 	# Kessel - Pellets Saugzeitpunkt
	'10/0/200' 	=> '112/10021/0/0/12153', 	# Kessel - Betriebsstunden (Text)

	'10/2/0' 	=> '112/10101/0/0/12090', 	# HK - Status (Text)
	'10/2/2' 	=> '112/10101/0/0/12092', 	# HK - Betrieb (Text)
	'10/2/20' 	=> '112/10101/0/0/12232', 	# HK - Urlaub Beginn
	'10/2/25' 	=> '112/10101/0/0/12239', 	# HK - Urlaub Ende

	'10/3/0' 	=> '112/10102/0/0/12090', 	# FBH - Status (Text)
	'10/3/2' 	=> '112/10102/0/0/12092', 	# FBH - Betrieb (Text)
	'10/3/20' 	=> '112/10102/0/0/12232', 	# FBH - Urlaub Beginn
	'10/3/25' 	=> '112/10102/0/0/12239', 	# FBH - Urlaub Ende

	'10/5/0' 	=> '112/10111/0/0/12129', 	# WW - Schaltzustand (Text)
);

# Mapping ETA can-bus-uri zu Gruppenadressen für Werte aus Value Rückgaben
my %value_GA_URI_mapping = (
	'10/0/1' 	=> '112/10021/0/0/12000', 		# Kessel - Kesselstatus (Code)
	'10/0/2' 	=> '112/10241/0/11149/2001',	# Kessel - Störmeldung
	'10/0/6' 	=> '112/10021/0/0/12080', 		# Kessel - I/O Taste
	'10/0/8' 	=> '112/10021/0/0/12115', 		# Kessel - Emissionsmessung
	'10/0/10' 	=> '112/10021/0/0/12001', 		# Kessel - Kessel Solltemperatur
	'10/0/11' 	=> '112/10021/0/0/12161', 		# Kessel - Isttemperatur
	'10/0/12' 	=> '112/10021/0/0/12300', 		# Kessel - Isttemperatur unten
	'10/0/21' 	=> '112/10021/0/0/12162', 		# Kessel - Abgastemperatur
	'10/0/22' 	=> '112/10021/0/0/12165', 		# Kessel - Drehzahl Abgasgebläse
	'10/0/23' 	=> '112/10021/0/0/12164', 		# Kessel - Restsauerstoff
	'10/0/40' 	=> '112/10021/0/11121/2120', 	# Kessel - VL1-Solltemperatur
	'10/0/41' 	=> '112/10021/0/11121/2121', 	# Kessel - VL1-Isttemperatur
	'10/0/45' 	=> '112/10021/0/11123/2001', 	# Kessel - Kesselpumpe 1
	'10/0/49' 	=> '112/10021/0/0/12078', 		# Kessel - UV-Speicher (Code)
	'10/0/50' 	=> '112/10021/0/11152/2120', 	# Kessel - VL2-Solltemperatur
	'10/0/51' 	=> '112/10021/0/11152/2121', 	# Kessel - VL2-Isttemperatur
	'10/0/55' 	=> '112/10021/0/11138/2001', 	# Kessel - Kesselpumpe 2
	'10/0/81' 	=> '112/10101/0/0/12090', 		# Kessel - Entaschung Status (Code)
	'10/0/86' 	=> '112/10021/0/0/12112', 		# Kessel - Entaschentaste
	'10/0/100' 	=> '112/10021/0/0/12073', 		# Kessel - Entaschen nach kg frühestens
	'10/0/103' 	=> '112/10021/0/0/12074', 		# Kessel - Entaschen nach kg spätestens
	'10/0/111' 	=> '112/10021/0/0/12120', 		# Kessel - Kübel leeren nach
	'10/0/170' 	=> '112/10201/0/0/12015', 		# Silo - Vorrat
	'10/0/175' 	=> '112/10021/0/0/12011', 		# Kessel - Pellets Behälterinhalt
	'10/0/181' 	=> '112/10021/0/0/12071', 		# Kessel - Pellets Füllen
	'10/0/201' 	=> '112/10021/0/0/12153', 		# Kessel - Betriebsstunden (Sekunden)
	'10/0/205' 	=> '112/10021/0/0/12016', 		# Kessel - Gesamtverbrauch
	'10/0/210' 	=> '112/10021/0/0/12014', 		# Kessel - kg seit Wartung
	'10/0/211' 	=> '112/10021/0/0/12012', 		# Kessel - kg seit Entaschung
	'10/0/212' 	=> '112/10021/0/0/12013', 		# Kessel - kg seit Kübel entleeren

	'10/2/1' 	=> '112/10101/0/0/12090', 		# HK - Status (Code)
	'10/2/3' 	=> '112/10101/0/0/12092', 		# HK - Betrieb (Code)
	'10/2/6' 	=> '112/10101/0/0/12080', 		# HK - I/O Taste
	'10/2/11' 	=> '112/10101/0/0/12126', 		# HK - Auto Taste
	'10/2/13' 	=> '112/10101/0/0/12125', 		# HK - Tag Taste
	'10/2/15' 	=> '112/10101/0/0/12230', 		# HK - Nacht Taste
	'10/2/17' 	=> '112/10101/0/0/12218', 		# HK - Kommen Taste
	'10/2/19' 	=> '112/10101/0/0/12231', 		# HK - Gehen Taste
	'10/2/30' 	=> '112/10101/0/0/12111', 		# HK - Solltemperatur
	'10/2/36' 	=> '112/10101/0/0/12240', 		# HK - Schieber Position
	'10/2/41' 	=> '112/10101/0/0/12104', 		# HK - Vorlauf bei -10°C
	'10/2/43' 	=> '112/10101/0/0/12103', 		# HK - Vorlauf bei +10°C
	'10/2/45' 	=> '112/10101/0/0/12107', 		# HK - Vorlauf Absenkung
	'10/2/47' 	=> '112/10101/0/0/12096', 		# HK - Heizgrenze Tag
	'10/2/49' 	=> '112/10101/0/0/12097', 		# HK - Heizgrenze Nacht
	'10/2/50' 	=> '112/10101/12095/0/1071', 	# HK - Außen verzögert (Lag x)
	'10/2/51' 	=> '112/10101/12095/0/1072', 	# HK - Außen verzögert (Lag Tf)
	'10/2/53' 	=> '112/10101/12095/0/1073', 	# HK - Außen verzögert (Lag y)

	'10/3/1' 	=> '112/10102/0/0/12090', 		# FBH - Status (Code)
	'10/3/3' 	=> '112/10102/0/0/12092', 		# FBH - Betrieb (Code)
	'10/3/6' 	=> '112/10102/0/0/12080', 		# FBH - I/O Taste
	'10/3/11' 	=> '112/10102/0/0/12126', 		# FBH - Auto Taste
	'10/3/13' 	=> '112/10102/0/0/12125', 		# FBH - Tag Taste
	'10/3/15' 	=> '112/10102/0/0/12230', 		# FBH - Nacht Taste
	'10/3/17' 	=> '112/10102/0/0/12218', 		# FBH - Kommen Taste
	'10/3/19' 	=> '112/10102/0/0/12231', 		# FBH - Gehen Taste
	'10/3/30' 	=> '112/10102/0/0/12111', 		# FBH - Solltemperatur
	'10/3/36' 	=> '112/10102/0/0/12240', 		# FBH - Schieber Position
	'10/3/41' 	=> '112/10102/0/0/12104', 		# FBH - Vorlauf bei -10°C
	'10/3/43' 	=> '112/10102/0/0/12103', 		# FBH - Vorlauf bei +10°C
	'10/3/45' 	=> '112/10102/0/0/12107', 		# FBH - Vorlauf Absenkung
	'10/3/47' 	=> '112/10102/0/0/12096', 		# FBH - Heizgrenze Tag
	'10/3/49' 	=> '112/10102/0/0/12097', 		# FBH - Heizgrenze Nacht
	'10/3/50' 	=> '112/10102/12095/0/1071', 	# FBH - Außen verzögert (Lag x)
	'10/3/51' 	=> '112/10102/12095/0/1072', 	# FBH - Außen verzögert (Lag Tf)
	'10/3/53' 	=> '112/10102/12095/0/1073', 	# FBH - Außen verzögert (Lag y)
	'10/3/60' 	=> '112/10102/12113/0/1109', 	# FBH - Zeitautomatik Schaltzustand
	'10/2/60' 	=> '112/10101/12113/0/1109', 	# HK - Zeitautomatik Schaltzustand	

	'10/5/1' 	=> '112/10111/0/0/12129', 		# WW - Schaltzustand (Code)
	'10/5/6' 	=> '112/10111/0/0/12134', 		# WW - Laden Taste
	'10/5/10' 	=> '112/10111/0/0/12132', 		# WW - Solltemperatur
	'10/5/16' 	=> '112/10111/0/0/12133', 		# WW - Einschaltdifferenz	
	'10/5/20' 	=> '112/10111/0/0/12271', 		# WW - Temperatur Speicher oben

	'10/5/60' 	=> '112/10111/12130/0/1109', 	# WW - Zeitautomatik Schaltzustand
	'10/5/61' 	=> '112/10111/12130/0/1110', 	# WW - Zeitautomatik Temperatur
);

# Mapping ETA can-bus-uri zu Gruppenadressen für Schreibaktionen
my %write_GA_URI_mapping = (
	'10/0/5' 	=> '112/10021/0/0/12080', 		# Kessel - I/O Taste
	'10/0/7' 	=> '112/10021/0/0/12115', 		# Kessel - Emissionsmessung
	'10/0/85' 	=> '112/10021/0/0/12112', 		# Kessel - Entaschentaste
	'10/0/101' 	=> '112/10021/0/0/12073', 		# Kessel - Entaschen nach kg frühestens
	'10/0/102' 	=> '112/10021/0/0/12074', 		# Kessel - Entaschen nach kg spätestens
	'10/0/110' 	=> '112/10021/0/0/12120', 		# Kessel - Kübel leeren nach	
	'10/0/180' 	=> '112/10021/0/0/12071', 		# Kessel - Pellets Füllen	

	'10/2/5' 	=> '112/10101/0/0/12080', 		# HK - I/O Taste
	'10/2/10' 	=> '112/10101/0/0/12126', 		# HK - Auto Taste
	'10/2/12' 	=> '112/10101/0/0/12125', 		# HK - Tag Taste
	'10/2/14' 	=> '112/10101/0/0/12230', 		# HK - Nacht Taste
	'10/2/16' 	=> '112/10101/0/0/12218', 		# HK - Kommen Taste
	'10/2/18' 	=> '112/10101/0/0/12231', 		# HK - Gehen Taste
	'10/2/35' 	=> '112/10101/0/0/12240', 		# HK - Schieber Position
	'10/2/40' 	=> '112/10101/0/0/12104', 		# HK - Vorlauf bei -10°C
	'10/2/42' 	=> '112/10101/0/0/12103', 		# HK - Vorlauf bei +10°C
	'10/2/44' 	=> '112/10101/0/0/12107', 		# HK - Vorlauf Absenkung
	'10/2/46' 	=> '112/10101/0/0/12096', 		# HK - Heizgrenze Tag
	'10/2/48' 	=> '112/10101/0/0/12097', 		# HK - Heizgrenze Nacht
	'10/2/52' 	=> '112/10101/12095/0/1072', 	# HK - Außen verzögert (Lag Tf)

	'10/3/5' 	=> '112/10102/0/0/12080', 		# FBH - I/O Taste
	'10/3/10' 	=> '112/10102/0/0/12126', 		# FBH - Auto Taste
	'10/3/12' 	=> '112/10102/0/0/12125', 		# FBH - Tag Taste
	'10/3/14' 	=> '112/10102/0/0/12230', 		# FBH - Nacht Taste
	'10/3/16' 	=> '112/10102/0/0/12218', 		# FBH - Kommen Taste
	'10/3/18' 	=> '112/10102/0/0/12231', 		# FBH - Gehen Taste
	'10/3/35' 	=> '112/10102/0/0/12240', 		# FBH - Schieber Position
	'10/3/40' 	=> '112/10102/0/0/12104', 		# FBH - Vorlauf bei -10°C
	'10/3/42' 	=> '112/10102/0/0/12103', 		# FBH - Vorlauf bei +10°C
	'10/3/44' 	=> '112/10102/0/0/12107', 		# FBH - Vorlauf Absenkung
	'10/3/46' 	=> '112/10102/0/0/12096', 		# FBH - Heizgrenze Tag
	'10/3/48' 	=> '112/10102/0/0/12097', 		# FBH - Heizgrenze Nacht
	'10/3/52' 	=> '112/10102/12095/0/1072', 	# FBH - Außen verzögert (Lag Tf)

	'10/5/5' 	=> '112/10111/0/0/12134', 		# WW - Laden Taste
	'10/5/15' 	=> '112/10111/0/0/12133', 		# WW - Einschaltdifferenz
);

# Mapping ETA can-bus-uri zu RRD Graphen (Gauge = Messerte) aus Value Rückgaben
my %value_URI_RRD_mapping = (
	'112/10021/0/0/12001' 		=> 'Heizung_KesselSolltemperatur',
	'112/10021/0/0/12161' 		=> 'Heizung_Kesseltemperatur',
	'112/10021/0/0/12300' 		=> 'Heizung_KesseltemperaturUnten',
	'112/10021/0/0/12162' 		=> 'Heizung_Abgastemperatur',
	'112/10021/0/0/12165' 		=> 'Heizung_DrehzahlAbgasgebläse',
	'112/10021/0/0/12164' 		=> 'Heizung_Restsauerstoff',

	'112/10021/0/11121/2120'	=> 'Heizung_VL1_Solltemperatur',
	'112/10021/0/11121/2121'	=> 'Heizung_VL1_Isttemperatur',
	'112/10021/0/11152/2120' 	=> 'Heizung_VL2_Solltemperatur',
	'112/10021/0/11152/2121' 	=> 'Heizung_VL2_Isttemperatur',

	'112/10101/0/0/12111' 		=> 'Heizung_HK_Solltemperatur',
	'112/10101/0/0/12240' 		=> 'Heizung_HK_Schieber',
	'112/10102/0/0/12111' 		=> 'Heizung_FBH_Solltemperatur',
	'112/10102/0/0/12240' 		=> 'Heizung_FBH_Schieber',
	'112/10111/0/0/12132' 		=> 'Heizung_WW_Solltemperatur',
	'112/10111/0/0/12271' 		=> 'Heizung_WW_TemperaturSpeicherOben',
);

# Mapping ETA can-bus-uri zu RRD Graphen für Tageszähler (aus Zählerstand) aus Value Rückgaben
my %value_URI_RRDdaycount_mapping = (
	'112/10021/0/0/12016' 		=> 'Heizung_PelletsverbrauchTag',
	'112/10021/0/0/12153' 		=> 'Heizung_Betriebssekunden',	
);

# Mapping der ETA Einheiten zu KNX Datenpunkttypen
my %unit_DPT_mapping = (
	"%" 			=> '6.001',
	"U/min"			=> '7.001',
	"\N{U+00b0}C"	=> '9.001',
	"Sek"			=> '9.010',
	'kg'			=> '14.051',
);
## Ende Definitionen ##

#Module laden
use strict;
use warnings;
use LWP::UserAgent;
use XML::Parser;
use IO::File;


# Plugin alle 1 Minuten aufrufen
$plugin_info{$plugname.'_cycle'} = 60*1;

#Letzte Laufzeit protokollieren
update_rrd("LaufzeitPlugin_".$plugname,"",$plugin_info{$plugname.'_runtime'});


# Variablen definieren
my %value_GA_URI;
my %write_GA_URI;
my %string_GA_URI;

# ETA Variablenset anlegen, wenn Plugin durch Speichern aufgerufen
my $SetVar;
if ((stat('/etc/wiregate/plugin/generic/' . $plugname))[9] > time()-10) {
# Code nach PL30
#if = ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'} or $plugin_info{$plugname.'_lastSetVariable'} == 0) {
	$SetVar = 1;
}

# ETA Variablenset anlegen, wenn Variablenset fehlt
if ($plugin_info{$plugname.'_lastSetVariable'} == 0) {
	$SetVar = 1;
}

# ETA Variablenset anlegen
if ($SetVar) {
	delete_set("http://".$IP_PU.$ResVariables, $set);
	create_set("http://".$IP_PU.$ResVariables, $set);
	plugin_log($plugname,"Variablenset anlegen: ".$set);
	$plugin_info{$plugname.'_lastSetVariable'} = time();
}

for my $ga (%string_GA_URI_mapping) {
    if (exists $string_GA_URI_mapping{$ga}) {
		#$plugin_subscribe{$ga}{$plugname} = 1;				#An Gruppenadresse anmelden
		$string_GA_URI{$string_GA_URI_mapping{$ga}} = $ga;	# Hash URI -> GA aus Hash GA->URI bilden
		if ($SetVar) {
			# ETA Uri zu Variablenset hinzufügen
			add_to_set("http://".$IP_PU.$ResVariables, $set, $string_GA_URI_mapping{$ga});
			plugin_log($plugname,	"Variablenset erweitern: ".$set.
									" - String URI".$string_GA_URI_mapping{$ga});
		}
    }
}

for my $ga (%value_GA_URI_mapping) {
    if (exists $value_GA_URI_mapping{$ga}) {
		#$plugin_subscribe{$ga}{$plugname} = 1;				#An Gruppenadresse anmelden
		$value_GA_URI{$value_GA_URI_mapping{$ga}} = $ga;	# Hash URI -> GA aus Hash GA->URI bilden
		if ($SetVar) {
			# ETA Uri zu Variablenset hinzufügen
			add_to_set("http://".$IP_PU.$ResVariables, $set, $value_GA_URI_mapping{$ga});
			plugin_log($plugname,	"Variablenset erweitern: ".$set.
									" - Value URI".$value_GA_URI_mapping{$ga});	
		}
    }
}

for my $ga (%write_GA_URI_mapping) {
    if (exists $write_GA_URI_mapping{$ga}) {
		$plugin_subscribe{$ga}{$plugname} = 1;				#An Gruppenadresse anmelden
		$write_GA_URI{$write_GA_URI_mapping{$ga}} = $ga;	# Hash URI -> GA aus Hash GA->URI bilden
		if ($SetVar) {
			# ETA Uri zu Variablenset hinzufügen
			add_to_set("http://".$IP_PU.$ResVariables, $set, $write_GA_URI_mapping{$ga});
			plugin_log($plugname,	"Variablenset erweitern: ".$set.
									" - Write URI".$write_GA_URI_mapping{$ga});
		}

    }
}

# Bei Schreibtelegramm Wert mit Faktor und Offset in Kesselsteuerung schreiben
if ($msg{'apci'} eq "A_GroupValue_Write" and exists $write_GA_URI_mapping{$msg{'dst'}}) {
	set_value(	"http://".$IP_PU.$ResSingleVariable,$write_GA_URI_mapping{$msg{'dst'}},
				$msg{'value'}
				* $plugin_info{$plugname.'_'.$write_GA_URI_mapping{$msg{'dst'}}.'_scaleFactor'}
				+ $plugin_info{$plugname.'_'.$write_GA_URI_mapping{$msg{'dst'}}.'_advTextOffset'});
	plugin_log(	$plugname,	$write_GA_URI_mapping{$msg{'dst'}}." - GA ".$msg{'dst'}.
							" - Wert schreiben: ".	$msg{'value'}.
							" / scaleFactor ".		$plugin_info{$plugname.'_'.$write_GA_URI_mapping{$msg{'dst'}}.'_scaleFactor'}.
							"  advTextOffset ".		$plugin_info{$plugname.'_'.$write_GA_URI_mapping{$msg{'dst'}}.'_advTextOffset'});
}


# Im Intervall oder nach Schreibtelegramm Werte aus der Kesselsteuerung lesen
if (! %msg or ($msg{'apci'} eq "A_GroupValue_Write" and exists $write_GA_URI_mapping{$msg{'dst'}})) {
	my @values = query_user_set_variables("http://".$IP_PU.$ResVariables, $set);
    
	for my $value (@values) {
		# Werte für String auf GA schreiben
		if (exists $string_GA_URI{$value->{uri}}) {
			my $dpt = $eibgaconf{$string_GA_URI{$value->{uri}}}{'DPTSubId'};
			knx_write($string_GA_URI{$value->{uri}},$value->{strValue},$dpt);
			plugin_log($plugname,	$value->{uri}." - GA ".$string_GA_URI{$value->{uri}}.
									" - String lesen: ".$value->{strValue});
		}

		# Werte für Value auf GA schreiben
		if (exists $value_GA_URI{$value->{uri}}) {
			my $dpt = $unit_DPT_mapping{$value->{unit}} || $eibgaconf{$value_GA_URI{$value->{uri}}}{'DPTSubId'};
			knx_write($value_GA_URI{$value->{uri}},($value->{RAW}/$value->{scaleFactor}-$value->{advTextOffset}),$dpt);
			plugin_log($plugname,	$value->{uri}." - GA ".$value_GA_URI{$value->{uri}}.
									" - Wert lesen: ".($value->{RAW}/$value->{scaleFactor}-$value->{advTextOffset}));
		}

		#Faktor und Offset für Write URI merken
		if (exists $write_GA_URI{$value->{uri}} and $SetVar) {	
			$plugin_info{$plugname.'_'.$value->{uri}.'_scaleFactor'} = $value->{scaleFactor};
			$plugin_info{$plugname.'_'.$value->{uri}.'_advTextOffset'} = $value->{advTextOffset};				
		}		
		
		# Werte für Value auf RRD schreiben
		if (exists $value_URI_RRD_mapping{$value->{uri}}) {
			update_rrd($value_URI_RRD_mapping{$value->{uri}},"",($value->{RAW}/$value->{scaleFactor}-$value->{advTextOffset}));
			plugin_log($plugname,	$value->{uri}." - RRD ".$value_URI_RRD_mapping{$value->{uri}}.
									" - Wert: ".($value->{RAW}/$value->{scaleFactor}-$value->{advTextOffset}));
		}
		# Werte für Value auf RRD Tagesverbrauch schreiben
		if (exists $value_URI_RRDdaycount_mapping{$value->{uri}}) {
			# Falls RRD noch nicht existiert, so soll er angelegt werden
			if (! -e $DirRrd.$value_URI_RRDdaycount_mapping{$value->{uri}}.".rrd" ) {
				RRDs::create(	$DirRrd.$value_URI_RRDdaycount_mapping{$value->{uri}}.".rrd",
								'--step' => 86400, 
								'DS:value:COUNTER:86500:0:10000000000', 
								'RRA:AVERAGE:0.5:1:365', 'RRA:AVERAGE:0.5:7:300');
				plugin_log($plugname,$value->{uri}." - COUNTER-RRD ".$value_URI_RRDdaycount_mapping{$value->{uri}}." neu angelegt");
			}
			
			update_rrd(	$value_URI_RRDdaycount_mapping{$value->{uri}},"",
						(86400*$value->{RAW}/$value->{scaleFactor}-$value->{advTextOffset}),"COUNTER");
			plugin_log($plugname,	$value->{uri}." - COUNTER-RRD ".
									$value_URI_RRDdaycount_mapping{$value->{uri}}.
									" - Wert: ".(86400*$value->{RAW}/$value->{scaleFactor}-$value->{advTextOffset}));			
		}		
	}
	
	# Wenn keine Werte zurückgeben werden, beim nächsten Durchlauf Variablenset neu anlegen
	if (@values eq 0) {
		$plugin_info{$plugname.'_lastSetVariable'} = 0;
	}
	
	# Fehlerprotokoll auslesen
	my @values = query_errors("http://".$IP_PU.$ResErrors);
	knx_write($GA_AnzahlFehler,1,$eibgaconf{$GA_AnzahlFehler}{'DPTSubId'} || $DPT_GA_AnzahlFehler);
	plugin_log($plugname,"Anzahl Fehlermeldungen: ".@values);
	if (@values > 0) {
		knx_write($GA_Fehler,1,$eibgaconf{$GA_Fehler}{'DPTSubId'} || $DPT_GA_Fehler);
		for my $value (@values) {
		
		# TODO: RSS-Feed schreiben
		plugin_log($plugname,	"Meldung (".$value->{time}."): ".$value->{priority}." - ".
								$value->{msg}." (".$value->{RAW}.")");
		}
	} 
	else {
		knx_write($GA_Fehler,0,$eibgaconf{$GA_Fehler}{'DPTSubId'} || $DPT_GA_Fehler);	
	}
	
	$plugin_info{$plugname.'_lastDataUpdate'} = time();
}



sub query_user_set_variables {
	my ($base_url, $set) = @_;
	my $url = "$base_url/$set";
	my $response = do_request(GET => $url);	
	return parse_response($response, 'variable');
}

sub do_request {
	my ($type, $url) = @_;
	my $request = HTTP::Request->new($type => $url);
	my $ua = LWP::UserAgent->new;
	my $response = $ua->request($request);
	#unless ($response->is_success) {
	#	die $response->status_line;
	#}
	if ($url =~ m|http://localhost:|) {
		# Sleep to allow testing with nc -l 8080 -w 1
		sleep 1;
	}
	if ($response->content eq undef) {
		return 'Abfrage '.$type.' - '.$url.' fehlgeschlagen' ;
	}
	return $response->content;
}


sub query_errors {
    my ($url) = @_;
    my $response = do_request(GET => $url);
    return parse_response($response, 'error'); 
}


sub parse_response {
    my ($response, $want_element) = @_;
    my @result;

    my $raw_value = '';
    my $get_characters;
    my $current_attributes;

    my $start_handler = sub {
	my ($expat, $element, %attr) = @_;

	return if ($element ne $want_element);

	$current_attributes = \%attr;
	$get_characters = 1;
    };

    my $end_handler = sub {
		my ($expat, $element) = @_;

		return if ($element ne $want_element);
		$get_characters = 0;

		$current_attributes->{RAW} = $raw_value;
		push @result, $current_attributes;
		$raw_value = '';
    };

    my $char_handler = sub {
		my ($expat, $value) = @_;
		if ($get_characters) {
			$raw_value .= $value;
		}
	};

    my $parser = XML::Parser->new(Handlers => {Start => $start_handler,Char => $char_handler,End => $end_handler });
    $parser->parse($response);
    return @result;
}


sub set_value {
	my ($base_url, $uri, $value) = @_;
	my $url = "$base_url/$uri";
	return post_request($url, value => $value);
}


sub post_request {
	my ($url, %form) = @_;
	my $ua = LWP::UserAgent->new;
	my $response = $ua->post($url, \%form);
	#unless ($response->is_success) {
	#	die $response->status_line;
	#
	if ($url =~ m|http://localhost:|) {
		# Sleep to allow testing with nc -l 8080 -w 1
		sleep 1;
	}
	return $response->content;
}


sub create_set {
	my ($base_url, $set) = @_;
	my $url = "$base_url/$set";
	# Ignore errors here, set might already be existing
	eval {
	do_request(PUT => $url);
	};
}


sub delete_set {
	my ($base_url, $set) = @_;
	my $url = "$base_url/$set";
	do_request(DELETE => $url);
}


sub add_to_set {
	my ($base_url, $set, $uri) = @_;
	my $url = "$base_url/$set/$uri";
	do_request(PUT => $url);
}


sub delete_from_set {
	my ($base_url, $set, $uri) = @_;
	my $url = "$base_url/$set/$uri";
	do_request(DELETE => $url);
}
