# Plugin zur Abfrage einer Sunny Webbox-2 (BT) 
# V 1.0
# Aufbau moeglichst so, dass man unterhalb der Definitionen nichts aendern muss!

##################
### DEFINITION ###
##################

my $ip = "192.168.1.110";
my $user = "Installer";
my $pass = "1111";
my $url = "/culture/login?Language=LangDE&Userlevels=".$user."&password=".$pass;

# 13.010 DPT_ActiveEnergy [-2 147 483 648 ... 2 147 483 647] Wh 
my $name = "PV-Anlage";		# Name fuer die RRD-Archive 
my $ga_ertrag = "13/3/1";	# GA fuer Gesamtertrag in Wh DPT13
my $ga_tagesertrag = "13/3/2";	# GA fuer Tagesertrag in Wh DPT13
my $ga_error = "13/3/0"; 	# GA erhaelt eine 1 wenn Anlagenzustand nicht Ok

$plugin_info{$plugname.'_cycle'} = 300; # Eigenen Aufruf-Zyklus setzen 

#######################
### ENDE DEFINITION ###
#######################

# Hauptverarbeitung
use LWP::Simple;
use XML::Simple;

my $xml = get("http://".$ip.$url);
return "Fehler beim auslesen!" unless $xml;
my $data = XMLin($xml)->{Content}->{Element}->{Tab}->{'hp.PlantOverview'}->{Element};
my $separator = $data->{'decimalSeparator'};
my $dataP = $data->{Element}[0]->{Items}->{XmlItem}->{'Solar-Wechselrichter'}->{Items}->{XmlItem};

my $zustand = $dataP->{Zustand}{'Value'};
my $gesErtrag = $dataP->{Gesamtertrag}{'Value'};
my $tagErtrag = $dataP->{Tagesertrag}{'Value'};
my $gesFactor = $dataP->{Gesamtertrag}{'factor'};
$gesErtrag =~ s/$separator/\./; 
$gesErtrag *= $gesFactor;

knx_write($ga_ertrag,$gesErtrag,13);
knx_write($ga_tagesertrag,$tagErtrag,13);

if ($zustand !~ /Ok/) {
    # Etwas mit dem Problem machen
    knx_write($ga_error,1,1)
}

# Werte loggen
update_rrd($name,"_Leistung",$gesErtrag*3600,"COUNTER");
update_rrd($name,"_Tag",$tagErtrag);

#DEBUG: return "Zustand $zustand Tag: $tagErtrag Wh Gesamt $gesErtrag Wh";
return;

