######################
# Garbage Collection #
######################
# Wiregate-Plugin
# (c) 2012 Fry under the GNU Public License

# $plugin_info{$plugname.'_cycle'}=0; return 'deaktiviert';

my $retval='';
chdir "/etc/wiregate/plugin/generic";

# Cleanup plugin_subscribe
my @plugins=<*.pl>; 
my $valid=join "|", map quotemeta, @plugins;
for my $ga (keys %plugin_subscribe)
{
   my @delme=grep !/^($valid)/, keys %{$plugin_subscribe{$ga}};
   for my $v (@delme)
   {
      delete $plugin_subscribe{$ga}{$v};
      $retval.=$ga.'->'.$v.', ';
   }
}

# Cleanup plugin_info
push @plugins, "conf.d";
my $valid=join "|", map quotemeta, @plugins;
my @delme=grep !/^($valid)/, keys %plugin_info;
for my $v (@delme)
{
    delete $plugin_info{$v};
    $retval.=$v.', ';
}

$plugin_info{$plugname.'_cycle'}=1000;

return $retval ? ('Geloescht: '.$retval) : undef;

