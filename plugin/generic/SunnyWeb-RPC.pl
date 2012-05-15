# holt über HTTP-RPC die Daten von der SMA-Webbox
# es wird GetProcessData und GetPlantOverview abgefragt
# by NetFritz 5.2012
#
use HTML::Entities;
use LWP::UserAgent;
use JSON::XS;
# ======= Anfang Konfig =======
my $url = "http://192.168.2.7:85"; # IP der Webbox
my $key = "004e:7d30b9bc";         # Key des WR muss vorher ermittelt werden
my $leistung_ga = "5/0/1"; 
my $leistung_pro_kw_ga = "5/0/2"; 
my $tagesertrag_ga = "5/0/3"; 
my $gesammtertrag_ga = "5/0/4"; 
my $zustand_ga = "5/0/5"; 
my $meldung_ga = "5/0/6"; 
my $DC_Strom_Eingang_ga = "5/0/7";
my $DC_Spannung_Eingang_ga = "5/0/8";
my $Netzstrom_ga = "5/0/9";
my $Leistung_Haushalt_ga = "5/0/15";
# ======= Ende Konfig =========
# Eigenen Aufruf-Zyklus auf 60 Sekunden setzen
# der Aufrufzyklus ist unabhängig von der Taktzeit und muss kürzer sein!
$plugin_info{$plugname.'_cycle'} = 60;
my $res;
my $ref;
# ===== Abfragestring GetProcessData =====
my $callobj = '/rpc?RPC={
                "version": "1.0",
                "proc": "GetProcessData",
                "id": "1",
                "format": "JSON",
                "params":
                {
                  "devices":
                  [
                  {
                    "key": "'. $key .'",
                    "channels": null
                  }
                  ]
                }
              }';
#
# ==== Abfragestring GetPlantOverview =====
my $callobj1 = '/rpc?RPC={
             "version": "1.0",
             "proc": "GetPlantOverview",
             "id": "1",
             "format": "JSON"
             }';
#
# ====== Abfrage GetProcessData ======
$res = $url.$callobj; 
$ref = rpcs($res);
#
my $Ipv = $ref->{'result'}->{'devices'}->[0]->{'channels'}->[0]->{'value'}; # DC Strom Eingang
my $Upv = $ref->{'result'}->{'devices'}->[0]->{'channels'}->[1]->{'value'}; # DC Spannung Eingang
my $Fac = $ref->{'result'}->{'devices'}->[0]->{'channels'}->[5]->{'value'}; # NetzFrequenz
my $Iac = $ref->{'result'}->{'devices'}->[0]->{'channels'}->[6]->{'value'}; # Netzstrom
my $Pac = $ref->{'result'}->{'devices'}->[0]->{'channels'}->[7]->{'value'}; # Leistung
my $Riso = $ref->{'result'}->{'devices'}->[0]->{'channels'}->[8]->{'value'}; # Isolationswiderstand
my $hon = $ref->{'result'}->{'devices'}->[0]->{'channels'}->[10]->{'value'}; # Einspeisezeit
my $hTotal = $ref->{'result'}->{'devices'}->[0]->{'channels'}->[11]->{'value'}; # Betriebszeit
my $ETotal = $ref->{'result'}->{'devices'}->[0]->{'channels'}->[12]->{'value'}; # Gesammtertrag
my $NetzEin = $ref->{'result'}->{'devices'}->[0]->{'channels'}->[13]->{'value'}; # Netz-Ein
# return $Ipv . "=" . $Upv . "=" . $Fac . "=" . $Iac . "=" . $Pac . "=" . $Riso . "=" . $hon . "=" . $hTotal . "=" . $ETotal . "=" . $NetzEin;
#
# ===== Abfrage GetPlantOverview =====
$res = $url.$callobj1; 
$ref = rpcs($res);
my $GriPwr = $ref->{'result'}->{'overview'}->[0]->{'value'}; # Leistung
my $GriEgyTdy = $ref->{'result'}->{'overview'}->[1]->{'value'}; # Tagesertrag
my $GriEgyTot = $ref->{'result'}->{'overview'}->[2]->{'value'}; # Gesamtertrag
my $OpStt = $ref->{'result'}->{'overview'}->[3]->{'value'}; # Zustand
my $Msg = $ref->{'result'}->{'overview'}->[4]->{'value'}; # Meldung
# return $GriPwr . "=" . $GriEgyTdy ."=". $GriEgyTot ."=". $OpStt ."=". $Msg ;
# my $Tag_CO2_vermeidung = $GriEgyTdy*700; # 700g/kWh
# Werte auf den BUS schreiben
 knx_write($leistung_ga,$GriPwr,9);
 knx_write($leistung_pro_kw_ga,$GriPwr/4.05,9);
 knx_write($tagesertrag_ga,$GriEgyTdy,9);
 knx_write($gesammtertrag_ga,$ETotal,9);
 knx_write($zustand_ga,$OpStt,16);
 knx_write($DC_Strom_Eingang_ga,$Ipv,9);
 knx_write($DC_Spannung_Eingang_ga,$Upv,9);
 knx_write($Netzstrom_ga,$Iac,9);
 # knx_write($meldung_ga,$$Msg,16);
my $Leistung_Zaehler = knx_read("5/0/12",0,9);
my $leistg_haush = knx_read("5/0/1",0,9)-$Leistung_Zaehler; # Leistung Haushalt
knx_write($Leistung_Haushalt_ga,$leistg_haush,9);
# Wert in RRD schreiben
update_rrd("pv_leistung","",$GriPwr); 
update_rrd("pv_leistung_kW","",$Pac/1000);
update_rrd("pv_tagesertrag","",$GriEgyTdy);
update_rrd("pv_DC_Strom_Eingang","",$Ipv);
update_rrd("pv_DC_Spannung_Eingang","",$Upv/100);
update_rrd("Leistung_Haushalt","",$leistg_haush);
# ===== Sub holt die Werte von der Webbox =====
sub rpcs{
   my $res = shift;
   my $brs = LWP::UserAgent->new;
   my $req = HTTP::Request->new(GET => $res);
   my $resp = $brs->request($req); 
   #
   if($resp->is_success()) {
     # print "Erfolg !";
   }else {
     return "Keine Antwort !";
   }
   #
   my $content = $resp->content;
   my %js_hash_ref = %{decode_json $content};
   my $ref=\%js_hash_ref; 
   #
   return($ref);
}
return;

