#!/usr/bin/perl
use manager;

$nextid = 0;
@activeids = ();
%cache = ();
%locktable = ();

$dump = &dumpshmemvars;
print "$dump\n";

print "Started Transaction: ", &newtxn, "\n";
print "Started Transaction: ", &newtxn, "\n";
print "Started Transaction: ", &newtxn, "\n";

print "Transaction 0 in position: ", &isactive (0), "\n";
print "Transaction 1 in position: ", &isactive (1), "\n";
print "Transaction 2 in position: ", &isactive (2), "\n";
print "Transaction 3 in position: ", &isactive (3), "\n";

print "\nResulting shared memory vars\n";
$dump = &dumpshmemvars;
print $dump;

buildshmemvars $dump;
print "Transaction 0 in position: ", &isactive (0), "\n";
print "Transaction 1 in position: ", &isactive (1), "\n";
print "Transaction 2 in position: ", &isactive (2), "\n";
print "Transaction 3 in position: ", &isactive (3), "\n";

print "\nIncrement transaction 1 step to: ", &nextstep (1), "\n";
print "\nDeactivating 0\n";

deactivate 0;

$dump = &dumpshmemvars;
print $dump;

