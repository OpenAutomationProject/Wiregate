#!/usr/bin/perl -w
####################
# Szenencontroller #
####################
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License

#$plugin_info{$plugname.'_cycle'}=0; return "deaktiviert";

my $use_short_names=1; # 1 fuer GA-Kuerzel (erstes Wort des GA-Namens), 0 fuer die "nackte" Gruppenadresse

# eibgaconf fixen falls nicht komplett indiziert
# entfaellt ab Wiregate PL32
#if($use_short_names && !exists $eibgaconf{ZV_Uhrzeit})
#{
#    for my $ga (grep /^[0-9\/]+$/, keys %eibgaconf)
#    {
#	$eibgaconf{$ga}{ga}=$ga;
#	my $name=$eibgaconf{$ga}{name};
#	next unless defined $name;
#        $eibgaconf{$name}=$eibgaconf{$ga};
#
#	next unless $name=~/^\s*(\S+)/;
#	my $short=$1;
#	$short='ZV_'.$1 if $eibgaconf{$ga}{name}=~/^Zeitversand.*(Uhrzeit|Datum)/;
#
#	$eibgaconf{$ga}{short}=$short;
#	$eibgaconf{$short}=$eibgaconf{$ga};
#    }
#}

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
my %scene=();
my $conf="/etc/wiregate/plugin/generic/conf.d/$plugname"; 
$conf.='.conf' unless $conf=~s/\.pl$/.conf/;
my $err=read_from_config();
return $err if $err;

# Konfigfile seit dem letzten Mal geaendert?
my $config_modified = ($scene{storage} ne 'configfile' && (24*60*60*(-M $conf)-time()) > $plugin_info{$plugname.'_configtime'});

# Dynamisch definierte Szenen aus plugin_info einlesen
recall_from_plugin_info();

# Plugin-Code
my $retval='';

if($event=~/restart|modified/ || $config_modified)
{
    $plugin_info{$plugname.'_configtime'}=(24*60*60*(-M $conf)-time());

    # Cleanup aller Szenenvariablen in %plugin_info 
    for my $k (grep /^$plugname\_/, keys %plugin_info)
    {
	delete $plugin_info{$k};
    }

    # Alle Szenen-GAs abonnieren
    my $count=0;
    my $scene_lookup='';

    for my $sc (sort keys %scene)
    {
	next if $sc=~/^(storage|debug)$/;

	my $store=$scene{$sc}{store};
	my $recall=$scene{$sc}{recall};

	$store=$scene{$sc}{store}=$eibgaconf{$store}{ga} if $store!~/^[0-9\/]+$/ && defined $eibgaconf{$store};
	$recall=$scene{$sc}{recall}=$eibgaconf{$recall}{ga} if $recall!~/^[0-9\/]+$/ && defined $eibgaconf{$recall};
	
	next unless defined $store && defined $recall;

	$scene_lookup.="St($store)=>'$sc', Rc($recall)=>'$sc', ";
	
	$plugin_subscribe{$store}{$plugname}=1;
	$plugin_subscribe{$recall}{$plugname}=1;

	$count++;
    }

    $plugin_info{$plugname.'__Lookup'}=$scene_lookup;
    $plugin_info{$plugname.'_cycle'}=0; 
   
    $retval.=$count." initialisiert";
}
elsif($event=~/bus/)
{
    # nur auf Write-Telegramme reagieren
    if($msg{apci} ne 'A_GroupValue_Write')
    {
	for my $k (keys %scene) { delete $scene{$k}; } # Hilfe fuer die Garbage Collection
	return;
    }

    # Aufruf durch GA
    my $ga=$msg{dst};
    my $n=int($msg{value}); # die Szenennummer 

    # die betreffende Szene finden
    unless($plugin_info{$plugname.'__Lookup'}=~/(St|Rc)\($ga\)=>\'(.+?)\',/)
    {
	plugin_log($plugname, "Storniere $ga");
	delete $plugin_subscribe{$ga}{$plugname}; # unbekannte GA
	for my $k (keys %scene) { delete $scene{$k}; } # Hilfe fuer die Garbage Collection
	return;
    }

    my $cmd=$1; chop $cmd;
    my $sc=$2;

    if($eibgaconf{$ga}{DPTSubId} eq '1.017')
    {
        # Szenennummer aus physikalischer Adresse ableiten falls DPTSubId==1.017
	unless($msg{src}=~/[0-9]+\.[0-9]+\.([0-9]+)/)
	{
	    for my $k (keys %scene) { delete $scene{$k}; } # Hilfe fuer die Garbage Collection
	    return;
	}
	$n=$1;
    }
    elsif($scene{$sc}{store} eq $scene{$sc}{recall})
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
    my $z="$sc\#$n";

    if($cmd eq 'S') # Szene speichern
    {
	$retval.="Szene $z speichern: " if $scene{debug};
	
	my $confirm_store=$scene{$sc}{confirm_store};
	$confirm_store=$eibgaconf{$confirm_store}{ga} if $confirm_store!~/^[0-9\/]+$/ && defined $eibgaconf{$confirm_store};    
	knx_write($confirm_store,1); # Translator feuert spaeter dann eine Null hinterher, um die LED auszuschalten

	delete $scene{$z};

	for my $ga (sort keys %{$scene{$sc}{gas}})
	{
	    my $wga=$scene{$sc}{gas}{$ga}; # auf diese GA muss spaeter geschrieben werden
	    $wga=$eibgaconf{$wga}{short} if $wga=~/^[0-9\/]+$/ && $use_short_names && defined $eibgaconf{$wga}{short};    
	    
	    $ga=$eibgaconf{$ga}{ga} if $ga!~/^[0-9\/]+$/ && defined $eibgaconf{$ga};    

	    $scene{$z}{$wga}=knx_read($ga,300);  # KOSTET ZEIT FALLS GERAETE NICHT ANTWORTEN!

	    if(defined $scene{$z}{$wga})
	    {
		$retval.=$wga.'->'.$scene{$z}{$wga}.' ' if $scene{debug};
	    }
	    else
	    {
		$retval.=$wga.'? ' if $scene{debug};
		delete $scene{$z}{$wga};
	    }
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
	$retval.="Szene $z abrufen: " if $scene{debug};

	for my $v (keys %{$scene{$z}})
	{
	    knx_write(groupaddress($v),$scene{$z}{$v});
	    $retval.=$v.'->'.$scene{$z}{$v}.' ' if $scene{debug};
	}
    }    
}

for my $k (keys %scene) { delete $scene{$k}; } # Hilfe fuer die Garbage Collection
return unless $retval;
return $retval;

########## Datenpersistenz - Speichern und Einlesen ###############

sub read_from_config
{
    open CONFIG, "<$conf" || return "no config found";
    my @lines = <CONFIG>;
    close CONFIG;
    eval("@lines");
    return "config error: $@" if $@;
}

sub store_to_config
{
    my $z=shift; # die Szenenbezeichnung 

    open CONFIG, ">>$conf";
    print CONFIG "\$scene{'$z'}={";
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
    my @keylist=keys %{$scene{$z}};
    map { $_=sprintf("'$_'=>'%.2f'",$scene{$z}{$_}) } @keylist;   
    $plugin_info{$plugname.'__'.$z} = join ',', @keylist;
}

sub recall_from_plugin_info
{
    for my $k (grep /^$plugname\__/, keys %plugin_info)
    {
	next unless($k=~/^$plugname\__(.*\#.*)$/);
	my $z=$1;
	$scene{$z}={};
	my $pi=$plugin_info{$k};
	while($pi=~m/\'(.*?)\'=>\'(.*?)\'/g) { $scene{$z}{$1}=$2 }
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

