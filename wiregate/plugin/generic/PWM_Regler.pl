###PWM-Regler
#v0.2 2012-08-21
#JuMi2006 - > http://knx-user-forum.de

### MAIN ### 
# Variablen definieren

my $base_time = 15 ; 		#in Minuten
my $regler_ga = "0/0/0"; 	#Stellwert vom Regler -> Achtung in Zeile 19 "DPT" durch den richtigen DPT ersetzen
my $send_ga = "0/0/0";		#GA vom Schaltaktor


### MAIN / VERARBEITUNG
### PWM ###

$plugin_subscribe{$regler_ga}{$plugname} = 1;
$plugin_info{$plugname.'_cycle'} = 60;
my $time = time();
my $on_perc = knx_read($regler_ga,DPT); #hier wird der Stellwert in % gelesen;

my $on_time = (($base_time/100)*$on_perc);
my $off_time = ($base_time - $on_time);
    
$on_time *= 60;     #Minuten in Sekunden umrechnen
$off_time *= 60;    #Minuten in Sekunden umrechnen


if ($plugin_info{$plugname.'_state'} eq 'pwm-off')                #status = aus
{
    if  (($plugin_info{$plugname.'_stat-time'} + $off_time) <= $time) #zyklus aus ist vorbei
    {
    #ANSCHALTEN
    knx_write($send_ga,1,1.001);
    #STATUS = EIN setzen
    $plugin_info{$plugname.'_state'} = 'pwm-on';
    #ANZEIT = jetzt
    $plugin_info{$plugname.'_stat-time'} = $time;
    } else {
	#Senden wiederholen#
	#knx_write($send_ga,0,1.001);
	}
} else {}


if ($plugin_info{$plugname.'_state'} eq 'pwm-on')                #status = an
{
    if  (($plugin_info{$plugname.'_stat-time'} + $on_time) <= $time) #zyklus an ist vorbei
    {
    #AUSCHALTEN
    knx_write($send_ga,0,1.001);
    #STATUS = AUS setzen
    $plugin_info{$plugname.'_state'} = 'pwm-off';
    #AUSZEIT = JETZT
    $plugin_info{$plugname.'_stat-time'} = $time; 
    } else {
	#Senden wiederholen#
	#knx_write($send_ga,1,1.001);
	}
} else {}

if (($plugin_info{$plugname.'_stat-time'} + $on_time + $off_time) <= $time)	#initialisierung
{
    #ANSCHALTEN
    knx_write($send_ga,1,1.001);
    #STATUS = EIN setzen
    $plugin_info{$plugname.'_state'} = 'pwm-on';
    #ANZEIT = jetzt
    $plugin_info{$plugname.'_stat-time'} = $time;
    plugin_log($plugname, "INITIALISIERUNG nach Abwesenheit");
} else {}
