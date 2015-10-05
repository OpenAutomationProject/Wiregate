#############################################################################
# Plugin: DebugAboGA
# V1.0 2015-10-05
# Copyright: Christian Mayer (mail at ChristianMayer.de)
# License: GPL (v3)
#
# Debug Skript um alle Abonierten GAs und deren Plugins im Plugin Log zu 
# zeigen.

$plugin_info{$plugname.'_cycle'} = 0;
my $ret_val = '';

foreach my $GA (sort keys %plugin_subscribe) {
  foreach my $plugin (sort keys %{$plugin_subscribe{$GA}} ) {
    $ret_val .= 'DebugAboGA ' . $GA . ': "' . $plugin . '" = ' . $plugin_subscribe{$GA}{$plugin} . "\n";
  }
}

return $ret_val;