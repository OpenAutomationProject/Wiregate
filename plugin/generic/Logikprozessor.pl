#!/usr/bin/perl -w
##################
# Logikprozessor #
##################
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License
#
# sendSMS Code based on sipgate-provided Perl script written by Sam Buca
#
# COMPILE_PLUGIN

#$plugin_info{$plugname.'_cycle'}=0; return 'deaktiviert';

use POSIX qw(floor strftime sqrt);
use Math::Trig qw(asin acos atan tan);

# Tools und vorbesetzte Variablen fuer die Logiken
sub limit { my ($lo,$x,$hi)=@_; return $x<$lo?$lo:($x>$hi?$hi:$x); }
sub scene { my ($n,$op)=@_; $n--; return $n | ((defined $op && $op eq 'store') ? 0x80 : 0); }

my $date=strftime("%W,%a,%u,%m,%d,%Y,%j,%H,%M,%T",localtime);
plugin_log($plugname, "Datum/Uhrzeit nicht lesbar: '$date'.") unless ($date=~/^(.+),(.+),(.+),(.+),(.+),(.+),(.+),(.+),(.+),(.+)$/);

my $calendar_week=$1+1;
my $day_of_week=$2;
my $day_of_week_no=$3;
my $month=int($4);
my $day_of_month=int($5);
my $year=int($6);
my $day_of_year=int($7);
my $hour=int($8);
my $minute=int($9);
my $time_of_day=$10; # '08:30:43'
my $weekend=($day_of_week_no>=6)?1:0;
my $weekday=1-$weekend;
my $holiday=is_holiday($year,$day_of_year);
my $workingday=($weekend==0 && $holiday==0)?1:0;
my $day=($hour>=7 && $hour<22)?1:0;
my $night=1-$day;
my $systemtime=time();
$date=sprintf("%02d/%02d",$month,$day_of_month);
my $eibd_backend_address=undef;

sub groupaddress;
sub sendSMS; 
sub sendProwl;
sub verify;

# Konfigfile seit dem letzten Mal geaendert?
my $conf="/etc/wiregate/plugin/generic/conf.d/$plugname"; 
$conf.='.conf' unless $conf=~s/\.pl$/.conf/;
unless(-f $conf)
{
    plugin_log($plugname, "Config err: $conf nicht gefunden.");
    exit;
}
my $configtime=24*60*60*(-M $conf);
my $config_modified = ($configtime < $plugin_info{$plugname.'_configtime'}-1);

# Aufrufgrund ermitteln
my $event=undef;
if (!$plugin_initflag) 
{ $event='restart'; } # Restart des daemons / Reboot 
elsif ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'})
{ $event='modified'; } # Plugin modifiziert
elsif (%msg) { $event='bus'; return if !$config_modified && $msg{apci} eq "A_GroupValue_Response"; } # Bustraffic
elsif ($fh) { $event='socket'; } # Netzwerktraffic
else { $event='cycle'; } # Zyklus

# Rueckgabewert des Plugins
my $retval='';

# Im Falle eines Timeouts soll der Logikprozessor in 10s neu gestartet werden
$plugin_info{$plugname."_cycle"}=10;  

if($event=~/restart|modified/ || $config_modified || !defined $plugin_cache{$plugname}{logic}) 
{
    my $delim=$/; # wird spaeter zurueckgeschrieben

    # eibpa.conf - falls existent - einlesen
    my %eibpa=();

    if(open EIBPA, "</etc/wiregate/eibpa.conf")
    {
	$/="\n";    
	while(<EIBPA>)
	{
	    next unless /^(.*)\s+([0-9]+\.[0-9]+\.[0-9]+)\s*$/;
	    
	    $eibpa{$2}=$1;
	    $eibpa{$1}=$2;
	}
	close EIBPA; 
    }
    $plugin_cache{$plugname}{eibpa}=\%eibpa;

    my %logic=();
    my %settings=();

    # Konfigurationsfile einlesen
    open CONFIG, "<$conf" || return "cannot open config";
    $/=undef;
    my $lines = <CONFIG>;
    $lines =~ s/((?:translate|\'translate\'|\"translate\")\s*=>\s*sub\s*\{)/$1 my \(\$logname,\$state,\$ga,\$input,\$year,\$day_of_year,\$month,\$day_of_month,\$calendar_week,\$day_of_week,\$day_of_week_no,\$hour,\$minute,\$time_of_day,\$systemtime,\$weekend,\$weekday,\$holiday,\$workingday,\$day,\$night,\$date\)=\@\_;/sg;
    $lines =~ s/((?:prowl|\'prowl\'|\"prowl\")\s*=>\s*sub\s*\{)/$1 my \(\%context\)=\@\_;my \(\$input,\$state,\$result\)=\(\$context{input},\$context{state},\$context{result}\);/sg; 
    close CONFIG;
    eval $lines;
    $/=$delim;

    return "config error: $@" if $@;

    $logic{'_eibd_backend_address'}=$eibd_backend_address if !defined $logic{'_eibd_backend_address'} && defined $eibd_backend_address;

    # bestimmte Variablen loeschen
    for my $k (grep /^$plugname\_/, keys %plugin_info)
    {
	next if $k=~m/^$plugname\_last/;
	next unless $k=~m/$plugname\__(.*)_(timer|delay|cool|followup)/ && !defined $logic{$1}; 
	delete $plugin_info{$k};
    }

    # Konfiguration pruefen #######################################################
    my $count=0;
    my $err=0;

    for my $t (grep !/^(debug$|_)/, keys %logic)
    {
	# Debuggingflag gesetzt
	my $debug = $logic{debug} || $logic{$t}{debug}; 

	# Eintrag pruefen
	if(defined $logic{$t}{receive} && ref $logic{$t}{receive} && ref $logic{$t}{receive} ne 'ARRAY')
	{
	    plugin_log($plugname, "Config err: \$logic{$t}{receive} ist weder Skalar noch ARRAY-Referenz ([...]).");
	    next;
	}

	if(defined $logic{$t}{translate} && ref $logic{$t}{translate} && ref $logic{$t}{translate} ne 'CODE')
	{
	    plugin_log($plugname, "Config err: \$logic{$t}{translate} ist weder Skalar noch CODE-Referenz (sub {...}).");
	    next;
	}

	if(defined $logic{$t}{fetch} && ref $logic{$t}{fetch} && ref $logic{$t}{fetch} ne 'ARRAY')
	{
	    plugin_log($plugname, "Config err: \$logic{$t}{fetch} ist weder Skalar noch ARRAY-Referenz ([...]).");
	    next;
	}

	if(defined $logic{$t}{trigger} && ref $logic{$t}{trigger} && ref $logic{$t}{trigger} ne 'ARRAY')
	{
	    plugin_log($plugname, "Config err: \$logic{$t}{trigger} ist weder Skalar noch ARRAY-Referenz ([ga1,ga2>=2,ga3==ANY,...]).");
	    next;
	}

	if(defined $logic{$t}{state} && ref $logic{$t}{state} && ref $logic{$t}{state} ne 'HASH')
	{
	    plugin_log($plugname, "Config err: \$logic{$t}{state} ist weder Skalar noch HASH-Referenz ({...}).");
	    next;
	}

	if(defined $logic{$t}{prowl} && ref $logic{$t}{prowl} 
                && ! ((ref $logic{$t}{prowl} eq 'HASH') || (ref $logic{$t}{prowl} eq 'CODE')))
	{
	    plugin_log($plugname, "Config err: \$logic{$t}{prowl} ist weder Skalar noch "
                    . "HASH-Referenz ({...}) noch CODE-Referenz (sub {...})." . (ref $logic{$t}{prowl}));
	    next; 
	}

	my @keywords=qw(receive fetch trigger transmit translate debug delay timer prowl eibd_cache reply_to_read_requests 
                         ignore_read_requests transmit_only_on_request recalc_on_request state transmit_changes_only
                         execute_on_input_changes_only cool rrd transmit_on_startup transmit_on_config followup prowl execute_only_if_input_defined);
	my $keywords="(".join("|",@keywords).")";

	for my $k (keys %{$logic{$t}})
	{
	    next if $k=~/^$keywords$/;
	    plugin_log($plugname, "Config warn: \$logic{$t}, Eintrag '$k' wird ignoriert. Typo?");
	}
    }

    # Korrektur der Flags reply_to_read_requests, damit nicht mehrere Logiken antworten...
    my %responding=();

    for my $t (grep !/^(debug$|_)/, keys %logic)
    {
	my $transmit=$logic{$t}{transmit};
	next if !defined $transmit;

	# Default ist nun, dass NICHT geantwortet wird
	my $reply=$logic{$t}{reply_to_read_requests};
	$reply = 1 if $logic{$t}{recalc_on_request} || $logic{$t}{transmit_only_on_request}; # macht ja nur so Sinn

	# Flag ignore_read_requests ist veraltet, wird aber noch unterstuetzt
	$reply=!$logic{$t}{ignore_read_requests} if !defined $reply && defined $logic{$t}{ignore_read_requests}; 

	if($logic{$t}{ignore_read_requests})
	{
	    plugin_log($plugname, "Config warn: \$logic{$t} - Option ignore_read_requests ist veraltet (und nun per Default gesetzt).");
	}
	if($reply && $logic{$t}{ignore_read_requests})
	{
	    plugin_log($plugname, "Config err: \$logic{$t} hat sowohl reply_to_read_requests als auch ignore_read_requests gesetzt.");
	    $reply=0;
	}
	if($reply && (!defined $transmit || ref $transmit))
	{
	    plugin_log($plugname, "Config warn: \$logic{$t}: reply_to_read_requests funktioniert nur bei GENAU EINER transmit-Adresse.");
	    $reply=0;
	}

	my $footnote="";
	$footnote.="(T)" if $logic{$t}{transmit_only_on_request};
	$footnote.="(R)" if $logic{$t}{recalc_on_request};

	if(defined $reply)
	{
	    $logic{$t}{reply_to_read_requests}=$reply;
	}
	else
	{
	    delete $logic{$t}{reply_to_read_requests};
	}
	next unless $reply;

	$transmit=[$transmit] unless ref $transmit;
	for my $tx (@{$transmit})
	{
	    $responding{$tx}=[] unless defined $responding{$tx};
	    push @{$responding{$tx}}, $t.$footnote;
	}
    }

    my @problemgas=sort grep @{$responding{$_}}>1, keys %responding; # alle GAs mit mehr als einer antwortenden Logik

    if(@problemgas)
    {
	my %changed=();

	plugin_log($plugname, "Config warn: Lesezugriffe auf folgende transmit-Adressen werden von mehreren Logiken beantwortet:");
	for my $ga (@problemgas)
	{
	    plugin_log($plugname, "$ga -> ".join(", ", @{$responding{$ga}}));
	    my @change=sort grep !/\([TR]\)$/, @{$responding{$ga}};
	    shift @change unless grep /\([TR]\)$/, @{$responding{$ga}}; # erste antwortende Logik mag noch ok sein...

	    for my $t (@change)
	    {
		$logic{$t}{reply_to_read_requests}=0;
		$changed{$t}=1;
	    }
	}

	plugin_log($plugname, "(T) - transmit_only_on_request gesetzt");
	plugin_log($plugname, "(R) - recalc_on_request gesetzt");
	plugin_log($plugname, "Bei folgende Logiken wurde daher reply_to_read_requests=>0 gesetzt:");
	plugin_log($plugname, join ", ", keys %changed);
    }
    # Ende Konfiguration pruefen #######################################################

    # es folgt die eigentliche Initialisierung - abonnieren von GAs, Aufbau von Hilfsstrukturen
    for my $t (grep !/^(debug$|_)/, keys %logic)
    {
	# Debuggingflag gesetzt
	my $debug = $logic{debug} || $logic{$t}{debug}; 

	# transmit-Adresse(n) abonnieren
	my $transmit=$logic{$t}{transmit};

	if(defined $transmit)
	{
	    $transmit=groupaddress $transmit;

	    if($transmit)
	    {	
		$transmit=[$transmit] unless ref $transmit;

		for my $trm (@{$transmit})
		{
		    if(defined $eibgaconf{$trm}{ga})
		    {
			if($logic{$t}{reply_to_read_requests})
			{
			    $plugin_subscribe_read{$trm}{$plugname}=1; 
			    $plugin_subscribe_write{$trm}{$plugname}=1; 
			    $logic{'__'.$trm}{$t}=1;
			}
		    }
		    else
		    {
			plugin_log($plugname, "\$logic{$t}: Transmit-GA $trm nicht in eibga.conf gefunden");
#			plugin_log($plugname, join" ",@{$transmit});
		    }
		}
	    }
	}

	# trigger-Adresse(n) abonnieren
	if(defined $logic{$t}{trigger})
	{
	    my $trigger=$logic{$t}{trigger};
	    $trigger=[$trigger] unless ref $trigger eq 'ARRAY';
	    my @trigcond = grep !/^(within\s*[0-9]+(?:m|min|h|s)?|all_in_order|any|all)$/, @{$trigger};

	    my @doubles=();

	    for my $cond (@trigcond)
	    {
		my ($trg,$op,$sval) = ($cond=~/^([^\s<=>!]*)(?:(==|\seq|\slt|\sgt|\sle|\sge|>|<|>=|<=|!=)(.+?))?$/);

		if(defined $eibgaconf{$trg}{ga})
		{
		    $trg=groupaddress $trg;
		    $plugin_subscribe_write{$trg}{$plugname}=1;    
		    $logic{'__'.$trg}{$t}=1;
		}
		else
		{
		    plugin_log($plugname, "\$logic{$t}: Trigger-GA $trg nicht in eibga.conf gefunden");
		    next;
		}
		
		if($debug)
		{
		    my $qtrg=quotemeta $trg;
		    push @doubles, $trg if grep /^$qtrg$/, @{$transmit};			
		}
	    }
	    plugin_log($plugname, "\$logic{$t}: Moegliche Zirkellogik: ".(join",", @doubles)." ist Trigger- und Transmit-GA, und weder delay, cool noch transmit_only_on_request ist spezifiziert.") if $debug && @doubles && !defined $logic{$t}{cool} && !defined $logic{$t}{delay} && !defined $logic{$t}{transmit_only_on_request};
	}

	# Nun alle receive-Adressen abonnieren (eine oder mehrere)
	my $receive=$logic{$t}{receive};

	if(defined $receive)
	{
	    $receive=groupaddress $receive;
	    my @doubles=();

	    if($receive)
	    {	
		$receive=[$receive] unless ref $receive;
		
		for my $rec (@{$receive})
		{
		    if(defined $eibgaconf{$rec}{ga})
		    {
			$plugin_subscribe_write{$rec}{$plugname}=1;    
			$logic{'__'.$rec}{$t}=1;
		    }
		    else
		    {
			plugin_log($plugname, "\$logic{$t}: Receive-GA $rec nicht in eibga.conf gefunden");
		    }

		    if($debug)
		    {
			my $qrec=quotemeta $rec;
			push @doubles, $rec if grep /^$qrec$/, @{$transmit};			
		    }
		}
	    }

	    plugin_log($plugname, "\$logic{$t}: Moegliche Zirkellogik: ".(join",", @doubles)." ist Receive- und Transmit-GA, und weder delay, cool noch transmit_only_on_request ist spezifiziert.") if $debug && @doubles && !defined $logic{$t}{cool} && !defined $logic{$t}{delay} && !defined $logic{$t}{transmit_only_on_request};
	}

	# Zeitangaben in delay, cool und eibd_cache normalisieren
	for my $opt (qw(delay cool eibd_cache))
	{
	    if(defined $logic{$t}{$opt} && $logic{$t}{$opt}=~/^([0-9]*)(m|h|min|s)$/)
	    {
		my $val=$1; 
		$val*=3600 if $2 eq 'h';
		$val*=60 if $2 eq 'm' || $2 eq 'min';
		$logic{$t}{$opt}=$val;
	    }
	}

        # Timer-Logiken reagieren idR nicht auf Bustraffic auf den receive-Adressen, stattdessen haben sie einen komplexen Timer-Eintrag, 
	# der das Aufrufmuster festlegt. Dieses wird hier standardisiert fuer spaetere leichtere Auswertung: $logic->{$t}{timer} ist eine 
	# Liste oder ein einzelner Eintrag. Jeder solche Eintrag ist ein Hash zB der Art
	#    {day_of_month=>[(1..7)],day_of_week=>'Mo',time=>['08:30','09:20']}
	# Das gerade genannte Beispiel bedeutet "jeden Monat jeweils der erster Montag, 8:30 oder 9:20". Verwendbare Klauseln sind:
	#    year, month, day_of_month, calendar_week, day_of_week und time
	# Pflichtfeld ist lediglich time, die anderen duerfen auch entfallen. Jeder Wert darf ein Einzelwert oder eine Liste sein.

	if(defined $logic{$t}{timer})
	{
	    $logic{$t}{timer}=[$logic{$t}{timer}] if ref $logic{$t}{timer} eq 'HASH';
	    
	    for my $s (@{$logic{$t}{timer}})
	    {
                # Schedule-Form standardisieren (alle Eintraege in Listenform setzen und Wochentage durch Zahlen ersetzen)
		standardize_and_expand_single_schedule($t,$s,$debug);
	    }

	    # fuer Timer-Logiken: ersten Call berechnen
	    set_next_call('timer',$t,$logic{$t}{timer},$year,$day_of_year,$month,$day_of_month,$calendar_week,$day_of_week_no,
			  $hour,$minute,$time_of_day,$systemtime,$debug);
	}

	if(defined $logic{$t}{followup})
	{
	    my $followup=$logic{$t}{followup};

	    for my $q (grep !/^debug$/, keys %{$followup})
	    {
		next unless ref $followup->{$q}; 
		$followup->{$q}=[$followup->{$q}] if ref $followup->{$q} eq 'HASH';
		
		for my $s (@{$followup->{$q}})
		{
		    # Followup-Form standardisieren (alle Eintraege in Listenform setzen und Wochentage durch Zahlen ersetzen)
		    standardize_and_expand_single_schedule($t,$s,$debug);
		}
	    }
	}

	# Zaehlen der erfolgreich eingetragenen Logiken
	$count++;
    }

    $plugin_info{$plugname.'_configtime'}=$configtime;

    # Alle Logiken im Cache speichern:
    $plugin_cache{$plugname}{logic}=\%logic;
    $plugin_cache{$plugname}{settings}=\%settings;

    $retval.=$count." initialisiert;  ";
}

# Falls das config-File nicht veraendert wurde, geht es hier eigentlich los... alle Logikdefinitionen stehen schon in %plugin_cache
my $logic=$plugin_cache{$plugname}{logic};
my $settings=$plugin_cache{$plugname}{settings};
my $eibpa=$plugin_cache{$plugname}{eibpa};

$eibd_backend_address=$logic->{'_eibd_backend_address'} if defined $logic->{'_eibd_backend_address'};

# Alle Logiken mit transmit_on_startup=>1 als followup vormerken - dadurch kann uns ein Timeout nicht so sehr treffen...
if($event=~/restart|modified/)
{
    for my $t (grep !/^(debug$|_)/, keys %{$logic})
    {
	followup({$t=>0}) if $logic->{$t}{transmit_on_startup};
    }
}

# Das Gleiche fuer transmit_on_config
if($config_modified)
{
    for my $t (grep !/^(debug$|_)/, keys %{$logic})
    {
	followup({$t=>0}) if $logic->{$t}{transmit_on_config};
    }
}

# Aufruf durch Bustraffic (d.h. eine Logik wird durch receive=>..., trigger=>... oder auch transmit=>... auf einer GA "getroffen"
if($event=~/bus/)
{
    return $retval if $msg{apci} eq "A_GroupValue_Response";

    my $ga=$msg{dst};
    my $in=$msg{value};
    $msg{sender}=$eibpa->{$msg{src}} if defined $eibpa->{$msg{src}};

    my $keep_subscription=0; # falls am Ende immer noch Null, die GA stornieren

    # welche translate-Logik ist aufgerufen?
    for my $t (sort grep !/^(debug$|_)/, keys %{$logic->{'__'.$ga}})
    {
	# Flags abfragen
	my $reply=$logic->{$t}{reply_to_read_requests};
	my $debug = $logic->{debug} || $logic->{$t}{debug}; 

	# transmit hoert auf read- und write-Telegramme
	my $transmit=groupaddress($logic->{$t}{transmit});
	my $transmit_ga=0;
	if(defined $transmit)
	{
	    unless(ref $logic->{$t}{transmit})
	    {
		$transmit_ga=1 if $ga eq $transmit;
		$transmit=[$transmit];
	    }
	    else
	    {
		$transmit_ga=1 if grep /^$ga$/, @{$transmit};
	    }
	    $keep_subscription=1 if $transmit_ga;

	    # Sonderfall: Read- und Write-Telegramme auf einer Transmit-Adresse
	    # Diesen Sonderfall erstmal aus dem Weg raeumen...
	    if($transmit_ga)
	    {    
		# Ein Read-Request auf einer Transmit-GA wird mit dem letzten Ergebnis beantwortet
		# ausser recalc_on_request ist gesetzt, dann wird neu berechnet
		if($msg{apci} eq "A_GroupValue_Read")
		{  		
		    next unless $reply;
		    
		    my $result=$plugin_info{$plugname.'__'.$t.'_result'};
		    
		    if(!defined $result || $logic->{$t}{recalc_on_request})
		    {
			# falls gespeichertes Ergebnis ungueltig, neuer Berechnungsversuch
			$result=execute_logic($t,undef,undef,$year,$day_of_year,$month,$day_of_month,$calendar_week,$day_of_week,$day_of_week_no,$hour,$minute,$time_of_day,$systemtime,$weekend,$weekday,$holiday,$workingday,$day,$night,$date) 
			    unless defined $logic->{$t}{recalc_on_request} && $logic->{$t}{recalc_on_request}==0;
			
			if(defined $result)
			{
			    $retval.="$ga:Lesetelegramm -> \$logic->{$t}{transmit}(Logik) -> $ga:$result gesendet;  " if $debug;
			    knx_write($ga, $result, undef, 0x40) if defined $result; # response, DPT aus eibga.conf		    
			    $plugin_info{$plugname.'__'.$t.'_result'}=$result; 
			    last; # maximal eine Antwort auf ein read-Telegramm!
			}
			else
			{
			    $retval.="$ga:Lesetelegramm -> \$logic->{$t}{transmit}(Logik) -> nichts zu senden;  " if $debug;
			}		   
		    }	    
		    elsif(defined $result)
		    {
			$retval.="$ga:Lesetelegramm -> \$logic->{$t}{transmit}(memory) -> $ga:$result gesendet;  " if $debug;
			knx_write($ga, $result, undef, 0x40); # response, DPT aus eibga.conf		    
			last; # maximal eine Antwort auf ein read-Telegramm!
		    }
		    else
		    {
			$retval.="$ga:Lesetelegramm -> \$logic->{$t}{transmit}(memory) -> nichts zu senden;  " if $debug;	           
		    }
		    
		    next;
		}
		elsif($reply && !defined $plugin_info{$plugname.'__'.$t.'_delay'}) 
		{
		    # Speichern hat keinen Zweck, wenn wir spaeter sowieso nicht auf read-requests reagieren
		    # oder wenn noch ein Delay-Timer laeuft! - dann ist das noch zu sendende Logikresultat gespeichert 
		    # und darf nicht geaendert werden		    
		    $plugin_info{$plugname.'__'.$t.'_result'}=$in if defined $in; 
		}
	    }
	}

	next unless $msg{apci} eq "A_GroupValue_Write" && defined $in;
	# Wir wissen ab hier: Es liegt ein Write-Telegramm vor, kein Read- (oder Response-) Telegramm

	my $receive=groupaddress($logic->{$t}{receive});
	my $receive_ga=0; 
	if(defined $receive) 
	{
	    unless(ref $logic->{$t}{receive})
	    {
		$receive_ga=1 if $ga eq $receive;
	    }
	    else
	    {
		$receive_ga=1 if grep /^$ga$/, @{$receive};
	    }

	    if($receive_ga)
	    {
		$keep_subscription=1;
		$retval.="$msg{src} $ga:$in -> \$logic->{$t}{receive}" if $debug;
	    }
	}

	my $trigger_ga=0;
	if(!$receive_ga && defined $logic->{$t}{trigger}) 
	{
	    my $trigger=$logic->{$t}{trigger};
	    
	    $trigger=[$trigger] unless ref $trigger eq 'ARRAY';
	    
	    my $any=1;
	    my $all=grep /^all$/i, @{$trigger};
	    my $all_in_order=grep /^all_in_order$/i, @{$trigger};
	    ($any,$all)=(0,0) if $all_in_order;
	    $any=0 if $all;
	    
	    # Karenzzeit ("within") in Sekunden berechnen 
	    my $within=60; 
	    if($all || $all_in_order)
	    {
		my @within=grep /^within\s*([0-9]+)(h|min|m|s)?$/, @{$trigger};
		$within=$1*(defined $2 ? ($2 eq 'h' ? 3600:(($2 eq 'min' || $2 eq 'm') ? 60:1)):1)
		    if @within && $within[0]=~/^within\s*([0-9]+)(h|min|m|s)?$/;
	    }
	    
	    my @trigcond = grep !/^(within\s*[0-9]+(?:m|min|h|s)?|all_in_order|any|all)$/, @{$trigger};
	    
	    for my $cond (@trigcond)
	    {
		my ($tga,$op,$sval) = ($cond=~/^\s*(.*?)\s*(?:(==|\seq|\slt|\sgt|\sle|\sge|>|<|>=|<=|!=)(.+?))?\s*$/);
		$tga=groupaddress($tga);
		
		if($all || $all_in_order) # erfuellte Bedingungen loeschen, falls zu viel Zeit verstrichen
		{
		    my $lasttime=$plugin_cache{$plugname}{triggercache}{$t}{$cond};
		    delete $plugin_cache{$plugname}{triggercache}{$t}{$cond} if defined $lasttime && $systemtime-$lasttime>$within;
		}
		
		next unless $ga eq $tga;
		
		$keep_subscription=1;
		$trigger_ga=1 unless $any;
		
		if($any && verify($in,$op,$sval)) # Fuer "any" wird hier gleich die Bedingung geprueft
		{
		    $trigger_ga=1;
		}		
	    }
	    
	    my $retv=0;
	    
	    # Das Folgende wird nur ausgefuehrt, wenn all oder all_in_order spezifiziert wurde UND wir schon wissen,
	    # dass eine der in trigger vorkommenden GAs vorliegt
	    if($trigger_ga && !$any)
	    {
		for my $cond (@trigcond)
		{
		    my ($tga,$op,$sval) = ($cond=~/^(.*?)(?:(==|\seq|\slt|\sgt|\sle|\sge|>|<|>=|<=|!=)(.+?))?$/);
		    $tga=groupaddress($tga);
		    $plugin_cache{$plugname}{triggercache}{$t}{$cond}=$systemtime if $ga eq $tga && verify($in,$op,$sval);
		    
		    if(defined $plugin_cache{$plugname}{triggercache}{$t}{$cond})
		    {
			if($debug)
			{
			    $retval.="$msg{src} $ga:$in -> \$logic->{$t}{trigger}(" unless $retv; 
			    $retval.="," if $retv; 
			    $retval.="$cond";
			    $retv=1;
			}
		    }
		    else
		    {
			$trigger_ga=0; # Bedingung nicht erfuellt -> trigger nicht faellig
			last if $all_in_order; # fur "all_in_order" testen wir nicht weiter, fuer "all" schon...
		    }
		}
		delete $plugin_cache{$plugname}{triggercache}{$t} if $trigger_ga; # Reset aller Bedingungen	    
	    }
	    
	    if($debug && $trigger_ga)
	    {
		$retval.="$msg{src} $ga:$in -> \$logic->{$t}{trigger}" unless $retv;		
		$retval.=($retv?",":"(")."triggered" unless $any; 
		$retv=1;
	    }
	    
	    $retval.=")" if $retv && !$any;	    
	}

	next unless $receive_ga || $trigger_ga; 
	# Wir wissen ab hier: Es liegt ein Write-Telegramm auf einer der receive-Adressen oder einer Trigger-Adresse vor

	# Cool-Periode definiert und noch nicht abgelaufen?
	if(defined $plugin_info{$plugname.'__'.$t.'_cool'} && $plugin_info{$plugname.'__'.$t.'_cool'}>time())
	{
	    $retval.="(Cool) -> nichts zu senden;  " if $debug;
	    next;
	}

	# Aufruf der Logik-Engine
	my $prevResult=$plugin_info{$plugname.'__'.$t.'_result'};
	my $result=execute_logic($t,$ga,$in,$year,$day_of_year,$month,$day_of_month,$calendar_week,$day_of_week,$day_of_week_no,$hour,$minute,$time_of_day,$systemtime,$weekend,$weekday,$holiday,$workingday,$day,$night,$date);

	# In bestimmten Sonderfaellen nichts senden. Diese Sonderfaelle behandeln wir erstmal
	if(!defined $transmit || !defined $result)	    
	{
	    $retval.="(Logik) -> nichts zu senden;  " if $debug;
	    
	    if($logic->{$t}{delay} && defined $plugin_info{$plugname.'__'.$t.'_delay'}) # Laufender Delay?
	    {
		$plugin_info{$plugname.'__'.$t.'_result'}=$prevResult; # altes Resultat wieder aufnehmen
	    }
	    next;
	}

        # Ggf warnen vor Logiken, die aussehen wie Zirkel
	plugin_log($plugname, "(circle logic?)") if $msg{src} eq $eibd_backend_address && $transmit_ga && $in==$result && $debug;

	# Wir wissen nun: Die Logik hat ein Ergebnis gebracht (result ist definiert) und eine/mehrere transmit-GAs sind definiert

	# In bestimmten Faellen wird dennoch nicht oder nicht sofort gesendet:
	if($logic->{$t}{transmit_only_on_request})
	{
	    if(ref $logic->{$t}{transmit})
	    {
		$retval.="(Logik) -> [".join(",",@{$logic->{$t}{transmit}})."]:$result gespeichert;  " if $debug;
	    }
	    else
	    {
		$retval.="(Logik) -> ".$logic->{$t}{transmit}.":$result gespeichert;  " if $debug;
	    }
	    next;
	}
	if($result eq 'cancel' && ($logic->{$t}{delay} || $logic->{$t}{followup}))
	{
	    if($logic->{$t}{delay} && defined $plugin_info{$plugname.'__'.$t.'_delay'})
	    {
		$plugin_info{$plugname.'__'.$t.'_result'}=$prevResult; # altes Resultat wieder aufnehmen

		if($result eq 'cancel')
		{
		    delete $plugin_info{$plugname.'__'.$t.'_delay'};
		    $retval.="(Logik) -> wartender Delay-Timer geloescht;  " if $debug;
		}
		else
		{
		    $retval.=sprintf("(Logik) -> unveraendert, $prevResult wird in %.0f s gesendet;  ", $plugin_info{$plugname.'__'.$t.'_delay'}-time()) if $debug;
		}
	    }
	    else
	    {
		$retval.="(Logik) -> nichts zu senden;  " if $debug;
	    }

	    # Followup durch andere Logik definiert? Dann in Timer-Liste eintragen	    
	    if($result eq 'cancel' && defined $logic->{$t}{followup})
	    {
		my $followup=$logic->{$t}{followup};

		for my $q (grep !/^debug$/, keys %{$followup})
		{
		    plugin_log($plugname, "Followup '$q' storniert.") 
			if defined $plugin_info{$plugname.'__'.$q.'_followup'} && ($debug || $logic->{$q}{debug} || $followup->{debug});

		    delete $plugin_info{$plugname.'__'.$q.'_followup'};
		}
	    }

	    next;
	}

        if($logic->{$t}{transmit_changes_only} && ($result eq $prevResult)) 
	{
	    if(ref $logic->{$t}{transmit})
	    {
		$retval.="(Logik) -> [".join(",",@{$logic->{$t}{transmit}})."]:$result unveraendert -> nichts zu senden;  " if $debug;
	    }
	    else
	    {
		$retval.="(Logik) -> ".$logic->{$t}{transmit}.":$result unveraendert -> nichts zu senden;  " if $debug;
	    }
	    next;
        }

	# Falls delay spezifiziert, wird ein "Wecker" gestellt, um in einem spaeteren Aufruf den Wert zu senden
	if($logic->{$t}{delay})
	{
	    $plugin_info{$plugname.'__'.$t.'_delay'}=$systemtime+$logic->{$t}{delay};
	    $plugin_info{$plugname.'__'.$t.'_cool'}=time()+$logic->{$t}{delay}+$logic->{$t}{cool} if defined $logic->{$t}{cool};
	    if($debug)
	    {
		if(ref $logic->{$t}{transmit})
		{
		    $retval.="(Logik) -> [".join(",",@{$logic->{$t}{transmit}})."]:$result wird in ".$logic->{$t}{delay}."s gesendet;  ";
		}
		else
		{
		    $retval.="(Logik) -> ".$logic->{$t}{transmit}.":$result wird in ".$logic->{$t}{delay}."s gesendet;  ";
		}
	    }
	}
	else # sofort senden
	{
	    for my $trm (@{$transmit})
	    {
		knx_write($trm, $result); # DPT aus eibga.conf		    
	    }

	    update_rrd($logic->{$t}{rrd},'',$result) if defined $logic->{$t}{rrd};

	    if($debug)
	    {
		if(ref $logic->{$t}{transmit})
		{
		    $retval.="(Logik) -> [".join(",",@{$logic->{$t}{transmit}})."]:$result gesendet;  ";
		}
		else
		{
		    $retval.="(Logik) -> ".$logic->{$t}{transmit}.":$result gesendet;  ";
		}
	    }

	    # Cool-Periode starten
	    $plugin_info{$plugname.'__'.$t.'_cool'}=time()+$logic->{$t}{cool} if defined $logic->{$t}{cool};

	    # Followup durch andere Logik definiert? Dann in Timer-Liste eintragen	    
	    if(defined $logic->{$t}{followup})
	    {
		set_followup($t,$logic->{$t}{followup},$year,$day_of_year,$month,$day_of_month,$calendar_week,
			     $day_of_week_no,$hour,$minute,$time_of_day,$systemtime,$debug);
	    }
	}
    }

    unless($keep_subscription)
    {
	delete $plugin_subscribe{$ga}{$plugname};
	delete $plugin_subscribe_read{$ga}{$plugname};
	delete $plugin_subscribe_write{$ga}{$plugname};
	delete $logic->{'__'.$ga};
    }
}

# Ab hier gemeinsamer Code fuer Ausfuehrung auf Bustraffic hin, sowie "zyklische" Ausfuehrung (auf Timer/Followup/Delay hin).

# Evtl. faellige Timer finden, gleichzeitig Timer fuer nachste Aktion setzen
my $nexttimer=undef;
for my $timer (grep /$plugname\__.*_(timer|delay|followup|cool)/, keys %plugin_info) # alle Timer
{
    my $scheduled_time=$plugin_info{$timer};

    # Timer koennte IM LAUFE DIESER SCHLEIFE durch Logikausfuehrungen geloescht worden sein
    next unless defined $scheduled_time; 

    if(time()>=$scheduled_time) # Timer faellig? -> dann ausfuehren bzw. Resultat senden
    {
	# Relevanten Eintrag von %logic ermitteln
	$timer=~/$plugname\__(.*)_(timer|delay|followup|cool)/;
	my $t=$1; 
	my $reason=$2;

	if($reason eq 'cool' || !defined $logic->{$t})
	{
	    delete $plugin_info{$timer};
	    next;
	}

	# Debuggingflag gesetzt
	my $debug = $logic->{debug} || $logic->{$t}{debug}; 
	
	# Transmit-GA
	my $prevResult=$plugin_info{$plugname.'__'.$t.'_result'};
	my $result=$prevResult; 
	# zu sendendes Resultat ist bei delay einfach das zuletzt berechnete Ergebnis der Logik (delay)

	# in anderen Faellen (timer-Logik) muss das Ergebnis erst durch Aufruf der Logik-Engine berechnet werden.
	if($reason ne 'delay')
	{
	    $result=execute_logic($t,undef,undef,$year,$day_of_year,$month,$day_of_month,$calendar_week,$day_of_week,$day_of_week_no,$hour,$minute,$time_of_day,$systemtime,$weekend,$weekday,$holiday,$workingday,$day,$night,$date);
	}

	# Timer loeschen bzw. neu setzen
	if($reason eq 'timer')
	{
	    set_next_call('timer',$t,$logic->{$t}{timer},$year,$day_of_year,$month,$day_of_month,$calendar_week,$day_of_week_no,
			  $hour,$minute,$time_of_day,$systemtime,$debug);
	}
	elsif($reason eq 'delay' || ($reason eq 'followup' && $plugin_info{$timer}==$scheduled_time)) # kein neus Followup
	{
	    delete $plugin_info{$timer};
	}

	if(defined $result && !$logic->{$t}{transmit_only_on_request} && defined $logic->{$t}{transmit} 
	   && (!$logic->{$t}{transmit_changes_only} || $result ne $prevResult))
	{
	    my $transmit=groupaddress $logic->{$t}{transmit};

	    if($transmit)
	    {	
		$transmit=[$transmit] unless ref $transmit;

		for my $trm (@{$transmit})
		{
		    knx_write($trm, $result); # DPT aus eibga.conf		    
		}

		update_rrd($logic->{$t}{rrd},'',$result) if defined $logic->{$t}{rrd};

		if($debug)
		{
		    if(ref $logic->{$t}{transmit})
		    {
			$retval.="\$logic->{$t}{transmit}(Logik) -> [".join(",",@{$logic->{$t}{transmit}})."]:$result gesendet ($reason);  ";
		    }
		    else
		    {
			$retval.="\$logic->{$t}{transmit}(Logik) -> ".$logic->{$t}{transmit}.":$result gesendet ($reason);  ";
		    }
		}

		# Cool-Periode starten
		$plugin_info{$plugname.'__'.$t.'_cool'}=time()+$logic->{$t}{cool} if defined $logic->{$t}{cool};
	    }

	    # Followup durch andere Logik definiert? Dann in Timer-Liste eintragen	    
	    if(defined $result && defined $logic->{$t}{followup})
	    {
		my $followup=$logic->{$t}{followup};

		if($result eq 'cancel')
		{
		    for my $q (grep !/^(debug$|_)/, keys %{$followup})
		    {
			plugin_log($plugname, "Followup '$q' storniert.") 
			    if defined $plugin_info{$plugname.'__'.$q.'_followup'} && ($debug || $logic->{$q}{debug} || $followup->{debug});
			
			delete $plugin_info{$plugname.'__'.$q.'_followup'};
		    }
		}
		else
		{
		    set_followup($t,$followup,$year,$day_of_year,$month,$day_of_month,$calendar_week,
		                 $day_of_week_no,$hour,$minute,$time_of_day,$systemtime,$debug);
		}
	    }
	}
    }
    else # noch nicht faelliger Timer
    {
	$nexttimer=$timer if !defined $nexttimer || $plugin_info{$timer}<$plugin_info{$nexttimer};
    }
}

# Suche Timer-Logiken, bei denen aus irgendeinem Grund der naechste Aufruf noch nicht berechnet wurde,
# bspw wegen eines Plugin-Timeouts waehrend der Berechnung
for my $t (grep defined $logic->{$_}{timer}, grep !/^(debug$|_)/, keys %{$logic})
{
    # bei Timer-Logiken muesste ja immer eine naechste Aufrufzeit vorgemerkt sein. Sehen wir mal nach:
    my $ttime=$plugin_info{$plugname.'__'.$t.'_timer'};
    next if defined $ttime && $ttime>$systemtime; # alles in Ordnung

    plugin_log($plugname, "\$logic->{$t}: Timer verpasst, berechne erneut");

    my $debug=$logic->{debug} || $logic->{$t}{debug};
    set_next_call('timer',$t,$logic->{$t}{timer},$year,$day_of_year,$month,$day_of_month,$calendar_week,$day_of_week_no,
		  $hour,$minute,$time_of_day,$systemtime,$debug);
}

# Cycle auf naechsten Aufruf setzen
unless(defined $nexttimer)
{
    $plugin_info{$plugname."_cycle"}=0; # kein Aufruf noetig   
}
else
{
    my $cycle=int($plugin_info{$nexttimer}-time());
    $cycle=1 if $cycle<1;
    $plugin_info{$plugname."_cycle"}=$cycle;
    if($logic->{debug})
    {
	$nexttimer=~s/^$plugname\__(.*)_(timer|delay|followup)$/$1/;
	$retval.="Naechster Timer/Delay/Followup: $nexttimer in $cycle s";
    }
}

return unless $retval;
return $retval;


# Fuer Logiken mit timer-Klausel: Zeit des naechsten Aufrufs bestimmen
# Fuer einen Tag den jeweils naechsten berechnen
sub next_day
{
    my $d=shift;

    my $leapyear = ($d->{year} % 4)==0 && ($d->{year} % 100!=0 || $d->{year} % 400==0);
    my @days_in_month=(0,31,28+$leapyear,31,30,31,30,31,31,30,31,30,31);
    
    $d->{day_of_week} = ($d->{day_of_week} % 7)+1;
    $d->{calendar_week} += $d->{day_of_week}==1;
    $d->{day_of_month} = ($d->{day_of_month} % $days_in_month[$d->{month}])+1;
    $d->{month} += $d->{day_of_month}==1;
    $d->{month} = 1 if $d->{month}==13;
    $d->{day_of_year} = ($d->{day_of_year} % (365+$leapyear))+1;
    $d->{year} += ($d->{day_of_month}==1 && $d->{month}==1);

    add_day_info($d);

    return $d;
}

sub is_holiday
{
    my $Y=int(shift);
    my $doy=int(shift);

    # Schaltjahr?
    my $leapyear = ($Y % 4)==0 && ($Y % 100!=0 || $Y % 400==0);

    # Osterdatum berechnen (Algorithmus von Ron Mallen, Codefragment von Randy McLeary, beruht auf der Formel von Gauss/Lichtenberg) 
    my $C = int($Y/100);
    my $G = $Y%19;
    my $K = int(($C - 17)/25);
    my $I = ($C - int($C/4) - int(($C - $K)/3) + 19 * $G + 15)%30;
    $I = $I - int($I/28) * (1 - int($I/28) * int(29/($I + 1)) * int((21 - $G)/11));
    my $L = $I - ($Y + int($Y/4) + $I + 2 - $C + int($C/4))%7;   
    my $M = 3 + int(($L + 40)/44);
    my $D = $L + 28 - 31 * int($M/4);
    # diesjaehriger Ostersonntag ist $Y-$M-$D

    # julianisches Osterdatum (Tag im Jahr) berechnen $Y-$J
    my @days_before_month=(0,0,31,59+$leapyear,90+$leapyear,120+$leapyear,151+$leapyear,181+$leapyear,212+$leapyear,243+$leapyear,
			   273+$leapyear,304+$leapyear,334+$leapyear);
    my $J = $days_before_month[$M]+$D; 

    # Feiertagstabelle als Tageszahl im Jahr (1=1.Januar, 32=1.Februar usw.): 1.1., 1.5., 3.10., 25./26.12. 
    # und die auf Ostern bezogenen Kirchenfeiertage: Karfreitag, Ostern (2x), Christi Himmelfahrt, Pfingsten (2x), Fronleichnam
    my @holidays=(1,121+$leapyear,276+$leapyear,359+$leapyear,360+$leapyear,$J-2,$J,$J+1,$J+39,$J+49,$J+50,$J+60);
    
    # settings aus der .conf auslesen     
    my $settings=$plugin_cache{$plugname}{settings};     
    push @holidays, @{$settings->{holidays}} if defined $settings->{holidays};
                    
    return (grep { $_==$doy } @holidays) ? 1 : 0;
}

sub add_day_info
{
    my $d=shift;
    
    $d->{weekend} = ($d->{day_of_week}>=6) ? 1 : 0;
    $d->{weekday} = !$d->{weekend};
    $d->{holiday} = is_holiday($d->{year},$d->{day_of_year});
    $d->{workingday} = (!$d->{weekend} && !$d->{holiday}) ? 1 : 0;
    $d->{date} = sprintf("%02d/%02d",$d->{month},$d->{day_of_month});
}

# Passt ein bestimmtes Datum auf das Schema in einer "Schedule"?
sub schedule_matches_day
{
    my ($schedule,$day)=@_; 
    # Beide Argumente sind Hash-Referenzen, wobei schedule jeweils auf Listen zeigt, aber $day alle Kategorien enthaelt
    # zB $day={year=>2012,month=>4,day_of_month=>13,calendar_week=>16,day_of_week=>4,...};

    my $match=1; 

    for my $c (keys %{$schedule})
    {
	next if $c eq 'time'; # es geht nur um Tage
	unless(grep /^$day->{$c}$/, @{$schedule->{$c}})
	{
	    $match=0;
	    last;
	}
    }

    return $match;
}


sub standardize_and_expand_single_schedule
{
    my ($t,$s,$debug)=@_;
    my @days_in_month=(0,31,29,31,30,31,30,31,31,30,31,30,31); # hier ist jedes Jahr ein Schaltjahr
    my %weekday=(Mo=>1,Mo=>1,Mon=>1,Di=>2,Tu=>2,Tue=>2,Mi=>3,We=>3,Wed=>3,Do=>4,Th=>4,Thu=>4,Fr=>5,Fri=>5,Sa=>6,Sat=>6,So=>7,Su=>7,Sun=>7);

    # Timereintrag pruefen und standardisieren
    unless(ref $s eq 'HASH')
    {
	plugin_log($plugname, "Logiktimer zu Logik '$t' ist kein Hash oder Liste von Hashes");
	next;
    }
    
    unless(defined $s->{time})
    {
	plugin_log($plugname, "Logiktimer zu Logik '$t' enthaelt mindestens einen Eintrag ohne Zeitangabe (time=>...)");
	next;
    }	    

    # Eintrag pruefen und standardisieren
    for my $k (keys %{$s})
    {
	unless($k=~/^(year|month|calendar_week|day_of_year|day_of_month|day_of_week|date|holiday|weekend|weekday|workingday|time)$/)
	{
	    plugin_log($plugname, "Logiktimer zu Logik '$t': Unerlaubter Eintrag '$k'; erlaubt sind year, month, calendar_week, day_of_year, day_of_month, day_of_week, date, weekend, weekday, holiday, workingday, und Pflichteintrag ist time");
	    next;
	}

	if($k=~/^(holiday|weekend|weekday|workingday)$/ && !ref $s->{$k} && $s->{$k}!~/^(0|1)$/)
	{
	    plugin_log($plugname, "Logiktimer zu Logik '$t': Unerlaubter Wert '$k\->$s->{$k}': erlaubt sind 0 und 1");
	    next;
	}
	
	unless(!ref $s->{$k} || ref $s->{$k} eq 'ARRAY')
	{
	    plugin_log($plugname, "Logiktimer zu Logik '$t': '$k' muss auf Skalar oder Array ($k=>[...]) verweisen");
	    next;
	}
	
	$s->{$k}=[$s->{$k}] unless ref $s->{$k} eq 'ARRAY'; # alle Kategorien in Listenform
	
	if($k eq 'day_of_week')
	{
	    for my $wd (sort { length($b) <=> length($a) } keys %weekday)
	    {
		foreach (@{$s->{$k}}) { s/$wd/$weekday{$wd}/gie } # Wochentage in Zahlenform
	    }
	}
	
	# Expandieren von Bereichen, z.B. month=>'3-5'
	if($k!~/^(time|date)$/ && grep /\-/, @{$s->{$k}})
	{
	    my $newlist=[];
	    for my $ks (@{$s->{$k}})
	    {
		if($ks=~/^([0-9]+)\-([0-9]+)$/)
		{
		    push @{$newlist}, ($1..$2);
		}
		else
		{
		    push @{$newlist}, $ks;
		}		    
	    }
	    @{$s->{$k}} = sort @{$newlist};
	} 
	elsif($k eq 'date')
	{
	    my $newlist=[];
	    for my $ks (@{$s->{date}})
	    {
		if($ks=~/^([0-9]+)\/([0-9]+)\-([0-9]+)\/([0-9]+)$/)
		{
		    my ($m1,$d1,$m2,$d2)=($1,$2,$3,$4); 
		    while($m1<$m2 || ($m1==$m2 && $d1<=$d2))
		    {
			push @{$newlist}, sprintf("%02d\/%02d",$m1,$d1);
			if($d1==$days_in_month[$m1]) { $m1++; $d1=1; } else { $d1++; }
		    }
		}
		elsif($ks=~s/([0-9]+)\/([0-9]+)/sprintf("%02d\/%02d",$1,$2)/ge)
		{
		    push @{$newlist}, $ks;
		}	
		else
		{
		    plugin_log($plugname, "Logiktimer zu Logik '$t': unerlaubte Datumsangabe date->$ks (erlaubt sind Einzeleintraege wie '02/03' oder Bereich wie '02/28-03/15')");
		}
	    }
	    @{$s->{date}} = sort @{$newlist};
	}
	else
	{
	    @{$s->{$k}}=sort @{$s->{$k}}; # alle Listen sortieren
	}
    }
}


# Fuer eine bestimmte Timer-Logik den naechsten Aufruf berechnen (relativ komplexes Problem wegen der 
# vielen moeglichen Konfigurationen und Konstellationen)
sub set_next_call
{
    # Typ (timer oder followup), der relevante Eintrag in %logic, Zeitangaben und das Debugflag
    my ($type,$t,$schedule,$year,$day_of_year,$month,$day_of_month,$calendar_week,$day_of_week_no,$hour,$minute,$time_of_day,$systemtime,$debug)=@_; 
    $type='timer' unless $type=~/^(timer|followup)$/;

    my $now=int($hour)*60+$minute;
    my $nowstring=sprintf("%02d:%02d",$hour,$minute);

    # Das "Day-Hash" wird dazu verwendet, Tage zu finden, auf die die Timer-Spezifikation zutrifft
    # Wir fangen dabei mit today, also heute, an.
    my $today={year=>$year,day_of_year=>$day_of_year,month=>$month,day_of_month=>$day_of_month,
	       calendar_week=>$calendar_week,day_of_week=>$day_of_week_no};
    add_day_info($today);
    
    # Suche den naechsten Aufruf dieser Logik
    my $nextcall=undef;

    # Zeitangabe im Tag. Am Ende interessiert uns (i) fuer den Fall, dass der naechste Aufruf morgen oder spaeter ist,
    # nur der erste Aufruf der Logik am Tag, und (ii) fuer den Fall, dass der naechste Aufruf schon heute stattfindet,
    # der erste Aufruf der Logik nach der aktuellen Tageszeit. Beides errechnen wir jetzt.
    my %firsttime=();
    for my $s (@{$schedule})
    {
	my $nexttime=undef;

	for my $ts (@{$s->{time}})
	{
	    $ts=~s/(\-[0-9][0-9]:[0-9][0-9])(\+[1-9][0-9]*(?:m|h|min))$/$2$1/;
	    unless($ts=~/^(.*?)([0-9][0-9]):([0-9][0-9])\+([1-9][0-9]*)(m|h|min)(?:\-([0-9][0-9]):([0-9][0-9]))?$/)
	    {
		# Einzelne Zeitangaben wie '07:30'
		if($ts=~/^(.*?)([0-9][0-9]):([0-9][0-9])$/)
		{
		    my $ti=sprintf("%02d:%02d",$2, $3);
		    $firsttime{$s}=$ti if !defined $firsttime{$s} || ($firsttime{$s} gt $ti);
		    $nexttime=$ti if $ti gt $nowstring && (!defined $nexttime || $nexttime gt $ti);
		}
		else
		{
		    plugin_log($plugname, "Logik '$t': Unerlaubter time-Eintrag '$ts' in timer oder followup (erlaubt sind Eintraege wie '14:05' oder '07:30+30m-14:30' oder '07:30+5m-08:00')");
		    next;
		}
	    }
	    else
	    {
		# Expandieren periodischer Zeitangaben, das sind Zeitangaben der Form
		# time=>'08:00+30min' - ab 08:00 alle 30min
		# time=>'08:00+5min-09:00' - ab 08:00 alle 5min mit Ende 09:00
		my ($head,$t1,$period,$t2)=($1,$2*60+$3,$4*($5 eq 'h' ? 60 : 1),(defined $6 ? ($6*60+$7) : 24*60));	    
		
		# erster Zeitpunkt am Tag
		my $ti=sprintf("%02d:%02d",$t1/60,$t1%60);
		$firsttime{$s}=$ti if !defined $firsttime{$s} || ($firsttime{$s} gt $ti);
		
		# erster Zeitpunkt nach aktueller Tageszeit
		if($t1>$now)
		{
		    $nexttime=$ti if !defined $nexttime || $nexttime gt $ti;
		}
		elsif($t1<=$now && $t2>$now)
		{
		    $t1+=int(($now-$t1)/$period+1)*$period;
		    next if $t1>$t2;
		    
		    $ti=sprintf("%02d:%02d",$t1/60,$t1%60);
		    $nexttime=$ti if !defined $nexttime || ($nexttime gt $ti);
		}		
	    }
	}

	# Steht heute aus diesem Schedule noch ein Termin an?
	$nextcall=$nexttime if schedule_matches_day($s,$today) && defined $nexttime && (!defined $nextcall || $nextcall gt $nexttime);
    }

    # Wenn $nextcall hier bereits definiert, enthaelt es die naechste Aufrufzeit des Timers im Format "08:30"
    my $schedules_done=0; 
    my $days_until_nextcall=0;

    # falls nextcall noch nicht definiert, geht es jetzt um den naechsten Tag mit Termin
    until($schedules_done || defined $nextcall || $days_until_nextcall>5000) # maximal ca. 15 Jahre suchen
    {
	$schedules_done=1;
	$days_until_nextcall++;
	$today=next_day($today);

	for my $s (@{$schedule})
	{
	    $schedules_done=0 if !defined $s->{year} || $s->{year}[-1]>=$today->{year}; 
	    next unless schedule_matches_day($s,$today);
		
	    # an diesem Tag gibt es einen Termin! Wann ist der erste?
	    $nextcall=$firsttime{$s} if !defined $nextcall || $nextcall gt $firsttime{$s};	
	}
    }

    if(defined $nextcall)
    {
	my $daytext='';
	my $datum="$today->{day_of_month}\.$today->{month}\.$today->{year}";
	$daytext = ($days_until_nextcall==1 ? " morgen" : " in $days_until_nextcall Tagen, am $datum,") if $days_until_nextcall;
    
	# Zeitdelta zu jetzt berechnen
	if($nextcall=~/^([0-9]+)\:([0-9]+)/)
	{
	    my $seconds=3600*($1-substr($time_of_day,0,2))+60*($2-substr($time_of_day,3,2))-substr($time_of_day,6,2);
	    plugin_log($plugname, "Naechster Aufruf der $type-Logik '$t' $daytext um $nextcall.") if $debug;

	    my $ttime=$systemtime+$seconds+3600*24*$days_until_nextcall;
	    $plugin_info{$plugname.'__'.$t.'_'.$type}=$ttime;
	}
	else
	{
	    plugin_log($plugname, "Ungueltige Uhrzeit des naechsten Aufrufs der $type-Logik '$t'$daytext.");# if $debug;
	    delete $plugin_info{$plugname.'__'.$t.'_'.$type};
	}
    }
    else
    {
	plugin_log($plugname, "Logik '$t' wird von $type nicht mehr aufgerufen (alle in time=>... festgelegten Termine sind verstrichen).") 
	    if @{$schedule} && $debug;

	delete $plugin_info{$plugname.'__'.$t.'_'.$type}; 
    }
}

# Setzen eines Followup-Calls
sub set_followup
{
    my ($t,$followup,$year,$day_of_year,$month,$day_of_month,$calendar_week,$day_of_week_no,$hour,$minute,$time_of_day,$systemtime,$debug)=@_;    my $logic=$plugin_cache{$plugname}{logic};
    $t='?' unless defined $t;
    
    if($t ne '?' && !defined $logic->{$t})
    {
	plugin_log($plugname, "'followup' mit unbekannter Ausgangslogik '$t' aufgerufen.");
    }
    elsif(!ref $followup)
    {
	plugin_log($plugname, "\$logic->{$t}: Fehler in Followup-Definition. Korrekt sind Definitionen wie {'Logik1'=>'3s'} oder {'Logik1'=>{time=>'10:00'}}");
    }
    else
    {
	$debug=1 if $followup->{debug};
	for my $q (grep !/^debug$/, keys %{$followup})
	{	
	    unless(defined $logic->{$q})
	    {
		plugin_log($plugname, "\$logic->{$t}: Followup-Definition verweist auf unbekannte Logik '$q'.");
	    }
	    else
	    {
		if(!ref $followup->{$q} && $followup->{$q}=~/^([0-9]*)(m|h|min|s)?$/)
		{
		    my $delay=$1; 
		    $delay*=3600 if $2 eq 'h';
		    $delay*=60 if $2 eq 'm' || $2 eq 'min';
		    $delay=5 unless defined $delay;
		    $plugin_info{$plugname.'__'.$q.'_followup'}=$systemtime+$delay;
		}
		elsif(!ref $followup->{$q})
		{
		    if($followup->{$q} eq 'cancel')
		    {
			plugin_log($plugname, "Followup '$q' storniert.") 
			    if defined $plugin_info{$plugname.'__'.$q.'_followup'} && ($debug || $logic->{$q}{debug});
		    }
		    else
		    {
			plugin_log($plugname, "Followup-Anfrage fuer '$q' enthaelt '$followup->{$q}'. Korrekt sind Definitionen wie {'Logik1'=>'3s'} oder {'Logik1'=>{time=>'10:00'}}");
		    }    
		    delete $plugin_info{$plugname.'__'.$q.'_followup'};
		}
		else
		{
		    set_next_call('followup',$q,$followup->{$q},$year,$day_of_year,$month,$day_of_month,$calendar_week,
				  $day_of_week_no,$hour,$minute,$time_of_day,$systemtime,undef);
		}

		if(($debug || $logic->{$q}{debug}) && defined $plugin_info{$plugname.'__'.$q.'_followup'})
		{
		    my $delay=int($plugin_info{$plugname.'__'.$q.'_followup'}-$systemtime);
		    plugin_log($plugname, "Followup '$q' folgt ".($delay>0 ? "in $delay s.":"sofort."));
		}
	    }
	}
    }
}    

# Fuer direkten Aufruf aus einer Logik
sub followup
{
    my ($followup)=@_;
    
    my $date=strftime("%W,%a,%u,%m,%d,%Y,%j,%H,%M,%T",localtime);
    plugin_log($plugname, "Datum/Uhrzeit nicht lesbar: '$date'.") unless ($date=~/^(.+),(.+),(.+),(.+),(.+),(.+),(.+),(.+),(.+),(.+)$/);

    my $calendar_week=$1+1;
    my $day_of_week=$2;
    my $day_of_week_no=$3;
    my $month=int($4);
    my $day_of_month=int($5);
    my $year=int($6);
    my $day_of_year=int($7);
    my $hour=int($8);
    my $minute=int($9);
    my $time_of_day=$10; # '08:30:43'
    my $systemtime=time();
    $date=sprintf("%02d/%02d",$month,$day_of_month);

    # Falls timer-Definition enthalten, muss diese zunaechst standardisiert werden. 
    for my $q (grep !/^debug$/, keys %{$followup})
    {
	next unless ref $followup->{$q};
	$followup->{$q}=[$followup->{$q}] if ref $followup->{$q} eq 'HASH';
		
	for my $s (@{$followup->{$q}})
	{
	    standardize_and_expand_single_schedule('?',$s,$followup->{debug});
	}
    }

    return set_followup(undef,$followup,$year,$day_of_year,$month,$day_of_month,$calendar_week,$day_of_week_no,$hour,$minute,$time_of_day,
			$systemtime,$followup->{debug});
}


# Es folgt die eigentliche Logik-Engine 
# Im wesentlichen Vorbesetzen von input und state, Aufrufen der Logik, knx_write, Zurueckschreiben von state
sub execute_logic
{
    my ($t,$ga,$in,$year,$day_of_year,$month,$day_of_month,$calendar_week,$day_of_week,$day_of_week_no,$hour,$minute,$time_of_day,$systemtime,$weekend,$weekday,$holiday,$workingday,$day,$night,$date)=@_; # Logikindex $t, Bustelegramm erhalten auf $ga mit Inhalt $in
    my $logic=$plugin_cache{$plugname}{logic};

    # Debuggingflag gesetzt
    my $debug = $logic->{debug} || $logic->{$t}{debug}; 
    
    # als erstes definiere das Input-Array fuer die Logik
    my $input=$in;

    # alle receive-GAs
    my $receive=groupaddress $logic->{$t}{receive};
    my $fetch=groupaddress $logic->{$t}{fetch};

    if(defined $fetch)
    {
	if(!defined $receive)
	{
	    $receive=$fetch;
	}
	else
	{
	    # Arrays machen, falls es noch keines ist
	    $fetch=[$fetch] unless ref $fetch; 
	    $receive=[$receive] unless ref $receive; 
	    push @{$receive}, @{$fetch};
	}
    }

    # Array-Fall: bereite Input-Array fuer Logik vor
    if(!ref $receive)
    {
	$in=$input=knx_read($receive, (defined $logic->{$t}{eibd_cache}?$logic->{$t}{eibd_cache}:300)) 
	    if defined $receive && (!defined $ga || $ga ne $receive);
    }
    else
    {
	$input=[];
	for my $rec (@{$receive})
	{
	    if($ga eq $rec)
	    {
		push @{$input}, $in;
	    }
	    else
	    {
		my $val=knx_read($rec, (defined $logic->{$t}{eibd_cache}?$logic->{$t}{eibd_cache}:300));
		push @{$input}, $val;
	    }
	}
    }
    
    # Alle Inputs definiert?
    if($logic->{$t}{execute_only_if_input_defined})
    {
	if(!ref $receive)
	{
	    return undef unless defined $input;
	}
	else
	{
	    for my $i (@{$input})
	    {
		return undef unless defined $i;
	    }
	}
    }
    
    # ab hier liegt $input komplett vor. Ggf testen, ob Inhalte sich gaendert haben
    if($logic->{$t}{execute_on_input_changes_only})
    {	
	my $inputstr=((!ref $receive) ? $input : join(";", @{$input})).";";

	if(defined $plugin_cache{$plugname}{inputcache}{$t})
	{
	    return undef if $plugin_cache{$plugname}{inputcache}{$t} eq $inputstr;
	}

	$plugin_cache{$plugname}{inputcache}{$t}=$inputstr;
    }

    # N un muss die Logik ausgewertet und das Resultat auf der Transmit-GA uebertragen werden
    my $result=undef;
    my %prowlContext=();
    my $timebefore=time();
    
    unless(ref $logic->{$t}{translate}) 
    {
	# Trivialer Fall: translate enthaelt einen fixen Rueckgabewert
	$plugin_info{$plugname.'__'.$t.'_result'}=$result=$logic->{$t}{translate};
	# prowlContext befuelen
	$prowlContext{result}=$result;
	$prowlContext{input}=$input;
    }
    elsif(!ref $logic->{$t}{state})
    {
	# Einfacher aber haeufiger Fall: skalarer $state
	# $state mit Ergebnis des letzten Aufrufs vorbesetzen
	my $state=$plugin_info{$plugname.'__'.$t.'_result'};
	
	# Funktionsaufruf, das Ergebnis vom letzten Mal steht in $state
	$result=$logic->{$t}{translate}($t,$state,$ga,$input,$year,$day_of_year,$month,$day_of_month,$calendar_week,$day_of_week,$day_of_week_no,$hour,$minute,$time_of_day,$systemtime,$weekend,$weekday,$holiday,$workingday,$day,$night,$date);
	
	# prowlContext befüllen
	$prowlContext{result}=$result;
	$prowlContext{state}=$state;
	$prowlContext{input}=$input;

	# Ergebnis des letzten Aufrufs zurueckschreiben
	if(defined $result)
	{
	    $plugin_info{$plugname.'__'.$t.'_result'}=$result;
	}
	else
	{
	    delete $plugin_info{$plugname.'__'.$t.'_result'};
	}
    }
    else
    {
	# Komplexer Fall: $state-Hash aus %logic initialisieren
	my $state=$logic->{$t}{state};
	my @vars=keys %{$state};
	push @vars, 'result';
	
	# Nun die dynamischen Variablen aus plugin_info hinzufuegen
	for my $v (@vars)
	{
	    $state->{$v}=$plugin_info{$plugname.'__'.$t.'_'.$v} if defined $plugin_info{$plugname.'__'.$t.'_'.$v};
	}
	
	# Funktionsaufruf, das Ergebnis vom letzten Mal steht in $state->{result}
	$result=$state->{result}=$logic->{$t}{translate}($t,$state,$ga,$input,$year,$day_of_year,$month,$day_of_month,$calendar_week,$day_of_week,$day_of_week_no,$hour,$minute,$time_of_day,$systemtime,$weekend,$weekday,$holiday,$workingday,$day,$night,$date);

	# prowlContext befüllen
	$prowlContext{result}=$result;
	$prowlContext{state}=$state;
	$prowlContext{input}=$input;
	
	# Alle dynamischen Variablen wieder nach plugin_info schreiben
	# Damit plugin_info nicht durch Konfigurationsfehler vollgemuellt wird, 
	# erlauben wir nur Eintraege mit defined-Werten
	for my $v (@vars)
	{
	    if(defined $state->{$v})
	    {
		$plugin_info{$plugname.'__'.$t.'_'.$v}=$state->{$v};
	    }
	    else
	    {
		# wenn die Logik den Wert undef in eine state-Variable schreibt, 
		# wird beim naechsten Aufruf wieder der Startwert aus %logic genommen,
		delete $plugin_info{$plugname.'__'.$t.'_'.$v};
	    }
	}
    }
    
    # Prowl-Nachrichten senden, falls definiert
    if(defined $logic->{$t}{prowl})
    {
        my %prowlParametersSource;
        if (ref $logic->{$t}{prowl}) {
            %prowlParametersSource = %{$logic->{$t}{prowl}} if (ref $logic->{$t}{prowl} eq 'HASH');
            %prowlParametersSource = $logic->{$t}{prowl}(%prowlContext) if (ref $logic->{$t}{prowl} eq 'CODE');
        }
        else 
        {
            %prowlParametersSource = ( event => $logic->{$t}{prowl} );
        }
        
        if (%prowlParametersSource) {
            sendProwl((
                    debug => $debug,
                    priority => $prowlParametersSource{priority} || $settings->{prowl}{priority},
                    event => $prowlParametersSource{event} || $settings->{prowl}{event},
                    description => $prowlParametersSource{description} || $settings->{prowl}{description},
                    application => $prowlParametersSource{application} || $settings->{prowl}{application},
                    url => $prowlParametersSource{url} || $settings->{prowl}{url},
                    apikey => $prowlParametersSource{url} || $settings->{prowl}{apikey}
                ));
        }
    }

    my $timeelapsed=time()-$timebefore;
    
    plugin_log($plugname, sprintf("WARNING: $t: time elapsed %0.2fs",$timeelapsed)) if $timeelapsed>0.5;

    return $result;
}

# Umgang mit GA-Kurznamen und -Adressen

sub groupaddress
{
    my $short=shift;

    return undef unless defined $short;

    if(ref $short)
    {
	my $ga=[];
	for my $sh (@{$short})
	{
	    if($sh!~/^[0-9\/]+$/ && defined $eibgaconf{$sh}{ga})
	    {
		push @{$ga}, $eibgaconf{$sh}{ga};
	    }
	    else
	    {
		push @{$ga}, $sh;
	    }
	}
        return $ga;
    }
    else
    {
	my $ga=$short;

	if($short!~/^[0-9\/]+$/ && defined $eibgaconf{$short}{ga})
	{
	    $ga=$eibgaconf{$short}{ga};
	}

	return $ga;
    }
}

sub sendProwl {
    my (%parameters)=@_;
    my ($priority, $event, $description, $application, $url, $apikey);

    my $settings=$plugin_cache{$plugname}{settings};

    # Parameter ermitteln
    # dom, 2012-11-05: $settings auch hier auswerten. Damit kann sendProwl() direkt aus der Logik aufgerufen werden!
    $priority = $parameters{priority} || $settings->{prowl}{priority} || 0;
    $event = $parameters{event} || $settings->{prowl}{event} || '[unbenanntes Ereignis]';
    $description = $parameters{description} || $settings->{prowl}{description} || '';
    $application = $parameters{application} || $settings->{prowl}{application} || 'WireGate KNX';
    $url = $parameters{url} || $settings->{prowl}{url} || '';
    $apikey = $parameters{apikey} || $settings->{prowl}{apikey} || '';
    
    use LWP::UserAgent;
    use URI::Escape;
    use Encode;
 
    # Falls nur ein einziger skalarer API key geliefert wurde, muss dieser in 
    # ein Array gehüllt werden
    if(ref $apikey ne 'ARRAY') {
        $apikey = [$apikey];
    }

    # Nachricht senden an jeden API key
    for my $singleApikey (@{$apikey}) {
        # HTTP Request aufsetzen
        my ($userAgent, $request, $response, $requestURL);
        $userAgent = LWP::UserAgent->new;
        $userAgent->agent("WireGatePlugin/1.0");

        $requestURL = sprintf("https://prowl.weks.net/publicapi/add?apikey=%s&application=%s&event=%s&description=%s&priority=%d&url=%s",
      	    uri_escape($singleApikey),
    	    uri_escape(encode("utf8", $application)),
    	    uri_escape(encode("utf8", $event)),
    	    uri_escape(encode("utf8", $description)),
    	    uri_escape($priority),
    	    uri_escape($url));
  
        $request = HTTP::Request->new(GET => $requestURL);
        #$request->timeout(5);

        $response = $userAgent->request($request);
  
        if ($response->is_success) {
   	    plugin_log($plugname, "Prowl-Nachricht erfolgreich abgesetzt: $priority, $event, $description, $application") if $parameters{debug};
        } elsif ($response->code == 401) {
   	    plugin_log($plugname, "Prowl-Nachricht nicht abgesetzt: API key gültig?");
        } else {
   	    plugin_log($plugname, "Prowl-Nachricht nicht abgesetzt: " . $response->content);
        }
    }
    return undef;
}

sub verify
{
    my ($a,$op,$b)=@_;

    return 1 if defined $a && (!defined $op || $b eq 'ANY');
    return 1 if $op eq '==' && $a==$b;
    return 1 if $op eq '<=' && $a<=$b;
    return 1 if $op eq '>=' && $a>=$b;
    return 1 if $op eq '!=' && $a!=$b;
    return 1 if $op eq '<' && $a<$b;
    return 1 if $op eq '>' && $a>$b;
    return 1 if $op eq 'eq' && $a eq $b;
    return 1 if $op eq 'lt' && $a lt $b;
    return 1 if $op eq 'le' && $a le $b;
    return 1 if $op eq 'gt' && $a gt $b;
    return 1 if $op eq 'ge' && $a ge $b;
    return 1 if $op eq 'ne' && $a ne $b;

    return 0;
}
