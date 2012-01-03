# Plugin zum loeschen *ALLER* Eintraege in $plugin_info
# fuer die kein Plugin mehr existiert.
# Vorraussetzung: die Benutzung *MUSS* konsequent wie empfohlen mit
# $plugin_info{$plugname.'_XYZ'} erfolgen.
# Es werden alle Eintraege geloescht, die nicht mit einem (noch) vorhandenen
# Plugin-Namen beginnen.
# *** ERST MIT $delete=0 prüfen ! ***

##################
### DEFINITION ###
##################

my $delete = 0; # Auf 1 setzen zum loeschen, sonst nur Ausgabe ins Plugin-Log
$plugin_info{$plugname.'_cycle'} = 86400;

#######################
### ENDE DEFINITION ###
#######################

my @plugin_basenames;
my $ret;

foreach (@plugins) {
    next if ($_ =~ /\~$/ or -d $_); # ignore backup-files and subdirectories
    push(@plugin_basenames, basename($_));
}

#Special Prefixes
push(@plugin_basenames, 'Global_');

while( my ($key, $value) = each(%plugin_info) ) {
    my (@prefix) = split '_',$key;
    if (! grep (/^\Q$prefix[0]\E.*/, @plugin_basenames)) {
        if ($delete) {
            delete $plugin_info{$key};
            $ret .= " *DELETED*: " . $key;
        } else {
            $ret .= " *WOULD delete*: " . $key;
        }
    }
}

return $ret;

