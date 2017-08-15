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
openshm;
print &dumpshmemvars;

$txn = newtxn;
print "Opening transaction: $txn\n";

print "\nWriting to cache:\n";
print "Current Step:", &currentstep ($txn), "\n";
cachewrite ($txn, '2-2', "");
print "Inserted at index: ", &cacheindex ($txn, '2-2') - 1, "\n";

nextstep $txn;
print "Current Step:", &currentstep ($txn), "\n";
cachewrite ($txn, '3-2', "");
print "Inserted at index: ", &cacheindex ($txn, '3-2') - 1, "\n";

nextstep $txn;
print "Current Step:", &currentstep ($txn), "\n";
cachewrite ($txn, '3-3', 123);
print "Inserted at index: ", &cacheindex ($txn, '3-3') - 1, "\n";

print "\nResulting data:\n";
print &dumpshmemvars;
closeshm;
