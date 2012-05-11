# Einfaches Plugin zum debuggen aller aktiven Plugin-subscriptions
# just zur Doku

$plugin_info{$plugname.'_cycle'} = 3600;
my $ret;

for my $k ( sort keys %plugin_subscribe ) {
	for my $p ( keys %{$plugin_subscribe{ $k }} ) {
    $ret .= "Plugin $p subscribed to $k\n";
  }
}

for my $k ( sort keys %plugin_socket_subscribe ) {
    $ret .= "Plugin $plugin_socket_subscribe{$k} subscribed to socket $k\n";
}

#return; # no debug out
return $ret;

