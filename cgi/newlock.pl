#!/usr/bin/perl
# $Id: newlock.pl,v 1.3 1998/06/06 02:25:03 kogorman Exp $

require "sys/ipc.ph";
use Carp;

###########################################################################
#prototypes
###########################################################################

sub dumplocks();        #returns string dump of global %locktable
sub buildlocktable($);  #builds a lock table from string dump
sub haslocks($);        #returns non-zero if an item is in the locktable
sub lockindex($$);      #returns index into lock array for a given txn
                            #returns undef if txn does not hold a lock
                            #on the item
sub sumlocks($);	#returns the sum of the locks held on an item;
sub lockval($$);	#returns a copy of the lock array a transaction
                            #holds on an item
                            #undef implies no lock
sub insertlock($@);     #inserts lock on item in locktable
sub deletelock($$);     #deletes a lock from the locktable

sub deltalock($$$);     #returns the difference between a new and old
                            #lock values
sub acquirelocks($@);   #returns a list of locks not acquirable.  If list
                            #is empty all locks were acquired, else no
                            #locks were added.  Conflicting locks may
                            #be wounded, whether locks were granted or
                            #not.
sub committedbal($);	#returns the committed balance in an account
sub cache_inquire($);	#returns the data array for an account
sub cache_deposit($$);	#write-through of cash through cache into an 
                            #account
sub cache_withdraw($$);	#write-through of cash through cache out of an 
                            #account
sub woundothers($$$$);	#Wounds (disposes of) transactions holding old
                            #competing non-zero locks on an item.
sub isactive($);        #returns index into activeids + 1 if a transaction
                            #is active.
                            #zero implies that txn is inactive
sub newtxn();           #returns id for new transaction and adds it to
                            #the active id list
sub currentstep($);     #returns the current step number for a transaction
                            #returns undef for inactive transactions
sub setstep($$);	#sets the step number
sub nextstep($);        #increments step count for the transaction
                            #returns step number.
                            #zero implies that txn is inactive
sub wound($);		#wounds a txn, leaving a trace for restart
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
$maxage = 3*60;             #maximum number of seconds a lock may go
                                #without being a candidate for timeout
$maxalive = 15*60;        #maximum number of seconds a transaction may
				#be inactive without being clobbered
				#just for being around so long
$SIZE=10000;		    #size of shared memory region
$nextvar = "~~~~~~~~\n";    #shared memory variable separator
$managerid = 0x27160;       #id of manager semaphore and shared memory

###########################################################################
#subroutines
###########################################################################

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
        foreach $aref (@{$locktable{$item}})
        {
            #append lockholder and timestamp
            $outstr = join "", $outstr, (sprintf "\t%s, %s, %s\n",
                ${@$aref}[0], ${@$aref}[1], ${@$aref}[2]);
        }
        $outstr = join "", $outstr, "\n";
    }

    return $outstr;
}

###########################################################################
# Subroutine:  buildlocktable
#
# Description: This subroutine takes a properly formatted lockatble
#              string and builds the global hash %locktable
#
# Inputs:      $stringtable - lock table stored as formatted string
#
# Effects:     %locktable is filled with a set of values
#
# Returns:     None
###########################################################################
sub buildlocktable($)
{
    my $stringtable = $_[0];
    my (@lines, @lock,
        $line, $tmp, $entry, $item);

    #split into individual lines
    @lines = split /\n/, $stringtable;
    while (@lines)
    {
        $line = shift(@lines);

        #determine type of line
        if ($line =~ m/\t/)
        {
            #we have a list of txns, values, and stamps to %locktable
            ($tmp, $entry) = split /\t/, $line;

            #split up txn/value/ts triple
            @lock = split /, /, $entry;
            insertlock $item, @lock;
        }
        else
        {
            #we have an item
            $item = $line;
        }
    }
}

###########################################################################
# Subroutine:  haslocks
#
# Description: This subroutine returns whether or not an item has locks
#
# Inputs:      $item - Item being checked for locks
#
# Effects:     None
#
# Returns:     exists $locktable{$item}
###########################################################################
sub haslocks($)
{
    my $item = $_[0];

    return (exists $locktable{$item});
}

###########################################################################
# Subroutine:  lockindex
#
# Description: This subroutine returns a the index into the list of locks
#              held by an item, where a specific transaction's lock may
#              be found.  This is need for deleting a transaction's locks.
#
# Inputs:      $item - The item being locked
#              $txn  - The transaction holding the lock
#
# Effects:     None
#
# Returns:     The index into the array of locks for the transaction
#              being searched for.
#              undef implies the transaction is not locking the item
###########################################################################
sub lockindex($$)
{
    my ($item, $txn) = @_;
    my ($index);

    #see if any txn holds a lock on the item
    if (!haslocks $item)
    {
        return undef;
    }

    for $index (0 .. $#{$locktable{$item}})
    {
        if ($locktable{$item}[$index][0] == $txn)
        {
            #found lock
            return $index;
        }
    }

    return undef;
}

###########################################################################
# Subroutine:  haslocks
#
# Description: This subroutine returns the sum total of all locks held
#              on an item
#
# Inputs:      $item - Item being checked for locks
#
# Effects:     None
#
# Returns:     The sum of locks held on an item
###########################################################################
sub sumlocks($)
{
    my $item = $_[0];
    my $sum = 0;

    if (exists $locktable{$item})
    {
        for $index (0 .. $#{$locktable{$item}})
        {
            $sum += $locktable{$item}[$index][1];
        }

        return $sum;
    }

    return 0;
}

###########################################################################
# Subroutine:  lockval
#
# Description: This subroutine returns a copy of the lock array the
#              specified transaction on the specified item.
#
# Inputs:      $item - Item being locked
#              $txn  - Transaction number
#
# Effects:     None
#
# Returns:     Copy of lock held by transaction on item.  Undefined is
#              returned if lock doesn't exist.
###########################################################################
sub lockval($$)
{
    my ($item, $txn) = @_;
    my $index;

    $index = lockindex ($item, $txn);
    if (defined $index)
    {
        #lock exists
        return @{$locktable{$item}[$index]};
    }
    else
    {
        #transaction doesn't hold lock
        return undef;
    }
}

###########################################################################
# Subroutine:  insertlock
#
# Description: This subroutine adds a lock to the lock table.  If the
#              locking transaction alread holds a lock, the lock
#              values will be modified.
#
# Inputs:      $item - Item being locked
#              @lock - lock being applied
#
# Effects:     The new lock will be inserted into @{$locktable{$item}}.
#              If the transaction already holds a lock on $item, its
#              lock amount and timestamp will be updated.
#
# Returns:     None
###########################################################################
sub insertlock ($@)
{
    my ($item, @lock) = @_;
    my $index;

    $index = lockindex ($item, $lock[0]);

    if (defined $index)
    {
        #lock exist change amount and timestamp
        $locktable{$item}[$index][1] = $lock[1];
        $locktable{$item}[$index][2] = $lock[2];
    }
    else
    {
        #create new lock
        push @{$locktable{$item}}, [$lock[0], $lock[1], $lock[2]];
    }
}

###########################################################################
# Subroutine:  deletelock
#
# Description: This subroutine deletes a lock to the lock table.
#
# Inputs:      $item - Item being locked
#              $txn  - Transaction releasing lock
#
# Effects:     The new lock will be deleted from @{$locktable{$item}}.
#
# Returns:     None
###########################################################################
sub deletelock ($$)
{
    my ($item, $txn) = @_;
    my $index;

    $index = lockindex ($item, $txn);

    if (defined $index)
    {
        #lock exist delete it
        splice @{$locktable{$item}}, $index, 1;

        #remove item entry if last txn is deleted
        if (@{$locktable{$item}} == ())
        {
            delete $locktable{$item};
            delete $cache{$item};
        }
    }
}

###########################################################################
# Subroutine:  deltalock
#
# Description: This subroutine computes the difference in old and new lock
#
# Inputs:      item, txn#, newvalue
#
# Effects:     None
#
# Returns:     new lock amount - old lock amount, except that negative
#              values are returned as zero.
###########################################################################
sub deltalock($$$)
{
    my ($item, $txn, $value) = @_;
    my @current;

    @current = lockval $item, $txn;
    if (!defined @current)
    {
        return $value;
    } else {
        if ($value > $current[1]) {
            return $value - $current[1];
        } else {
            return 0;
        }
    }
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
#              ($txn, $item1:$amount1, $item2:$amount2, ...)
#
# Effects:     %locktable will contain any newly acquired locks.
#              If at least 1 lock is not available, %locktable will be
#              unchanged.
#
# Returns:     () if all locks are acquired.
#              ($itemA:$amountA, $itemB:$amountB, ...) where $itemX may
#                  not be locked.
###########################################################################
sub acquirelocks ($@)
{
    my ($txn, @locks) = @_;
    my (@notallowed, @allowed,
       $item, $amt, $stamp, $existing, $index, $delta, $bal, $old);

    #initialize variables
    @notallowed = ();
    @allowed = ();
    $stamp = time;

    #determine which, if any locks are not allowed
    foreach $val (@locks)
    {
        #split lock request
        ($item, $amt) = split /:/, $val;

        #Ensure a dummy lock, so that wounding won't remove the cache
        if (!defined(lockindex $item, $txn)) {
            push @{$locktable{$item}}, [$txn, 0, $stamp];
        }

        #Is this increasing the lock amount?
        $delta = deltalock( $item, $txn, -$amt );
        if ( !$delta ) {
            #Non-increasing
            push @allowed, $val;
        } elsif ($bal=committedbal($item),
                ($need =(sumlocks($item)+$delta) - $bal) <= 0) {
            #There's a large enough balance for the increased lock
            push @allowed, $val;
        } elsif (woundothers($item,$txn,$stamp,$need),
                ((sumlocks($item)+$delta) <= $bal)) {
            #Wounding other lock holders helped enough
            push @allowed, $val;
        } else {
            push @notallowed, $val;
        }
    }

    #if all locks are allowed, add to table
    if (@notallowed == ())
    {
        foreach $val (@allowed)
        {
            ($item, $amt) = split /:/, $val;
            $index = lockindex $item, $txn;

            if (defined $index)
            {
                #Get old lock value
                $old = $locktable{$item}[$index][1];
                if ($amt < $old) { $locktable{$item}[$index][1] = -$amt; }
            } else {
                #Create new lock entry
                push @{$locktable{$item}}, [$txn, -$amt, $stamp];
            }
        }
    }

    return @notallowed;
}

###########################################################################
# Subroutine:  committedbal
#
# Description: Return the committed balance for an account.  Read the
#              cache if it exists, otherwise read the bank database, and
#              create the cache entry.
#
# Inputs:      $_[0] - The account in question
#
# Effects:     May create the cache entry
#
# Returns:     The balance field from the cache entry
###########################################################################
sub committedbal($) {
    my $item = $_[0];
    my @ret;

    @ret = cache_inquire($item);
    return $ret[3];
}

###########################################################################
# Subroutine:  cache_inquire
#
# Description: Return the cached data for an account.  Inquire of the
#              bank branch if necessary.
#
# Inputs:      $_[0] - The account in question
#
# Effects:     May create the cache entry
#
# Returns:     The data as ($accountid, $holder, $ssan, $bal)
###########################################################################
sub cache_inquire($) {
    my $item = $_[0];
    my @what;

    if (!exists $cache{$item}) {
        @what = &bank_inquire($item);
        $cache{$item}[0] = ["cache", join(":",@what[0..3])];
    }

    @what = split /:/, $cache{$item}[0][1];
}

###########################################################################
# Subroutine:  cache_deposit
#
# Description: Write-through operation on cache, to add money to an account.
#
# Inputs:      $_[0] - The account in question
#              $_[1] - The dollar amount
#
# Effects:     Changes cached balance and the branch data
#
# Returns:     Nothing
###########################################################################
sub cache_deposit($$) {
    my ($item,$amt) = @_;
    my (@what,$bal);

    # Make it exist
    $bal = &committedbal($item);

    @what = split /:/, $cache{$item}[0][1];
    $what[3] = $bal + $amt;
    $cache{$item}[0][1] = join ":", @what;
    bank_deposit($item,$amt);
}

###########################################################################
# Subroutine:  cache_withdraw
#
# Description: Write-through operation on cache, to take money from an account.
#
# Inputs:      $_[0] - The account in question
#              $_[1] - The dollar amount
#
# Effects:     Changes cached balance and the branch data
#
# Returns:     Nothing
###########################################################################
sub cache_withdraw($$) {
    my ($item,$amt) = @_;
    my (@what,$bal);

    # Make it exist
    $bal = &committedbal($item);

    @what = split /:/, $cache{$item}[0][1];
    $what[3] = $bal - $amt;
    $cache{$item}[0][1] = join ":", @what;
    bank_withdraw($item,$amt);
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
# Returns:     1 if transaction is active
#              0 if transaction is wounded
#              undefined if transaction is inactive
###########################################################################
sub isactive($)
{
    my $txn = $_[0];

    for $aref (@activeids)
    {
        if (${@$aref}[0] == $txn)
        {
            return ${@$aref}[1] ne '-' ? 1 : 0;
        }
    }
    return undef;
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
            return ${@$aref}[1] ne '-' ? ${@$aref}[1] : undef;
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
#              Updates the 'time last active'
#
# Returns:     The next step number for the transaction
#              undefined value if transaction is inactive or wounded
###########################################################################
sub nextstep($)
{
    for $aref (@activeids)
    {
        if (${@$aref}[0] == $_[0])
        {
            ${@$aref}[3] = time;
            if (${@$aref}[1] ne '-') { return ++(${@$aref}[1]); }
            else                     { return undef; }
        }
    }
    return undef;
}

###########################################################################
# Subroutine:  setstep
#
# Description: This subroutine sets the current step for a
#              transaction.
#
# Inputs:      $_[0] - The transaction id being checked.
#
# Effects:     Sets the stepnumber as indicated
#              Dies if this transaction does not exist
#
# Returns:     The step number.
###########################################################################
sub setstep($$)
{
    my ($txn,$step) = @_;

    for $aref (@activeids) {
        if (${@$aref}[0] == $txn) {
            ${@$aref}[3] = time;
            ${@$aref}[1] = $step;
	    return $step;
        }
    }
    confess "No such transaction: $txn";
}

###########################################################################
# Subroutine:  stamp
#
# Description: Returns the timestamp of a transaction.
#
# Inputs:      $_[0] - The transaction id being checked.
#
# Effects:     No side effects.
#
# Returns:     The timestamp (or undef).
###########################################################################
sub stamp($)
{
    for $aref (@activeids)
    {
        if (${@$aref}[0] == $_[0])
        {
            return ${@$aref}[2];
        }
    }
    return undef;
}

###########################################################################
# Subroutine:  lastactive
#
# Description: Returns the time elapsed since the transaction was last
#              active
#
# Inputs:      $_[0] - The transaction id being checked.
#
# Effects:     No side effects
#
# Returns:     The time in seconds, or undef
###########################################################################
sub lastactive($)
{
    for $aref (@activeids)
    {
        if (${@$aref}[0] == $_[0])
        {
            return time - ${@$aref}[3];
        }
    }

    return undef;
}

###########################################################################
# Subroutine:  newtxn
#
# Description: This subroutine adds a new transaction to the active id
#              list, and returns the transaction number.
#
# Inputs:      None
#
# Effects:     $nextid is added to @activeids, with initial step and times.
#              $nextid is incremented.
#
# Returns:     Activated transaction id.
###########################################################################
sub newtxn()
{
    push @activeids, [$nextid, 0, time, time];
    return $nextid++;
}

###########################################################################
# Subroutine:  woundothers
#
# Description: Wound (dispose of) other transactions holding stale non-zero
#              locks on an item, until the indicated amount has been
#              unlocked.
#
#              NOTE: wounding is not possible if the target has an older
#              timestamp than the wounder AND the target has kept itself
#              current by interacting within the last $maxage period.
#
# Inputs:      $_[0] - The item in question
#              $_[1] - The transaction to keep
#              $_[2] - The timestamp that's good
#              $_[3] - The amount to unlock
#
# Effects:     Clears all traces of wounded transactions
#
# Returns:     Nothing
###########################################################################
sub woundothers($$$$) {
    my ($item,$txn,$stamp,$delta) = @_;
    my ($aref,$target);

    if (haslocks $item) {
        for $aref (@{$locktable{$item}}) {
            # Wound if it's old, non-zero, and not the requestor
            if ( $txn != ($target = ${@$aref}[0])	#not me
          #    &&($stamp - ${@$aref}[2]) > $maxage	#stale?
              && ${@$aref}[1] > 0			#nontrivial lock
              && (stamp($txn) < stamp($target)		#target younger
		      || lastactive($target) > $maxage)	#  OR tardy
		) {
                $delta -= ${@$aref}[1];
                wound($target);
                if ($delta <=0) {return;} 
            }
        }
    }
}

###########################################################################
# Subroutine:  wound
#
# Description: Makes a transaction un-runnable, so that it knows it must
#              restart
#
# Inputs:      $_[0] - The target transaction id being checked.
#
# Effects:     Transaction's locks will be removed from %locktable.
#              Transaction's step number will be undefined
#
# Returns:     1 if transaction is has been found and wounded
#              0 if transaction is already wounded or inactive
###########################################################################
sub wound($) {
    my $txn = $_[0];
    my ($index, $i);

    $index = undef;
    $i = -1;

    foreach $aref (@activeids)
    {
        $i++;

        if (${@$aref}[0] == $txn)
        {
            if (!defined ${@$aref}[1]) { return 0; }
            ${@$aref}[1] = '-';

            #remove from lock table
            foreach $item (keys %locktable)
            {
                deletelock $item, $txn;
            }
            return 1;
        }
    }

    return 0;
}

###########################################################################
# Subroutine:  deactivate
#
# Description: This subroutine removes a transaction from the active list
#              and returns success or failure.
#
# Inputs:      $_[0] - The transaction id being checked.
#
# Effects:     Transaction will be removed from @activeids.  Transaction's
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

    $index = undef;
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

    if (!defined $index )
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
            deletelock $item, $txn;
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
# Subroutine:  cachewrite
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
        if (defined $index)
        {
            #item has cached value.  update value.
            $cache{$txn}[$index][1] = $value;
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
                return $index;
            }
        }
    }

    return undef;
}

###########################################################################
# Subroutine:  cacheread
#
# Description: This subroutine returns a the value of an item cached by
#              a transaction.  This subroutine will die if the cache
#              entry requested does not exist.
#
# Inputs:      $txn  - The transaction owning the cache (or account #)
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
    if (defined $index)
    {
        return $cache{$txn}[$index][1];
    }
    else
    {
        confess "Invalid cache item: $item";
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
            $shmemstring .= (sprintf "%d %s %d %d, ",
                ${@$aref}[0], ${@$aref}[1], ${@$aref}[2], ${@$aref}[3] );
        }

        #replace trailing comma space with newline
        $shmemstring =~ s/..$/\n/;
    }
    else
    {
        $shmemstring .= "EMPTY\n";
    }
    $shmemstring .= $nextvar;

    #add %locktable
    $dump = dumplocks;
    if ($dump)
    {
       $shmemstring .= $dump;
    }
    else
    {
        $shmemstring .= "EMPTY\n";
    }
    $shmemstring .= $nextvar;

    #add %cache
    $dump = dumpcache;
    if ($dump)
    {
        $shmemstring .= $dump;
    }
    else
    {
        $shmemstring .= "EMPTY\n";
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

        #make $id $step $ts $last string into array [$id, $step, $ts, $last]
        foreach $activepair (@thislist)
        {
            @pair = split " ", $activepair;
            push @activeids, [$pair[0], $pair[1], $pair[2], $pair[3]];
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
#              SIDE EFFECT: all transactions that have been unreferenced
#              for too long ($maxalive) will also be completely clobbered.
#
# Returns:     None
###########################################################################
sub closeshm()
{
    foreach $aref (@activeids) {
        if (time - ${@$aref}[3] > $maxalive) {
	    deactivate(${@$aref}[0]);
        }
    }

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
