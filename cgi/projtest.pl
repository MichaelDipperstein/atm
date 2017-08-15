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
$shmemstring = dumpshmemvars;
buildshmemvars $shmemstring;

#Make txn active
$currenttxn = newtxn;
print "ID for new transaction is: $currenttxn \n";

print "\nGetting locks for txn $currenttxn\n";
@locks = acquirelocks ($currenttxn, '0-0:Write', '1-1:Read');
if (@locks == ())
{
    print "Resulting locktable:\n", &dumplocks, "\n";
}
else
{
    perror "Failed to acquire locks: @locks\n";
}

#Make txn another active
$currenttxn = newtxn;
print "ID for new transaction is: $currenttxn\n";

#Try to acquire existing locks
print "\nGetting exitsing locks for txn $currenttxn\n";
@locks = acquirelocks ($currenttxn, '0-0:Write', '1-1:Read');
if (@locks == ())
{
    perror "Illegal lock acquisition.";
}
else
{
    print "Failed to acquire locks: @locks\n";
}

#try to share a read lock
print "\nSharing a read lock.\n";
@locks = acquirelocks ($currenttxn, '1-1:Read');
if (@locks == ())
{
    print "Resulting locktable:\n", &dumplocks, "\n";
}
else
{
    perror "Failed to acquire locks: @locks\n";
}

print "\nGetting new locks for txn $currenttxn\n";
@locks = acquirelocks ($currenttxn, '2-2:Write', '3-3:Read');
if (@locks == ())
{
    print "Resulting locktable:\n", &dumplocks, "\n";
}
else
{
    perror "Failed to acquire locks: @locks\n";
}

#Verify duplicate entries aren't made for existing lock
print "\nAcquiring two existing locks and one new lock.\n";
@locks = acquirelocks ($currenttxn, '2-2:Write', '0-1:Read', '3-3:Read');
if (@locks == ())
{
    print "Resulting locktable:\n", &dumplocks, "\n";
}
else
{
    perror "Failed to acquire locks: @locks\n";
}

#Verify read of object is okay when txn holds write lock
printf "\nRequesting read of item while holding write lock.\n";
@locks = acquirelocks ($currenttxn, '2-2:Read');
if (@locks == ())
{
    print "Resulting locktable:\n", &dumplocks, "\n";
}
else
{
    perror "Failed to acquire locks: @locks\n";
}

printf "\nRequesting read of item while other txn holds write lock.\n";
@locks = acquirelocks ($currenttxn, '0-0:Read');
if (@locks == ())
{
    perror "Illegal lock acquisition";
}
else
{
    print "Failed to acquire locks: @locks\n";
}

#outdated lock test
$currenttxn = newtxn;
print "ID for new transaction is: $currenttxn\n";
print "\nInserting bogus old locks for txn $currenttxn\n";
push @{$locktable{'4-0'}{Write}}, [$currenttxn, 1234567];
push @{$locktable{'4-1'}{Write}}, [$currenttxn, 1234567];
push @{$locktable{'4-1'}{Read}}, [$currenttxn, 1234567];
push @{$locktable{'4-2'}{Read}}, [$currenttxn, 1234567];
print "New table:\n", &dumplocks;

#Acquire newer sharing read lock
print "\nSharing with timedout lock.\n";
@locks = acquirelocks (1, '4-2:Read');
if (@locks == ())
{
    print "Resulting locktable:\n", &dumplocks, "\n";
}
else
{
    perror "Failed to acquire locks: @locks\n";
}

#Acquire wounding
print "\nWounding timedout lock.\n";
@locks = acquirelocks (1, '4-1:Read');
if (@locks == ())
{
    print "Resulting locktable:\n", &dumplocks, "\n";
}
else
{
    perror "Failed to acquire locks: @locks\n";
}

#Acquire upgade
print "\nUpgrading one lock, acquiring other lock.\n";
@locks = acquirelocks (1, '4-1:Write', '4-0:Read');
if (@locks == ())
{
    print "Resulting locktable:\n", &dumplocks, "\n";
}
else
{
    perror "Failed to acquire locks: @locks\n";
}

#build %locktable
print "\n\nNow onto rebuilding the lock table from a string.\n";
$dump = dumplocks;
print "Copied locktable to string.\n";
%locktable = ();
print "Cleared lock table\n";
print "Results: (should be blank)\n";
print &dumplocks, "\n";
print "Rebuilding lock table.\n";
buildlocktable $dump;
print "New table:\n", &dumplocks;

#terminate current txn
print "\nTerminating txn 1\n";
deactivate 1;
print "New table:\n", &dumplocks;

#test cache data structure
print "\nFilling write cache with some writes\n";
cachewrite(0, '0-0', 123.00);
cachewrite(0, '1-1', 45.67);
cachewrite(1, '1-1', 23.45);
cachewrite(1, '0-2', 987.65);

print "Dumping cache.\n";
print &dumpcache;

print "\nCache string tests.\n";
$dump = dumpcache;
print "Copied cache to string.\n";
%cache = ();
print "Cleared write cache\n";
print "Results: (should be blank)\n";
print &dumpcache, "\n";
print "Rebuilding write cache.\n";
buildcache $dump;
print "New cache:\n", &dumpcache;

$index = cacheindex(1, '0-2');
if ($index)
{
    print "\nTransaction 1's write to 0-2 is in position ",
        ($index - 1), "\n";
}
else
{
    perror "Cached write not found.";
}

print "\nUpdating 0 and 1's write to 1-1\n";
cachewrite(0, '1-1', 56.78);
cachewrite(1, '1-1', 12.34);
print "New cache:\n", &dumpcache;

#Test dumping and rebuilding of all data for shmem
print "\nBuilding interresting shmem string\n";
newtxn();
newtxn();
$shmemstring = dumpshmemvars;

$nextid = 0;
@activeids = ();
%locktable = ();
%cache = ();
print "Cleared shmem variables.\n";

print $shmemstring;
buildshmemvars $shmemstring;

print "next id: $nextid\t 1000 ids from now: ", ($nextid + 1000), "\n";

#add @activeids
print "active id:\n";
for $aref (@activeids)
{
    print "[", ${@$aref}[0], " ", ${@$aref}[1], "]\n";
}
print "\n";

#add %locktable
print "current lock table:\n", &dumplocks;

#add %cache
print "current cache:\n", &dumpcache;


#test shared memory
writeshm &dumpshmemvars;

%locktable = ();
%cache = ();

buildshmemvars &readshm;
print "values retreived:\n", &dumpshmemvars;

%locktable = ();
%cache = ();

openshm;
print "values retreived:\n", &dumpshmemvars;
closeshm;
