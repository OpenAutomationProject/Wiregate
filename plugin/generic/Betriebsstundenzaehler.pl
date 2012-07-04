###Betriebsstundenzaehler###

# $reset = 1 -> Der Zaehler wird auf den den Startwert $reset_value gesetzt.
# Dazu einmal Speichern und danach $reset wieder auf 0 setzen und speichern.
# 
# Das Plugin zeichnet die Betriebsdauer der $ga auf und kann mit zyklischem senden
# der Quelladresse umgehen. 0 = Aus und 1 = An
# 
# Version: 0.1 (2012-07-04)
# Lizenz: GPL
# Autor: JuMi2006 (http://knx-user-forum.de)


###Konfiguration###
$plugin_info{$plugname.'_cycle'} = 84600;
my $ga = '1/1/10';
my $reset = '0';
my $reset_value = '1234';

###Ende Konfiguration###


### Ab hier keine Aenderungen mehr ###

my $time = time();
my $diff;
$plugin_subscribe{$ga}{$plugname} = 1;

### Reset
if ($reset == 1)
{
$plugin_info{$plugname.'_bstunden'} = $reset_value;
$plugin_info{$plugname.'_last-on'} = '0';
$plugin_info{$plugname.'_status'} = '0';
}

else
{

### Bei 1 und vorheriger Status = 1
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $ga && $msg{'value'} == '1' && $plugin_info{$plugname.'_status'} == '1' )
{
if ($plugin_info{$plugname.'_last-on'} <= '0')
{
$diff = '0';
}
else
{
$diff = ($time - $plugin_info{$plugname.'_last-on'});
}
$plugin_info{$plugname.'_neustunden'} = ($plugin_info{$plugname.'_bstunden'} + $diff);
$plugin_info{$plugname.'_bstunden'} = $plugin_info{$plugname.'_neustunden'};
$plugin_info{$plugname.'_last-on'} = $time;
$plugin_info{$plugname.'_status'} = '1';
}
else
{}

### Bei 1 und vorheriger Status = 0
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $ga && $msg{'value'} == '1' && $plugin_info{$plugname.'_status'} == '0' )
{
$diff = '0';
$plugin_info{$plugname.'_neustunden'} = ($plugin_info{$plugname.'_bstunden'} + $diff);
$plugin_info{$plugname.'_bstunden'} = $plugin_info{$plugname.'_neustunden'};
$plugin_info{$plugname.'_last-on'} = $time;
$plugin_info{$plugname.'_status'} = '1';
}
else
{}

### Bei 0 und vorheriger Status = 1
if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $ga && $msg{'value'} == '0' && $plugin_info{$plugname.'_status'} == '1') 
{
my $diff = ($time - $plugin_info{$plugname.'_last-on'});
$plugin_info{$plugname.'_neustunden'} = ($plugin_info{$plugname.'_bstunden'} + $diff);
$plugin_info{$plugname.'_bstunden'} = $plugin_info{$plugname.'_neustunden'};
$plugin_info{$plugname.'_status'} = '0';
}
}

### Ausgabe
my $sec = int($plugin_info{$plugname.'_bstunden'});
my $m = int $sec / 60;
my $s = $sec - ($m * 60);
my $h = int $m / 60;
$m = $m - ($h * 60);

return "$h:$m:$s";