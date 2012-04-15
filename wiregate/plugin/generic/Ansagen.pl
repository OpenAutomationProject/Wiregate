###########
# Ansagen #
###########
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License version 2 or later

# $plugin_info{$plugname.'_cycle'}=0; return 'deaktiviert';

use POSIX qw(floor);

# Defaultkonfiguration
my $logfile='/var/log/Ansagen.log';
my $speechdir='/var/lib/Ansagen/Sprache/';
my %channels=('default'=>'welcome');
my $beepchannel='paging';
my $beep = "Beep/03d.wav"; 
my @additional_subscriptions=();

# Konfigurationsfile einlesen
my $conf=$plugname; $conf=~s/\.pl$/.conf/;
open FILE, "</etc/wiregate/plugin/generic/conf.d/$conf" || return "no config found";
my @lines = <FILE>;
close FILE;
eval("@lines");
return "config error" if $@;

# Aufrufgrund ermitteln
my $event=undef;
if (!$plugin_initflag) 
{ $event='restart'; } # Restart des daemons / Reboot
elsif ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'})
{ $event='modified'; } # Plugin modifiziert
elsif (%msg) { $event='bus'; } # Bustraffic
elsif ($fh) { $event='socket'; } # Netzwerktraffic
else { $event='cycle'; } # Zyklus

chdir $speechdir;

if($event=~/restart|modified/)
{
    my %gas=();

    # Erstaufruf - an GAs anmelden, auf die die Muster in %channels zutreffen
    for my $ga (keys %eibgaconf)
    {
	my $name=$eibgaconf{$ga}{'name'};
	next unless defined $name;

	for my $pat (keys %channels)
	{
	    next if $pat eq 'default';

	    if($name=~/$pat/)
	    {
		$plugin_subscribe{$ga}{$plugname}=1;
		$gas{$channels{$pat}}++;
	    }
	}
    }

    for my $ga (@additional_subscriptions)
    {
	$plugin_subscribe{$ga}{$plugname}=1;
	$gas{$channels{default}}++;
    }

    $plugin_info{$plugname.'_cycle'}=0;
    
    return join ' ', map $_.'->'.$gas{$_}, keys %gas; 
}
elsif($event=~/bus/ && $msg{'apci'} eq 'A_GroupValue_Write')
{
    my $ga=$msg{'dst'};
    my $val=$msg{'value'};
    my $dpt=$eibgaconf{$ga}{'DPTSubId'};
    $dpt=1.017 unless defined $dpt; # = Trigger, bedeutet Textansage ohne Daten
    
    my $name=$eibgaconf{$ga}{'name'};   
    my $channel=$channels{default};
    my $pattern=$name;

    for my $pat (keys %channels)
    {
	if($pattern=~s/$pat//)
	{
	    $channel=$channels{$pat};
	    last;
	}
    }

    # Hole alle verfuegbaren Durchsagedateien 
    my $find=checkexec('find');
    my @speech=split /\n/, `$find . -name "*.wav"`;
    
    return 'no speech files found' unless @speech;
    
    my @statement=();
    
    # Textteil (Gruppenadresse ausgesprochen)
    if(defined $pattern)
    {
	push(@statement, words(\@speech, $pattern));
    }
    
    # Informationsteil (Inhalt des Telegramms)
    given($dpt)
    {
	when (1.001) # An/Aus
	{ push(@statement, 'Zahlen/'.($val?'an':'aus').'.wav'); } 
	when (1.008) # Hoch/Runter
	{ push(@statement, 'Zahlen/'.($val?'hoch':'runter').'.wav'); }
	when(1.009) # Auf/Zu
	{ push(@statement, 'Zahlen/'.($val?'auf':'zu').'.wav'); }
	when([5.010,7.001,12.001]) # Ordinalzahl
	{ push(@statement, number(\@speech, $val, -1)); }
	when([6.010,8.001,13.001]) # Kardinalzahl
	{ push(@statement, number(\@speech, $val)); }
	when([5.001,6.001]) # Prozent
	{ 
	    push(@statement, number(\@speech, $val));
	    push(@statement, 'Zahlen/Prozent.wav'); 
	}
	when(9.001) # Temperatur
	{
	    push(@statement, number(\@speech, $val, 1));
	    push(@statement, 'Zahlen/Grad.wav');
	}
	when(11.001) # Datum
	{
	    if($val=~/^([0-9][0-9][0-9][0-9])-([0-9][0-9])-([0-9][0-9])/)
	    {
		my @monat=qw(Januar Februar Maerz April Mai Juni Juli August September Oktober November Dezember);
		push(@statement, number(\@speech, $3, -1));
		push(@statement, 'Monate/'.$monat[$2-1].'.wav') if defined $2 && $2>0 && $2<13;
	    }    
	    else
	    {
		return "Unbekanntes Datumsformat $val";
	    }
	}
	when(7.005) # Zeitdauer
	{ 
	    $val=-$val if $val<0;
	    my $h=floor($val/3600);
	    $val-=3600*$h;
	    my $m=floor($val/60);
	    $val-=60*$m;
	    if($h)
	    {
		push(@statement, number(\@speech, $h)); 
		push(@statement, 'Zeiten/Stunden.wav'); 
	    }
	    if($h || $m)
	    {
		push(@statement, number(\@speech, $m)); 
		push(@statement, 'Zeiten/Minuten.wav'); 
	    }
	    push(@statement, number(\@speech, $val)); 
	    push(@statement, 'Zeiten/Sekunden.wav'); 
        }
	when(10.001) # Uhrzeit
	{
	    if($val=~/^(Mo|Di|Mi|Do|Fr|Sa|So)\s+([0-9][0-9])\:([0-9][0-9])/)
	    {
		push(@statement, "Wochentage/$1.wav");
		push(@statement, number(\@speech, $2));
		push(@statement, "Zeiten/Uhr.wav");
		push(@statement, number(\@speech, $3));
	    }
	    elsif($val=~/^([0-9][0-9])\:([0-9][0-9])}\:([0-9][0-9])/)
	    {
		push(@statement, number(\@speech, $2));
		push(@statement, "Zeiten/Uhr.wav");
		push(@statement, number(\@speech, $3));
	    }
	    else
	    {
		return "Unbekanntes Uhrzeitformat $msg{value}";
	    }
	}
	when(1.017) # Trigger, kein Datenzusatz
	{}
	default	 # kein Datenzusatz, aber mit Logeintrag
	{ return "Datentyp $dpt nicht implementiert"; }  
    }
    # Das komplette Statement in die Ausgabe geben
    speak($channel, $name, @statement);
    
    return $name.' '.$msg{value};
}

return; 

sub checkexec
{
    my @path = split /:/, $ENV{PATH};
    map s|(.)/$|$1|, @path;
    for (@path)
    {
        my $full="$_/$_[0]";
        if(-x $full)
        {
            return "$_/$_[0]";
        }
    }
    die "$_[0] must be in your PATH and executable.\n";
}


sub words
{
    my $speech=shift;
    my $pattern=shift;

    # Konstruiere die abzuspielenden File(s) aus dem GA-Kuerzel
    # erster Versuch: eine Datei passt komplett auf das Muster im Kuerzel
    my $pat1=$pattern;
    $pat1=~s/[_\s]+/.*?/g; # allgemeine Fassung
#    $pat1=~s/\s+.*$//; # meine spezielle GA-Struktur
#    $pat1=~s/_+/.*?/g; # meine spezielle GA-Struktur
    $pat1='.*'.$pat1.'.*\.wav$';
    
    my @hits=();
    my $hit=bestmatch($speech,$pat1);
    push(@hits, $hit) if $hit; # gefunden

    unless(@hits)
    {
	$pattern='_'.$pattern;
	$pattern=~s/\s+/_/g; # allgemeine Fassung
#	$pattern=~s/\s+.*$//; # meine spezielle GA-Struktur

	# zweiter Versuch: aus Kuerzeln die Bausteine zusammenbauen
	while($pattern=~s/^_([^_]+)//)
	{
	    my $pat2=$1.'\.wav$'; 
	    $hit=bestmatch($speech,$pat2);
	    push(@hits, $hit) if $hit; # gefunden
	}	

	if($pattern)
	{
	    $pattern=~s/_/.*/g; # Restnachricht
	    $pattern.='.*\.wav$';
	    $pattern='.*'.$pattern;
	
	    $hit=bestmatch($speech,$pattern);
	    push(@hits, $hit) if $hit; # gefunden
	}
    }

    return @hits;
}


sub number
{
    my $speech=shift;
    my $x=shift; $x=~s/,/./; 
    my $digits=0;  
    $digits=shift if @_; # max. Anzahl Nachkommastellen, -1 fuer Ordinalzahlen

    my @hits=();

    if($x<0) 
    {
	push(@hits, 'Zahlen/minus.wav');
	$x=-$x;
	$digits=0 if $digits<0; # keine negativen Ordinalzahlen
    }

    my $t=$digits<0?'o':'c';
    my $n=floor($x);
    my $m=$x-$n;

    # Manche Zahlen existieren direkt als WAV
    # von 0-12, sowie die runden 10er und 100 sowie 1000 
    # MUESSEN existieren, und zwar als Kardinalzahlen (c4.wav),
    # Ordinalzahlen (o6.wav), die Zehner ausserdem mit vorangestelltem 'und'
    # (u30.wav, uo30.wav)

    if(-f 'Zahlen/'.$t.$n.'.wav') 
    {
	push(@hits, 'Zahlen/'.$t.$n.'.wav');
    }
    else
    {
	return if($n>=1000000); # Zahlen ueber eine Million nicht implementiert

	if($n>=1000)
	{
	    $digits=0 if $digits>0; # waere Pseudo-genauigkeit und zu langer Text
	    
	    if($n==1000)
	    {
		push(@hits, 'Zahlen/'.$t.'1000.wav');
		$n = 0;
	    }
	    else
	    {
		my $m=floor($n/1000);
		@hits=number($speech,$m,0) if $m>1;
		$n %= 1000;
		if($n)
		{
		    push(@hits, 'Zahlen/c1000.wav');
		}
		else
		{
		    push(@hits, 'Zahlen/'.$t.'1000.wav');
		}	
	    }
	    
	    if($n>=100 && $n<200)
	    {
		push(@hits, 'Zahlen/u1.wav');
	    }
	}

	if(-f 'Zahlen/'.$t.$n.'.wav') 
	{
	    push(@hits, 'Zahlen/'.$t.$n.'.wav');
	}
	elsif($n>100)
	{
	    $digits=0 if $digits>0; # waere Pseudo-genauigkeit und zu langer Text
	    my $h = int($n/100);
	    $n %= 100;
	    push(@hits, 'Zahlen/u'.$h.'.wav') if $h>1;
	    if($n)
	    {
		push(@hits, 'Zahlen/c100.wav');
	    }
	    else
	    {
		push(@hits, 'Zahlen/'.$t.'100.wav');
	    }	
	}
	
	my $d = $n % 10;
	
	if(-f 'Zahlen/'.$t.$n.'.wav') 
	{
	    push(@hits, 'Zahlen/'.$t.$n.'.wav');
	}
	else
	{
	    my $z = $n-$d;
	    
	    push(@hits, 'Zahlen/u'.$d.'.wav');
	    push(@hits, 'Zahlen/u'.$t.$z.'.wav');
	}
    }
	
    if($digits>0) 
    {
	$m = sprintf "%.$digits"."f", $m;
	
	if($m>0) 
	{
	    push(@hits, 'Zahlen/Komma.wav');
	    for (1..$digits)
	    {
		$m*=10.; my $d=floor($m); $m-=$d;
		push(@hits, "Zahlen/c$d.wav");
	    }
	}
    }

    return @hits;
}

sub bestmatch
{
    my $speech=shift;
    my $pattern=shift;

    my @hits=sort { length($a) cmp length($b) } grep /$pattern/i, @{$speech};
    
    return @hits ? (shift @hits) : undef;
}


sub speak
{
    my $channel=shift; # ALSA-Channel
    my $name=shift; # Name der Ansage (aus eibga.conf) - fuers Log

    open LOG, ">>$logfile";
    my $date=checkexec('date');
    my $datetime=`$date +"%F %X"`;
    $datetime=~s/\s*$//s; 
	
    if(@_)
    {
	my $aplay=checkexec('aplay');
	my $mpc=checkexec('mpc');
	system $mpc, 'pause';
	
	# Nur fuer Russound-Paging: Star Trek 'Beep' vorweg weckt Russound auf
	if($channel=~/$beepchannel/)
	{
	    my $lastbeep=$plugin_info{$plugname.'_lastbeep'};

	    # max ein Beep pro Minute
	    if(!defined $lastbeep || time()>$lastbeep+60)
	    {
		unshift(@_, $beep);
		$plugin_info{$plugname.'_lastbeep'}=time();
	    }
	}

	system $aplay, '-c2', "-D$channel", @_;

#	map s!^.*/(.*?)\.wav!$1!, @_;
	print LOG $datetime.' '.$channel.':'.(join ' ', @_)."\n";

	system $mpc, 'toggle';
    }
    else
    {
	print LOG "$datetime $name - keine akustische Ansage moeglich\n";
    }

    close LOG;
}

