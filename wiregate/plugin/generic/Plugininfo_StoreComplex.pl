# Beispielplugin um komplexe Datenstrukturen in $plugin_info abzulegen
# V0.1

use Storable;

$plugin_info{$plugname."_cycle"} = 86400;

my %localhash = ( 'test' => 'value1', 
		'counter' => $plugin_info{$plugname."_ticks"} );

store \%localhash, $plugin_info{$plugname."_complex"};

return "stored hash in plugin_info";

# zum laden sowas wie:
#use Storable;
#my %loadedhash = %{retrieve $plugin_info{'PluginInfo_StoreComplex.pl_complex'}};
#return $loadedhash{'counter'};

