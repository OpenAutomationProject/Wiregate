#Plugin zum Quittieren aller unquittierten Meldungen im rss-log
#http://knx-user-forum.de/cometvisu/23692-wg-plugin-quittierung-fuer-rsslog.html
#
#benötigt rsslog-plugin: http://openautomation.svn.sourceforge.net/viewvc/openautomation/wiregate/plugin/generic/RSSlog.pl
#erstellt unter Verwendung des rss-log Plugins von makki http://knx-user-forum.de/members/makki.html
#Copyright: ZeitlerW http://knx-user-forum.de/members/zeitlerw.html
#License: GPL (v2)

###################
### DEFINITION  ###
###################

$plugin_info{$plugname . '_cycle'} = 0; # Aufrufzyklus - never

###Quittungs - GA ####
my $ack_ga="15/0/2";

########################
### Ende DEFINITION  ###
########################

use DBI;
my $logdb = '/etc/wiregate/rss/rsslog.db';

# check setup, rights, DB
if (! -d dirname($logdb)) {
    mkdir(dirname($logdb),0777);
}
if (! -e $logdb) {
    return "$logdb existiert nicht! Bitte mit rsslog.php anlegen"; # FIXME: create sqlite-db
}

if ($msg{'apci'} eq "A_GroupValue_Write") { # Telegramm eingetroffen
        if ($msg{'dst'} eq $ack_ga) {
            return if $msg{'value'} == 0;
            plugin_log($plugname, $msg{'value'});
            my $dbargs = {AutoCommit => 0, PrintError => 1};
            my $dbh = DBI->connect("dbi:SQLite2:dbname=$logdb", "", "", $dbargs);

            $dbh->do('UPDATE Logs set state=1 where state=0;');

            if ($dbh->err()) { return "DB-Fehler: $DBI::errstr\n"; }
            $dbh->commit();
            $dbh->disconnect();
            knx_write($ack_ga,0,1);
            return; # "V: " . $dbh->{sqlite_version};
        }
} else { # zyklischer Aufruf/initialisierung
    #subscribe GAs
        $plugin_subscribe{$ack_ga}{$plugname} = 1;
}
return; # "Noop";

