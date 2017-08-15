#!/usr/bin/perl
# $Id: banking.pl,v 1.3 1998/06/01 16:55:40 kogorman Exp $

require 5.002;
use strict;
use Socket;
use FileHandle;

sub bank_inquire {
	my ($account) = @_;
	my (@answer);
	@answer = bank_hit($account,"Get");
}

sub bank_deposit {
	my ($account,$amount) = @_;
	my (@answer);
	@answer = bank_hit($account,"Deposit&dep=$amount&with=0");
}

sub bank_withdraw {
	my ($account,$amount) = @_;
	my (@answer);
	@answer = bank_hit($account,"Withdraw&with=$amount&dep=0");
}

sub bank_open {
	my ($bank,$holder,$ssan,$bal) = @_;
	my (@answer);
	@answer = bank_hit($bank,"Create&holder=$holder&SSAN=$ssan&bal=$bal");
}

sub bank_hit {
	my ($account,$arg) = @_;
	my $host = "www.cs.ucsb.edu";
	my (@answer,$bank,$branch);
	my (@acct,$acct,@name,$name,@ssan,$ssan,@abal,$abal);
	if ($arg =~ m/^Create/ ) {
		($bank) = $account =~ m/^(\d*)$/;
		$branch = "bank=$bank";
	} else {
		($bank) = $account =~ m/^(\d*)-\d*$/;
		$branch = "bank=$bank&account=$account";
	}
	my $iaddr = gethostbyname('www.cs.ucsb.edu');
	my $proto = getprotobyname('tcp');
	my $port  = getservbyname('http','tcp');
	my $paddr = sockaddr_in(0,$iaddr);
	my $hisiaddr = inet_aton($host) or die "unknown host";
	my $hispaddr = sockaddr_in($port, $hisiaddr);

	socket(WEB, PF_INET, SOCK_STREAM, $proto) or die "Socket: $!";
	connect(WEB, $hispaddr)			or die "bind: $!";

	autoflush WEB 1;
	# print STDERR "asking\n";
	print WEB "GET /cgi-bin/mdipper/bank.pl?$branch&send=$arg HTTP/1.0\n\n";

	# print STDERR "reading\n";
	@answer=<WEB>;
	close WEB;
	@acct = grep(m/Account Number:/, @answer);
	$acct = shift @acct;
	($acct) = $acct =~ m/: (.*)$/;

	@name = grep(m/Name:/, @answer);
	$name = shift @name;
	($name) = $name =~ m/: (.*)$/;

	@ssan = grep(m/Social Security Number:/, @answer);
	$ssan = shift @ssan;
	($ssan) = $ssan =~ m/: (.*)$/;

	@abal = grep(m/Balance:/, @answer);
	$abal = shift @abal;
	($abal) = $abal =~ m/: (.*)$/;

	if ($acct eq $account) { ($acct,$name,$ssan,$abal,@answer); }
	else                   { ();}
}

1;
