#################
# Subscriptions #
#################
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License version 2 or later

# $plugin_info{$plugname.'_cycle'}=0; return "Subscriptions deaktiviert.";

my %eibshort;

for my $ga (keys %eibgaconf)
{
    next unless $eibgaconf{$ga}{name}=~/^(\S+)/;
    my $short=$1;
    $eibshort{$short}=$eibgaconf{$ga};
    $eibshort{$short}{ga}=$ga;
    $eibshort{$ga}=$short;
}

my %plugins=();

delete $plugin_subscribe{''}; # delete stale subscriptions

for my $ga (keys %plugin_subscribe)
{
    my $sh=$ga;
    $sh=$eibshort{$ga} if defined $eibshort{$ga};

    for my $pl (keys %{$plugin_subscribe{$ga}})
    {
	$plugins{$pl}{$sh}=1 if $plugin_subscribe{$ga}{$pl};
    }
}

my @changedplugins=();

for my $pl (keys %plugins)
{
    my $pluglist=join(',', sort grep { $plugins{$pl}{$_} } keys %{$plugins{$pl}});
	
    $pluglist.=" => $pl";

    unless($plugin_info{$plugname.'_'.$pl} eq $pluglist)
    {
	$plugin_info{$plugname.'_'.$pl} = $pluglist;
	push @changedplugins, $pl;
    }
}

my $retval="(".(join ") (", map { $plugin_info{$plugname."_".$_} } @changedplugins).")";

$plugin_info{$plugname.'_cycle'}=10;

return if $retval eq '()';

return $retval;

