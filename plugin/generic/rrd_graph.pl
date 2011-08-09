# Demo-Plugin Grafiken in RRD speichern

# Eigenen Aufruf-Zyklus auf 300 Sekunden (Default globales RRD-Intervall) setzen
$plugin_info{$plugname.'_cycle'} = $wg_config{''}{'rrd_interval'};

update_rrd("WZ_temp","",knx_read("3/1/36",0,9));
update_rrd("Kueche_temp","",knx_read("3/1/46",0,9));
update_rrd("Schlafen_temp","",knx_read("3/2/56",0,9));
update_rrd("Ankleide_temp","",knx_read("3/2/66",0,9));
update_rrd("Zisterne","",knx_read("5/5/101",0,9));

update_rrd("S300TH_temp","",knx_read("14/4/6",0,9));
update_rrd("S300TH_hum","",knx_read("14/4/7",0,5));


return;
# PI-Regler
update_rrd("WC-Stell_HS","",knx_read("3/1/55",0,5));
update_rrd("WC-Stell_PI-Plugin","",knx_read("14/5/53",0,5));
update_rrd("SZ-Stell_PI-Plugin","",knx_read("14/5/63",0,5));
update_rrd("SZ-Stell_HS","",knx_read("3/2/55",0,5));

# Luftfeuchte Bad

# Einen Wert der Luftfeuchte von der Gruppenadresse 5/2/79 in einem rrd speichern
# Luftfeuchte_Bad_knx5-2-79 ist ein beliebiger Text; keine Umlaute oder Sonderzeichen (/\: etc)
# und einmalig!
# Dann wird die Funktion knx_read mit der Gruppenadresse aufgerufen, diese liefert 
# jedoch nur den rohen "Byte-Wert" vom Bus bzw. aus dem cache (max. Alter 300s, 
# sonst wird ein Lesetelegramm abgesetzt und die Antwort abgewartet)
# Dieser Bytewert (0-255) wird dann von der Funktion decode_dpt5 in 0-100(%) 
# umgewandelt.
update_rrd("Luftfeuchte_Bad_knx5-2-79","",knx_read("5/2/79",300,9));

# Luftfeuchte Duschbad: Man kann genauso schreiben:
my $wert = knx_read("5/2/19",300,9);
update_rrd("Luftfeuchte_Duschbad_knx5-2-19","",$wert);

# Beispiel fuer Temperaturwert (DPT9/EIS5)
update_rrd("Temp_Kueche_knx3-1-46","",knx_read("3/1/46",300,9));

# Abgerufen koennen die Grafiken durch Modifikation der Grafik-URL eines vorhandenen 
# 1-Wire Sensors werden: z.B. 28.0D22CB010000_temp.rrd im letzten Beispiel durch
# Temp_Kueche_knx3-1-46.rrd ersetzen. Gross/Kleinschreibung beachten!


#     DPT 1 (1 bit) = EIS 1/7 (move=DPT 1.8, step=DPT 1.7)
#     DPT 2 (1 bit controlled) = EIS 8 
#     DPT 3 (3 bit controlled) = EIS 2 
#     DPT 4 (Character) = EIS 13
#     DPT 5 (8 bit unsigned value) = EIS 6 (DPT 5.1) oder EIS 14.001 (DPT 5.10)
#     DPT 6 (8 bit signed value) = EIS 14.000
#     DPT 7 (2 byte unsigned value) = EIS 10.000
#     DPT 8 (2 byte signed value) = EIS 10.001
#     DPT 9 (2 byte float value) = EIS 5
#     DPT 10 (Time) = EIS 3
#     DPT 11 (Date) = EIS 4
#     DPT 12 (4 byte unsigned value) = EIS 11.000
#     DPT 13 (4 byte signed value) = EIS 11.001
#     DPT 14 (4 byte float value) = EIS 9
#     DPT 15 (Entrance access) = EIS 12
#     DPT 16 (Character string) = EIS 15

#return "RRDs wurden aktualisiert";
return 0;
