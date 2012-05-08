##################
# Heizungsregler #
##################
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License

# $plugin_info{$plugname.'_cycle'}=0; return "deaktiviert";

use POSIX qw(floor);
use Math::Round qw(nearest);

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

# Aufrufgrund ermitteln
my $event=undef;
if (!$plugin_initflag) 
{ $event='restart'; } # Restart des daemons / Reboot
#elsif ((stat('/etc/wiregate/plugin/generic/' . $plugname))[9] > time()-2) 
# ab PL30:
elsif ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'})
{ $event='modified'; } # Plugin modifiziert
elsif (%msg) { $event='bus'; } # Bustraffic
#elsif ($fh) { $event='socket'; } # Netzwerktraffic
else { $event='cycle'; } # Zyklus

# Konfigurationsfile einlesen
my $conf=$plugname; $conf=~s/\.pl$/.conf/;
$conf="/etc/wiregate/plugin/generic/conf.d/$conf";
my %house=();
my $err=read_from_house_config();
return $err if $err;

# Initialisierung
my %dyn=();
my $retval='';
my $t=time();

if($event=~/restart|modified/)
{
    # Cleanup aller Variablen
    for my $k (grep /^$plugname\_/, keys %plugin_info)
    {
	delete $plugin_info{$k};
    }

    # Alle Controller-GAs abonnieren, Reglerstati initialisieren
    for my $r (grep ref($house{$_}), keys %house)
    {
	$plugin_subscribe{$house{$r}{control}}{$plugname}=1;
	RESET($r);
    }

    $plugin_info{$plugname.'_cycle'}=$house{cycle}; 

    store_to_plugin_info(\%dyn);

    $event='cycle';
}

%dyn=recall_from_plugin_info();

# Zyklischer Aufruf - Regelung
if($event=~/cycle/)
{ 
    my $Vreq=undef;
    my $anynews=0;
    for my $r (grep ref($house{$_}), keys %house)
    {
	if($dyn{$r}{mode} eq 'ON')
	{
	    # PID-Regler
	    my ($T,$T0,$U,$Vr)=PID($r); 
	    $retval.=sprintf "$r\->%.1f(%.1f)%d%% ", $T?$T:"T?", $T0, 100*$U;
	    $anynews=1;
	    $Vreq=$Vr if defined $Vr && (!defined $Vreq || $Vr>$Vreq);
	}
	elsif($dyn{$r}{mode} eq 'OPTIMIZE')
	{
	    # Optimierung der PID-Parameter durch Ermittlung der Sprungantwort
	    $retval.="$r\->".OPTIMIZE($r); 
	    $anynews=1;
	    $Vreq=$house{inflow_max} if defined $house{inflow_max};    
	}
	elsif($dyn{$r}{mode} eq 'OFF')
	{
	    $retval.="$r\->OFF ";     
	}
    }
    
    if(defined $Vreq)
    {
	$Vreq=$house{inflow_max} if defined $house{inflow_max} && $Vreq>$house{inflow_max};
	knx_write($house{inflow_control},$Vreq,9.001) if defined $house{inflow_control};
	$retval.=sprintf "Vreq=%d", $Vreq;
	$anynews=1;
    }

    $retval=~s/\s*$//; # Space am Ende entfernen

    return unless $anynews;
}
elsif($event=~/bus/)
{
    return if $msg{apci} eq 'A_GroupValue_Response';

    # Aufruf durch GA - neue Wunschtemperatur
    my $ga=$msg{dst};

    # erstmal den betroffenen Raum finden
    my @rms=(grep ref($house{$_}) && $house{$_}{control} eq $ga, keys %house);
    my $r=shift @rms;

    # $r ist undef falls obige Schleife fertig durchlaufen wurde
    if(defined $r)
    {
	my $T0=0;
	$T0 = $msg{value} if defined $msg{value};
	my $mode=$dyn{$r}{mode};

	# Jemand moechte einen Sollwert wissen
	if($msg{apci} eq 'A_GroupValue_Read')
	{
	    $T0=$dyn{$r}{T0};
	    $T0=$dyn{$r}{T0old} if $dyn{mode} eq 'OPTIMIZE';
	    knx_write($ga,$T0,9.001); 
	    return;
	}
	
	# spezielle Temperaturwerte sind 0=>OFF und -1=>OPTIMIZE
	if($T0==0)
	{
	    RESET($r); 
	    writeactuators($r,0); 
	    $dyn{$r}{mode}='OFF';
	    $retval.="$r\->OFF";
	}
	elsif($T0==-1)
	{
	    return if $dyn{$r}{mode} eq 'OPTIMIZE'; # Entprellen

	    # Initialisierung der Optimierungsfunktion
	    $dyn{$r}{mode}='OPTIMIZE';
	    $dyn{$r}{T0old}=$dyn{$r}{T0};
	    writeactuators($r,0); 
	    my ($T,$V,$E,$R,$spread,$window)=readsensors($r);

	    $retval.=sprintf "$r\->OPT", $T;
	}
	else # neue Wunschtemperatur
	{
	    return if $dyn{$r}{T0} == $T0; # Entprellen
	    
	    RESET($r) if $mode eq 'OPTIMIZE'; # Optimierung unterbrochen
	    $dyn{$r}{mode}='ON'; # ansonsten uebrige Werte behalten
	    $dyn{$r}{T0}=$T0;
	    my ($T,$T0,$U,$Vr)=PID($r); 
	    $retval.=sprintf "$r\->%.1f(%.1f)%d%%", $T, $T0, 100*$U;
	}
    }
    else  
    {
	# GA-Abonnement loeschen
	delete $plugin_subscribe{$ga}{$plugname};
    }
}

# Speichere Statusvariablen aller Regler
store_to_plugin_info(\%dyn);

return $retval eq '' ? undef : $retval;


########## Datenpersistenz - Speichern und Einlesen ###############

sub store_to_plugin_info
{
    my $dyn=shift;

    # Alle Laufzeitvariablen im Hash %{$dyn} 
    # in das (flache) Hash plugin_info schreiben
    for my $r (keys %{$dyn})
    {
	for my $k (grep /^$plugname\_$r\_(temps|times|Uvals)_/, keys %plugin_info)
	{
	    delete $plugin_info{$k};
	}

	for my $v (keys %{$dyn->{$r}})
	{
	    next if $v=~/^(temps|times|Uvals)$/; # Arrays
	    $plugin_info{$plugname.'_'.$r.'_'.$v}=$dyn->{$r}{$v};
	}

	for my $array (qw(temps times Uvals))
	{
	    my $arr=$dyn->{$r}{$array};
	    next unless $arr;
	    for my $i (0..$#{$arr})
	    {
		$plugin_info{$plugname.'_'.$r.'_'.$array.'_'.$i}=$arr->[$i];
	    }
	}
    }
}

sub recall_from_plugin_info
{
    my %dyn=();

    for my $k (grep /^$plugname\_/, keys %plugin_info)
    {
	next unless $k=~/^$plugname\_([^_]+)\_(\S+)$/; 
	my $r=$1; my $v=$2; 

	unless($v=~/^(temps|times|Uvals)_([0-9]+)$/)
	{
	    $dyn{$r}{$v}=$plugin_info{$k};
	}
	else
	{
	    my $array=$1; my $i=$2;
	    $dyn{$r}{$array}[$i]=$plugin_info{$k};
	}
    }

    return %dyn;
}

sub read_from_house_config
{
    open CONFIG, "<$conf" || return "no config found";
    my @lines = <CONFIG>;
    close CONFIG;
    eval("@lines");
    return "config error" if $@;
}

sub store_to_house_config
{
    my $r=shift; # der betreffende Raum im Haus

    open CONFIG, ">>$conf";
    print CONFIG "\$house{$r}{pid}={";
    for my $k (sort keys %{$house{$r}{pid}})
    {
	print CONFIG sprintf "$k=>%.2f, ", $house{$r}{pid}{$k} unless $k eq 'date';
	print CONFIG "$k=>'$house{$r}{pid}{date}'," if $k eq 'date';
    }
    print CONFIG "};\n";
    close CONFIG;
}

########## Kommunikation mit Sensoren und Aktoren ###############

sub readsensors
{
    my $r=shift; # interessierender Raum
    my @substructures=();

    push @substructures, values %{$house{$r}->{circ}} if defined $house{$r}->{circ};
    push @substructures, $house{$r};

    my %T=();
    my %R=();

    for my $type (qw(sensor inflow floor outflow window))
    {
	my $dpt=$type eq 'window' ? 1 : 9;

	# Alle Sensoren eines Typs im gesamten Raum einlesen
	for my $ss (@substructures)
	{
	    if(defined $ss->{$type})
	    {
		my $sensorlist=(ref $ss->{$type})?$ss->{$type}:[$ss->{$type}];
		for my $s (@{$sensorlist})
		{
		    unless(defined $T{$type}{$s})
		    {
			$T{$type}{$s}=knx_read($s,$house{cycle},$dpt);
			delete $T{$type}{$s} unless defined $T{$type}{$s};
		    }
		}
	    }
	}

	# Ueber alle Sensoren mitteln, dabei wird jeder Sensor genau einmal
	# beruecksichtigt, auch wenn er in der Konfiguration mehrfach steht
	my $n=0;
	for my $k (keys %{$T{$type}})
	{   
	    if(defined $T{$type}{$k}) 
	    {
		if($type eq 'window')
		{
		    $R{$type}=1 if int($T{$type}{$k})==1;
		}
		else
		{
		    $R{$type}+=$T{$type}{$k};
		    $n++;
		}
	    }
	}
	$R{$type}/=$n if defined $R{$type} && $type ne 'window';
    }

    # Falls Fensterkontakte nicht lesbar -> Fenster als geschlossen annehmen
    $R{window}=0 unless defined $R{window};

    # outflow (Ruecklauf) und floor (Estrich) nehmen wir als gleich an,
    # falls nicht beide Werte vorhanden sind. Das sollte immer noch besser
    # sein als der globale Hauswert, um danach den Spread zu berechnen.
    unless(defined $R{outflow} && defined $R{floor})
    {
	$R{outflow}=$R{floor} if defined $R{floor};
	$R{floor}=$R{outflow} if defined $R{outflow};
    }

    # Falls Vor- oder Ruecklauf nicht fuer den Raum definiert,
    # nehmen wir die Hauswerte - falls diese verfuegbar sind
    for my $type (qw(inflow outflow))
    {
	if(!defined $R{$type} && defined $house{$type})
	{
	    $R{$type} = knx_read($house{$type},$house{cycle},9);
	    delete $R{$type} unless $R{$type};
	}
    }

    # Jetzt Spread (Spreizung) berechnen, falls alle Daten verfuegbar
    if(defined $R{inflow} && defined $R{outflow})
    {
       $R{spread}=$R{inflow}-$R{outflow};
    }

    # und wenn alle Stricke reissen, bleibt der vorkonfigurierte Wert
    $R{spread}=$house{spread} unless defined $R{spread};

    return @R{qw(sensor inflow floor outflow spread window)};
}

sub writeactuators
{
    my $r=shift; # Raum mit Substruktur
    my $U=shift; # Ventileinstellung

#    plugin_log($plugname, "Trying to write $r, $U");
    
    my @substructures=values %{$house{$r}->{circ}} if defined $house{$r}->{circ};
    push @substructures, $house{$r};

    for my $ss (@substructures)
    {
	if(defined $ss->{actuator})
	{
	    unless(ref $ss->{actuator})
	    {
		knx_write($ss->{actuator},100*$U,5.001); # DPT NOCH UNKLAR ########
	    }
	    else
	    {
		for my $s (@{$ss->{actuator}})
		{
		    knx_write($s,100*$U,5.001);
		}
	    }
	}
    }
#    plugin_log($plugname, "Done trying to write $r, $U");
}

########## PID-Regler #####################

sub RESET
{
    my $r=shift; # zu regelnder Raum im Haus
    
    $dyn{$r} = {
	mode=>'OFF', T0=>20, Told=>0, told=>$t, IS=>0, DF=>0, 
	temps=>[], times=>[], Uvals=>[], U=>0
	};
}

sub PID
{
    my $r=shift; # zu regelnder Raum im Haus
    my ($T,$V,$E,$R,$spread,$window)=readsensors($r);

    # Ohne Temperaturmessung und Spread keine Regelung -> aufgeben
    my ($mode,$T0,$Told,$told,$IS,$DF,$temps,$times,$Uvals,$U) 
	= @{$dyn{$r}}{qw(mode T0 Told told IS DF temps times Uvals U)};
 
    return ($T,$T0,$U,0) unless $T && $spread; 

    # Regelparameter einlesen
    my ($Tv,$Tn,$lim,$prop,$refspread)=(5,30,1,1,10); # Defaults

    ($Tv,$Tn,$lim,$prop,$refspread)
	=@{$house{$r}{pid}}{qw(Tv Tn lim prop refspread)}
        if defined $house{$r}{pid};

    $Tv*=60; $Tn*=60; # in Sekunden umrechnen

    # Anzahl Datenpunkte fuer Steigungsberechnung
    my $S1=12; $S1=$house{mindata} if defined $house{mindata};
 
    # Anzahl Datenpunkte fuer Ermittlung neuer Vorhaltetemperatur 
    my $S2=$S1;

    push @{$temps},$T; shift @{$temps} while @{$temps}>$S1;
    push @{$times},$t; shift @{$times} while @{$times}>$S1;

    if($window)
    {
	$U=0; # Heizung aus falls Fenster offen	
	push @{$Uvals}, $U; shift @{$Uvals} while @{$Uvals}>$S2;	

	$dyn{$r} = {
	    mode=>$mode, T0=>$T0, Told=>$T, told=>$t, IS=>$IS, DF=>$DF, 
	    temps=>$temps, times=>$times, Uvals=>$Uvals, U=>$U
	};
	
	writeactuators($r,$U); 
	return ($T,$T0,$U,0); 
    }

    # Skalierung fuer aktuellen Spread
    my $coeff = $refspread/($spread*$prop);
    
    # Proportionalteil (P)
    my $P = $T0 - $T;
    
    # Integralteil (I)
    $IS += $P * ($t - $told) / $Tn;
    
    # kein negativer I-Anteil bei reiner Heizung (nur fuer Klimaanlage erforderlich)
    $IS=0 if $IS<0; 

    # Begrenzung des I-Anteils zur Vermeidung von Ueberschwingern ("wind-up")
    $IS=+$lim/$coeff if $IS>+$lim/$coeff;
    
    # Differentialteil (D) - gemittelt wegen moeglichem Sensorrauschen
    $S1=scalar(@{$times});
    if($S1>=2)
    {
	my ($SX,$SX2,$SY,$SXY)=(0,0,0,0);
	for my $i (0..$S1-1)
	{
	    my $time=$times->[$i]-$times->[0];
	    $SX+=$time;
	    $SX2+=$time*$time;
	    $SY+=$temps->[$i];
	    $SXY+=$time*$temps->[$i];
	}
	$DF = - $Tv * ($S1*$SXY - $SX*$SY)/($S1*$SX2 - $SX*$SX);
    }
# Fuer den Fall S1==2 fuehrt die obige Regression zum gleichen Ergebnis wie:
#    $DF = - $Tv * ($T - $Told) / ($t - $told);
   
    # und alles zusammen, skaliert mit der aktuellen Spreizung
    $U = ($P + $IS + $DF) * $coeff;
    
    # Stellwert begrenzen auf 0-1
    $U=1 if $U>1; 
    $U=0 if $U<0;
    push @{$Uvals}, $U; shift @{$Uvals} while @{$Uvals}>$S2;	

    # Wunsch-Vorlauftemperatur ermitteln
    my $Vr=$V;
    if(defined $Vr)
    {
	$Vr=$T0+3 if $Vr<$T0+3;
	my $Uavg=0; $Uavg+=$_ foreach (@{$Uvals}); $Uavg/=scalar(@{$Uvals});

	$Vr+=1 if $Uavg>0.9;
	$Vr-=1 if $Uavg<0.6 && $V>$T0+6 && $spread>6;
	$Vr-=1 if $Uavg<0.75 && $V>$T0+5 && $spread>5;
	$Vr-=1 if $Uavg<0.7 && $V>$T0+4 && $spread>4;
	$Vr-=1 if $Uavg<0.6 && $V>$T0+3 && $spread>3;
    }

    # Variablen zurueckschreiben
    $dyn{$r} = {
	mode=>$mode, T0=>$T0, Told=>$T, told=>$t, IS=>$IS, DF=>$DF, 
	temps=>$temps, times=>$times, Uvals=>$Uvals, U=>$U
    };
    
    # Ventil einstellen 
    writeactuators($r,$U); 
    
    # Ist, Soll, Stellwert, Spread, Wunsch-Vorlauftemp.
    return ($T,$T0,$U,$Vr); 
}

########## Optimierungsroutine #####################

sub OPTIMIZE
{
    my $r=shift;
    my ($T,$V,$E,$R,$spread,$window)=readsensors($r);

    # Ohne Temperaturmessung und Spread keine Regelung -> aufgeben
    return "(OPT) " unless defined $T && defined $spread; 

    # Praktische Abkuerzungen fuer Statusvariablen
    my ($mode,$phase,$T0old) = @{$dyn{$r}}{qw(mode phase T0old)};

    # Falls Fenster offen  -> Abbruch, Heizung aus und Regler resetten
    if($window)
    {
	if($phase ne 'COOL')
	{
	    RESET($r);
	    $dyn{$r}{mode}='ON'; 
	    $dyn{$r}{T0}=$T0old;
	    return "FAILED:WINDOW ";
	}
	else
	{
	    # Tn, Tv, prop und refspread wurden am Ende der HEAT-Periode bereits berechnet
	    # Wir nutzen die "cooling"-Periode sowieso nicht.
	    # Also Parameter ins Konfig-File schreiben.
	    my ($Tn, $Tv, $prop, $refspread) = @{$dyn{$r}}{qw(Tn Tv prop refspread)};
	    my $date=`/bin/date +"%F %X"`; chomp $date;
	    my $lim=0.5; 
	    $house{$r}{pid}={Tv=>$Tv, Tn=>$Tn, lim=>$lim, prop=>$prop, refspread=>$refspread, date=>$date};
	    store_to_house_config($r);
	}
    }

    # Warte bis Therme voll aufgeheizt
    # das Aufheizen der Therme geschieht in der Hauptschleife
    $phase='WAIT' unless defined $phase;

    if($phase eq 'WAIT')
    {
	if(defined $V && defined $house{inflow_max} && $V<$house{inflow_max}-3)
	{
	    writeactuators($r,0); # noch nicht heizen
	    return "WAIT(V=$V) "; 
	}
	
        # Falls Heizung noch nicht voll an, jetzt starten
	writeactuators($r,1); # maximal heizen

	# Temperaturaufzeichnung beginnen
	$dyn{$r} = {
	    mode=>$mode, phase=>'HEAT', 
	    T0old=>$T0old, told=>0, optstart=>$t, 
	    maxpos=>0, maxslope=>0, 
	    sumspread=>$spread, temps=>[0], times=>[$T]
	};
	
	return sprintf("%.1f(HEAT)%.1f ",$T,$spread);
    }

    my ($optstart, $sumspread, $told, $temps, $times) 
	= @{$dyn{$r}}{qw(optstart sumspread told temps times)};

    my $tp=$t-$optstart;

    # falls aus irgendeinem Grund zu frueh aufgerufen, tu nichts
    return sprintf("%.1f(", $T).'SKP'.sprintf(")%.1f ",$spread) 
	if $tp-$told<$house{cycle}/2;

    # Temperaturkurve aufzeichnen
    push @{$times}, $tp; 
    push @{$temps}, $T; 
    $sumspread+=$spread;

    # Anzahl Datenpunkte fuer Steigungsberechnung. Hier verdoppelt, weil wir
    # mehr Praezision brauchen.
    my $S1=25; $S1=2*$house{mindata} if defined $house{mindata}; 
    
    if(scalar(@{$temps})<=$S1)
    {
	$dyn{$r} = {
	    mode=>$mode, phase=>$phase, 
	    T0old=>$T0old, told=>$tp, optstart=>$optstart, 
	    maxpos=>0, maxslope=>0, 
	    sumspread=>$sumspread, temps=>$temps, times=>$times
	};

	return sprintf("%.1f(", $T).'OPT'.sprintf(")%.1f ",$spread);
    }

    # Steigung der Temperaturkurve durch Regression bestimmen
    my ($SX,$SY,$SY2,$SXY)=(0,0,0,0);
    
    for my $i (-$S1..-1)
    {
	$SX+=$temps->[$i];
	$SY+=$times->[$i];
	$SY2+=$times->[$i]*$times->[$i];
	$SXY+=$times->[$i]*$temps->[$i];
    }
    
    my $slope = ($S1*$SXY - $SX*$SY)/($S1*$SY2 - $SY*$SY);
    
    if($phase eq 'HEAT')
    {
	my ($maxpos, $maxslope) = @{$dyn{$r}}{qw(maxpos maxslope)};
	
	if($slope<=0 || $maxslope<=0 || $slope>=0.7*$maxslope)
	{
	    my $retval='';
	    
	    if($slope>$maxslope)
	    {
		$maxslope = $slope; 
		$maxpos = nearest(1,$#{$temps}-$S1/2);
		$retval=sprintf "%.2fKph",$slope*60*60;
	    }
	    elsif($slope>0)
	    {
		$retval=sprintf "%.2fKph=%d%%", $slope*60*60, 100*$slope/$maxslope;
	    }
	    else
	    {
		$retval=sprintf "%.2fKph",$slope*60*60;
	    }
	    
	    # Statusvariablen zurueckschreiben
	    $dyn{$r} = {
		mode=>$mode, phase=>'HEAT', 
		T0old=>$T0old, told=>$tp, optstart=>$optstart, 
		maxpos=>$maxpos, maxslope=>$maxslope, 
		sumspread=>$sumspread, temps=>$temps, times=>$times
	    };
	    
	    return sprintf("%.1f(", $T).$retval.sprintf(")%.1f ",$spread);
	}

	# Erwaermung deutlich verlangsamt -> Optimierung berechnen
	# Abschaetzung des finalen Plateauniveaus durch Annahme 
	# exponentieller Thermalisierung    
 	
        # Position maximaler Steigung
	my $pos1 = nearest(1,$maxpos-$S1/2);
	my $t1 = $times->[$maxpos];
	
	# Endpunkt
	my $t3 = $times->[nearest(1,-1-$S1/2)];
	
	# Punkt in der Mitte zwischen max. Steigung und Endpunkt
	my $pos2 = undef;
	for my $p ($maxpos..$#{$times})
	{
	    if($times->[$p]>=($t1+$t3)/2) { $pos2=$p; last; }
	}
	unless(defined $pos2)
	{
	    RESET($r);
	    $dyn{$r}{mode}='ON'; # ansonsten uebrige Werte behalten
	    $dyn{$r}{T0}=$T0old;
	    return "FAILED:POS2";
	} 
	$pos2 = nearest(1,$pos2-$S1/2);	
	
	# Temperaturen an den Punkten t=0, maxtime, (maxtime+t)/2, t
	# gemittelt ueber S1 Werte
	my ($X0,$X1,$X2,$X3)=(0,0,0,0);
	for my $i (0..($S1-1))
	{
	    $X0+=$temps->[$i];
	    $X1+=$temps->[$i+$pos1];
	    $X2+=$temps->[$i+$pos2];
	    $X3+=$temps->[-$i-1];
	}
	$X0/=$S1; $X1/=$S1; $X2/=$S1; $X3/=$S1;  

	# Berechnung des Plateauwertes bei exponentieller Thermalisierung
	my $Xplateau=($X1*$X3 - $X2*$X2)/($X1 - 2*$X2 + $X3);

	# Analyse der Sprungantwort
	my $refspread = $sumspread/scalar(@{$times});
	my $DX = $Xplateau - $X0; 
	my $Ks = $DX/$refspread; 
	my $Tu = $t1 - 2*($tp-$told) - ($X1-$X0)/$maxslope; 
	my $Tg = $DX/$maxslope;
	
	# Optimierung der PID-Parameter nach Chien/Hrones/Reswick
	# (siehe zB Wikipedia). Wir nehmen aber etwas andere Koeffizienten, 
	# das fuehrt zu ruhigerem Regelverhalten...
	
	# Proportionalbereich prop=1/Kp, kleineres prop ist aggressiver
	my $prop = $maxslope*$Tu/(0.3*$refspread); 
	
	# Nachstellzeit des Integralteils, kleiner ist aggressiver
	my $Tn = $Tg/60; 
	
	# Vorhaltezeit des Differentialteils, groesser ist aggressiver
	my $Tv = $Tu/60; 

	# alle drei Parameter muessen positiv sein, sonst Fehler
	unless($prop>=0 && $Tn>=0 && $Tv>=0)
	{
	    RESET($r);
	    $dyn{$r}{mode}='ON';
	    $dyn{$r}{T0}=$T0old;
	    $dyn{$r}{Told}=$T;
	    
	    return "FAILED:NEG";
	}

	# Statusvariablen zurueckschreiben
	$dyn{$r} = {
	    mode=>$mode, phase=>'COOL', 
	    T0old=>$T0old, told=>$tp, optstart=>$optstart, 
	    Tn=>$Tn, Tv=>$Tv, prop=>$prop, refspread=>$refspread, tcool=>$t3,
	    sumspread=>$sumspread, temps=>$temps, times=>$times
	};
	
	# Abkuehlung einleiten
	writeactuators($r, 0);
	
	return sprintf("%.1f(COOL) ",$T);
    }
    
    if($phase eq 'COOL' && $slope>0)
    {
	return sprintf("%.1f(%.2fKph) ",$T,$slope*60*60);
    }

    # Abspeichern der optimierten Parameter im Konfigurationsfile
    # aus der Laenge der "cooling"-Periode bis zum Maximum koennte man noch was berechnen, 
    # aber wir setzen $lim hier als Konstante
    my ($Tn, $Tv, $prop, $refspread, $tcool)
	= @{$dyn{$r}}{qw(Tn Tv prop refspread tcool)};
    my $date=`/bin/date +"%F %X"`; chomp $date;
    my $lim=0.5; 
    $house{$r}{pid}={Tv=>$Tv, Tn=>$Tn, lim=>$lim, prop=>$prop, refspread=>$refspread, date=>$date};
    store_to_house_config($r);

    # Regelung starten
    RESET($r);
    $dyn{$r}{mode}='ON';
    $dyn{$r}{T0}=$T0old;
    $dyn{$r}{Told}=$T;

    # Info an den User
    return sprintf "t=%dh:%02dmin Tv=%.1fmin Tn=%dmin lim=%.1f prop=%.1f spread=%.1f ", $tp/3600,($tp/60)%60,$Tv,$Tn,$lim,$prop,$refspread;
}	    

