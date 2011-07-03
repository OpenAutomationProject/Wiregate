# Plugin zum Zeit abhängigem schaten von GA's (Schaltuhr)
# Version 0.2 03.07.2011
# Copyright: swiss (http://knx-user-forum.de/members/swiss.html)
# License: GPL (v2)
# Aufbau möglichst so, dass man unterhalb der Einstellungen nichts verändern muss!


####################
###Einstellungen:###
####################
my @Schaltzeiten;

#Pro Schaltpunkt einfach den unten stehenden Eintrag kopieren und anpassen.

push @Schaltzeiten, { name => "bewässerung_ein", montag => 1, dienstag => 1, mittwoch => 1, donnerstag => 1, freitag => 1, samstag => 0, sonntag => 1, Stunden => 15, Minuten => 45, Wert => 1, DPT => 1, ga => '2/0/0' };

push @Schaltzeiten, { name => "bewässerung_aus", montag => 1, dienstag => 1, mittwoch => 1, donnerstag => 1, freitag => 1, samstag => 0, sonntag => 1, Stunden => 15, Minuten => 46, Wert => 0, DPT => 1, ga => '2/0/0' };

######################
##ENDE Einstellungen##
######################

use POSIX;

# Eigenen Aufruf-Zyklus auf 30sek. setzen
$plugin_info{$plugname.'_cycle'} = 30;

#Hier wird ein Array angelegt, um die Wochentagsnummer von localtime zu übersetzen
my @Wochentag = ('sonntag', 'montag', 'dienstag', 'mittwoch', 'donnerstag', 'freitag', 'samstag');

my $sec;
my $min;
my $hour;
my $mday;
my $mon;
my $year;
my $wday;
my $yday;
my $isdst;


foreach my $element (@Schaltzeiten) {

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$year += 1900;

	if ($element->{$Wochentag[$wday]} == 1 && $element->{Stunden} == $hour && $element->{Minuten} == $min) {
		knx_write($element->{ga},$element->{Wert},$element->{DPT});
	}
next;
}