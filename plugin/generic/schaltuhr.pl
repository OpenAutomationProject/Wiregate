# Plugin zum Zeit abhängigem schalten von GA's (Schaltuhr)
# Version 0.8 BETA 03.10.2012
# Copyright: swiss (http://knx-user-forum.de/members/swiss.html)
# License: GPL (v2)
# Aufbau möglichst so, dass man unterhalb der Einstellungen nichts verändern muss!
# -Erweitert um Sonnenauf / - untergang von ZeitlerW (http://knx-user-forum.de/members/zeitlerw.html)
# -Inspiriert von kleinklausi's Rolladen - Plugin

my @Schaltzeiten;

####################
###Einstellungen:###
####################

# Die Standortdaten 
# Die Koordinaten des Hauses. Sehr einfach ?ber http://www.getlatlon.com/ zu ermitteln.
my ($lat, $lon) = (
    51.66787081407156, # Breitengrad in Grad
    13.64227294921875  # L?ngengrad in Grad
    );

#Winkel für Beginn der Dämmerung
# siehe auch: http://search.cpan.org/~rkhill/Astro-Sunrise-0.91/Sunrise.pm#DESCRIPTION 
my $winkel=-3;


#Pro Schaltpunkt einfach den unten stehenden Eintrag kopieren und anpassen.
#Sollen Schaltzeiten astronomisch geschaltet werden, so muss bei Astro 'a' für Sonnenaufgang
#und 'u' für Sonnenuntergang eingetragen werden. Der Stunden und Minutenwert wird dann ignoriert.

push @Schaltzeiten, { name => "test", montag => 1, dienstag => 1, mittwoch => 1, donnerstag => 1, freitag => 1, samstag => 0, sonntag => 0, Stunden => 21, Minuten => 10, Wert => 1, DPT => 1, ga => '1/0/0', KW => '', Monat => '', Astro => '' };
push @Schaltzeiten, { name => "test1", montag => 1, dienstag => 1, mittwoch => 1, donnerstag => 1, freitag => 1, samstag => 0, sonntag => 0, Stunden => 21, Minuten => 11, Wert => 0, DPT => 1, ga => '1/0/0', KW => '', Monat => '', Astro => '' };
push @Schaltzeiten, { name => "test2", montag => 1, dienstag => 1, mittwoch => 1, donnerstag => 1, freitag => 1, samstag => 0, sonntag => 0, Stunden => 21, Minuten => 10, Wert => 1, DPT => 1, ga => '1/0/25', KW => '', Monat => '', Astro => '' };
push @Schaltzeiten, { name => "test3", montag => 1, dienstag => 1, mittwoch => 1, donnerstag => 1, freitag => 1, samstag => 0, sonntag => 0, Stunden => 21, Minuten => 12, Wert => 0, DPT => 1, ga => '1/0/25', KW => '', Monat => '', Astro => '' };


######################
##ENDE Einstellungen##
######################

use POSIX;
use Time::Local;
# Wir brauchen auch Sonnenstandsberechnung
use Astro::Sunrise;

# Eigenen Aufruf-Zyklus auf 20sek. setzen
$plugin_info{$plugname.'_cycle'} = 20;

#Hier wird ein Array angelegt, um die Wochentagsnummer von localtime zu übersetzen
my @Wochentag = ('sonntag', 'montag', 'dienstag', 'mittwoch', 'donnerstag', 'freitag', 'samstag');

my @sunrise=split(/:/,sun_rise($lon,$lat,$winkel));
my @sunset=split(/:/,sun_set($lon,$lat,$winkel));
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

if(($plugin_info{$plugname.'_time'}+60) <= $plugin_info{$plugname.'_last'}){
    foreach my $element (@Schaltzeiten) {
             if ($element->{Astro} ne '') {
                 if ($element->{Stunden} ne '' or $element->{Minuten} ne '') {
                    if ($element->{Astro} eq 'a') {
                        $element->{Stunden}+=$sunrise[0];
                        $element->{Minuten}+=$sunrise[1];
                    } elsif ($element->{Astro} eq 'u') {
                                        $element->{Stunden}+=$sunset[0];
                                        $element->{Minuten}+=$sunset[1];
                    }
                 }else{
                    if ($element->{Astro} eq 'a') {
                        $element->{Stunden}=$sunrise[0];
                        $element->{Minuten}=$sunrise[1];
                    } elsif ($element->{Astro} eq 'u') {
                                        $element->{Stunden}=$sunset[0];
                                        $element->{Minuten}=$sunset[1];
                    }                
                 }
              
              }
            if ($element->{$Wochentag[$wday]} == 1 && $element->{Stunden} == $hour && $element->{Minuten} == $min && $element->{KW} ne '') {
            $plugin_info{$plugname.'_time'} = time();
                if ($element->{KW} == $kw) {
                    knx_write($element->{ga},$element->{Wert},$element->{DPT});
                    plugin_log($plugname,'Schaltpunkt: ' . $element->{name} . ' ausgeführt. Wert: ' . $element->{Wert} . ' an Gruppenadresse ' . $element->{ga} . ' gesendet');
                    next;
                } else {
                    next;
                }
            } elsif ($element->{$Wochentag[$wday]} == 1 && $element->{Stunden} == $hour && $element->{Minuten} == $min && $element->{Monat} ne '') {
                $plugin_info{$plugname.'_time'} = time();
                if ($element->{Monat} == $mon) {
                    knx_write($element->{ga},$element->{Wert},$element->{DPT});
                    plugin_log($plugname,'Schaltpunkt: ' . $element->{name} . ' ausgeführt. Wert: ' . $element->{Wert} . ' an Gruppenadresse ' . $element->{ga} . ' gesendet');
                    next;
                } else {
                    next;
                }
            } elsif ($element->{$Wochentag[$wday]} == 1 && $element->{Stunden} == $hour && $element->{Minuten} == $min && $element->{KW} eq '' && $element->{Monat} eq '') {
                $plugin_info{$plugname.'_time'} = time();
                knx_write($element->{ga},$element->{Wert},$element->{DPT});
                plugin_log($plugname,'Schaltpunkt: ' . $element->{name} . ' ausgeführt. Wert: ' . $element->{Wert} . ' an Gruppenadresse ' . $element->{ga} . ' gesendet');
                next;
            }   
    next;
    }
}else{
 return;
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

# wenn die Wochennummer gr??er als 52 ist
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
# wenn die Wochennummer grösser als 52 ist
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