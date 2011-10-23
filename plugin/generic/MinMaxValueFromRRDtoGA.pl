### Plugin Min/Max values from RRD auf den Bus
my $RRDName = "28.7FD4EB010000_temp";
my $ds   = "MIN"; # Datasource: MIN AVERAGE MAX - egal bei Werten <180h
my $start = "now-20h"; # AT-STYLE TIME SPECIFICATION 
my $end   = "now";
$plugin_info{$plugname.'_cycle'} = 3600; # alle x sekunden
my $debug = 0;
my $gamin = '11/2/20'; # DPT9.001 leer um Versand zu unterbinden-> ''
my $gamax = '11/2/21'; # leer um Versand zu unterbinden-> ''
### ENDE Definitionen

# return early on write/response (telegram from myself!)
if ($msg{'apci'} && $msg{'apci'} ne "A_GroupValue_Read") {
	return;
}

my ($min,$max) = (0,0);
my ($dbstart, $step, $names, $data) =
	RRDs::fetch('/var/www/rrd/'.$RRDName.'.rrd', "--start=$start","--end=$end", $ds);

foreach my $line (@$data) {
   foreach my $val (@$line) {
	next unless defined $val;
	$min = $val if $val < $min;
   	$max = $val if $val > $max;
    }
}

if ($msg{'apci'} eq "A_GroupValue_Read" and $msg{'dst'} eq $gamin) {
	knx_write($gamin,$min,9,1);
	return;
} elsif ($msg{'apci'} eq "A_GroupValue_Read" and $msg{'dst'} eq $gamax) {
	knx_write($gamax,$max,9,1);
	return;
}

if ($gamin) {
	knx_write($gamin,$min,9);
	$plugin_subscribe{$gamin}{$plugname} = 1;
}
if ($gamax) {
	knx_write($gamax,$max,9);
	$plugin_subscribe{$gamax}{$plugname} = 1;
}
return("Min $min Max $max in $start") if $debug;
return;
