# Plugin zur Abfrage einer Sunny Webbox-2 (BT) via HTTP/XML
# es existiert noch ein zweites, erweiteretes Plugin SunnyWeb-CSV!
# -> Gesamt-Anlagenstatus/Ertrag sofern mehrere Wechselrichter
# angeschlossen sind!
# V 1.1 2012-05-03
# Aufbau moeglichst so, dass man unterhalb der Definitionen nichts aendern muss!

##################
### DEFINITION ###
##################

my $ip = "192.168.0.110";
my $user = "Installer";
my $pass = "1234";
my $url = "/culture/login?Language=LangDE&Userlevels=".$user."&password=".$pass;

# 13.010 DPT_ActiveEnergy [-2 147 483 648 ... 2 147 483 647] Wh - 4 byte signed
my $name = "PV-Anlage";		# Name fuer die RRD-Archive 
my $ga_ertrag = "10/0/1";	# GA fuer Gesamtertrag in Wh DPT13
my $ga_tagesertrag = "10/0/2";	# GA fuer Tagesertrag in Wh DPT13
# 14.056 DPT_Value_Power W  - 4 byte float
my $ga_leistung = "10/0/3";	# GA fuer akt. Leistung in W DPT14
my $ga_error = "10/0/4"; 	# GA erhaelt eine 1 wenn Anlagenzustand nicht Ok
$plugin_info{$plugname.'_cycle'} = 300; # Eigenen Aufruf-Zyklus setzen 

my $debug = 0; # Debug-Ausgaben aktivieren?

#######################
### ENDE DEFINITION ###
#######################

# Hauptverarbeitung
use LWP::Simple; # comment wenn lokales XML
use XML::Simple;

my $xml = get("http://".$ip.$url); # comment wenn lokales XML
return "Fehler beim auslesen!" unless $xml;
if ($debug) {
    open (XMLFILE, '>/tmp/sunny1.xml');
    print XMLFILE $xml;
    close (XMLFILE); 
}
 
# Die Webbox ist ziemlich lahm, ca. 2.3s im Schnitt; geschickter waere es, das XML per wget/curl mit der crontab zu holen siehe SunnyWeb-CSV.
my $data = XMLin($xml)->{Content}->{Element}->{Tab}->{'hp.PlantOverview'}->{Element};
#my $data = XMLin('/tmp/sunny.xml')->{Content}->{Element}->{Tab}->{'hp.PlantOverview'}->{Element};
my $separator = $data->{'decimalSeparator'};
my $dataP = $data->{Element}[0]->{Items}->{XmlItem}->{'Solar-Wechselrichter'}->{Items}->{XmlItem};

my $zustand = $dataP->{Zustand}{'Value'};

my $gesErtrag = $dataP->{Gesamtertrag}{'Value'};
my $gesFactor = $dataP->{Gesamtertrag}{'factor'} || 1;
#my $dseparator = $data->{'decimalSeparator'};
#my $gseparator = $data->{'groupSeparator'};
# as lang=DE we assume x.xxx,yy
# a little haky-cranky as perl writes UTF8 numbers otherwise
$gesErtrag =~ s/\.//g;
$gesErtrag =~ s/,/\./;
$gesErtrag *= $gesFactor;

my $tagErtrag = $dataP->{Tagesertrag}{'Value'};
my $tagFactor = $dataP->{Tagesertrag}{'factor'} || 1;
$tagErtrag =~ s/\.//;
$tagErtrag =~ s/,/\./;
$tagErtrag *= $tagFactor;

my $aktLeistung = $dataP->{Leistung}->{Items}->{XmlItem}{'Summe'}{'Value'};
my $leistFactor = $dataP->{Leistung}->{Items}->{XmlItem}{'Summe'}{'factor'} || 1;
$aktLeistung =~ s/\.//;
$aktLeistung =~ s/\,/\./;
$aktLeistung *= $leistFactor;

knx_write($ga_ertrag,$gesErtrag,13);
knx_write($ga_tagesertrag,$tagErtrag,13);
knx_write($ga_leistung,$aktLeistung,14);

if ($zustand !~ /Ok/) {
    # Etwas mit dem Problem machen
    knx_write($ga_error,1,1);
} else {
    knx_write($ga_error,0,1);
}

# Werte loggen
update_rrd($name,"_Leistung",$gesErtrag*3600,"COUNTER");
update_rrd($name,"_Tag",$tagErtrag);
update_rrd($name,"_aktLeistung",$aktLeistung);

#my $dataD = XMLin($xml)->{DeviceTree}->{Devices}->{Device}->{Devices}->{Device}; # only first, a little hacky
#my $dataD = XMLin('/tmp/sunny.xml')->{DeviceTree}->{Devices}->{Device}->{Devices}->{Device}; # only first, a little hacky

#my @wrs; # Array der einzelnen Wechselrichter
#for my $key (sort keys %$dataD) {
#    print "$dataD->{$key}->{deviceType} <= $key => $dataD->{$key}->{Value}\n";
#    push (@wrs,$dataD->{$key}->{Value}); # SN in array ablegen
#}

#foreach (@wrs) {
    # hier koennte man nun noch die einzelnen WR-Details holen
#}    

# avoid memleaks?
$xml = (); # comment wenn lokales XML
$data = ();
$dataP = ();
#$dataD = ();
undef $xml; # comment wenn lokales XML
undef $data;
undef $dataP;
#undef $dataD;


# finally wollen wir Tausender im log, wilde RE
$gesErtrag =~ s/(^[-+]?\d+?(?=(?>(?:\d{3})+)(?!\d))|\G\d{3}(?=\d))/$1./g;
$tagErtrag =~ s/(^[-+]?\d+?(?=(?>(?:\d{3})+)(?!\d))|\G\d{3}(?=\d))/$1./g;
$aktLeistung =~ s/(^[-+]?\d+?(?=(?>(?:\d{3})+)(?!\d))|\G\d{3}(?=\d))/$1./g;
return "Zustand $zustand Leistung: $aktLeistung W Tag: $tagErtrag Wh Gesamt $gesErtrag Wh\n" if $debug;
return;

