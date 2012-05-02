####################
# Szenencontroller #
####################
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License

# $plugin_info{$plugname.'_cycle'}=0; return "deaktiviert";

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
my %scene=();
my $err=read_from_config();
return "config err" if $err;

# Dynamisch definierte Szenen aus plugin_info einlesen
recall_from_plugin_info();

if($event=~/restart|modified/)
{
    # Cleanup aller Szenenvariablen in %plugin_info 
    for my $k (grep /^$plugname\_/, keys %plugin_info)
    {
	delete $plugin_info{$k};
    }

    # Alle Szenen-GAs abonnieren
    my $count=0;
    my $scene_lookup='';

    for my $room (keys %scene)
    {
	next if $room eq 'storage';

	my $store=$scene{$room}{store};
	my $recall=$scene{$room}{recall};

	$store=$scene{$room}{store}=$eibgaconf{$store}{ga} if $store!~/^[0-9\/]+$/ && defined $eibgaconf{$store};
	$recall=$scene{$room}{recall}=$eibgaconf{$recall}{ga} if $recall!~/^[0-9\/]+$/ && defined $eibgaconf{$recall};
	
	next unless defined $store && defined $recall;

	$scene_lookup.="St($store)=>'$room', Rc($recall)=>'$room', ";
	
	$plugin_subscribe{$store}{$plugname}=1;
	$plugin_subscribe{$recall}{$plugname}=1;

	$count++;
    }

    $plugin_info{$plugname.'__SceneLookup'}=$scene_lookup;
    $plugin_info{$plugname.'_cycle'}=0; 
   
    return $count." initialisiert";
}

if($event=~/bus/)
{
    # nur auf Write-Telegramme reagieren
    return if $msg{apci} ne 'A_GroupValue_Write'; 

    # Aufruf durch GA
    my $ga=$msg{dst};
    my $n=int($msg{value}); # die Szenennummer 

    # die betreffende Szene finden
    unless($plugin_info{$plugname.'__SceneLookup'}=~/(St|Rc)\($ga\)=>\'(.+?)\',/)
    {
	delete $plugin_subscribe{$ga}{$plugname}; # unbekannte GA
	return;
    }

    my $cmd=$1; chop $cmd;
    my $room=$2;

    if($eibgaconf{$ga}{DPTSubId} eq '1.017')
    {
        # Szenennummer aus physikalischer Adresse ableiten falls DPTSubId==1.017
	return unless $msg{src}=~/[0-9]+\.[0-9]+\.([0-9]+)/;
	$n=$1;
    }
    elsif($scene{$room}{store} eq $scene{$room}{recall})
    {
        # Speichern oder Abrufen? Falls beides die gleiche GA, aus 7. Bit der Szenennummer ableiten
	$cmd = ($n & 0x80)?'S':'R';
        $n = ($n & 0x7f)+1; 
    }
    else # Aufruf mit Wert = Szenennummer
    {
        $n = 128 if $n>128; # begrenzen auf max. 128
    }

    # Szenencode
    my $z="$room\__$n";

    # Debugging
#    plugin_log($plugname, "Szene $z ".($cmd eq 'S'?'speichern':'abrufen'));

    if($cmd eq 'S') # Szene speichern
    {
	delete $scene{$z};

	for my $ga (keys %{$scene{$room}{gas}})
	{
	    my $wga=$scene{$room}{gas}{$ga}; # auf diese GA muss spaeter geschrieben werden
	    $wga=$eibgaconf{$wga}{short} if $wga=~/^[0-9\/]+$/ && $use_short_names && defined $eibgaconf{$wga}{short};    
	    $ga=$eibgaconf{$ga}{ga} if $ga!~/^[0-9\/]+$/ && defined $eibgaconf{$ga};    
	    $scene{$z}{$wga}=knx_read($ga,300);
	    delete $scene{$z}{$wga} unless defined $scene{$z}{$wga};
	}

	if($scene{storage} eq 'configfile')
	{
	    store_to_config($z);
	}
	else
	{
	    store_to_plugin_info($z);
	}
    }
    else # Szene abrufen
    {
	for my $v (keys %{$scene{$z}})
	{
	    my $ga=$v;
	    $ga=$eibgaconf{$ga}{ga} if $ga!~/^[0-9\/]+$/ && defined $eibgaconf{$ga};
	    knx_write($ga,$scene{$z}{$v});
	}
    }    
}

return;

########## Datenpersistenz - Speichern und Einlesen ###############

sub read_from_config
{
    open CONFIG, "<$conf" || return "no config found";
    my @lines = <CONFIG>;
    close CONFIG;
    eval("@lines");
    return "config error" if $@;
}

sub store_to_config
{
    my $z=shift; # die Szenenbezeichnung 

    open CONFIG, ">>$conf";
    print CONFIG "\$scene{$z}={";
    for my $v (sort keys %{$scene{$z}})
    {
	print CONFIG sprintf "'$v'=>%.2f, ", $scene{$z}{$v};
    }
    print CONFIG "};\n";
    close CONFIG;
}

# alternativ: speichern ins globale Hash plugin_info

sub store_to_plugin_info
{
    my $z=shift; # die Szenenbezeichnung   

    # Alle Laufzeitvariablen im Hash %{$dyn} 
    # in das (flache) Hash plugin_info schreiben
    for my $k (grep /^$plugname\__$z/, keys %plugin_info)
    {
	delete $plugin_info{$k};
    }
    
    for my $v (keys %{$scene{$z}})
    {
	$plugin_info{$plugname.'__'.$z.'__'.$v}=$scene{$z}{$v};
    }
}

sub recall_from_plugin_info
{
    for my $k (grep /^$plugname\__/, keys %plugin_info)
    {
	next unless($k=~/^$plugname\__([A-Z0-9 ]+__[0-9]+)__(.*)$/i);
	my ($z,$v)=($1,$2); 
	$scene{$z}{$v}=$plugin_info{$k};
    }
}

