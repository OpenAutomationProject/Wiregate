### Plugin zum erstellen von RSS-logs
# Fuer Verwendung mit rsslog.php / CometVisu
# man koennte natuerlich ebenso das rsslog.php direkt mit LWP::Useragent oder
# wget aufrufen, hier soll aber auch die Verwendung von SQLite Datenbanken 
# demonstriert werden.
# Wichtig:
# - benoetigt Paket libdbd-sqlite2-perl
# - weil in PHP nur sqlite2 verfuegbar
# 
# v0.1
# 2012-01-08

###################
### DEFINITION  ###
###################

$plugin_info{$plugname . '_cycle'} = 0; # Aufrufzyklus - never

my @actionGA;
# Datenpunkttypen MUESSEN in der globalen config angegeben sein!
# Logeintrag bei bestimmtem Wert
push @actionGA, { title => "Eintrag1 ohne Wert", content => 'Textinhalt1', tags => "tag1,tag3", trigger_ga => "1/1/11", value => 1 };
# Logeintrag beliebigem Wert: value weglassen 
# %s wird mit sprintf durch den Wert ersetzt, anderes wie %.2f geht auch in content oder title!
# man printf ;)
push @actionGA, { title => "Eintrag2 mit Wert unabhaengig vom Wert %.2f", content => 'Textinhalt %s', tags => "tag4", trigger_ga => "1/1/11"};

# Nun einge Beispiele aus der Praxis:
push @actionGA, { title => "Haustuere", content => 'Haustuere auf', tags => "security,sensoren", trigger_ga => "5/1/10", value => 1};
push @actionGA, { title => "Haustuere", content => 'Haustuere zu', tags => "security,sensoren", trigger_ga => "5/1/10", value => 0};
push @actionGA, { title => "Garagentor", content => 'Garagentor %d (0=zu, 1=auf)', tags => "security,sensoren", trigger_ga => "5/4/103"};
push @actionGA, { content => 'Trittmatte', tags => "security,sensoren", trigger_ga => "5/1/11", value => 1};
push @actionGA, { content => 'Bluetooth Zutritt', tags => "security,sensoren", trigger_ga => "5/1/12", value => 1};
# title & tags darf auch leer sein

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
    foreach my $element (@actionGA) {
        if ($msg{'dst'} eq "$element->{trigger_ga}") {
            if (defined $element->{value}) { # skip if value is defined and not what we like
                next unless "$msg{'value'}" eq "$element->{value}"; }

            my $dbargs = {AutoCommit => 0, PrintError => 1};
            my $dbh = DBI->connect("dbi:SQLite2:dbname=$logdb", "", "", $dbargs);

            $dbh->do('INSERT INTO Logs(content, title, tags, t) VALUES( ' .
                   "  '" . sprintf($element->{content},$msg{'value'}) . "'," .
                   "  '" . sprintf($element->{title},$msg{'value'}) . "'," .
                   "  '" . $element->{tags} . "'," .
                   "  datetime('now') );");

            if ($dbh->err()) { return "DB-Fehler: $DBI::errstr\n"; }
            $dbh->commit();
            $dbh->disconnect();
            return; # "V: " . $dbh->{sqlite_version};
        }
    }
} else { # zyklischer Aufruf/initialisierung
    #subscribe GAs
    foreach my $element (@actionGA) {
        $plugin_subscribe{$element->{trigger_ga}}{$plugname} = 1;
    }
}
return; # "Noop";

