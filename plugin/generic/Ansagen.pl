###########
# Ansagen #
###########
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License version 2 or later

# $plugin_info{$plugname.'_cycle'}=0; return 'deaktiviert';

use POSIX qw(floor);
use feature "switch"; # aktiviert given...when-Struktur von Perl 5.10

# Defaultkonfiguration
my $speechdir='/var/lib/mpd/music/Ansagen';
my $mpddir='/var/lib/mpd/music';
my %channels=('default'=>'welcome');
my $beepchannel='paging';
my $beep = "Beep/03d.wav"; 
my @additional_subscriptions=();
my %mpdhost=('default'=>'127.0.0.1/6600');
my $mode='mpd'; 
my $radioga=undef;
my %stations=(); # Internet-Radiostationen

# Konfigurationsfile einlesen
my $conf=$plugname; $conf.='.conf' unless $conf=~s/\.pl$/.conf/;
open FILE, "</etc/wiregate/plugin/generic/conf.d/$conf" || return "no config found";
my @lines = <FILE>;
close FILE;
eval("@lines");

# speechdir muss im mpddir liegen!
$speechdir=~s!/$!!;
$mpddir=~s!/$!!;
return "config error: $@" if $@ || ($mode eq 'mpd' && $speechdir !~ /^$mpddir/);

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
    for my $k (grep /^$plugname\_/, keys %plugin_info)
    {
	delete $plugin_info{$k};
    }

    # Rueckwaertskompatible Behandlung von eibgaconf
    for my $ga (grep /^[0-9\/]+$/, keys %eibgaconf)
    {
	my $name=$eibgaconf{$ga}{name};
	next unless defined $name;

	my $channel_found=undef;
	for my $pat (keys %channels)
	{
	    next if $pat eq 'default' || $name!~/$pat/;
	    $channel_found=$channels{$pat};
	    last;
	}
	next unless $channel_found;

	$gas{$channel_found}++;
	$plugin_subscribe{$ga}{$plugname}=1;

	if($name=~/$radioga/)
	{
	    speak($channel_found,$name,'AUS');
	    $plugin_info{$plugname.'_radio_'.$channel_found}='AUS';
	    plugin_log($plugname, 'Internetradio auf Kanal '.$channel_found.', GA='.$ga); 
	}
    }

    my $channel_found=$channels{'default'};
    if($channel_found)
    {
	for my $ga (@additional_subscriptions)
	{
	    my $name=$eibgaconf{$ga}{name};
	    
	    $gas{$channel_found}++;
	    $plugin_subscribe{$ga}{$plugname}=1;
	    
	    if($name=~/$radioga/)
	    {
		speak($channel_found,$name,'AUS');
		$plugin_info{$plugname.'_radio_'.$channel_found}='AUS';
		plugin_log($plugname, 'Internetradio auf Kanal '.$channel_found.', GA='.$ga); 
	    }
	}
    }

    $plugin_info{$plugname.'_cycle'}=0;
    
    return join ' ', map $_.'->'.$gas{$_}, keys %gas; 
}
elsif($event=~/bus/)
{
    return if $msg{apci} eq "A_GroupValue_Response";

    my $ga=$msg{dst};
    my $val=$msg{value};
    my $dpt=$eibgaconf{$ga}{DPTSubId};
    $dpt=1.017 unless defined $dpt; # = Trigger, bedeutet Textansage ohne Daten
    
    my $name=$eibgaconf{$ga}{name};   
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
    
    # Radiosender bei dpt 16 (Text=Sendername)
    if($mode eq 'mpd' && $name=~/$radioga/ && $dpt=~/^16/)
    {
	if($msg{apci} eq 'A_GroupValue_Read')
	{
	    # Host und Port ermitteln
	    $mpdhost{$channel}=~m!^\s*(.*)\s*/\s*(.*)\s*$!;
	    my $host=$1; my $port=$2;

	    # aus irgendeinem Grund funktioniert %ENV im wiregate-Plugin nicht
	    # also so:
	    my $mpc=checkexec('mpc');
	    $mpc="export MPD_HOST=$host; export MPD_PORT=$port; $mpc";

	    # Laeuft gerade das Radio oder eine Ansage?
	    my $lfd_radio = $plugin_info{$plugname.'_radio_'.$channel} ne 'AUS';
	    my $lfd_ansage = `$mpc`=~/playing/s && !$lfd_radio;

	    return unless $lfd_radio && !$lfd_ansage;

	    my $mpcout=`$mpc`;    
	    $mpcout=~s/\n.*//s; # erste Zeile rausschneiden
	    knx_write($ga, $mpcout, undef, 0x40); # response, DPT aus eibga.conf		    
	}
	else
	{
	    $val=~s/\000*$//; # streiche Nullen am Ende
	    return speak($channel, $name, $val);
	}
    }
    
    return unless $msg{apci} eq 'A_GroupValue_Write';

    # Hole alle verfuegbaren Durchsagedateien 
    my $find=checkexec('find');
    my @speech=split /\n/, `$find . -name '*.wav'`;
    map s!^\./!!, @speech; # Pfade relativ zum speechdir
    return 'no speech files found' unless @speech;
    
    my @statement=();
    
    # Praefix bei Gefahrenwarnung (dpt 5.005)
    push(@statement, words(\@speech, 'Achtung')) if $dpt eq '5.005'; # Gefahrenwarnung
    
    # Textteil (Gruppenadresse ausgesprochen)
    push(@statement, words(\@speech, $pattern)) if defined $pattern;
    
    # Informationsteil (Inhalt des Telegramms)
    given($dpt)
    {
	when (1.001) # An/Aus
	{ 
	    push(@statement, 'Zahlen/'.($val?'an':'aus').'.wav'); 
	} 
	when (1.008) # Hoch/Runter
	{ 
	    push(@statement, 'Zahlen/'.($val?'hoch':'runter').'.wav'); 
	}
	when(1.009) # Auf/Zu
	{ 
	    push(@statement, 'Zahlen/'.($val?'auf':'zu').'.wav'); 
	}
	when(2.007) # Auf/Ab/Stop
	{ 
	    push(@statement, 'Zahlen/'.($val==1?'auf':($val==-1?'ab':'stop')).'.wav'); 
	}
	when(5.005) # Gefahrenwarnung
	{ 
	    my %warnstufe=(0=>'keine_Meldung', 1=>'Hinweis', 2=>'Vorwarnung', 3=>'Warnung', 4=>'Gefahr', 5=>'Gefahr_hoch');
	    push(@statement, 'Warnung/'.$warnstufe{$val}.'.wav'); 
	}
	when([5.010,7.001,12.001]) # Ordinalzahl
	{ 
	    push(@statement, number(\@speech, $val, -1)); 
	}
	when([3.007,6.010,8.001,13.001]) # Kardinalzahl
	{ 
	    push(@statement, number(\@speech, $val)); 
	}
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
		return "Unbekanntes Datumsformat '$val'";
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
		push(@statement, number(\@speech, $3)) if int($3)>0;
	    }
	    elsif($val=~/^([0-9][0-9])\:([0-9][0-9])/)
	    {
		push(@statement, number(\@speech, $1));
		push(@statement, "Zeiten/Uhr.wav");
		push(@statement, number(\@speech, $2)) if int($2)>0;
	    }
	    else
	    {
		return "Unbekanntes Uhrzeitformat '$val'";
	    }
	}
	when(/^16/) # Freitext
	{
	    $val=~s/\000*$//; # streiche Nullen am Ende
	    push(@statement, words(\@speech, $val));
	}
	when(1.017) # Trigger, kein Datenzusatz
	{}
	default	 # kein Datenzusatz, aber mit Logeintrag
	{ 
	    return "Datentyp $dpt nicht implementiert"; 
	}  
    }
    # Das komplette Statement in die Ausgabe geben
    return speak($channel, $name, @statement);
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

    my @hits=sort { length($a) <=> length($b) } grep /$pattern/i, @{$speech};
    
    return @hits ? (shift @hits) : undef;
}


sub speak
{
    my $channel=shift; # ALSA-Channel
    my $name=shift; # Name der Ansage (aus eibga.conf) - fuers Log

    my $retval='';
    my $date=checkexec('date');
    my $datetime=`$date +"%F %X"`;
    $datetime=~s/\s*$//s; 
	
    # Fuer Russound-Ausgabe: Star Trek 'Beep' vorweg weckt Russound (und User) fuer Ansage auf
    if($channel=~/$beepchannel/ && $name!~/$radioga/)
    {
	my $lastbeep=$plugin_info{$plugname.'_lastbeep_'.$channel};
	
	# max ein Beep pro Minute
	if(!defined $lastbeep || time()>$lastbeep+60)
	{
	    unshift(@_, $beep);
	    $plugin_info{$plugname.'_lastbeep_'.$channel}=time();
	}
    }

    if(@_)
    {
	if($mode eq 'aplay')
	{
	    my $aplay=checkexec('aplay');
	    system $aplay, '-c2', "-D$channel", @_;

	    map s!^.*/(.*?)\.wav!$1!, @_;
	    $retval.=$channel.':'.(join ' ', @_);
	}
	elsif($mode eq 'mpd')
	{
	    # Host und Port ermitteln
	    $mpdhost{$channel}=~m!^\s*(.*)\s*/\s*(.*)\s*$!;
	    my $host=$1; my $port=$2;

	    # aus irgendeinem Grund funktioniert %ENV im wiregate-Plugin nicht
	    # also so:
	    my $mpc=checkexec('mpc');
	    $mpc="export MPD_HOST=$host; export MPD_PORT=$port; $mpc";

	    # Laeuft gerade das Radio oder eine Ansage?
	    my $lfd_radio = $plugin_info{$plugname.'_radio_'.$channel} ne 'AUS';
	    my $lfd_ansage = `$mpc`=~/playing/s && !$lfd_radio;

	    # Sonderfall Internetradio statt Sprachausgabe
	    if($name=~/$radioga/)
	    {
		my $val=$_[0];

		if($val=~s/V([+-]?[0-9X])$//)
		{
		    my $vol=$1;
		    $vol = ($vol eq 'X' ? 100: 10*$vol);
		    system "$mpc volume $vol"; # ermoeglicht gleichzeitig Sender u Lautstaerke festzulegen
		}

		if($val eq 'AUS')
		{
		    system "$mpc clear";
		    $plugin_info{$plugname.'_radio_'.$channel}='AUS';
		}
		elsif($val =~ /^VOLUME\s*([+-]?[0-9]+)/)
		{
		    system "$mpc volume $1";		    
		}
		elsif(grep /$val/i, keys %stations)
		{
		    my $station=undef;
		    
		    unless(defined $stations{$val})
		    {
			my @hits=grep /$val/i, sort { length($a) <=> length($b) } keys %stations;
			$val=shift @hits;
		    }
		    $station=$stations{$val};

		    my $wget=checkexec('wget');
		    
		    # MusicPal-Links "uebersetzen"
		    if($station=~/freecom\.vtuner\.com/)
		    {
			$station=~s!freecom\.vtuner\.com!vtuner.com!;
			$station=~s!setupapp/fc/asp!setupapp/guide/asp!;
			$station=~s!dynam.*?\.asp!dynampls.asp!;
			$station=~s!\?ex45v=.*\&id=!\?id=!;
		    }
		    
		    # vtuner-Links "uebersetzen"
		    $station = `$wget 2>/dev/null -O - $station` if $station=~/vtuner/;
		    
		    system "$mpc clear" unless $lfd_ansage; # nur leeren falls abgespielt
		    system "$mpc add \"$station\"";
		    plugin_log($plugname, "$mpc add \"$station\"");
		    system "$mpc play" unless `$mpc`=~/playing/s; # starten falls noch nicht aktiv
		    $plugin_info{$plugname.'_radio_'.$channel}=$station;

		    $retval.="$channel:Radiosender '$val'='$station'";
		}
		else
		{
		    $retval.="Unbekannter Radiosender '$val'";
		}
	    }
	    else # Regelfall: Sprachausgabe
	    {
		system "$mpc update"; # Aktualisierung verfuegbarer Soundclips

		push @_, "silence.wav"; # kurze Pause zwischen Ansagen

		map s!^/*!$speechdir/!, @_; # alle Eintraege relativ zum speechdir
		map s!^$mpddir/!!, @_; # mpd braucht einen Pfadnamen relativ zum music-Dir
		map s!/+!/!, @_; # zur Sicherheit

		push @_, $plugin_info{$plugname.'_radio_'.$channel} if $lfd_radio; # nach der Ansage wieder zurueck aufs Radio

		# wird momentan noch was gespielt?
                # dann Playlist leeren, ggf Radio stoppen falls abgespielt
		system "$mpc crossfade 0"; # nur leeren falls abgespielt
		system "$mpc clear" unless $lfd_ansage; 
		# ein Fall noch zu klaeren: wenn Radio laeuft und zwei Ansagen kurz hintereinander kommen,
		# wird die zweite die erste unterbrechen, weil $lfd_ansage hier (inkorrekt) 0 sein wird.

		system "$mpc add \"".(join "\" \"", @_)."\"";
#		plugin_log($plugname, "$mpc add \"".(join "\" \"", @_)."\"");
		system "$mpc play" unless `$mpc`=~/playing/s; # starten falls noch nicht aktiv

		map s!^.*/(.*?)\.wav!$1!, @_;

		$retval.=$channel.':'.(join ' ', @_);
	    }
	}
	else
	{
	    $retval.="$name - no output (mpd or aplay) defined";
	}
    }
    else
    {
	$retval.="$name - no audio output possible (file not found)";
    }
    
    return $retval;
}

