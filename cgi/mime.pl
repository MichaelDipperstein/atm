#!/usr/bin/perl
# $Id: mime.pl,v 1.3 1998/06/06 02:26:57 kogorman Exp $

sub MIME_header {
	local ($mime_type, $title_string, $header) = @_;

	if (!$header) { $header = $title_string; }

	print "Content-type: $mime_type\n\n";
	print "<HTML>\n";
	print "<HEAD><TITLE>$title_string</TITLE></HEAD>\n";
	print "<BODY>\n";
	print "<H2>$header -- ",scalar(localtime()),"</H2>\n";
}
1;
