#!/usr/bin/perl -w
##########################
# Anwesenheitssimulation #
##########################
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License

#$plugin_info{$plugname.'_cycle'}=0; return 'deaktiviert';

# Eine Gruppenadresse zum Starten und Stoppen der Anwesenheitssimulation. Diese ist vom Typ DPT 1 (Switch)
my $erzeugen=$eibgaconf{SI_erzeugen}{ga};
# alternativ einfach 
# my $erzeugen = '1/2/3';
# oder so aehnlich

# Eine Gruppenadresse zum Triggern der Erzeugung einer neuen Simulation aus eib.log Diese GA ist vom Typ DPT 1 (Trigger)
my $starten=$eibgaconf{SI_starten}{ga};

# gafilter ist die Liste der validen GAs (koennen auch Kurz- oder Langnamen sein)
# Beispiel: alle GAs der Haupt- und Mittelgruppe 6/2 und 6/3:
# my @gafilter=grep m!^(6/2/|6/3/)!, keys %eibgaconf;
# Ich verwende GA-Kurznamen (das erste Wort der GA-Bezeichnung ist ein eindeutiger Bezeichner der GA) und 
# kann daher etwas komfortabler schreiben:
my @gafilter=grep /^(LI|LD|JA|JS|JP)\S*$/, keys %eibgaconf;
# das bedeutet: alle Lichtschalt- und -dimmaktionen, alle Jalousiebefehle.

# Falls im Simulationsskript zur besseren Lesbarkeit GA-Namenskuerzel verwendet werden sollen, dies auf 1 setzen
my $use_shorts=0;
# Wer nicht weiss, was er hier eintragen soll, bitte 0 eintragen

# ---- Unterhalb dieser Zeile ist nichts mehr zu konfigurieren ------------

# Kein regelmaessiger Aufruf, nur auf Bustraffic reagieren
$plugin_subscribe{$erzeugen}{$plugname}=1;
$plugin_subscribe{$starten}{$plugname}=1;
$plugin_info{$plugname.'_cycle'}=0;
return "initialisiert" unless %msg;

# Name des Simulationsskriptes
my $simscript="AnwSimSkript.pl";

# Wir haben Bustraffic. Telegramm-GA ermitteln
my $incoming=$msg{dst};

if($msg{apci} eq "A_GroupValue_Read" && $incoming eq $starten)
{
    # Leserequest "laeuft die Anwesenheitssimulation gerade?"
    my $running = -f "/etc/wiregate/plugin/generic/$simscript";
    knx_write($incoming, $running, undef, 0x40) if defined $running; # response
    return;
}

return unless $msg{apci} eq "A_GroupValue_Write";

# Wir haben ein Schreibtelegramm. Telegramminhalt ermitteln
my $in=int($msg{value});

# Rueckgabewert
my $retval=undef;

# Muss ein Skript erzeugt werden?
if($incoming eq $erzeugen || ($incoming eq $starten && $in==1 && ! -f "/etc/wiregate/plugin/$simscript"))
{
    # breche evtl. laufende Anwesenheitssimulation ab
    delete $plugin_info{$simscript.'_line'};
    system "rm", "-f", "/etc/wiregate/plugin/generic/$simscript"; 

    # Vorlage in eib.log-Archiven vorhanden? Ggf. entpacken, ansonsten aussteigen
    my @gzsources=grep m!/var/log/eib\.log\.[0-9]\.gz$!, </var/log/eib.log.*.gz>;
    for my $source (@gzsources)
    {
	$source=~s/\.gz$//;
	system "/bin/gunzip /var/log/$source\.gz" if -f "/var/log/$source\.gz" && ! -f "/var/log/$source";
    }
    # Quelldateien in lexikalisch umgekehrter Reihenfolge sortieren
    my @sources=sort { $b cmp $a } grep m!/var/log/eib\.log(\.[0-9])?$!, </var/log/eib.log*>; 

    $retval=join ",", @sources;

    # loesche evtl. vorhandenes Skript
    system "rm", "-f", "/etc/wiregate/plugin/$simscript"; 

    # Initialisierung
    my $lasttime=undef;
    my $starttime=0; 
    my $week=7*24*3600;
    my @first=(0,0,31,59,90,120,151,181,212,243,273,304,334);

    # Konstruktion des GA-Filters als Regex
    @gafilter=grep m![0-9]+/[0-9]+/[0-9]+!, map $eibgaconf{$_}{ga}, @gafilter;
    my $gapat=",(?:".(join "|", map quotemeta($_), @gafilter)."),";

    $/="\n";

    for(;;)
    { 
	if(eof IN) 
	{
	    last unless @sources;
	    close IN;

	    while(@sources)
	    {
		my $source=shift @sources;
		open IN, "<$source";
		last unless eof IN;
	    }

	    next;
	}

	$_=<IN>;

	next unless /$gapat/;

	chomp;
	
	next unless /^([0-9][0-9][0-9][0-9])\-([0-9][0-9])\-([0-9][0-9]) ([0-9][0-9])\:([0-9][0-9])\:([0-9][0-9])[^,]*,A_GroupValue_Write,[^,]*,([0-9]+\/[0-9]+\/[0-9]+),[^,]*,([^,]*),[^,]*,([^,]*),.*$/; 

	my ($year, $month, $day, $hour, $min, $sec, $ga, $val, $dpt)=($1, $2, $3, $4, $5, $6, $7, $8, $9); 
	$val="'$val'" if $dpt=~/^(16|10|11)/; 

	$ga=$eibgaconf{$ga}{short} if $use_shorts && defined $eibgaconf{$ga}{short};

	# "absolute" Zeit innerhalb der Woche in Sekunden ermitteln
	my $daynum=365*$year+$first[$month]+$day+2; $year-- if $month<=2; $daynum+=int($year/4) - int($year/100) + int($year/400); 
	my $time=(($daynum*24+$hour-1)*60+$min)*60+$sec-$starttime;
	
	# Zeitabstand zum letzten Telegramm ermitteln
	if(defined $lasttime)
	{
	    last if $time>7*24*3600;
	    $time%=$week;
	    print SIM "],\n[$time,'$year-$month-$day $hour:$min:$sec', " if $time!=$lasttime;
	}
	else
	{
	    $starttime=$time;
	    $time=0;
	    # erzeuge eine neue Anwesenheitssimulation aus @sources
	    open SIM, ">/etc/wiregate/plugin/$simscript.tmp";

	    # Skript-Header einfuegen
	    print SIM "#!/usr/bin/perl -w\n\n";
	    print SIM "# Das Folgende wurde aus /var/log/eib.log.* extrahiert. Zeitangaben in den Zeilen entsprechen der Quelle.\n";
	    print SIM "my \$starttime = $starttime;\n";
	    print SIM "my \@script = (\n";
	    print SIM "[$time,'$year-$month-$day $hour:$min:$sec', ";
	}
	print SIM "'$ga',$val,$dpt, ";

	$lasttime=$time;
    }

    close IN;

    return "Quelldateien $retval enthalten keine einzige verwendbare Zeile, $simscript konnte nicht erstellt werden!" unless defined $lasttime;

    print SIM "]);\n\n";

    print SIM <<'EOF';
# Nun das oben definierte Skript ausfuehren
my $retval="";
my $cycle=1;
delete $plugin_info{$plugname."_line"} if !$plugin_initflag || ($plugin_info{$plugname."_lastsaved"}>$plugin_info{$plugname."_last"});
my $line=$plugin_info{$plugname."_line"};
my $cooler=0;

if(defined $line && $line<=$#script)
{
	my @action=@{$script[$line]};
	shift @action;
	my $timestamp=shift @action;
	$retval.="Wiederhole $timestamp: ";
	while (@action && $cooler++<100)
	{
		my $ga=shift @action; my $val=shift @action; my $dpt=shift @action;
		$retval.="knx_write($ga,$val,$dpt); ";
EOF

    print SIM "\t\t".'$ga=$eibgaconf{$ga}{ga};'."\n" if $use_shorts;

    print SIM <<'EOF';
		# knx_write($ga, $val, $dpt);
	}
	$line++; $line=0 unless $line<=$#script;
	$cycle=$script[$line][0]-(time()-$starttime)%(7*24*3600);
}
else
{
	for($line=0;$line<=$#script;$line++) 
	{
	    $cycle=$script[$line][0]-(time()-$starttime)%(7*24*3600);
	    last if $cycle>=0;
	}
	if($line>$#script)
	{
	    $line=0;
	    $cycle=($script[$line][0]-(time()-$starttime))%(7*24*3600);
	}
}

$cycle=1 if $cycle<=0;
$plugin_info{$plugname."_cycle"}=$cycle;
$retval.="(->".$cycle."s bis ".$script[$line][1].")";
$plugin_info{$plugname."_line"}=$line;
return $retval;
EOF

    close SIM;

    system "mv", "/etc/wiregate/plugin/$simscript.tmp", "/etc/wiregate/plugin/$simscript";

    return "Anwesenheitssimulation $simscript wurde aus folgenden Quelldateien erstellt: $retval" if $incoming eq $eibgaconf{SI_erzeugen}{ga};
}

if($incoming eq $starten)
{
    delete $plugin_info{$simscript.'_line'};

    if($in) 
    { 
	system "cp", "/etc/wiregate/plugin/$simscript", "/etc/wiregate/plugin/generic/$simscript"; 
	system "touch", "/etc/wiregate/plugin/generic/$simscript"; 

	if(defined $retval)
	{
	    return "Anwesenheitssimulation $simscript wurde aus folgenden Quelldateien erstellt und gestartet: $retval";
	}
	else
	{
	    return "Anwesenheitssimulation $simscript gestartet"; 
	}
    }
    else
    { 
	system "rm", "-f", "/etc/wiregate/plugin/generic/$simscript"; 
	return "Anwesenheitssimulation $simscript gestoppt"; 
    }
}

