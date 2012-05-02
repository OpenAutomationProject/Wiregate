#!/usr/bin/perl -w
##############
# Translator #
##############
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License

#$plugin_info{$plugname.'_cycle'}=0; return 'deaktiviert';

my $use_short_names=0; # 1 fuer GA-Kuerzel (erstes Wort des GA-Namens), 0 fuer die "nackte" Gruppenadresse

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

sub limit { my ($lo,$x,$hi)=@_; return $x<$lo?$lo:($x>$hi?$hi:$x); }

# Konfigurationsfile einlesen
my %trans=();
my $conf=$plugname; $conf=~s/\.pl$/.conf/;
open FILE, "</etc/wiregate/plugin/generic/conf.d/$conf" || return "no config found";
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

# Plugin-Code
if($event=~/restart|modified/)
{
    # alle Variablen loeschen und neu initialisieren, alle GAs abonnieren
    for my $k (grep /^$plugname\_/, keys %plugin_info)
    {
	delete $plugin_info{$k};
    }

    my $count=0;
    my $rxtx_lookup='';

    for my $t (keys %trans)
    {
	my $receive=$trans{$t}{receive};
	my $transmit=$trans{$t}{transmit};
	
	$receive=$eibgaconf{$receive}{ga} if $receive!~/^[0-9\/]+$/ && defined $eibgaconf{$receive};
	$transmit=$eibgaconf{$transmit}{ga} if $transmit!~/^[0-9\/]+$/ && defined $eibgaconf{$transmit};
    
	next unless defined $receive && defined $transmit;
	
	$rxtx_lookup.="Rx($receive)=>'$t', Tx($transmit)=>'$t', ";
	
	$plugin_subscribe{$receive}{$plugname}=1;
	$plugin_subscribe{$transmit}{$plugname}=1;

	$count++;

	$plugin_info{$plugname.'_'.$t.'_result'}=undef;

	if(ref $trans{$t}{state})
	{
	    for my $v (keys %{$trans{$t}{state}})
	    {
		$plugin_info{$plugname.'_'.$t.'_'.$v}=$trans{$t}{state}{$v};
	    }
	}
	elsif(defined $trans{$t}{state})
	{
	    $plugin_info{$plugname.'_'.$t.'_result'}=$trans{$t}{state};
	}
    }

    $plugin_info{$plugname.'__RxTxLookup'}=$rxtx_lookup;
    $plugin_info{$plugname.'_cycle'}=0;

    return $count." initialisiert";
}

# Bustraffic bedienen - nur Schreibzugriffe der iButtons interessieren
if($event=~/bus/)
{
    return if $msg{apci} eq "A_GroupValue_Response";

    my $ga=$msg{dst};

    unless($plugin_info{$plugname.'__RxTxLookup'}=~/(Tx|Rx)\($ga\)=>\'(.+?)\',/)
    {
	delete $plugin_subscribe{$ga}{$plugname}; # unbekannte GA
	return;
    }

    my $cmd=$1; chop $cmd;
    my $t=$2;

    if($msg{apci} eq "A_GroupValue_Read")
    {
	# Ein Read-Request auf einer Transmit-GA wird mit dem letzten Ergebnis beantwortet
	if($cmd eq 'T')
	{
	    my $transmit=$ga;
	    $transmit=$eibgaconf{$ga}{short} if $use_short_names;
	    my $result=$plugin_info{$plugname.'_'.$t.'_result'};
	    plugin_log($plugname, "memory: $result ($transmit)");
	    knx_write($ga, $result);
	}
	return;
    }
    elsif($msg{apci} eq "A_GroupValue_Write")
    {
	my $input=$msg{value};

        # Write-Telegramm auf unserer Transmit-Adresse?
	# Vorsicht! - das koennten wir selbst gewesen sein, also nicht antworten!
	if($cmd eq 'T')
	{
	    $plugin_info{$plugname.'_'.$t.'_result'}=$input; # einfach Input ablegen
	    return;
	}

	my $result=undef;

	# Ein Write-Request auf einer Receive-GA wird uebersetzt und das Resultat auf der Transmit-GA uebertragen
	if(ref $trans{$t}{state})
	{
	    # Komplexer state-Hash: Basis sind die Werte im Configfile
	    my $state=$trans{$t}{state};
	    
	    # Nun die dynamischen Variablen aus plugin_info hinzufuegen
	    for my $k (keys %plugin_info)
	    {
		next unless $k=~/^$plugname\_$t\_(.*)$/;
		my $v=$1;
		$state->{$v}=$plugin_info{$plugname.'_'.$t.'_'.$v};
	    }

	    # Funktionsaufruf, das Ergebnis vom letzten Mal steht in $state->{result}
	    $result=$trans{$t}{translate}($state,$input);

	    # Alle dynamischen Variablen wieder nach plugin_info schreiben
	    # Damit plugin_info nicht durch Konfigurationsfehler vollgemuellt wird, 
	    # erlauben wir nur vorhandene Eintraege
	    for my $v (keys %{$state})
	    {
		next unless exists $plugin_info{$plugname.'_'.$t.'_'.$v};
		$plugin_info{$plugname.'_'.$t.'_'.$v}=$state->{$v};
	    }
	}
	else # Einfacher Fall - skalare state-Variable
	{
	    # Einfache state-Skalar: Ergebnis des letzten Aufrufs
	    my $state=$plugin_info{$plugname.'_'.$t.'_result'};
	    
	    # Funktionsaufruf, das Ergebnis vom letzten Mal steht in $state
	    $result=$trans{$t}{translate}($state,$input);
	}

	# Ergebnis des letzten Aufrufs zurueckschreiben
	$plugin_info{$plugname.'_'.$t.'_result'}=$result;
	
	# Uebersetzung auf Bus schreiben, ausser im Sonderfall receive==transmit, dann nur auf Anfrage senden
	my $receive=$trans{$t}{receive};
	my $transmit=$trans{$t}{transmit};
	
	$receive=$eibgaconf{$receive}{ga} if $receive!~/^[0-9\/]+$/ && defined $eibgaconf{$receive};
	$transmit=$eibgaconf{$transmit}{ga} if $transmit!~/^[0-9\/]+$/ && defined $eibgaconf{$transmit};

	# Debugging
	unless($transmit eq $receive)
	{
	    plugin_log($plugname, "$input ($receive) -> $result ($transmit)");
	    knx_write($transmit, $result);
	}
    }
}

return;
