# Datenlogger PV-Anlage Kostal Piko 10.1
# v0.2
use LWP::Simple;
my $Wechselrichter_IP = "pvserver:pvwr\@192.168.2.101"; # Standard IP Kostal Piko 10.1
my $CurrentDataPath  = "/index.fhtml"; # Uebersicht aktuelle Leistungsdaten
my $LogDownloadPath  = "/LogDaten.dat"; # Log (TXT-Format)
my @values;
# Arrays to hold GAs for detailed values from the strings / outputs
# If a GA is left empty, it is not send to the bus
my @myDcVoltageGA;   # DC voltage in [V], DPT 14.027
my @myDcCurrentGA;   # DC current in [A], DPT 14.019
my @myDcPowerGA;   # DC power [W], DPT 13.010
my @myAcVoltageGA;   # AC voltage in [V], DPT 14.027
my @myAcCurrentGA;   # AC current in [A], DPT 14.019
my @myAcPowerGA;   # AC power in [W], DPT 13.010
my @myAcDailyEnergyGA;  # Energy output, daily accumulation in [Wh], DPT 13.010
my @myTemperatureGA;  # Temperature of inverter in [°C], DPT 9.001
my @myStatusGA;    # Status of inverter, DPT 5.010
#$myDcVoltageGA[1]     = "0/4/237";
#$myDcVoltageGA[2]     = "0/4/237";
#$myDcCurrentGA[1]     = "0/4/238";
#$myDcCurrentGA[2]     = "0/4/238";
#$myDcPowerGA[1]       = "0/4/239";
#$myDcPowerGA[2]       = "0/4/239";
#$myAcVoltageGA[1]     = "0/4/240";
#$myAcVoltageGA[2]     = "0/4/240";
#$myAcVoltageGA[3]     = "0/4/240";
#$myAcCurrentGA[1]     = "0/4/241";
#$myAcCurrentGA[2]     = "0/4/241";
#$myAcCurrentGA[3]     = "0/4/241";
#$myAcPowerGA[1]       = "0/4/242";
#$myAcPowerGA[2]       = "0/4/242";
#$myAcPowerGA[3]       = "0/4/242";
#$myAcPowerGA[4]       = "0/4/242";
$myAcDailyEnergyGA[1] = "7/0/118";
#$myTemperatureGA[1]   = "0/4/244";
$myStatusGA[1]        = "7/0/10";
my $content = get( "http://$Wechselrichter_IP$CurrentDataPath" );
return "PV-Datenabfrage fehlgeschlagen" unless defined $content;
my @CurrentData = split( /\<td/, $content );
my $i = 0;
foreach ( @CurrentData ) {
 $_ =~ s/\r//g;    # Wagenrücklauf entfernen
 $_ =~ s/\n//g;    # Zeilenumbruch entfernen
 $_ =~ />(.*)</;
 @values[$i] = $1;
 $i++;
}
$values[3] =~ s/<.+?>//g;
my $WR_Name = $values[3];
my $AC_Leistung_Ges = $values[15];
$AC_Leistung_Ges =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_P_AC","",$AC_Leistung_Ges,"GAUGE");
my $Gesamtenergie = $values[18];
$Gesamtenergie =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_W_total","",$Gesamtenergie,"GAUGE");
my $Tagesenergie = $values[27];
$Tagesenergie =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_W_tag","",$Tagesenergie,"GAUGE");
if( $myAcDailyEnergyGA[1] ) { knx_write( $myAcDailyEnergyGA[1], $Tagesenergie*1000, 13 ); }    
my $WR_Status = $values[33];
$WR_Status =~ s/\s//g;    # Leerzeichen entfernen
if( $myStatusGA[1] ) { knx_write( $myStatusGA[1], $WR_Status, 16 ); }    
my $DC1_U = $values[57];
$DC1_U =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_U_DC1","",$DC1_U,"GAUGE") if ($DC1_U > 0);
my $DC1_I = $values[66];
$DC1_I =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_I_DC1","",$DC1_I,"GAUGE");
my $DC1_P = $DC1_U * $DC1_I;
$DC1_P =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_P_DC1","",$DC1_P,"GAUGE");
my $DC2_U = $values[83];
$DC2_U =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_U_DC2","",$DC2_U,"GAUGE") if ($DC2_U > 0);
my $DC2_I = $values[92];
$DC2_I =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_I_DC2","",$DC2_I,"GAUGE");
my $DC2_P = $DC2_U * $DC2_I;
$DC2_P =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_P_DC2","",$DC2_P,"GAUGE");
# my $DC3_U = $values[109];
# my $DC3_I = $values[118];
# my $DC3_P = $DC3_U * $DC3_I;
my $AC1_U = $values[60];
$AC1_U =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_U_AC1","",$AC1_U,"GAUGE") if ($AC1_U > 0);
my $AC1_P = $values[69];
$AC1_P =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_P_AC1","",$AC1_P,"GAUGE");
my $AC2_U = $values[86];
$AC2_U =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_U_AC2","",$AC2_U,"GAUGE") if ($AC2_U > 0);
my $AC2_P = $values[95];
$AC2_P =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_P_AC2","",$AC2_P,"GAUGE");
my $AC3_U = $values[112];
$AC3_U =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_U_AC3","",$AC3_U,"GAUGE") if ($AC3_U > 0);
my $AC3_P = $values[121];
$AC3_P =~ s/[a-z\s&]//gi;
update_rrd("Photovoltaik_P_AC3","",$AC3_P,"GAUGE");
# Zyklischer Aufruf anpassen
if ($WR_Status eq 'Aus') {
 $plugin_info{$plugname.'_cycle'}  = 300; 
 }
else {
 $plugin_info{$plugname.'_cycle'}  = 60; 
 }
return ('WR Status: ' . $WR_Status . '   Cycle: ' . $plugin_info{$plugname.'_cycle'});
