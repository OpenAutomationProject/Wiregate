### Plugin Min/Max values from RRD auf den Bus
# http://knx-user-forum.de/wiregate/38275-ermittlung-der-mittleren-heiztemperatur-fuer-sommer-winter-umschaltung.html
# v0.4
my $RRDName = "Temperatur_Aussen_Wetterstation";
my $ds   = "AVERAGE"; # Datasource: MIN AVERAGE MAX - egal bei Werten <180h
my $start = "now-72h"; # AT-STYLE TIME SPECIFICATION 
my $end   = "now";
$plugin_info{$plugname.'_cycle'} = 3600; # alle x sekunden
my $debug = 1;
my $gamin = '9/0/27'; # leer um Versand zu unterbinden-> ''
my $gamax = '9/0/28'; # leer um Versand zu unterbinden-> ''
my $gaavg = '9/0/26'; # leer um Versand zu unterbinden-> ''

my $dpt = $eibgaconf{$gaavg}{'DPTSubId'} || $eibgaconf{$gamin}{'DPTSubId'} || $eibgaconf{$gamax}{'DPTSubId'} || "9.001";
# hier einen Wert setzen (statt "9.001" z.B. "5.001"), falls es nicht im import/config ist

### ENDE Definitionen

# return early on write/response (telegram from myself!)
if ($msg{'apci'} && $msg{'apci'} ne "A_GroupValue_Read") {
	return;
}

my ($min,$max);
my $avg;
my $sum = 0;
my $counter = 0;

my ($dbstart, $step, $names, $data) =
	RRDs::fetch('/var/www/rrd/'.$RRDName.'.rrd', "--start=$start","--end=$end", $ds);

foreach my $line (@$data) {
   foreach my $val (@$line) {
	next unless defined $val;
	$min = $val unless defined $min;
	$max = $val unless defined $max;
	$min = $val if $val < $min;
   	$max = $val if $val > $max;
   	$counter += 1;
   	$sum += $val;
    }
}

$avg = $sum / $counter;


if ($msg{'apci'} eq "A_GroupValue_Read" and $msg{'dst'} eq $gamin) {
	knx_write($gamin,$min,$dpt,1);
	return;
} elsif ($msg{'apci'} eq "A_GroupValue_Read" and $msg{'dst'} eq $gamax) {
	knx_write($gamax,$max,$dpt,1);
	return;
} elsif ($msg{'apci'} eq "A_GroupValue_Read" and $msg{'dst'} eq $gaavg) {
	knx_write($gaavg,$avg,$dpt,1);
	return;
}

if ($gamin) {
	knx_write($gamin,$min,$dpt);
	$plugin_subscribe{$gamin}{$plugname} = 1;
}
if ($gamax) {
	knx_write($gamax,$max,$dpt);
	$plugin_subscribe{$gamax}{$plugname} = 1;
}
if ($gaavg) {
	knx_write($gaavg,$avg,$dpt);
	$plugin_subscribe{$gaavg}{$plugname} = 1;
}

return("Min $min Max $max Avg $avg in $start") if $debug;
return;
