#!/usr/bin/perl
BEGIN {require "manager.pl";};

$nextid = 0;
@activeids = ();
%locktable = ();
%cache = ();

###########################################################################
#test code
###########################################################################
#initialize shared memory variables

#test shared memory

writeshm &dumpshmemvars;
