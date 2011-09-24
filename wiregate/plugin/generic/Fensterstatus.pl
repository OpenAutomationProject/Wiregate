# Plugin zum Erfassen des Gesamt-Fenster-Status
# Version 0.3 / 24.09.2011
# Copyright: JNK (http://knx-user-forum.de/members/jnk.html)
# License: GPL (v2)
#

####################
###Einstellungen:###
####################

my @Fenster_GA = ('7/7/7', '7/7/8'); # hier alle Fenster-Einzel-GA
my $Sammel_GA = '7/7/9'; # hier die Sammel-GA
my $zustand_geschlossen = 01;    # auf richtige polarität achten!
my $zustand_offen = 00;

######################
##ENDE Einstellungen##
######################

#
# Flossen weg, der Rest geht automatisch
#
$plugin_info{$plugname.'_cycle'} = 0; # nur bei Telegramm aufrufen

if (($msg{'apci'} eq 'A_GroupValue_Write') && (grep {$_ eq $msg{'dst'};} @Fenster_GA)) {
    # Telegramm auf einer Einzel-GA erhalten
    my $status = $zustand_geschlossen; # mit geschlossen anfangen
    my $old_status = $plugin_info{$plugname.'_oldstatus'};
    foreach my $GA (@Fenster_GA) {
        if (knx_read($GA, 0, 1) == $zustand_offen) { # da war eine 'offen', also Status auf 1 setzen
            $status = $zustand_offen;
            last;
        }
    }
    if ($old_status != $status){ #
        knx_write($Sammel_GA, $status, 1); # Status hat sich geaendert, senden
        $plugin_info{$plugname.'_oldstatus'} = $status; # neuen Status speichern
	    return 'Sent Value'.$status;
    } 
    return 0; # nichts gesendet, Also
}

# keine Telegramme, also Init

foreach my $GA (@Fenster_GA) {  # an allen Fenster-Einzel-GA anmelden
    $plugin_subscribe{$GA}{$plugname} = 1; 
}
# bis zum Beweis des Gegenteils sind alle Fenster zu
$plugin_info{$plugname.'_oldstatus'} = $zustand_geschlossen;

return 'Init';