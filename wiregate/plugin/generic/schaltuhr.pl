# Plugin zum Zeit abhängigem schaten von GA's (Schaltuhr)
# Version 0.5 BETA 03.07.2011
# Copyright: swiss (http://knx-user-forum.de/members/swiss.html)
# License: GPL (v2)
# Aufbau möglichst so, dass man unterhalb der Einstellungen nichts verändern muss!


####################
###Einstellungen:###
####################
my @Schaltzeiten;

#Pro Schaltpunkt einfach den unten stehenden Eintrag kopieren und anpassen.

push @Schaltzeiten, { name => "bewässerung_ein", montag => 1, dienstag => 1, mittwoch => 1, donnerstag => 1, freitag => 1, samstag => 0, sonntag => 1, Stunden => 21, Minuten => 02, Wert => 1, DPT => 1, ga => '2/0/0', KW => '', Monat => '' };

push @Schaltzeiten, { name => "bewässerung_aus", montag => 1, dienstag => 1, mittwoch => 1, donnerstag => 1, freitag => 1, samstag => 0, sonntag => 1, Stunden => 21, Minuten => 03, Wert => 0, DPT => 1, ga => '2/0/0', KW => '', Monat => '' };

######################
##ENDE Einstellungen##
######################

use POSIX;
use Time::Local;

# Eigenen Aufruf-Zyklus auf 20sek. setzen
$plugin_info{$plugname.'_cycle'} = 20;

#Hier wird ein Array angelegt, um die Wochentagsnummer von localtime zu übersetzen
my @Wochentag = ('sonntag', 'montag', 'dienstag', 'mittwoch', 'donnerstag', 'freitag', 'samstag');

my $sec; #Sekunde
my $min; # Minute
my $hour; #Stunde
my $mday; #Monatstag
my $mon; #Monatsnummer
my $year; #Jahr
my $wday; #Wochentag 0-6
my $yday; #Tag ab 01.01.xxxx
my $isdst;

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year += 1900;
$mon += 1;

my $kw = getWeekNumber($year, $mon, $mday);

foreach my $element (@Schaltzeiten) {
	if (knx_read($element->{ga},0,$element->{DPT}) ne $element->{Wert}) {
		if ($element->{$Wochentag[$wday]} == 1 && $element->{Stunden} == $hour && $element->{Minuten} == $min && $element->{KW} ne '') {
			if ($element->{KW} == $kw) {
				knx_write($element->{ga},$element->{Wert},$element->{DPT});
				next;
			} else {
				next;
			}
		} elsif ($element->{$Wochentag[$wday]} == 1 && $element->{Stunden} == $hour && $element->{Minuten} == $min && $element->{Monat} ne '') {
			if ($element->{Monat} == $mon) {
				knx_write($element->{ga},$element->{Wert},$element->{DPT});
				next;
			} else {
				next;
			}
		} elsif ($element->{$Wochentag[$wday]} == 1 && $element->{Stunden} == $hour && $element->{Minuten} == $min && $element->{KW} eq '' && $element->{Monat} eq '') {
			knx_write($element->{ga},$element->{Wert},$element->{DPT});
			next;
		}
	}	
next;
}

sub getWeekNumber {
my ($year, $month, $day) = @_;
my $weekNumber = checkWeekNumber($year, $month, $day);
# wenn Wochennummer gleich 0, dann ist das aktuelle Datum
# in der Woche vor dem 4. Januar
# also in der letzten Woche des letzten Jahres
if ($weekNumber eq 0)
{
# Wochennummer des letzten Woche des letzten Jahres suchen
$weekNumber = checkWeekNumber(($year - 1), 12, 31);

# wenn die Wochennummer größer als 52 ist
# dann prüfen ob diese Wochennummer korrekt ist oder
# sie bereits die erste Woche des aktuellen Jahres ist
if ($weekNumber gt 52)
{
$weekNumber = checkWeekNumber($year, 1, 1);
# wenn der 1. Januar des aktuellen Jahres in der Woche 0 liegt
# dann ist es die Woche 53
if ($weekNumber eq 0)
{
$weekNumber = 53;
}
}
}
# wenn die Wochennummer größer als 52 ist
# dann prüfen ob diese Wochennummer korrekt ist oder
# sie bereits die erste Woche des nächsten Jahres ist
elsif ($weekNumber gt 52)
{
$weekNumber = checkWeekNumber(($year + 1), 1, 1);
# wenn der 1. Januar des nächsten Jahres in der Woche 0 liegt
# dann ist es die Woche 53
if ($weekNumber eq 0)
{
$weekNumber = 53;
}
}

return ($weekNumber);
}

sub checkWeekNumber {
my ($year, $month, $day) = @_;

# 4. Januar als erste Woche erstellen
my $firstDateTime = timelocal(0, 0, 12, 4, 0, $year);
# Wochentag des 4. Januar ermitteln
my $dayOfWeek = (localtime($firstDateTime))[6];
$dayOfWeek = abs((($dayOfWeek + 6) % 7));
# geh zu Wochenanfang (Montag) zurück
$firstDateTime -= ($dayOfWeek * 3600 * 24);

# aktuelles Datum erstellen
my $currentDateTime = timelocal(0, 0, 14, $day, ($month - 1),$year);

# Differenz in Tagen berechnen
my $diffInDay = ($currentDateTime - $firstDateTime) / 3600 / 24;
# Anzahl der Wochen zwischen aktuellem Datum und 4. Januar berechnen
my $weekNumber = floor($diffInDay / 7) + 1;

return ($weekNumber);
}