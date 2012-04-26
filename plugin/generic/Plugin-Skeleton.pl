#!/usr/bin/perl -w
#
######################
# <NAME DES PLUGINS> #
######################
#
# Wiregate-Plugin
#
# (c) 2012 <AUTOR>, licensed under the GNU Public License v2 or later
#
# this skeleton is (c) 2012 Fry, licensed under the GNU Public License v2 or later
#

# Option zum einfachen Deaktivieren
# $plugin_info{$plugname.'_cycle'}=0; return "deaktiviert";

# Benutzte Perl-Packages
use POSIX qw(floor strftime);

# Optional: wer blanke Gruppenadressen hasst, gibt jeder GA einen Namen
# und pflegt diesen auch in /etc/wiregate/eibga.conf ein (wie auch die DPTs). 
#
# Empfehlung: bei mir ist das erste Wort des GA-Namens ein eindeutiges Kuerzel,
# zum Beispiel "LI_K1 Licht an/aus Kinderzimmer 1"=4/3/17. Ich arbeite dann in allen
# Plugins statt mit 4/3/17 mit $eibshort{LI_K1}{ga}.
#
# Hilfs-Hash eibshort initialisieren
my %eibshort;
for my $ga (keys %eibgaconf)
{
    next unless defined $eibgaconf{$ga}{'name'};
    my $short=$eibgaconf{$ga}{'name'};

    # wer lieber mit vollen GA-Namen arbeitet, kommentiert die nächste Zeile aus
    next unless $short=~/^(\S+)/; $short=$1;

    $eibshort{$short}=$eibgaconf{$ga};
    $eibshort{$short}{ga}=$ga;
    $eibshort{$ga}=$short; # inverses Lookup
}

# Aufrufgrund ermitteln
my $event=undef;
if (!$plugin_initflag) 
{ $event='restart'; } # Restart des daemons / Reboot
elsif ($plugin_info{$plugname.'_lastsaved'} > $plugin_info{$plugname.'_last'})
{ $event='modified'; } # Plugin modifiziert
elsif (%msg) { $event='bus'; } # Bustraffic
elsif ($fh) { $event='socket'; } # Netzwerktraffic
else { $event='cycle'; } # Zyklus

# Konfigurationsfile einlesen
# Im Konfigurationsfile muss das Hash %config definiert werden (ohne "my"!)
# zum Beispiel so: 
# %config=( subscribe => [ '4/3/16', $eibshort{LI_K1}{ga} ] );
#
my $conf=$plugname; $conf=~s/\.pl$/.conf/;
$conf="/etc/wiregate/plugin/generic/conf.d/$conf";
my %config=();
open CONFIG, "<$conf" || return "no config found";
my @lines = <CONFIG>;
close CONFIG;
eval("@lines");
return "config error: $@" if $@;

# Plugin-Code fuer die verschiedenen Aufrufvarianten
if($event=~/restart|modified/)
{
    # Erster Aufruf nach Reboot, Daemon-Restart oder Plugin-Modifikation

    # Cleanup aller Variablen
    for my $k (grep /^$plugname\_/, keys %plugin_info)
    {
	delete $plugin_info{$k};
    }

    # Alle GAs abonnieren
    for my $ga (@{$config{subscribe}})
    {
	plugin_subscribe{$ga}{plugname}=1;
    }

    $plugin_info{$plugname.'_cycle'}=1000; 

    return 'initialisiert';
}
elsif($event=~/cycle/)
{ 
    # Aktivitaet bei zyklischem Aufruf

    return 'cycle';
}
elsif($event=~/bus/)
{
    # Aufruf durch Bustraffic
    return if $msg{apci} eq 'A_GroupValue_Response'; # darauf nicht reagieren

    my $ga=$msg{dst};
    my $val=$msg{value}; 
    # falls DPT-Typen nicht in /etc/wiregate/eibga.conf eingepflegt sind,
    # muss $val hier durch expliziten Aufruf von decode_dpt(...) ermittelt werden.

    given($ga)
    {
	when ($eibshort{LI_K1}{ga}) 
	{ 
	    if($msg{apci} eq 'A_GroupValue_Write')
	    {
		# AKtivitaet bei erhaltenem Bustelegramm
		return $ga; # Returnwert des Plugins
	    }
	    elsif($msg{apci} eq 'A_GroupValue_Read')
	    {
		# Antwort auf Lesetelegramm senden
		knx_write($ga, 1, 1);
		return; # ohne Wert
	    }	    
	} 
	when ('4/3/17') # Version mit "nackter" GA 
	{ 
	    if($msg{apci} eq 'A_GroupValue_Write')
	    {
		# AKtivitaet bei erhaltenem Bustelegramm
		return $ga; # Returnwert des Plugins
	    }
	    elsif($msg{apci} eq 'A_GroupValue_Read')
	    {
		# Antwort auf Lesetelegramm senden
		knx_write($ga, 1, 1);
		return; # ohne Wert
	    }	    
	} 
	default
	{
	    # GA-Abonnement loeschen
	    delete $plugin_subscribe{$ga}{$plugname};  
	}
    }

}

return;

