#!/usr/bin/perl -w
##################
# Logikprozessor AddOn: create RSS Log via HTTP::Request
##################
#
# COMPILE_PLUGIN
#
# benoetigt einen Konfigurationseintrag in Logikprozessor.conf:
# %settings=(
#  nma => {
#    apikey => "YOUR_API_KEY",
#	 application => 'SmartHome Logikprozessor',
#	 targetUrl => 'https://URL_TO_YOUR_VISU/cometvisu',
#    url => 'http://www.notifymyandroid.com/publicapi/notify'
#  }
# );
# 
# weitere Erklaerungen: http://knx-user-forum.de/code-schnipsel/19912-neues-plugin-logikprozessor-pl-36.html#post384076
#

sub sendNma {
    my (%parameters)=@_;
    my ($priority, $event, $description, $application, $url, $apikey, $targetUrl);

    my $settings=$plugin_cache{"Logikprozessor.pl"}{settings};
	
    # Parameter ermitteln
    # dom, 2012-11-05: $settings auch hier auswerten. Damit kann addRssLog() direkt aus der Logik aufgerufen werden!
	$priority = $parameters{priority} || $settings->{nma}{priority} || 0;
    $event = $parameters{event} || $settings->{nma}{event} || '[unbenanntes Ereignis]';
    $description = $parameters{description} || $settings->{nma}{description} || '';
    $application = $parameters{application} || $settings->{nma}{application} || 'WireGate KNX';
    $targetUrl = $parameters{targetUrl} || $settings->{nma}{targetUrl} || '';
	$url = $parameters{url} || $settings->{nma}{url} || '';
    $apikey = $parameters{apikey} || $settings->{nma}{apikey} || '';
    
    use LWP::UserAgent;
    use URI::Escape;
    use Encode;

	# HTTP Request aufsetzen
	my ($userAgent, $request, $response, $requestURL);
	$userAgent = LWP::UserAgent->new;
	$userAgent->agent("WireGatePlugin/1.0");

	$requestURL = sprintf($url."?apikey=%s&priority=%s&event=%s&description=%s&application=%s&url=%s",
		uri_escape($apikey),
		uri_escape($priority),
		uri_escape(encode("utf8", $event)),
		uri_escape(encode("utf8", $description)),
		uri_escape(encode("utf8", $application)),
		uri_escape($targetUrl));

	$request = HTTP::Request->new(GET => $requestURL);
	#$request->timeout(5);

	$response = $userAgent->request($request);
        if ($response->is_success) {
   	    plugin_log($plugname, "NMA-Nachricht erfolgreich abgesetzt: $priority, $event, $description, $application") if $parameters{debug};
        } elsif ($response->code == 401) {
   	    plugin_log($plugname, "NMA-Nachricht nicht abgesetzt: API key gültig?");
        } else {
   	    plugin_log($plugname, "NMA-Nachricht ($requestURL) nicht abgesetzt: " . $response->content);
        }

    return undef;
}

