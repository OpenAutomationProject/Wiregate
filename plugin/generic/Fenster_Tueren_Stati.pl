# Tueroeffnungen kontrollieren
# 2012-11-04
# JuMi2006 -> http://knx-user-forum.de
# Pro Tuer: geschlossen = 1 , offen = 0
# Gesamtstatus: alles zu = 1   noch mindestens eine Tuer offen = 0
# $send_ga ist der Gesamtstatus
# Die GAs sollten sauber in die eibga.conf eingepflegt sein 
# bzw. aus der ETS importiert werden

$plugin_info{$plugname.'_cycle'} = 300;
my (@doors,$closed,@opened,$status);	# Variablen initialisieren

### KONFIGURATION ###

# Jede Zeile eine Tuer
push @doors, { name => "Tuer 1", 	ga => "1/2/10"};
push @doors, { name => "Tuer 2", 	ga => "1/2/20"};
push @doors, { name => "Tuer 3", 	ga => "1/2/40"};
push @doors, { name => "Tuer 4", 	ga => "1/2/50"};
push @doors, { name => "Tor 1", 	ga => "1/2/60"};
push @doors, { name => "Tor 2", 	ga => "1/2/35"};

my $send_ga = '0/0/112'; #An diese GA wird der Gesamtstaus gesendet.

### KONFIGURATION ENDE ###

my $elements = @doors;

foreach my $door (@doors) {
$plugin_subscribe{$door->{ga}}{$plugname} = 1;
$status = knx_read($door->{ga},0,1);
$closed += $status;
if ($status == 0)
	{
	push @opened, ($door->{name});
	}
}

if ($closed == $elements)
{
    knx_write($send_ga,1,1);
    return "Alle Tueren/Tore geschlossen!";
}
else
{
my $open = $elements - $closed;
knx_write($send_ga,0,1);
my $open_doors = join(" ",@opened);
return "$open TŸren/Tore offen: $open_doors";
}