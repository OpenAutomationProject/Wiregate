#!/usr/bin/perl -w
##################
# Logikprozessor AddOn: create RSS Log via HTTP::Request
##################
#
# COMPILE_PLUGIN

sub addRssLogViaHttpRequest {
    my (%parameters)=@_;
    my ($title, $content, $tags, $url);

	my $settings=$plugin_cache{"Logikprozessor.pl"}{settings};
	
    # Parameter ermitteln
    # dom, 2012-11-05: $settings auch hier auswerten. Damit kann addRssLog() direkt aus der Logik aufgerufen werden!
    $title = $parameters{title} || $settings->{rssLog}{title} || '';
    $content = $parameters{content} || $settings->{rssLog}{content} || '';
    $tags = $parameters{tags} || $settings->{rssLog}{tags} || '';
    $url = $parameters{url} || $settings->{rssLog}{url} || '';
    
    use LWP::UserAgent;
    use URI::Escape;
    use Encode;

	# HTTP Request aufsetzen
	my ($userAgent, $request, $response, $requestURL);
	$userAgent = LWP::UserAgent->new;
	$userAgent->agent("WireGatePlugin/1.0");

	$requestURL = sprintf($url."?t=%s&c=%s&tags=%s",
		uri_escape(encode("utf8", $title)),
		uri_escape(encode("utf8", $content)),
		uri_escape(encode("utf8", $tags)));

	$request = HTTP::Request->new(GET => $requestURL);
	#$request->timeout(5);

	$response = $userAgent->request($request);

	if ($response->is_success) {
		plugin_log($plugname, "RSSLog erfolgreich abgesetzt: $title, $content, $tags, $url") if $parameters{debug};
	} else {
		plugin_log($plugname, "RSSLog ($requestURL) nicht abgesetzt: " . $response->content);
	}

    return undef;
}
