#!/usr/bin/perl
# $Id: manager.pl,v 1.11 1998/06/03 16:12:23 mdipper Exp $

require "sys/ipc.ph";

###########################################################################
#prototypes
###########################################################################
sub perror($);          #display error message and dies

sub listlocks($$);      #returns list of locks given hash keys
sub dumplocks();        #returns string dump of global %locktable
sub buildlocktable($);  #builds a lock table from string dump

sub haslocks($);        #returns non-zero if an item is in the locktable
                            #a value of 1 implies only Read locks
                            #a value of 2 implies only Write locks
                            #a value of 3 implies both Read and Write locks
sub lockindex($$$);     #returns index + 1 into lock array for a given txn
                            #a return value of 0 implies txn does not hold
                            #a lock on the item

sub acquirelocks(@);    #returns a list of locks not acquirable.  If list
                            #is empty all locks were acquired, else
                            #no locks were acquired
sub oktoshare($$);      #returns non-zero if existing locks on an item
                            #do not conflict with type of lock specified
sub woundothers($$$$);  #returns non-zero if all locks on an item have
                            #been time out.

sub isactive($);        #returns index into activeids + 1 if a transaction
                            #is active.
                            #zero implies that txn is inactive
sub newtxn();           #returns id for new transaction and adds it to
                            #the active id list
sub currentstep($);     #returns the current step number for a transaction
                            #returns undef for inactive transactions
sub nextstep($);        #increments step count for the transaction
                            #returns step number.
                            #zero implies that txn is inactive
sub deactivate($);      #removes txn id from active id list and removes
                            #all active locks associated with txn

sub dumpcache();        #returns string dump of global %cache
sub buildcache($);      #builds a write cache from string dump

sub cachewrite($$$);    #caches writes, creating a new entry if necessary
sub cacheread($$);      #returns item value
sub cacheindex($$);     #returns index + 1 into cache array for a given txn
                            #a return value of 0 implies txn has not
                            #written a value to the item

sub dumpshmemvars();    #returns stind of all global variables
sub buildshmemvars($);  #builds all shmem variables from string dump

sub openshm();          #opens and latches shared memory for retrival 
                            #of global tables
sub closeshm();         #dumps tables to shared memory and releases latches

sub getsem();		#get mutex for shared memory
sub letsem();		#release mutex for shared memory

sub readshm();		#read shared memory to scalar return value
sub writeshm($);	#write shared memory

###########################################################################
#global variables
###########################################################################
$maxage = 180;              #maximum number of seconds a lock may go
                                #without being a candidate for timeout
$SIZE=10000;		    #size of shared memory region
$nextvar = "~~~~~~~~\n";    #shared memory variable separator
$managerid = 0x27150;       #id of manager semaphore and shared memory

###########################################################################
#subroutines
###########################################################################

sub perror($)
{
    print STDERR "ERROR: $_[0]\n";
    die;
}

###########################################################################
# Subroutine:  listlocks
#
# Description: This subroutine returns a list of all of transactions
#              holding a lock of the specified type on the specified item
#
# Inputs:      $item - the item which locks are to be listed for
#              $type - the type of lock being listed (Read or Write)
#
# Effects:     None
#
# Returns:     List of transactions holding a lock and their timestamps.
#              The list is formated: ([txn1, ts1], [txn2 ts2], ...)
###########################################################################
sub listlocks($$)
{
    my($item, $type) = @_;
    my (@locks,
        $last, $tmp);

    for $aref (@{$locktable{$item}{$type}})
    {
        push @locks, "@$aref, ";
    }

    $last = pop @locks;
    ($last, $tmp) = split /, /, $last;
    push @locks, $last;
    return @locks;
}

###########################################################################
# Subroutine:  dumplocks
#
# Description: This subroutine returns a formatted string containing all of
#              the data in the locktable.  The string may be used to
#              display the locktable, or to transfer it to shared memory.
#
# Inputs:      None
#
# Effects:     None
#
# Returns:     Formatted string containing all of the locktable data
###########################################################################
sub dumplocks()
{
    my $outstr;
    $outstr = "";

    foreach $item (sort {$a <=> $b} (keys %locktable))
    {
        #append locked item
        $outstr = join "", $outstr, (sprintf "%s\n", $item);
        foreach $locktype (sort {$a <=> $b} (keys %{$locktable{$item}}))
        {
            #append lock type
            $outstr = join "", $outstr, (sprintf "\t%s\n\t\t", $locktype);
            foreach $val (&listlocks ($item, $locktype))
            {
                #append lockholder and timestamp
                $outstr = join "", $outstr, (sprintf "%s", $val);
            }
            $outstr = join "", $outstr, "\n";
        }
    }

    return $outstr;
}

###########################################################################
# Subroutine:  buildlocktable
#
# Description: This subroutine takes a properly formatted lock table
#              string and builds the global hash %locktable
#
# Inputs:      $stringtable - locktable stored as formatted string
#
# Effects:     %locktable is filled with a set of values
#
# Returns:     None
###########################################################################
sub buildlocktable($)
{
    my $stringtable = $_[0];
    my (@lines, @pairs,
        $line, $tmp, $item, $type, $locks, $txn, $stamp);

    #split into individual lines
    @lines = split /\n/, $stringtable;
    while (@lines)
    {
        $line = shift(@lines);

        #determine type of line
        if ($line =~ m/\t\t/)
        {
            #we have a list of locks, add to %locktable
            ($tmp, $locks) = split /\t\t/, $line;

            #split up txn/ts pairs
            @pairs = split /, /, $locks;

            #insert txn/ts pairs
            foreach $i (@pairs)
            {
                ($txn, $stamp) = split / /, $i;
                push @{$locktable{$item}{$type}}, [$txn, $stamp];
            }
        }
        else
        {
            if ($line =~ m/\t/)
            {
                #we have a lock type
                ($tmp, $type) = split /\t/, $line;
            }
            else
            {
                #we have an item
                $item = $line;
            }
        }
    }
}

###########################################################################
# Subroutine:  haslocks
#
# Description: This subroutine returns the types of locks held on an item.
#
# Inputs:      $_[0] - Item being checked for locks
#
# Effects:     None
#
# Returns:     0 if item is not locked
#              1 if item is only read locked
#              2 if item is only write locked
#              3 if item is read and write locked
###########################################################################
sub haslocks($)
{
    my $item = $_[0];
    my $retval;

    $retval = 0;
    if (exists $locktable{$item})
    {
        if (exists $locktable{$item}{Read})
        {
            #has a read lock
            $retval += 1;
        }

        if (exists $locktable{$item}{Write})
        {
            #has a write lock
            $retval += 2;
        }
    }

    return $retval;
}

###########################################################################
# Subroutine:  lockindex
#
# Description: This subroutine returns a the index into the list of locks
#              held by an item, where a specific transaction's lock may
#              be found.  This is need for deleting a transaction's locks.
#
# Inputs:      $item - The item being locked
#              $type - The type of lock being held
#              $txn  - The transaction holding the lock
#
# Effects:     None
#
# Returns:     1 + The index into the array of locks for the transaction
#              being searched for.
#              0 implies the transaction is not locking the item
###########################################################################
sub lockindex($$$)
{
    my ($item, $type, $txn) = @_;
    my ($typeslocked, $index);

    #validate lock types
    if (($type ne Read) && ($type ne Write))
    {
        perror "Illegal lock type.";
        return 0;
    }

    #see if any txn holds a lock of type $type
    $typesheld = haslocks $item;
    if (!$typesheld)
    {
        return 0;
    }

    if ($type eq Read)
    {
        if (!($typesheld % 2))
        {
           return 0; #no read locks
        }
    }
    else
    {
        if ($typesheld < 2)
        {
            return 0; #no write locks
        }
    }

    for $index (0 .. $#{$locktable{$item}{$type}})
    {
        if ($locktable{$item}{$type}[$index][0] == $txn)
        {
            #found lock
            return $index + 1;
        }
    }

    return 0;
}

###########################################################################
# Subroutine:  acquirelocks
#
# Description: This subroutine attempts to acquire a list of locks for a
#              set of transactions.  If all are available, the locks will
#              be acquired, otherwise a list of locks unacquirable locks
#              will be returned
#
# Inputs:      List of formatted locks to acquire for a transaction.  The
#              expected format is as follows:
#              ($txn, $item1:$type1, $item2:$type2, ...)
#
# Effects:     %locktable will contain any newly acquired locks.
#              If at least 1 lock is not available, %locktable will be
#              unchanged.
#
# Returns:     () if all locks are acquired.
#              ($itemA:$typeA, $itemB:$typeB, ...) where $itemX may
#                  not be locked.
###########################################################################
sub acquirelocks (@)
{
    my ($txn, @locks) = @_;
    my (@notallowed, @allowed, @upgrade,
        $item, $type, $stamp, $existing, $index);

    #initialize variables
    @notallowed = ();
    @allowed = ();
    @upgrade = ();
    $stamp = time;

    #determine which, if any locks are not allowed
    foreach $val (@locks)
    {
        #split lock request
        ($item, $type) = split /:/, $val;

        $existing = haslocks $item;
        if ($existing)
        {
            #item already has a lock on it
            if ((lockindex $item, $type, $txn) == 0)
            {
                #txn doesn't already hold this lock
                if (!oktoshare $existing, $type)
                {
                    #lock may not be shared with existing locks
                    if (!(($type eq Read) && (lockindex $item, Write, $txn)))
                    {
                        #write lock is not held when read is requested
                        if (!(woundothers $item, $type, $txn, $stamp))
                        {
                            #not conflicting with timedout locks
                            #disallow lock request
                            push @notallowed, $val;
                        }
                        else
                        {
                            #all conflicts were wounded
                            if (($type eq Write) &&
                                (lockindex $item, Read, $txn))
                            {
                                #upgrade read to write
                                push @upgrade, $val;
                            }
                            else
                            {
                                #new lock
                                push @allowed, $val;
                            }
                        }
                    }
                }
                else
                {
                    #sharing a read lock
                    push @allowed, $val;
                }
            }
        }
        else
        {
            #locking item with no prior locks
            push @allowed, $val;
        }
    }

    #if all locks are allowed, add to table
    if (@notallowed == ())
    {
        foreach $val (@allowed)
        {
            ($item, $type) = split /:/, $val;

            push @{$locktable{$item}{$type}}, [$txn, $stamp];
        }

        foreach $val (@upgrade)
        {
            ($item, $type) = split /:/, $val;

            $index = lockindex $item, Read, $txn;

            if ($index)
            {
                #Get old timestamp and delete read lock
                $stamp = $locktable{$item}{Read}[($index - 1)][1];
                splice @{$locktable{$item}{Read}}, ($index - 1), 1;

                #if last lock of type remove type
                if (@{$locktable{$item}{Read}} == ())
                {
                    delete $locktable{$item}{Read};
                }

                #Insert upgraded lock
                push @{$locktable{$item}{$type}}, [$txn, $stamp];
            }
            else
            {
                perror "Invalid lock upgrade indication.";
            }
        }
    }

    return @notallowed;
}

###########################################################################
# Subroutine:  oktoshare
#
# Description: This subroutine returns a non-zero value if it okay for a
#              transaction to share a lock on item that already has
#              existing locks
#
# Inputs:      $existing - The lock types currently held on an item
#                          The accepted values are the same as the output
#                          for &haslocks:
#                          0 - No locks
#                          1 - Read only
#                          2 - Write only
#                          3 - Read and Write
#              $type     - The type of lock being checked
#
# Effects:     None
#
# Returns:     1 implies locks may be shared
#              0 implies incompatible sharing relation
###########################################################################
sub oktoshare ($$)
{
    my ($existing, $type) = @_;

    if ($existing > 1)
    {
        #write lock held: can't share
        return 0;
    }
    else
    {
        if ($existing == 0)
        {
            #no lock held: no sharing
            return 1;
        }
        else
        {
            if ($type eq Read)
            {
                #Read-Read sharing is okay
                return 1;
            }
            else
            {
                #Read-Write sharing is not allowed
                return 0;
            }
        }
    }
}

###########################################################################
# Subroutine:  woundothers
#
# Description: This subroutine returns a non-zero value if all conflicting
#              locks have been timedout.  Old locks will be timed locks
#              will be broken, even if all locks cannot be broken.
#
# Inputs:      $item     - The item with conflicting locks
#              $type     - The type of lock being requested
#              $txn      - The transaction doing the wounding
#              $stamp    - Time stamp for the lock
#
# Effects:     Transaction with old locks will be remove from @activeids
#              and their locks will be removed from %locktable
#
# Returns:     1 implies conflicts have been cleared up
#              0 implies conflicts may not be cleared up
#
# NOTE:        IF THERE IS AT LEAST 1 NON-TIMEDOUT LOCK, A STALE LOCK
#              MAY OR MAY NOT BE BROKEN
###########################################################################
sub woundothers($$$$)
{
    my ($item, $type, $txn, $stamp) = @_;
    my $existing;

    $existing = haslocks $item;

    if ($existing == 0)
    {
        #no locks held; nothing to wound
        return 1;
    }

    #Wound the writers
    if ($existing > 1)
    {
        #try to wound write lock holders
        for $aref (@{$locktable{$item}{Write}})
        {
            if (($stamp - ${@$aref}[1]) > $maxage)
            {
                if (${@$aref}[0] != $txn)
                {
                    deactivate ${@$aref}[0];
                }
            }
            else
            {
                if (${@$aref}[0] != $txn)
                {
                    return 0;
                }
            }
        }
    }

    #Wound the readers if we want a write lock
    if ((($existing % 2) == 1) && ($type eq Write))
    {
        #try to wound read lock holders
        for $aref (@{$locktable{$item}{Read}})
        {
            if (($stamp - ${@$aref}[1]) > $maxage)
            {
                if (${@$aref}[0] != $txn)
                {
                    deactivate ${@$aref}[0];
                }
            }
            else
            {
                if (${@$aref}[0] != $txn)
                {
                    return 0;
                }
            }
        }
    }

    #All wounding was good
    return 1;
}

###########################################################################
# Subroutine:  isactive
#
# Description: This subroutine tests for transaction active status.
#
# Inputs:      $_[0] - The transaction id being checked.
#
# Effects:     None
#
# Returns:     1 + The index into active id array for the transaction
#              0 if transaction is inactive
###########################################################################
sub isactive($)
{
    my $index;

    $index = 0;
    for $aref (@activeids)
    {
        $index++;
        if (${@$aref}[0] == $_[0])
        {
            return 1;
        }
    }
    return 0;
}

###########################################################################
# Subroutine:  currentstep
#
# Description: This subroutine returns the current step for a transaction.
#              A value of undef will be returned if the transaction is
#              inactive.
#
# Inputs:      $_[0] - The transaction id being checked.
#
# Effects:     None
#
# Returns:     The current step number for a transaction
#              Undef if transaction is inactive
###########################################################################
sub currentstep($)
{
    for $aref (@activeids)
    {
        if (${@$aref}[0] == $_[0])
        {
            return (${@$aref}[1]);
        }
    }

    return undef;
}

###########################################################################
# Subroutine:  nextstep
#
# Description: This subroutine increments the current step for a
#              transaction and returns the value.  A value of 0 will be
#              returned if the transaction is inactive.
#
# Inputs:      $_[0] - The transaction id being checked.
#
# Effects:     Increments the transaction's step number by 1.
#
# Returns:     The next step number for the transaction
#              0 if transaction is inactive
###########################################################################
sub nextstep($)
{
    for $aref (@activeids)
    {
        if (${@$aref}[0] == $_[0])
        {
            return ++(${@$aref}[1]);
        }
    }

    return 0;
}

###########################################################################
# Subroutine:  newtxn
#
# Description: This subroutine adds a new transaction to the active id
#              list, and returns the transaction number.
#
# Inputs:      None
#
# Effects:     $nextid is added to @active ids.
#              $nextid is incremented.
#
# Returns:     Activated transaction id.
###########################################################################
sub newtxn()
{
    push @activeids, [$nextid, 0];
    return $nextid++;
}

###########################################################################
# Subroutine:  deactivate
#
# Description: This subroutine removes a transaction from the active list
#              and returns success or failure.
#
# Inputs:      $_[0] - The transaction id being checked.
#
# Effects:     Transaction will be removed for @activeids.  Transaction's
#              locks will be removed from %locktable, and all of the
#              transaction's writes will be removed from %cache.
#
# Returns:     1 if transaction is has been removed from the active list
#              0 if transaction is already inactive
###########################################################################
sub deactivate($)
{
    my $txn = $_[0];
    my ($index, $i);

    $index = -1;
    $i = -1;

    foreach $aref (@activeids)
    {
        $i++;

        if (${@$aref}[0] == $txn)
        {
            $index = $i;
            last;
        }
    }

    if ($index == -1)
    {
        return 0;
    }
    else
    {
        #remove from active list
        splice @activeids, $index, 1;

        #remove from lock table
        foreach $item (keys %locktable)
        {
            foreach $type (keys %{$locktable{$item}})
            {
                $index = lockindex $item, $type, $txn;
                if ($index)
                {
                    #remove lock
                    splice @{$locktable{$item}{$type}}, ($index - 1), 1;

                    #if last lock of type remove type
                    if (@{$locktable{$item}{$type}} == ())
                    {
                        delete $locktable{$item}{$type};
                        #if last type for item, remove item
                        if (%{$locktable{$item}} == ())
                        {
                            delete $locktable{$item};
                        }
                    }
                }
            }
        }

        #remove cached writes
        if (exists $cache{$txn})
        {
            delete $cache{$txn};
        }

        return 1;
    }
}

###########################################################################
# Subroutine:  dumpcache
#
# Description: This subroutine returns a formatted string containing all
#              of the data in the write cache.  The string may be used to
#              display the write cache, or to transfer it to shared memory.
#
# Inputs:      None
#
# Effects:     None
#
# Returns:     Formatted string containing all of the write cache data
###########################################################################
sub dumpcache()
{
    my $outstr;
    $outstr = "";

    foreach $txn (sort {$a <=> $b} (keys %cache))
    {
        #append the transaction
        $outstr = join "", $outstr, (sprintf "%s\n", $txn);

        foreach $aref (@{$cache{$txn}})
        {
            #append the item/value pair
            #the ` is used as a separator, because the cache value
            #may be a string.  It is the job of the program using
            #the cache to insure that the cahced string does not
            #contain a `.
            $outstr = join "", $outstr, (sprintf "\t%s`%s\n",
                @$aref[0], @$aref[1]);
        }
    }

    return $outstr;
}

###########################################################################
# Subroutine:  buildcache
#
# Description: This subroutine takes a properly formatted write cache
#              string and builds the global hash %cache
#
# Inputs:      $stringcache - locktable stored as formatted string
#
# Effects:     %cache is filled with a set of values
#
# Returns:     None
###########################################################################
sub buildcache($)
{
    my $stringcache = $_[0];
    my (@lines, @pairs,
       $line, $tmp, $entry, $item);

    #split into individual lines
    @lines = split /\n/, $stringcache;
    while (@lines)
    {
        $line = shift(@lines);

        #determine type of line
        if ($line =~ m/\t/)
        {
            #we have a list of items and values, add to %cache
            ($tmp, $entry) = split /\t/, $line;

            #split up txn/value pairs
            @pairs = split /`/, $entry;

            push @{$cache{$item}}, [$pairs[0], $pairs[1]];
        }
        else
        {
            #we have a txn
            $item = $line;
        }
    }
}

###########################################################################
# Subroutine:  cachewrites
#
# Description: This subroutine adds writes to the write cache.  If an
#              entry exits, its value will be updated, otherwise a new
#              entry will be collected.
#
# Inputs:      $txn   - The transaction writing a value
#              $item  - The item being written to
#              $value - The value being written
#
# Effects:     %cache is updated with new $value
#
# Returns:     None
###########################################################################
sub cachewrite($$$)
{
    my ($txn, $item, $value) = @_;
    my $index = 0;

    if (exists $cache{$txn})
    {
        #transaction has cache enteries
        $index = cacheindex($txn, $item);
        if ($index)
        {
            #item has cached value.  update value.
            $cache{$txn}[($index - 1)][1] = $value;
        }
        else
        {
            #item doesn't have cached value.  make entry.
            push @{$cache{$txn}}, [$item, $value];
        }
    }
    else
    {
        #create an entry for this transaction
        push @{$cache{$txn}}, [$item, $value];
    }
}

###########################################################################
# Subroutine:  cacheindex
#
# Description: This subroutine returns a the index into the list of items
#              written to by a transaction.
#
# Inputs:      $txn  - The transaction holding the lock
#              $item - The item being locked
#
# Effects:     None
#
# Returns:     1 + The index into the array of items written to for the
#              transaction being searched.
#              0 implies the transaction has not written to the item
###########################################################################
sub cacheindex($$)
{
    my ($txn, $item) = @_;
    my $index;

    if (exists $cache{$txn})
    {
        #transaction has cache enteries
        for $index (0 .. $#{$cache{$txn}})
        {
            if ($cache{$txn}[$index][0] eq $item)
            {
                return $index + 1;
            }
        }
    }

    return 0;
}

###########################################################################
# Subroutine:  cacheindex
#
# Description: This subroutine returns a the value of an item cached by
#              a transaction.  This subroutine will die if the cache
#              entry requested does not exist.
#
# Inputs:      $txn  - The transaction holding the lock
#              $item - The item being locked
#
# Effects:     None
#
# Returns:     The cached value of the item for the transaction passed
#              as a parameter.
###########################################################################
sub cacheread($$)
{
    my ($txn, $item) = @_;
    my $index;

    $index = cacheindex($txn, $item);
    if ($index)
    {
        return $cache{$txn}[$index -1][1];
    }
    else
    {
        perror "Invalid cache item: $item";
    }
}

###########################################################################
# Subroutine:  dumpshmemvars
#
# Description: This subroutine returns a formatted string containing all
#              of the data stored in shared memory.  The string may be used
#              to display the shared memory data, or to transfer it to
#              shared memory.
#
# Inputs:      None
#
# Effects:     None
#
# Returns:     Formatted string containing all of the shared memeory data
###########################################################################
sub dumpshmemvars()
{
    my ($shmemstring, $dump);

    #add $nextid
    $shmemstring = join "", $shmemstring, (sprintf "%d\n", $nextid);
    $shmemstring = join "", $shmemstring, $nextvar;

    #add @activeids
    if (@activeids)
    {
        foreach $aref (@activeids)
        {
            $shmemstring = join "", $shmemstring, (sprintf "%d %d, ",
                ${@$aref}[0], ${@$aref}[1]);
        }

        #remove trailing comma space
        chop $shmemstring;
        chop $shmemstring;
        $shmemstring = join "", $shmemstring, "\n";
    }
    else
    {
        $shmemstring = join "", $shmemstring, "EMPTY\n";
    }
    $shmemstring = join "", $shmemstring, $nextvar;

    #add %locktable
    $dump = dumplocks;
    if ($dump)
    { 
       $shmemstring = join "", $shmemstring, $dump;
    }
    else
    {
        $shmemstring = join "", $shmemstring, "EMPTY\n";
    }
    $shmemstring = join "", $shmemstring, $nextvar;

    #add %cache
    $dump = dumpcache;
    if ($dump)
    {
        $shmemstring = join "", $shmemstring, $dump;
    }
    else
    {
        $shmemstring = join "", $shmemstring, "EMPTY\n";
    }
}

###########################################################################
# Subroutine:  buildshmemvars
#
# Description: This subroutine takes a properly formatted shared memory
#              data string and assigns values to $nextid, @activeids,
#              %locktable, and %cache;
#
# Inputs:      $shmemstring - locktable stored as formatted string
#
# Effects:     $nextid, @cativeids, %locktable, and %cache are filled with
#              a set of values extracted from the input string
#
# Returns:     None
###########################################################################
sub buildshmemvars($)
{
    my $shmemstring = $_[0];
    my (@shmemvars, @thislist, @pair,
       $thisvar);

    @shmemvars = split $nextvar, $shmemstring;

    #build write cache
    $thisvar = pop @shmemvars;
    if ($thisvar ne "EMPTY\n")
    {
        buildcache $thisvar;
    }
    else
    {
        %cache = ();
    }

    #build lock table
    $thisvar = pop @shmemvars;
    if ($thisvar ne "EMPTY\n")
    {
        buildlocktable $thisvar;
    }
    else
    {
        %locktable = ();
    }

    #build active id list
    @activeids = ();
    $thisvar = pop @shmemvars;
    if ($thisvar ne "EMPTY\n")
    {
        #get list of $id $step
        @thislist = split ", ", $thisvar;

        #make $id $step string into array [$id, $step]
        foreach $activepair (@thislist)
        {
            @pair = split " ", $activepair;
            push @activeids, [$pair[0], $pair[1]];
        }
    }

    #get next transaction ID
    $nextid = pop @shmemvars;
    chop $nextid;
}

###########################################################################
# Subroutine:  openshm
#
# Description: This subroutine opens a properly formatted shared memory
#              data block and assigns values to $nextid, @activeids,
#              %locktable, and %cache;
#
# Inputs:      None
#
# Effects:     $nextid, @cativeids, %locktable, and %cache are filled with
#              a set of values extracted from the shared memory
#
# Returns:     None
###########################################################################
sub openshm()
{
   getsem;
   buildshmemvars &readshm;
}

###########################################################################
# Subroutine:  closeshm
#
# Description: This subroutine stores a formatted string containing all
#              of the data stored in shared memory.
#
# Inputs:      None
#
# Effects:     Formatted string containing all of the shared memeory data
#              is placed in shared memory
#
# Returns:     None
###########################################################################
sub closeshm()
{
   writeshm &dumpshmemvars;
   letsem;
}

###########################################################################
# Subroutine:  getsem
#
# Description: This subroutine gets the semaphore latch used for shrared
#              memory.  It will block until the lock is available.  If the
#              lock does not exist, it will be created.  If the lock
#              cannot be acquired, this subroutine will die.
#
# Inputs:      None
#
# Effects:     Acquires a semaphore latch on the shared memory data block.
#              A semaphore will be created if it doesn't already exist.
#              Semaphore value of 0 will be used for locked.
#
# Returns:     None
###########################################################################
sub getsem()
{
    my $semid;

    $semid = semget($managerid, 1, 0666);

    if (!defined($semid))
    {
        #create a semaphore if it doesn't exist
        $semid = semget($managerid, 1, &IPC_CREAT | 0666);
        die "Can't get semaphore: $!\n"
            unless defined($semid);

        for ($s = 0; $s < 1; $s++)
        {
            unless (semop($semid, pack("sss", $s, 1, 0)))
            {
                die "Can't signal semaphore: $!\n";
            }
        }
    }

    unless (semop($semid, pack("sss", 0, -1, 0)))
    {
        die "Can't wait for semaphore: $!\n";
    }
}

###########################################################################
# Subroutine:  letsem
#
# Description: This subroutine releases the semaphore latch used for
#              shrared memory.  It will die if release fails.
#
# Inputs:      None
#
# Effects:     Release a semaphore latch on the shared memory data block.
#              Semaphore value of 1 will be used for unlocked.
#
# Returns:     None
###########################################################################
sub letsem()
{
    my $semid;

    $semid = semget($managerid, 1, &IPC_CREAT | 0666);

    die "Can't get semaphore: $!\n"
        unless defined($semid);

    unless (semop($semid, pack("sss", 0, 1, 0)))
    {
        die "Can't signal semaphore: $!\n";
    }
}

###########################################################################
# Subroutine:  readshm
#
# Description: This subroutine reads the shared memory data block and
#              returns the data string stored in it.
#
# Inputs:      None
#
# Effects:     None
#
# Returns:     $_ - The shared memory variables data string stored in
#                   shared memory.
###########################################################################
sub readshm()
{
    my ($shmid, $len);

    $shmid = shmget($managerid, $SIZE, 0666);

    if (!defined($shmid))
    {
        #write blank to new shared memory
        &writeshm("");
    }

    unless (shmread($shmid, $_, 0, $SIZE))
    {
        die "Can't read shared memory: $!\n";
    }

    #get size of data string
    $len = unpack("L", $_);

    #extract shared memory variable and store them in $_
    substr($_, length(pack("L" ,0)), $len);
}

###########################################################################
# Subroutine:  writeshm
#
# Description: This subroutine writes the shared memory variable string to
#              the shared memory data block.
#
# Inputs:      $data - The shared memory variables data string stored in
#                      shared memory.
#
# Effects:     None
#
# Returns:     None
###########################################################################
sub writeshm($)
{
    my $data = $_[0];
    my $shmid;

    $shmid = shmget($managerid, $SIZE, &IPC_CREAT | 0666);

    die "Can't get shared memory: $!\n"
        unless defined($shmid);

    #write size of shared memory variable string followed by
    #shared memory variable string to shared memory
    unless (shmwrite($shmid, pack("La*", length($data), $data), 0, $SIZE))
    {
        die "Can't write to shared memory: $!\n";
    }
}

1;  #Return value for require
