#!/usr/bin/perl
BEGIN {require "manager.pl";};

$nextid = 0;
@activeids = ();
%locktable = ();
%cache = ();

###########################################################################
#test code
###########################################################################

openshm;
print "values retreived:\n", &dumpshmemvars;
closeshm;
