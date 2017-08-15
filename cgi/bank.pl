#!/usr/bin/perl
# $Id: bank.pl,v 1.5 1998/05/15 20:19:22 kogorman Exp $

require "common.pl";
require "mime.pl";
require "sys/ipc.ph";

$SIZE = 10000;

&parse_form_data(*hello);

$proto = $ENV{'SERVER_PROTOCOL'};
$sware = $ENV{'SERVER_SOFTWARE'};
$surl  = $ENV{'SERVER_URL'};
$bankno = $hello{'bank'};
$send   = $hello{'send'};

#print "$proto 200 OK\n";
#print "Server: $sware\n";
############################################################### no bank #
if ( $bankno eq "" ) {
&MIME_header ("text/html","Bank Project Index Page");

print <<EOF;
<H1>Bank Project Index Page</H1>
<H3>Bank Pages</H3>
<UL>
<LI><A HREF="$surl/cgi-bin/mdipper/bank.pl?bank=0">Branch 0</A></LI>
<LI><A HREF="$surl/cgi-bin/mdipper/bank.pl?bank=1">Branch 1</A></LI>
<LI><A HREF="$surl/cgi-bin/mdipper/bank.pl?bank=2">Branch 2</A></LI>
<LI><A HREF="$surl/cgi-bin/mdipper/bank.pl?bank=3">Branch 3</A></LI>
<LI><A HREF="$surl/cgi-bin/mdipper/bank.pl?bank=4">Branch 4</A></LI>
<LI><A HREF="$surl/cgi-bin/mdipper/bank.pl?bank=5">Branch 5</A></LI>
<LI><A HREF="$surl/cgi-bin/mdipper/bank.pl?bank=6">Branch 6</A></LI>
<LI><A HREF="$surl/cgi-bin/mdipper/bank.pl?bank=7">Branch 7</A></LI>
<LI><A HREF="$surl/cgi-bin/mdipper/bank.pl?bank=8">Branch 8</A></LI>
<LI><A HREF="$surl/cgi-bin/mdipper/bank.pl?bank=9">Branch 9</A></LI>
</UL>
</BODY>
</HTML>
EOF

############################################################### Return to menu
} elsif ( !$send || $send =~ /^Return/ ) {
&MIME_header ("text/html","Bank $bankno Menu");

print <<EOF;
Select one of the following:<P>
To deposit or withdraw, begin with inquiry.<P>
<FORM ACTION="/cgi-bin/mdipper/bank.pl" METHOD=GET>
<INPUT TYPE="hidden" NAME="bank" VALUE="$bankno">
<P>
<INPUT TYPE="submit" NAME="send" VALUE="Inquire of an account">
<INPUT TYPE="submit" NAME="send" VALUE="Open an account">
<INPUT TYPE="submit" NAME="send" VALUE="Dump branch file">
</FORM>
</BODY>
</HTML>
EOF

############################################################### Dump
} elsif ($send =~ /^Dump/ ) {
&MIME_header ("text/html","Bank $bankno Data Dump");
&readshm;
&dump;
print <<EOF;
</BODY>
</HTML>
EOF

############################################################### Inquire
} elsif ($send =~ /^Inquire/ ) {
&MIME_header ("text/html","Bank $bankno Account Inquiry");
print <<EOF;
<FORM ACTION="/cgi-bin/mdipper/bank.pl" METHOD=GET>
<INPUT TYPE="hidden" NAME="bank" VALUE="$bankno">
Account #: <INPUT TYPE="text" NAME="account" SIZE=10 MAXLENGTH=10>
<P>
<INPUT TYPE="submit" NAME="send" VALUE="Get Account Information">
<INPUT TYPE="reset"  VALUE="Start Over">
</FORM>
</BODY>
</HTML>
EOF

############################################################### Get / Deposit / Withdraw
} elsif ($send =~ /^Get/ || $send =~ /^Deposit/ || $send =~ /^Withdraw/ ) {
$account = $hello{'account'};
$dep = $hello{'dep'};
$with = $hello{'with'};
&readshm;
&parse;
if (!$anum) {
	&MIME_header ("text/html","Bank $bankno Account $account Not Found");
	&show;
	&dump;
	print <<EOF;
<P>
Use your browser's BACK key or function to correct and retry.<P>
</BODY>
</HTML>
EOF
	exit(0);
}

if ($send =~ /^Get/ ) {
	&MIME_header ("text/html","Bank $bankno Account $account Information");
	$dep=$with=0;
} elsif ($send =~ /^Deposit/) {
   if ($dep+0 == 0 ) {
      &MIME_header ("text/html","Bank $bankno Account $account Deposit Rejected!");
      print "<H1>No deposit amount</H1>\n";
      &show;
   } elsif ( $dep !~ m/^\d+(\.\d\d)?$/ ) {
      &MIME_header ("text/html","Bank $bankno Account $account Deposit Rejected!");
      print "<H1>Deposit amount is not a valid number</H1>\n";
      &show;
   } elsif ( $dep+0 < 0 ) {
      &MIME_header ("text/html","Bank $bankno Account $account Deposit Rejected!");
      print "<H1>Deposit amount is less than zero</H1>\n";
      &show;
   } elsif ( $with ne '0' ) {
      &MIME_header ("text/html","Bank $bankno Account $account Deposit Rejected!");
      print "<H1>Withdrawal amount not zero, but this is a deposit</H1>\n";
      &show;
   }else{
      &MIME_header ("text/html","Bank $bankno Account $account Deposit Accepted");
      &getsem;
      &readshm;
	$abal += $dep;
	$dep = 0;
	&newdata;
      &writeshm;
      &letsem;
   }
} elsif ($send =~ /^Withdraw/) {
   if ($dep ne '0' ) {
      &MIME_header ("text/html","Bank $bankno Account $account Withdrawal Rejected!");
      print "<H1>Deposit amount not zero, but this is a withdrawal</H1>\n";
      &show;
   } elsif ( $with !~ m/^\d+(\.\d\d)?$/ ) {
      &MIME_header ("text/html","Bank $bankno Account $account Deposit Rejected!");
      print "<H1>Deposit amount is not a valid number</H1>\n";
      &show;
   } elsif ($with+0  == 0 ) {
      &MIME_header ("text/html","Bank $bankno Account $account Withdrawal Rejected!");
      print "<H1>Withdrawal amount is zero</H1>\n";
      &show;
   } elsif ($with+0  < 0 ) {
      &MIME_header ("text/html","Bank $bankno Account $account Withdrawal Rejected!");
      print "<H1>Withdrawal amount is negative</H1>\n";
      &show;
   } elsif ($abal-$with  < 0 ) {
      &MIME_header ("text/html","Bank $bankno Account $account Withdrawal Rejected!");
      print "<H1>Withdrawal amount is more than the balance</H1>\n";
      &show;
   }else{
      &MIME_header ("text/html","Bank $bankno Account $account Withdrawal Accepted");
      &getsem;
      &readshm;
	$abal -= $with;
	$with = 0;
	&newdata;
      &writeshm;
      &letsem;
   }
}
print <<EOF;
<FORM ACTION="/cgi-bin/mdipper/bank.pl" METHOD=GET>
<INPUT TYPE="hidden" NAME="bank" VALUE="$bankno">
<INPUT TYPE="hidden" NAME="account" VALUE="$account">
<PRE>
        Account Number: $anum
 Account Holder's Name: $aname
Social Security Number: $assn
       Current Balance: $abal
</PRE>

Deposit amount: <INPUT TYPE="text" NAME="dep" VALUE="$dep" SIZE=15 MAXLENGTH=15>
<INPUT TYPE="submit" NAME="send" VALUE="Deposit"><BR>
Withdrawal amount: <INPUT TYPE="text" NAME="with" VALUE="$with" SIZE=15 MAXLENGTH=15>
<INPUT TYPE="submit" NAME="send" VALUE="Withdraw"><BR>
<INPUT TYPE="submit" NAME="send" VALUE="Return to menu">
</FORM>
</BODY>
</HTML>
EOF

############################################################### Open
} elsif ($send =~ /^Open/ ) {
&MIME_header ("text/html","Bank $bankno Account Creation");
print <<EOF;
<FORM ACTION="/cgi-bin/mdipper/bank.pl" METHOD=GET>
<INPUT TYPE="hidden" NAME="bank" VALUE="$bankno">
<P>
Account Holder's Name:  <INPUT TYPE="text" NAME="holder" SIZE=30 MAXLENGTH=30><BR>
Social Security Number: <INPUT TYPE="text" NAME="SSAN" SIZE=30 MAXLENGTH=30><BR>
Opening Balance: <INPUT TYPE="text" NAME="bal" SIZE=30 MAXLENGTH=30><BR>

<INPUT TYPE="submit" NAME="send" VALUE="Create the Account">
<INPUT TYPE="reset"  VALUE="Start Over">
</FORM>
</BODY>
</HTML>
EOF

############################################################### Create
} elsif ($send =~ /^Create/ ) {
$aname = $hello{'holder'};
$assn = $hello{'SSAN'};
$abal = $hello{'bal'};
$emesg="";
if ($aname =~ m/[\n:]/) {$emesg=", Holder's Name";}
if ($abal !~ m/^\d*(\.\d\d)?$/ ) {$emesg .= ", Opening Balance";}
if ($assn =~  m/[\n:]/) {$emesg .= ", SSAN";}
if ($emesg) {
	$emesg =~ s/,/:/;
	&MIME_header("text/html","Error in field(s)$emesg");
	print <<EOF;
<P>
Use your browser's BACK key or function to correct and retry.<P>
</BODY>
</HTML>
EOF
	exit(0);
}

&getsem;
&readshm;
$aname =~ s/://g;
$assn =~ s/://g;
$abal =~ s/://g;
$anum = $bankno."-".($nextacct++);
$acct = join(":", $anum, $aname, $assn, $abal+0);
push @data,$acct;
&writeshm;
&letsem;
&MIME_header ("text/html","Bank $bankno New Account Information");
&dump;
print <<EOF;
<FORM ACTION="/cgi-bin/mdipper/bank.pl" METHOD=GET>
<INPUT TYPE="hidden" NAME="bank" VALUE="$bankno">
<P>
<PRE>
        Account Number: $anum
 Account Holder's Name: $aname
Social Security Number: $assn
       Current Balance: $abal
</PRE>

<INPUT TYPE="submit" NAME="send" VALUE="Return to menu">
</FORM>
</BODY>
</HTML>
EOF

############################################################### default
} else {
&MIME_header ("text/plain","Bank $bankno Error");
print "Error: could not parse the input\n";
print "Use the \"Back\" button to return to the form\n";
}
exit(0);






############################################################### Semaphore routines
sub getsem {
	$semid = semget(0x27140, 10,  0666 );
	if (!defined($semid)) {
		$semid = semget(0x27140, 10, &IPC_CREAT | 0666 );
        	die "Can't get semaphore: $!\n" unless defined($semid);
		for ($s=0; $s<10; $s++) {
			unless (semop($semid, pack("sss", $s,  1, 0))) {die "Can't signal semaphore: $!\n";}
		}
	}
	unless (semop($semid, pack("sss", $bankno, -1, 0))) {die "Can't wait for semaphore: $!\n";}
};
sub letsem{
	$semid = semget(0x27140, 10, &IPC_CREAT | 0666 );
        die "Can't get semaphore: $!\n" unless defined($semid);
	unless (semop($semid, pack("sss", $bankno,  1, 0))) {die "Can't signal semaphore: $!\n";}
};



############################################################### Shared Memory routines
sub readshm{
	$shmid = shmget(0x27140+$bankno, $SIZE,  0666 );
	if (!defined($shmid)) { &writeshm(""); }
	unless (shmread($shmid, $_, 0, $SIZE)) {die "Can't read shared memory: $!\n";}
	$len = unpack("L",$_);
	@data = split(/\n/,substr($_, length(pack("L",0)), $len));
	$nextacct = shift(@data);
};

sub writeshm{
	my $a = join("\n", $nextacct, @data);
	$shmid = shmget(0x27140+$bankno, $SIZE, &IPC_CREAT | 0666 );
        die "Can't get shared memory: $!\n" unless defined($shmid);
	unless (shmwrite($shmid, pack("La*", length($a), $a), 0, $SIZE)) {die "Can't write to shared memory: $!\n";}
};



############################################################### Handling the branch's data
sub parse {
	@match = grep m/^$account:/, @data;
	($anum, $aname, $assn, $abal) = split(/:/, $match[0]);
}

sub newdata {
	@data = grep !m/^$account:/, @data;
	push @data, join(":",$anum, $aname, $assn, $abal);
}


############################################################### Debugging stuff
sub show {
        print "<PRE>";
	print "CGI Environment variables:\n";
	foreach $key (sort keys %ENV) {
	    print "    <B>$key</B> = $ENV{$key}\n";
	}
	print "\n";
	print "Form data:\n";
	foreach $key (sort keys %hello) {
	    print "    <B>$key</B> = '$hello{$key}'\n";
	}
	print "</PRE>\n";
}



sub dump {
	print "<PRE>\nRaw branch data:\n$nextacct\n";
	print join("\n",@data);
	print "\n</PRE>\n";
}
