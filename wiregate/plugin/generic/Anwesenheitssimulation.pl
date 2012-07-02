#!/usr/bin/perl -w
##########################
# Anwesenheitssimulation #
##########################
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License

#$plugin_info{$plugname.'_cycle'}=0; return 'deaktiviert';

# Aufrufgrund ermitteln
my $event=undef;
if (!$plugin_initflag) 
{ $event='restart'; } # Restart des daemons / Reboot
elsif ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'})
{ $event='modified'; } # Plugin modifiziert
elsif (%msg) { $event='bus'; } # Bustraffic
elsif ($fh) { $event='socket'; } # Netzwerktraffic
else { $event='cycle'; } # Zyklus

# eine Gruppenadresse zum Starten und Stoppen. Diese ist vom Typ DPT 1 (An/Aus)
$plugin_subscribe{'1/2/0'}{$plugname}=1;

# kein regelmaessiger Aufruf
$plugin_info{$plugname.'_cycle'}=0;

# Nur auf Bustraffic reagieren
return unless $event=~/bus/ && $msg{apci} eq "A_GroupValue_Write";
my $in=int($msg{value});

# Name des Simulationsskriptes
my $simscript="/etc/wiregate/plugin/generic/Anwesenheitssimulationsskript.pl";

unless($in) { system "rm", "-f", $simscript; return "Anwesenheitssimulation gestoppt"; }

# Start Anwesenheitssimulation: einfach ein neues Plugin aus eib.log erzeugen, der wiregate-Daemon fuehrt es dann aus
open SIM, ">$simscript";

my $line=1; 

print SIM <<EOF;
#!/usr/bin/perl -w

\$plugin_info{\$plugname.'_line'}=1 unless defined \$plugin_info{\$plugname.'_line'};

given(\$plugin_info{\$plugname.'_line'}) { 
when($line) { 
EOF

my $time=`/bin/date +%X`; $time=~/^([0-9][0-9])\:([0-9][0-9])\:([0-9][0-9])/; 
my ($h,$m,$s)=($1,$2,$3); 
my $lastdaynum=undef; 
my @first=(0,0,31,59,90,120,151,181,212,243,273,304,334);

open IN, "</var/log/eib.log"; 

$/="\n";

while($_=<IN>) 
{ 
    chomp;
    
    next unless /^([0-9][0-9][0-9][0-9])\-([0-9][0-9])\-([0-9][0-9]) ([0-9][0-9])\:([0-9][0-9])\:([0-9][0-9])[^,]*,[^,]*,[^,]*,([0-9]+\/[0-9]+\/[0-9]+),[^,]*,([^,]*),[^,]*,([^,]*),.*$/; 

    my ($year, $month, $day, $hour, $min, $sec, $ga, $val, $dpt)=($1, $2, $3, $4, $5, $6, $7, $8, $9); 
    $val="'$val'" if $dpt=~/^(16|10|11)/; 

    # Alle Telegramme auf manchen GAs ausfiltern
    next if $ga=~m!^(5|6)/0!;  

    my $daynum=365*$year+$first[$month]+$day; $year-- if $month<=2; $daynum+=int($year/4) - int($year/100) + int($year/400); 

    my $delta = ($h>20 ? 1:0); # falls nach 20 Uhr, starte Simulation erst am n�chsten Tag 
    $delta=$daynum-$lastdaynum if defined $lastdaynum;
    $delta=(($delta*24+($hour-$h))*60+($min-$m))*60+($sec-$s); 

    next if $delta<0; 

    if($delta>0)
    {
	($lastdaynum,$h,$m,$s)=($daynum,$hour,$min,$sec);  
	$line++;
	
	print SIM <<EOF;
\$plugin_info{\$plugname.'_cycle'}=$delta; }
when($line) {
EOF

    }

    print SIM <<EOF;
# $_ 
knx_write('$ga', $val, $dpt);
EOF

}
close IN;


print SIM <<EOF;
} 

default { \$plugin_info{\$plugname.'_line'}=1; } 
}

\$plugin_info{\$plugname.'_line'}++;

return \$plugin_info{\$plugname.'_line'}-1;

EOF

close SIM;

return "Anwesenheitssimulation gestartet";
