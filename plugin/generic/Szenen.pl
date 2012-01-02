# Beta-Version
#
#
# Plugin für Szenen
# ga1 = GA
# wert = Wert der auf die GA gesendet werden soll (DPT ist durch import der GAs aus der ETS festzulegen
# Aufbau moeglichst so, dass man unterhalb der Definitionen nichts aendern muss!


my $trigger_ga = '8/2/0';  # triggert die Szene mit einer 1 (DPT 1)
$plugin_subscribe{$trigger_ga}{$plugname} = 1;

my @GAs;
push @GAs, { name => "Wohnzimmer TV", ga1 => "1/1/35", wert => 1 };
push @GAs, { name => "Wohnzimmer Kamin", ga1 => "1/1/11", wert => 0 };
push @GAs, { name => "Wohnzimmer Tür", ga1 => "1/1/2", wert => 0 };
push @GAs, { name => "Wohnzimmer Mitte", ga1 => "1/1/38", wert => 0 };
push @GAs, { name => "Wohnzimmer Fenster", ga1 => "1/1/34" , wert => 0 };

#push @GAs, { name => "Wohnzimmer TV dimmen", ga1 => "1/1/37" , wert => 50};


if ($msg{'apci'} eq "A_GroupValue_Write" && $msg{'dst'} eq $trigger_ga && defined $msg{'value'} && $msg{'value'} == "1" ) {

	foreach my $element (@GAs) {
		knx_write($element->{ga1}, $element->{wert}, 1.001);	
	}
}