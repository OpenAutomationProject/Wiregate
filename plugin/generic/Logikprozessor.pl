#!/usr/bin/perl -w
##################
# Logikprozessor #
##################
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License

#$plugin_info{$plugname.'_cycle'}=0; return 'deaktiviert';

my $use_short_names=1; # 1 fuer GA-Kuerzel (erstes Wort des GA-Namens), 0 fuer die "nackte" Gruppenadresse

# eibgaconf fixen falls nicht komplett indiziert
if($use_short_names && !exists $eibgaconf{ZV_Uhrzeit})
{
    for my $ga (grep /^[0-9\/]+$/, keys %eibgaconf)
    {
	$eibgaconf{$ga}{ga}=$ga;
	my $name=$eibgaconf{$ga}{name};
	next unless defined $name;
	$eibgaconf{$name}=$eibgaconf{$ga};

	next unless $name=~/^\s*(\S+)/;
	my $short=$1;
	$short='ZV_'.$1 if $eibgaconf{$ga}{name}=~/^Zeitversand.*(Uhrzeit|Datum)/;

	$eibgaconf{$ga}{short}=$short;
	$eibgaconf{$short}=$eibgaconf{$ga};
    }
}

# Tools und vorbesetzte Variablen fue die Logiken
sub limit { my ($lo,$x,$hi)=@_; return $x<$lo?$lo:($x>$hi?$hi:$x); }
my $day_of_week=`/bin/date +"%a"`;
my $weekend=($day_of_week=~/Sa|So/);
my $time_of_day=`/bin/date +"%X"`;
my $hour_of_day=substr($time_of_day,0,2);
my $day=($hour_of_day>7 && $hour_of_day<23);
my $night=!$day;

# Konfigurationsfile einlesen
my %devices=(0=>'Wiregate');
my %logic=();
my $conf="/etc/wiregate/plugin/generic/conf.d/$plugname"; $conf=~s/\.pl$/.conf/;
open FILE, "<$conf" || return "no config found";
my @lines = <FILE>;
close FILE;
eval("@lines");
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
my $config_modified = (24*60*60*(-M $conf)-time()) > $plugin_info{$plugname.'_configtime'};

# Plugin-Code
my $retval='';

if($event=~/restart|modified/ || $config_modified) 
{
    $plugin_info{$plugname.'_configtime'}=(24*60*60*(-M $conf)-time());

    # alle Variablen loeschen und neu initialisieren, alle GAs abonnieren
    for my $k (grep /^$plugname\_/, keys %plugin_info)
    {
	delete $plugin_info{$k};
    }

    my $count=0;
    my $err=0;

    for my $t (keys %logic)
    {
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

	# transmit-Adresse abonnieren
	my $transmit=groupaddress($logic{$t}{transmit});
	$plugin_subscribe{$transmit}{$plugname}=1;

	$count++;

	# alle receive-Adressen abonnieren (eine oder mehrere)
	my $receive=groupaddress($logic{$t}{receive});

	next unless $receive;
	
	unless(ref $receive)
	{ 
	    $plugin_subscribe{$receive}{$plugname}=1; 
	}
	else
	{
	    for my $rec (@{$receive})
	    {
		$plugin_subscribe{$rec}{$plugname}=1;
	    }
	}
    }

    $plugin_info{$plugname.'_cycle'}=0;
    $retval.=$count." initialisiert";
}

if($event=~/bus/)
{
    # Bustraffic bedienen - nur Schreibzugriffe der iButtons interessieren
    return unless $msg{apci}=~/A_GroupValue_(Write|Read)/;  

    my $ga=$msg{dst};
    my $in=$msg{value};
    my $keep_subscription=0; # falls am Ende immer noch Null, die GA stornieren

    # welche translate-Logik ist aufgerufen?
    for my $t (keys %logic)
    {
	my $transmit=groupaddress($logic{$t}{transmit});
	my $transmit_ga = ($ga eq $transmit);

	my $receive=groupaddress($logic{$t}{receive});
	my $receive_ga=0; 

	if(defined $receive)
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
		    knx_write($ga, $result);		    
		}
		next;
	    }
	    elsif(!$receive_ga) # Receive geht vor!
	    {
		if(defined $in) # Write-Telegramm: das waren moeglicherweise wir selbst, also nicht antworten
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

	# Wir wissen ab hier: Es liegt ein Write-Telegramm auf einer der receive-Adressen vor

	# Nebenbei berechnen wir noch zwei Flags, die Zirkelkommunikation verhindern sollen
        # (Logik antwortet auf sich selbst in einer Endlosschleife)

	# kommt transmit-GA unter den receive-GAs vor? 
	# Wenn transmit_ga gesetzt ist, ist das schon mal der Fall
	my $possible_circle=$transmit_ga; 

        # war Wiregate der Sender des Telegramms?
	my $sender_is_wiregate=int($msg{src})==0; 

	# Es folgt die eigentliche Logik-Engine - als erstes definiere das Input-Array fuer die Logik
	my $input=$in; # Skalarer Fall (der haeufigste)

        # Array-Fall: bereite Input-Array fuer Logik vor
	if(ref $receive)
	{
	    $input=();
	    for my $rec (@{$receive})
	    {
		my $rec=groupaddress($rec);
		
		$possible_circle=1 if $transmit eq $rec;
		
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
	# und das Resultat auf der Transmit-GA uebertragen
	my $result=undef;
	
	unless(ref $logic{$t}{translate}) 
	{
	    # Trivialer Fall: translate enthaelt einen fixen Rueckgabewert
	    $plugin_info{$plugname.'_'.$t.'_result'}=$result=$logic{$t}{translate};
	}
	elsif(!ref $logic{$t}{state})
	{
	    # Einfacher aber haeufiger Fall: skalarer $state
	    # $state mit Ergebnis des letzten Aufrufs vorbesetzen
	    my $state=$plugin_info{$plugname.'_'.$t.'_result'};
	    
	    # Funktionsaufruf, das Ergebnis vom letzten Mal steht in $state
	    $result=$logic{$t}{translate}($state,$input);
	    
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
	
	# In bestimmten Sonderfaellen nichts schicken
	next unless defined $result; # Resultat undef => nichts senden
	next if $logic{$t}{transmit_only_on_request};
	next if $possible_circle && $sender_is_wiregate && $in eq $result;
	
	# Falls delay spezifiziert, wird ein "Wecker" gestellt, um in einem spaeteren Aufruf den Wert zu senden
	if($logic{$t}{delay})
	{
	    $plugin_info{$plugname.'__'.$t.'_timer'}=time()+$logic{$t}{delay};
	    set_timer();
	}
	else
	{
	    knx_write($transmit, $result);
	}
    }

    unless($keep_subscription)
    {
	delete $plugin_subscribe{$ga}{$plugname};
    }
}

# Evtl. faellige Timer finden
for my $timer (grep /$plugname\__.*_timer/, keys %plugin_info) # alle Timer
{
    next if time()<$plugin_info{$timer}; # weiter falls noch nicht faellig
    
    # Timer loeschen
    delete $plugin_info{$timer}; 
    
    # Relevanten Eintrag von %logic ermitteln
    $timer=~/$plugname\__(.*)_timer/;
    my $t=$1; 
    
    # Transmit-GA
    my $transmit=groupaddress($logic{$t}{transmit});
    
    # zu sendendes Resultat
    my $result=$plugin_info{$plugname.'_'.$t.'_result'};
    next unless defined $result;
    
    knx_write($transmit, $result);

    # Timer fuer nachste Aktion setzen
    set_timer();   
}

return unless $retval;
return $retval;


# Zeit bis zum naechsten Aufruf dieses Plugins berechnen

sub set_timer
{
    # optimalen Wert fuer Aufrufzyklus finden, um beim naechsten Aufruf was zu senden
    my $nexttimer=undef;
    for my $timer (grep /$plugname\__.*_timer/, keys %plugin_info) # alle Timer
    {
	$nexttimer=$plugin_info{$timer} if !defined $nexttimer || $plugin_info{$timer}<$nexttimer;
    }

    unless(defined $nexttimer)
    {
	$plugin_info{$plugname."_cycle"}=0;
    }
    else
    {
	my $cycle=$nexttimer-time();
	$cycle=1 if $cycle<1;
    	$plugin_info{$plugname."_cycle"}=$cycle;
    }
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

sub shortname
{
    my $gas=shift;

    return unless defined $gas;
    return $gas unless $use_short_names;

    if(ref $gas)
    {
	my $sh=[];
	for my $ga (@{$gas})
	{
	    if($ga=~/^[0-9\/]+$/ && defined $eibgaconf{$ga}{short})
	    {
		push @{$sh}, $eibgaconf{$ga}{short};
	    }
	    else
	    {
		push @{$sh}, $ga;
	    }
	}
	return $sh;
    }
    else
    {
	my $sh=$gas;

	if($gas=~/^[0-9\/]+$/ && defined $eibgaconf{$gas}{short})
	{
	    $sh=$eibgaconf{$gas}{short};
	}

	return $sh;
    }
}
