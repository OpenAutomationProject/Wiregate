#!/usr/bin/perl -w
##################
# Logikprozessor #
##################
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License

#$plugin_info{$plugname.'_cycle'}=0; return 'deaktiviert';

# eibgaconf fixen falls nicht komplett indiziert
# Kann ab Wiregate PL32 entfallen
#if(!exists $eibgaconf{ZV_Uhrzeit})
#{
#    for my $ga (grep /^[0-9\/]+$/, keys %eibgaconf)
#    {
#	$eibgaconf{$ga}{ga}=$ga;
#	my $name=$eibgaconf{$ga}{name};
#	next unless defined $name;
#	$eibgaconf{$name}=$eibgaconf{$ga};
#
#	next unless $name=~/^\s*(\S+)/;
#	my $short=$1;
#	$short='ZV_'.$1 if $eibgaconf{$ga}{name}=~/^Zeitversand.*(Uhrzeit|Datum)/;
#
#	$eibgaconf{$ga}{short}=$short;
#	$eibgaconf{$short}=$eibgaconf{$ga};
#    }
#}

# Tools und vorbesetzte Variablen fur die Logiken
sub limit { my ($lo,$x,$hi)=@_; return $x<$lo?$lo:($x>$hi?$hi:$x); }
my $date=`/bin/date +"%W,%a,%u,%m,%d,%Y,%j,%H,%M,%X"`;
plugin_log($plugname, "Datum/Uhrzeit konnte nicht lesbar.") unless $date=~/^(.+),(.+),(.+),(.+),(.+),(.+),(.+),(.+),(.+),(.+)$/;
my $calendar_week=$1;
my $day_of_week=$2;
my $day_of_week_no=$3;
my $month=int($4);
my $day_of_month=int($5);
my $year=int($6);
my $day_of_year=int($7);
my $hour=int($8);
my $minute=int($9);
my $time_of_day=$10; # '08:30:43'
my $weekend=($day_of_week_no>=6);
my $weekday=!$weekend;
my $holiday=is_holiday($year,$day_of_year);
my $workingday=(!$weekend && !$holiday);
my $day=($hour>7 && $hour<23);
my $night=!$day;
my $systemtime=time();
my $date=sprintf("%02d/%02d",$month,$day_of_month);

# Konfigurationsfile einlesen
my $eibd_backend_address='1.1.254';
my %logic=();
my %settings=();
my $conf="/etc/wiregate/plugin/generic/conf.d/$plugname"; 
$conf.='.conf' unless $conf=~s/\.pl$/.conf/;
open FILE, "<$conf" || return "no config found";
$/=undef;
my $lines = <FILE>;
$lines =~ s/((?:translate|\'translate\'|\"translate\")\s*=>\s*sub\s*\{)/$1 my \(\$state,\$input\)=\@\_;/sg; 
close FILE;
eval($lines);
return "config error: $@" if $@;

# Aufrufgrund ermitteln
my $event=undef;
if (!$plugin_initflag) 
{ $event='restart'; } # Restart des daemons / Reboot
elsif ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'})
{ $event='modified'; } # Plugin modifiziert
elsif (%msg) { $event='bus'; } # Bustraffic
elsif ($fh) { $event='socket'; } # Netzwerktraffic
else { $event='cycle'; } # Zyklus

# Konfigfile seit dem letzten Mal geaendert?
my $configtime=24*60*60*(-M $conf);
my $config_modified = ($configtime < $plugin_info{$plugname.'_configtime'}-1);

# Plugin-Code
my $retval='';

if($event=~/restart|modified/ || $config_modified) 
{
    # alle Variablen loeschen
    for my $k (grep /^$plugname\_/, keys %plugin_info)
    {
	next if $k=~/^$plugname\_last/;
	delete $plugin_info{$k};
    }

    $plugin_info{$plugname.'_configtime'}=$configtime;

    my $count=0;
    my $err=0;

    for my $t (keys %logic)
    {
	next if $t eq 'debug';
	$t=~s/^_//g;

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

	if(defined $logic{$t}{timer} && defined $logic{$t}{delay})
	{
	    plugin_log($plugname, "Config err: \$logic{$t}: delay und timer festgelegt, ignoriere delay");
	}

	# transmit-Adresse abonnieren
	my $transmit=groupaddress($logic{$t}{transmit});
	$plugin_subscribe{$transmit}{$plugname}=1;
	plugin_log($plugname, "\$logic{$t}: Transmit-GA $transmit nicht in %eibgaconf gefunden") if $debug && !exists $eibgaconf{$transmit};

	# Zaehlen und Logeintrag
	$count++;

	# Timer-Logiken reagieren nicht auf Bustraffic auf den receive-Adressen
	# fuer Timer-Logiken: ersten Call berechnen
	if($logic{$t}{timer})
	{
	    set_next_call($t, $debug);
	    next;
	}

	# fuer Nicht-Timer-Logiken: alle receive-Adressen abonnieren (eine oder mehrere)
	my $receive=groupaddress($logic{$t}{receive});

	next unless $receive;
	
	unless(ref $receive)
	{ 
	    $plugin_subscribe{$receive}{$plugname}=1; 
	    plugin_log($plugname, "\$logic{$t}: Receive-GA $receive nicht in %eibgaconf gefunden") if $debug && !exists $eibgaconf{$receive};
	}
	else
	{
	    for my $rec (@{$receive})
	    {
		$plugin_subscribe{$rec}{$plugname}=1;
		plugin_log($plugname, "\$logic{$t}: Receive-GA $rec nicht in %eibgaconf gefunden") if $debug && !exists $eibgaconf{$rec};
	    }
	}
    }

    $retval.=$count." initialisiert";
}

if($event=~/bus/)
{
    return if $msg{apci} eq "A_GroupValue_Response";

    my $ga=$msg{dst};
    my $in=$msg{value};
    my $keep_subscription=0; # falls am Ende immer noch Null, die GA stornieren

    # welche translate-Logik ist aufgerufen?
    for my $t (keys %logic)
    {
	next if $t eq 'debug';
	$t=~s/^_//g;

	my $transmit=groupaddress($logic{$t}{transmit});
	my $transmit_ga = ($ga eq $transmit);

	my $receive=groupaddress($logic{$t}{receive});
	my $receive_ga=0; 

	if(defined $receive && !$logic{$t}{timer})
	{
	    unless(ref $logic{$t}{receive})
	    {
		$receive_ga=1 if $ga eq $receive;
	    }
	    else
	    {
		$receive_ga=1 if grep /^$ga$/, @{$receive};
	    }
	}

	next unless $receive_ga || $transmit_ga; # diese Logik nicht anwendbar

	$keep_subscription=1;

	# Debuggingflag gesetzt
	my $debug = $logic{debug} || $logic{$t}{debug}; 

	# Sonderfall: Read- und Write-Telegramme auf der Transmit-Adresse?
    	if($transmit_ga)
	{    
	    # Ein Read-Request auf einer Transmit-GA wird mit dem letzten Ergebnis beantwortet
	    # Read-Requests auf die receive-Adressen werden gar nicht beantwortet
	    if($msg{apci} eq "A_GroupValue_Read")
	    {  
		my $result=$plugin_info{$plugname.'_'.$t.'_result'};
		if(defined $result)
		{
		    $retval.="$ga:Lesetelegramm -> \$logic{$t}{transmit}(memory) -> $ga:$result gesendet. " if $debug;
		    knx_write($ga, $result, undef, 0x40); # response, DPT aus eibga.conf		    
		}
		next;
	    }
	    elsif(!$receive_ga) # Receive geht vor - bei Timer-Logiken ist receive_ga immer 0
	    {
		if(defined $in) # Write/Response-Telegramm: das waren moeglicherweise wir selbst, also nicht antworten
		{
		    $plugin_info{$plugname.'_'.$t.'_result'}=$in; # einfach Input ablegen
		}
		else
		{
		    delete $plugin_info{$plugname.'_'.$t.'_result'};
		}
		next;
	    }
	}

	next unless $msg{apci} eq "A_GroupValue_Write" && $receive_ga;
	# Wir wissen ab hier: Es liegt ein Write-Telegramm auf einer der receive-Adressen vor

	# Nebenbei berechnen wir noch zwei Flags, die Zirkelkommunikation verhindern sollen
        # (Logik antwortet auf sich selbst in einer Endlosschleife)

	# Cool-Periode definiert und noch nicht abgelaufen?
	if(defined $plugin_info{$plugname.'__'.$t.'_cool'} && $plugin_info{$plugname.'__'.$t.'_cool'}>time())
	{
	    $retval.="$ga:$in -> \$logic{$t}{receive}(Cool) " if $debug;
	    next;
	}

	# Aufruf der Logik-Engine
	my $result=execute_logic($t, $receive, $ga, $in);

        # war Wiregate der Sender des Telegramms?
        # Zirkelaufruf mit wiederholt gleichen Ergebnissen ausschliessen
	my $sender_is_wiregate = $msg{src} eq $eibd_backend_address; 
	next if $sender_is_wiregate && $transmit_ga && $in == $result;

	# In bestimmten Sonderfaellen nichts schicken
	unless(defined $result) # Resultat undef => nichts senden
	{
	    $retval.="$ga:$in -> \$logic{$t}{receive}(Logik) -> nichts zu senden " if $debug;
	    next;
	}

	if($logic{$t}{transmit_only_on_request})
	{
	    $retval.="$ga:$in -> \$logic{$t}{receive}(Logik) -> $transmit:$result gespeichert "	if $debug;
	    next;
	}

	# Falls delay spezifiziert, wird ein "Wecker" gestellt, um in einem spaeteren Aufruf den Wert zu senden
	if($logic{$t}{delay})
	{
	    $plugin_info{$plugname.'__'.$t.'_timer'}=$systemtime+$logic{$t}{delay};
	    $plugin_info{$plugname.'__'.$t.'_cool'}=time()+$logic{$t}{delay}+$logic{$t}{cool} if defined $logic{$t}{cool};
	    $retval.="$msg{src} $ga:$in -> \$logic{$t}{receive}(Logik) -> $transmit:$result, zu senden in ".$logic{$t}{delay}."s " if $debug;
	}
	else
	{
	    knx_write($transmit, $result);
	    $retval.="$msg{src} $ga:$in -> \$logic{$t}{receive}(Logik) -> $transmit:$result gesendet " if $debug;

	    # Cool-Periode starten
	    $plugin_info{$plugname.'__'.$t.'_cool'}=time()+$logic{$t}{cool} if defined $logic{$t}{cool};
	}
    }

    unless($keep_subscription)
    {
	delete $plugin_subscribe{$ga}{$plugname};
    }
}

# Evtl. faellige Timer finden, gleichzeitig Timer fuer nachste Aktion setzen
my $nexttimer=undef;
for my $timer (grep /$plugname\__.*_timer/, keys %plugin_info) # alle Timer
{
    if(time()>=$plugin_info{$timer}) # Timer faellig? -> dann ausfuehren bzw. Resultat senden
    {
	# Relevanten Eintrag von %logic ermitteln
	$timer=~/$plugname\__(.*)_timer/;
	my $t=$1; 

	# Debuggingflag gesetzt
	my $debug = $logic{debug} || $logic{$t}{debug}; 
	
	# Transmit-GA
	my $transmit=groupaddress($logic{$t}{transmit});
	my $toor=$logic{$t}{transmit_only_on_request};
	my $result=undef;

	unless($logic{$t}{timer})
	{
	    # zu sendendes Resultat = zuletzt berechnetes Ergebnis der Logik
	    $result=$plugin_info{$plugname.'_'.$t.'_result'};
	    $retval.="\$logic{$t} -> $transmit:".
		       (defined $result?$result.($toor?" gespeichert":" gesendet"):"nichts zu senden")." (delayed) " if $debug;
	}
	else
	{
	    # ...es sei denn, es ist eine timer-Logik. Die muss jetzt ausgefuehrt werden
	    # Aufruf der Logik-Engine
	    $result=execute_logic($t, groupaddress($logic{$t}{receive}), undef, undef);
	    $retval.="\$logic{$t} -> $transmit:".
		       (defined $result?$result.($toor?" gespeichert":" gesendet"):"nichts zu senden")." (Timer) " if $debug;
	    
	}

	# Timer loeschen bzw. neu setzen
	set_next_call($t, $debug);

	if(defined $result && !$toor)
	{
	    knx_write($transmit, $result);

	    # Cool-Periode starten
	    $plugin_info{$plugname.'__'.$t.'_cool'}=time()+$logic{$t}{cool} if defined $logic{$t}{cool};
	}
    }
    else # noch nicht faelliger Timer
    {
	$nexttimer=$plugin_info{$timer} if !defined $nexttimer || $plugin_info{$timer}<$nexttimer;
    }
}

# Suche Timer-Logiken, bei denen aus irgendeinem Grund der naechste Aufruf noch nicht berechnet wurde,
# bspw wegen eines Plugin-Timeouts waehrend der Berechnung
for my $t (keys %logic)
{
    next if $t eq 'debug' || !defined $logic{$t}{timer};
    
    my $timer=$plugin_info{$plugname.'__'.$t.'_timer'};

    next if defined $timer && $timer>time();

    # Debuggingflag gesetzt
    my $debug = $logic{debug} || $logic{$t}{debug}; 
    set_next_call($t, $debug);
}

# Cycle auf naechsten Aufruf setzen
unless(defined $nexttimer)
{
    $plugin_info{$plugname."_cycle"}=0; # kein Aufruf noetig   
}
else
{
    my $cycle=int($nexttimer-time());
    $cycle=1 if $cycle<1;
    $plugin_info{$plugname."_cycle"}=$cycle;
    $retval.="Cycle (Timer) gestellt auf ".$cycle."s" if $logic{debug};
}

# experimentell - wir helfen der Garbage Collection etwas nach...
for my $k (keys %logic) { delete $logic{$k}; }
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
    my @holidays=(1,121+$leapyear,276+$leapyear,359+$leapyear,360+$leapyear,$J-2,$J,$J+39,$J+49,$J+50,$J+60);
    
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
    my ($t,$s)=@_;
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
#		plugin_log($plugname, "\$logic{$t} Aufrufdaten $k: ".join " ", @{$s->{$k}});
	} 
	elsif($k eq 'date')
	{
	    my $newlist=[];
	    for my $ks (@{$s->{date}})
	    {
		if($ks=~/^([0-9]+)\/([0-9]+)\-([0-9]+)\/([0-9]+)$/)
		{
		    my ($m1,$d1,$m2,$d2)=($1,$2,$3,$4); 
		    while($m1<$m2 || ($m1==$m2 && $d1<$d2))
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
#	    plugin_log($plugname, "\$logic{$t} Aufrufdaten date: ".join " ", @{$s->{date}});	
	}
	else
	{
	    @{$s->{$k}}=sort @{$s->{$k}}; # alle Listen sortieren
	}
    }
    
    # Expandieren periodischer Zeitangaben, das sind Zeitangaben der Form
    # time=>'08:00+30min' - ab 08:00 alle 30min
    # time=>'08:00+5min-09:00' - ab 08:00 alle 5min mit Ende 09:00
    if(grep /\+/, @{$s->{time}}) 
    {
	my $newtime=[];
	for my $ts (@{$s->{time}})
	{
	    unless($ts=~/^(.*?)([0-9][0-9]):([0-9][0-9])\+([1-9][0-9]*)(m|h)(?:\-([0-9][0-9]):([0-9][0-9]))?$/)
	    {
		if($ts=~/^(.*?)([0-9][0-9]):([0-9][0-9])$/)
		{
		    push @{$newtime}, sprintf("%02d:%02d",$2, $3);
		}
		else
		{
		    plugin_log($plugname, "Logiktimer zu Logik '$t': Unerlaubter time-Eintrag '$ts' (erlaubt sind Eintraege wie '14:05' oder '07:30+30m-14:30' oder '07:30+5m-08:00')");
		    next;
		}
	    }
	    else
	    {
		my ($head,$t1,$period,$t2)=($1,$2*60+$3,$4*($5 eq 'h' ? 60 : 1),(defined $6 ? ($6*60+$7) : 24*60));	    
		
		for(my $tm=$t1; $tm<=$t2; $tm+=$period)
		{
		    push @{$newtime}, sprintf("%02d:%02d",$tm/60,$tm%60);
		}
	    }
	}
	@{$s->{time}} = sort @{$newtime};
#	    plugin_log($plugname, "\$logic{$t} Aufrufzeiten: ".join " ", @{$newtime});
    }
}


# Fuer eine bestimmte Timer-Logik den naechsten Aufruf berechnen (relativ komplexes Problem wegen der 
# vielen moeglichen Konfigurationen und Konstellationen)
sub set_next_call
{
    my ($t,$debug)=@_; # der relevante Eintrag in %logic, und das Debugflag
    my $nextcall=undef;
    my $days_until_nextcall=0;

    # $logic{$t}{timer} ist eine Liste oder ein einzelner Eintrag
    # jeder solche Eintrag ist ein Hash im Format 
    # {day_of_month=>[(1..7)],day_of_week=>'Mo',time=>['08:30','09:20']}
    # das gerade genannte Beispiel bedeutet "jeden Monat jeweils der erster Montag, 8:30 oder 9:20"
    # verwendbare Klauseln sind year, month, day_of_month, calendar_week, day_of_week und time
    # Pflichtfeld ist lediglich time, die anderen duerfen auch entfallen. 
    # Jeder Wert darf ein Einzelwert oder eine Liste sein.
    my $schedule=$logic{$t}{timer}; 

#    return unless defined $schedule;

    # Das "Day-Hash" wird dazu verwendet, Tage zu finden, auf die die Timer-Spezifikation zutrifft
    # Wir fangen dabei mit today, also heute, an.
    my $today={year=>$year,day_of_year=>$day_of_year,month=>$month,day_of_month=>$day_of_month,
	       calendar_week=>$calendar_week,day_of_week=>$day_of_week_no};
    add_day_info($today);

    my $time_of_day=`/bin/date +"%X"`;

    # Schedule-Form standardisieren (alle Eintraege in Listenform setzen und Wochentage durch Zahlen ersetzen)
    # dabei gleich schauen, ob HEUTE noch ein Termin ansteht
    $schedule=[$schedule] if ref $schedule eq 'HASH';

    for my $s (@{$schedule})
    {
	standardize_and_expand_single_schedule($t,$s);

	# Steht heute aus diesem Schedule noch ein Termin an?
	next unless schedule_matches_day($s,$today) && $s->{time}[-1] gt $time_of_day;

	# Heute steht tatsaechlich noch ein Termin an! Welcher ist der naechste? 
	# Rueckwaerts durch die Liste $s->{time} suchen
	my $nc=undef;
	for(my $i=$#{$s->{time}}; $i>=0 && $s->{time}[$i] gt $time_of_day; $i--) { $nc=$s->{time}[$i]; }
	$nextcall=$nc unless defined $nextcall && $nextcall lt $nc;
    }

    # Wenn $nextcall hier bereits definiert, enthaelt es die naechste Aufrufzeit des Timers im Format "08:30"
    my $schedules_done=0; 

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
	    $nextcall=$s->{time}[0] unless defined $nextcall && $nextcall lt $s->{time}[0];	
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
	    plugin_log($plugname, "Naechster Aufruf der Timer-Logik '$t'$daytext um $nextcall."); # if $debug;

	    my $timer=$systemtime+$seconds+3600*24*$days_until_nextcall;
	    $plugin_info{$plugname.'__'.$t.'_timer'}=$timer;
	}
	else
	{
	    plugin_log($plugname, "Ungueltige Uhrzeit des naechsten Aufrufs der Timer-Logik '$t'$daytext."); # if $debug;
	}
    }
    else
    {
	plugin_log($plugname, "Logik '$t' wird nicht mehr aufgerufen (alle in time=>... festgelegten Termine sind verstrichen).") 
	    if $logic{$t}{timer}; # if $debug;

	delete $plugin_info{$plugname.'__'.$t.'_timer'}; 
    }
}

# Es folgt die eigentliche Logik-Engine 
# Im wesentlichen Vorbesetzen von input und state, Aufrufen der Logik, knx_write, Zurueckschreiben von state
sub execute_logic
{
    my ($t, $receive, $ga, $in)=@_; # Logikindex $t, Bustelegramm erhalten auf $ga mit Inhalt $in
    # $receive muss die direkten Gruppenadressen enthalten - Decodierung von Kuerzeln wird nicht vorgenommen

	# Debuggingflag gesetzt
	my $debug = $logic{debug} || $logic{$t}{debug}; 
    
    # als erstes definiere das Input-Array fuer die Logik
    my $input=$in;

    # Array-Fall: bereite Input-Array fuer Logik vor
    if(!ref $receive)
    {
	# wenn ga gesetzt, steht der Input-Wert in $in
	# wenn receive undefiniert, gibt es keine receive-GA
	$in=$input=knx_read($receive, 300) if !$ga && $receive;
    }
    else
    {
	$input=();
	for my $rec (@{$receive})
	{
	    if($ga eq $rec)
	    {
		push @{$input}, $in;
	    }
	    else
	    {
		push @{$input}, knx_read($rec, 300);
	    }
	}
    }
    
    # ab hier liegt $input komplett vor, und nun muss die Logik ausgewertet 
    # und das Resultat auf der Transmit-GA uebertragen werden
    my $result=undef;
    my %prowlContext=();
    
    unless(ref $logic{$t}{translate}) 
    {
	# Trivialer Fall: translate enthaelt einen fixen Rueckgabewert
	$plugin_info{$plugname.'_'.$t.'_result'}=$result=$logic{$t}{translate};
	# prowlContext befüllen
	$prowlContext{result}=$result;
	$prowlContext{input}=$input;
    }
    elsif(!ref $logic{$t}{state})
    {
	# Einfacher aber haeufiger Fall: skalarer $state
	# $state mit Ergebnis des letzten Aufrufs vorbesetzen
	my $state=$plugin_info{$plugname.'_'.$t.'_result'};
	
	# Funktionsaufruf, das Ergebnis vom letzten Mal steht in $state
	$result=$logic{$t}{translate}($state,$input);
	
	# prowlContext befüllen
	$prowlContext{result}=$result;
	$prowlContext{state}=$state;
	$prowlContext{input}=$input;

	# Ergebnis des letzten Aufrufs zurueckschreiben
	if(defined $result)
	{
	    $plugin_info{$plugname.'_'.$t.'_result'}=$result;
	}
	else
	{
	    delete $plugin_info{$plugname.'_'.$t.'_result'};
	}
    }
    else
    {
	# Komplexer Fall: $state-Hash aus %logic initialisieren
	my $state=$logic{$t}{state};
	my @vars=keys %{$state};
	push @vars, 'result';
	
	# Nun die dynamischen Variablen aus plugin_info hinzufuegen
	for my $v (@vars)
	{
	    $state->{$v}=$plugin_info{$plugname.'_'.$t.'_'.$v} if defined $plugin_info{$plugname.'_'.$t.'_'.$v};
	}
	
	# Funktionsaufruf, das Ergebnis vom letzten Mal steht in $state->{result}
	$result=$state->{result}=$logic{$t}{translate}($state,$input);

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
		$plugin_info{$plugname.'_'.$t.'_'.$v}=$state->{$v};
	    }
	    else
	    {
		# wenn die Logik den Wert undef in eine state-Variable schreibt, 
		# wird beim naechsten Aufruf wieder der Startwert aus %logic genommen,
		delete $plugin_info{$plugname.'_'.$t.'_'.$v};
	    }
	}
    }
    
    # Prowl-Nachrichten senden, falls definiert
    if(defined $logic{$t}{prowl})
    {
        my %prowlParametersSource;
        if (ref $logic{$t}{prowl}) {
            %prowlParametersSource = %{$logic{$t}{prowl}} if (ref $logic{$t}{prowl} eq 'HASH');
            %prowlParametersSource = $logic{$t}{prowl}(%prowlContext) if (ref $logic{$t}{prowl} eq 'CODE');
        }
        else 
        {
            %prowlParametersSource = ( event => $logic{$t}{prowl} );
        }
        
        sendProwl((
                debug => $debug,
                priority => $prowlParametersSource{priority} || $settings{prowl}{priority},
                event => $prowlParametersSource{event} || $settings{prowl}{event},
                description => $prowlParametersSource{description} || $settings{prowl}{description},
                application => $prowlParametersSource{application} || $settings{prowl}{application},
                url => $prowlParametersSource{url} || $settings{prowl}{url},
                apikey => $prowlParametersSource{url} || $settings{prowl}{apikey}
            ));
    }

    return $result;
}

# Umgang mit GA-Kurznamen und -Adressen

sub groupaddress
{
    my $short=shift;

    return unless defined $short;

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
    
    # Parameter ermitteln
    $priority = $parameters{priority} || 0;
    $event = $parameters{event} || '[unbenanntes Ereignis]';
    $description = $parameters{description} || '';
    $application = $parameters{application} || 'WireGate KNX';
    $url = $parameters{url} || '';
    $apikey = $parameters{apikey} || '';
    
    use LWP::UserAgent;
    use URI::Escape;
 
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
    	    uri_escape($application),
    	    uri_escape($event),
    	    uri_escape($description),
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

