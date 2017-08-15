#!/usr/bin/perl
# $Id: atm2.pl,v 1.3 1998/06/08 02:15:55 kogorman Exp $

require "common.pl";
require "mime.pl";
require "banking.pl";
BEGIN {require "newlock.pl";};

&parse_form_data(*form);

$proto = $ENV{'SERVER_PROTOCOL'};
$sware = $ENV{'SERVER_SOFTWARE'};
$surl  = $ENV{'SERVER_URL'};
$txn = $form{'txn'};
$fact = $form{'act'};
$rows = 8;

&openshm;
END {closeshm;};

################################################################## New txn
if ( !defined $txn || $fact =~ m/^New/ ) {
	$txn = &newtxn;		# Assign txn number
#	undef %form;		# Effectively blank the form
	for ($i=0; $i<$rows; $i++) {
		cachewrite($txn,"a$i","");
	}
	cachewrite($txn,"cash","");
	$formstep = 0;
	$fact = $form{'act'} = "New";
} else {
	$formstep = $form{"step"};
}

################################################################## Txn check
unless ( ($active = isactive($txn)) ) {
	&MIME_header ("text/html","Bank Demo - Transaction # $txn is Aborted");
	print <<EOF;
	Transaction $txn is no longer active in the system.<P>
	<FORM ACTION="/cgi-bin/mdipper/atm2.pl" METHOD=GET>
EOF
	if (defined $active) { # defined means wounded
		setstep($txn,0);
		print <<EOF;
		You have lost your holds on accounts.  You may retry this
		transaction, or start a new one.<P>
		<INPUT TYPE="hidden" NAME="txn" VALUE=$txn>
		<INPUT TYPE="submit" NAME="act" VALUE="Retry">
EOF
	}
	print <<EOF;
	<INPUT TYPE="submit" NAME="act" VALUE="New transaction">
	</BODY></HTML>
EOF
	exit 0;
}

################################################################## Step check
$stepnum = &currentstep($txn);
if ($fact =~ /^Retry/) {
	$formstep = 0;
}
unless ($formstep eq $stepnum) {
	&MIME_header ("text/html","Bank Demo - Transaction # $txn is out of sync");
	print <<EOF;
	<PRE>
	Transaction $txn is no longer in sync; you may have used the
	browser's "Back" key -- please don't do that

	This transaction has been aborted.
	</PRE>
	<FORM ACTION="/cgi-bin/mdipper/atm2.pl" METHOD=GET>
	<INPUT TYPE="submit" NAME="act" VALUE="New transaction">
	</BODY></HTML>
EOF
	&deactivate($txn);
	exit 0;
}

################################################################## Read cache
for ($i=0; $i<$rows; $i++) {
	$cact[$i] = cacheread($txn,"a$i");
}
$oldcash  = cacheread($txn,"cash");
$fcash = $form{"cash"};

# HACK: fudge some things for transaction recovering from wounds
if ($fact =~ /^Retry/) {
	$fact = $form{'act'} = "Update";
	for ($i=0; $i<$rows; $i++) {
		if($cact[$i]) { $form{"amt$i"} = cacheread($txn,$cact[$i]); }
	}
}

################################################################## Abort?
if ($fact =~ /^Cancel/) {
	&MIME_header ("text/html","Bank Demo - Transaction # $txn - Aborting at Step $stepnum");
	print <<EOF;
	<FORM ACTION="/cgi-bin/mdipper/atm2.pl" METHOD=GET>
	Aborting transaction $txn!<P>
	<INPUT TYPE="submit" NAME="act" VALUE="New transaction">
	</BODY>
	</HTML>
EOF

	&deactivate($txn);
	exit 0;
} elsif ($fact !~ /^(New|Update|Finish)/) {
	&MIME_header ("text/html","Bank Demo - Unknown Error Type");
	print <<EOF;
	<FORM ACTION="/cgi-bin/mdipper/atm2.pl" METHOD=GET>
	A problem has occurred in this page.<P>
	\$fact: $fact
	<INPUT TYPE="submit" NAME="act" VALUE="New transaction">
	</BODY>
	</HTML>
EOF
	exit 0;
}

############################################################# Update or Commit testing
&MIME_header ("text/html","Bank Demo - Transaction # $txn Step $stepnum");

$stepnum = &nextstep($txn);
print <<EOF;
<FORM ACTION="/cgi-bin/mdipper/atm2.pl" METHOD=GET>
<INPUT TYPE="hidden" NAME="txn" VALUE=$txn>
<INPUT TYPE="hidden" NAME="step" VALUE=$stepnum>
EOF

# Check inputs and lock availability
undef @error;
undef @act;
undef $casherror;
if (!&okayamt($fcash) || $fcash<0) {$casherror = "Invalid dollar amount";}
$cashchange = ($fcash - $oldcash != 0) ;
$cashback = $fcash;
$changed = 0;
for ($i=0; $i<$rows; $i++ ) {
	# Verify the form of the account numbers
	if ($cact[$i] eq "") { # No lock held
		if ($form{"acct$i"} ne "") {
			$fact[$i] = $form{"acct$i"};
			if (!&okayacct($fact[$i]))  { $error[$i] = "Invalid account #"; }
			elsif(&isdupe($fact[$i]))   { $error[$i] = "Duplicate account #"; }
			else                        { 
				@lock = ("$fact[$i]:Read");
				if( &acquirelocks($txn, @lock) ) {
					$error[$i] = "Cannot read-lock"; 
				} else {
					$cact[$i]=$fact[$i];
					cachewrite($txn,$fact[$i],"");
				}
			}
		}
	} else { $fact[$i] = $cact[$i]; }

	# Verify the existence of the account
	if ($fact[$i] ne "" && !$error[$i] ) {
                ($canum,$holder[$i],$ssan[$i],$bal[$i]) = cache_inquire($fact[$i]);
		if (! $holder[$i]) {
			$error[$i] = "No such account";
			$cact[$i] = "";
		}
	}

	# Ensure the dollars can be reserved
	if ($fact[$i] ne "" && !$error[$i] ) {
		$delta[$i] = &cacheread($txn,$fact[$i]);
		$amt[$i] = $form{"amt$i"};
		$changed |= ($delta[$i] != $amt[$i]);
		if (!&okayamt($amt[$i])) {
			$error[$i] = "Invalid dollar amount";
		} elsif ( $bal[$i] + $amt[$i] < 0 ) {
			$error[$i] = "Insufficient funds";
		} else {
			if (defined $amt[$i]) {
				@lock = ("$fact[$i]:$amt[$i]");
			} else {
				@lock = ("$cact[$i]:0");
			}
			if( &acquirelocks($txn, @lock) ) { $error[$i] = sprintf("Cannot hold \$%s",dollars(-$amt[$i])); }
		}
	}

	# Calculate the contribution of the non-erroneous lines
	if ( !$error[$i] ) {
		$delta[$i] = $amt[$i] = &dollars($amt[$i]);
		$cashback -= $delta[$i];
		$bal[$i] = &dollars($bal[$i]);
		&cachewrite($txn,$cact[$i],$delta[$i]) if ($cact[$i]);
	}

	if ( !$error[$i] ) {
		&cachewrite($txn,"a$i",$cact[$i]);
	}
}
$fcash = &dollars($fcash) unless $casherror;
$cashback = &dollars($cashback);
cachewrite($txn,"cash",$fcash);

if (@error || $casherror || $cashback < 0) {
	if ($fact =~ /^Finish/ ) {
		print <<EOF;
		<FONT COLOR="red">You cannot commit a transaction with errors</FONT><P>
EOF
	}
	&body;
	&buttons;
	exit 0;
}

################################################################## Commit
if ($fact =~ /^Finish/ && !$changed && !$cashchange) {
	for ( $i=0; $i<$rows; $i++) {
		if ($delta[$i]) {
			if ($delta[$i] >0 ) {
				cache_deposit($cact[$i],$delta[$i]);
			} elsif ($delta[$i] < 0 ) {
				cache_withdraw($cact[$i],-$delta[$i]);
			}
		}
	}
	&committed;
	print <<EOF;
	<INPUT TYPE="submit" NAME="act" VALUE="New transaction">
	</BODY>
	</HTML>
EOF
	&deactivate($txn);
	exit(0);
}
if ($fact =~ /^Finish/ ) {
	print <<EOF;
	<FONT COLOR="red">You cannot commit a transaction with changes</FONT><P>
EOF
}

################################################################ Update
# Format the next form
&body;
&buttons;

exit 0;


############################################### Format dollars
sub dollars {
	if ($_[0] eq "") {return "";}
	($sign,$dollars,$cents) = $_[0] =~ m/^([-+]?)(\d+)(\.\d\d)?$/;
	if ($cents eq "") {$cents = ".00";};
	$dollars =~ s/^0*(\d)/$1/;
	$sign . $dollars . $cents;
}

############################################### Validate input
sub okayamt {
	$_[0] =~ m/^([-+]?\d+(\.\d\d)?)?$/;
}

############################################### Validate input
sub okayacct {
	$_[0] =~ m/^\d+-\d+$/;
}

############################################### Validate account
sub isdupe {
	my $act = $_[0];
	my $i;
	for ($i = 0; $i<$rows; $i++ ) {
		if ($act eq $cact[$i]) {return 1;}
	}
	return 0;
}


############################################### Output committed page
sub committed {
	print <<EOF;
	<table border=2>
	<caption><h2>Committed Results</h2></caption>
	<tr valign="bottom"><th>Account</th><th>Holder</th><th>SSAN#</th>
		<th>Original<BR>Balance</th><th>Amount</th><th>New<BR>Balance</th></tr>
	<tr><td colspan=4>Cash or checks for deposit</td><td align="right">$fcash</td><td></td></tr>
EOF
	for  ($i=0; $i<$rows; $i++) {
		if ($cact[$i] eq "") {
			print <<EOF;
			<tr><td colspan=6>Unused</td></tr>
EOF
		} else {
			$delta[$i] = &dollars($delta[$i]);
			if ($delta[$i] eq "") { $delta[$i] = "No change"; $nbal = $bal[$i]; }
			else                  { $nbal = &dollars($bal[$i] + $delta[$i]); }
			print <<EOF;
			<tr><td>$cact[$i] </td><td> $holder[$i] </td><td> $ssan[$i] </td>
				<td align="right">$bal[$i]</td><td align="right">$delta[$i]</td>
				<td align="right">$nbal</td></tr>
EOF
		}
	}
	print <<EOF;
	<tr><td colspan=4></h4>Cash back to customer</h4></td>
		<td align="right"><h1><font color="green">\$$cashback</font></h1></td><td></td></tr>
	</table>
EOF
}

############################################### Output body of page
sub body {
	$pcash = $casherror ? $oldcash : $fcash;
	print <<EOF;
	<table border=2>
	<tr valign="bottom"><th>Account</th><th>Holder</th><th>SSAN#</th><th>Balance</th><th>Prior<BR>Amount</th>
		<th>Amount</th><th>Status</th></tr>
	<tr><td colspan=4>Cash or checks for deposit: </td>
		<td align="right">$pcash</td>
		<td><INPUT TYPE="text" NAME="cash" VALUE="$fcash" SIZE=12 MAXLENGTH=12 ></td>
		<td> <FONT COLOR="red">$casherror</FONT></td></tr>
EOF
	for  ($i=0; $i<$rows; $i++) {
		if ($cact[$i] eq "") {
			print <<EOF;
			<tr><td><INPUT TYPE="text" NAME="acct$i" VALUE="$fact[$i]" SIZE=12 MAXLENGTH=12></td>
				<td colspan=5> </td>
				<td><FONT COLOR="red">$error[$i]</FONT></td></tr>
EOF
		} else {
			print <<EOF;
			<tr><td>$cact[$i] </td>
				<td> $holder[$i] </td><td> $ssan[$i] </td>
				<td align="right">$bal[$i]</td>
				<td align="right">$delta[$i]</td>
				<td align="right"><INPUT TYPE="text" NAME="amt$i" VALUE="$amt[$i]" SIZE=12 MAXLENGTH=12></td>
				<td> <FONT COLOR="red">$error[$i]</FONT></td></tr>
EOF
		}
	}
	if ( $cashback >= 0 ) {
		$color = "green";
		$caption = "Cash back to customer";
	} else {
		$color = "red";
		$caption = "Transaction is deficient in cash";
	}
	print <<EOF;
	<tr><td colspan=5><h4><font color=$color>$caption</font></h4></td>
		<td align="right"> <h1><font color=$color>\$$cashback</font></h1></td><td></td></tr>
	</table>
EOF
}

############################################### Print buttons
sub buttons {
	print <<EOF;
	<INPUT TYPE="submit" NAME="act" VALUE="Update account info">
	<INPUT TYPE="submit" NAME="act" VALUE="Finish transaction">
	<INPUT TYPE="submit" NAME="act" VALUE="Cancel transaction">
	<INPUT TYPE="reset"  VALUE="Clear inputs">
	</BODY>
	</HTML>
EOF
}

############################################### Debugging stuff
sub show {
        print "<PRE>";
	print "CGI Environment variables:\n";
	foreach $key (sort keys %ENV) {
	    print "    <B>$key</B> = $ENV{$key}\n";
	}
	print "\n";
	print "Form data:\n";
	foreach $key (sort keys %form) {
	    print "    <B>$key</B> = '$form{$key}'\n";
	}
	print "</PRE>\n";
}
