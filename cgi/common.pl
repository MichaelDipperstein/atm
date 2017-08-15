#!/usr/bin/perl
# $Id: common.pl,v 1.1 1998/05/06 19:25:57 kogorman Exp $

##++
##  This "mini" library contains the parse_form_data and
##  return_error subroutines. 
##
##  The following applies _only_ if you picked up the Examples.tar
##  before June 20th:
##
##  Some of the examples described in the book (and in Examples.tar 
##  on the ORA FTP site), I stated that you needed to use these 
##  subroutines, but I didn't explicitly cover how to do this.
##
##  There are two ways to do so:
##
##     1. You can cut and paste these subroutines directly into
##        the program.
##
##     2. You can leave this file as is, and then insert the
##        following line at the top of your program:
##
##        require "common.pl";
##
##  Shishir Gundavaram
##  June 20, 1996
##--

sub parse_form_data
{
    local (*FORM_DATA) = @_;

    local ($request_method, $query_string, @key_value_pairs,
           $key_value, $key, $value);

    $request_method = $ENV{'REQUEST_METHOD'};

    if ($request_method eq "GET") {
        $query_string = $ENV{'QUERY_STRING'};
    } elsif ($request_method eq "POST") {
        read (STDIN, $query_string, $ENV{'CONTENT_LENGTH'});
    } else {
        &return_error (500, "Server Error",
                       "Server uses unsupported method");
    }

    @key_value_pairs = split (/&/, $query_string);

    foreach $key_value (@key_value_pairs) {
        ($key, $value) = split (/=/, $key_value);
        $value =~ tr/+/ /;
        $value =~ s/%([\dA-Fa-f][\dA-Fa-f])/pack ("C", hex ($1))/eg;

        if (defined($FORM_DATA{$key})) {
            $FORM_DATA{$key} = join ("\0", $FORM_DATA{$key}, $value);
        } else {
            $FORM_DATA{$key} = $value;
        }
    }
}

sub return_error
{
    local ($status, $keyword, $message) = @_;

    print "Content-type: text/html", "\n";
    print "Status: ", $status, " ", $keyword, "\n\n";

    print <<End_of_Error;

<title>CGI Program - Unexpected Error</title>
<h1>$keyword</h1>
<hr>$message</hr>
Please contact $webmaster for more information.

End_of_Error

    exit(1);
}

1;

