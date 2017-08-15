#!/usr/bin/perl
# $Id: ipc.pl,v 1.4 1998/06/06 02:28:51 kogorman Exp $

require "common.pl";
require "mime.pl";
require "sys/ipc.ph";

$SIZE = 10000;

	$semid = semget(0x27140, 10, &IPC_CREAT | 0666 );
        die "Can't get semaphore: $!\n" unless defined($semid);
	for ($i=0; $i<10; $i++) {
		if (semop($semid, pack("sss", $i, -1, &IPC_NOWAIT))) {
			$j=1;
			while (semop($semid, pack("sss", $i, -1, &IPC_NOWAIT))) {$j++;}
			print "Bank $i was unlocked by $j";
			if ($j==1) {print "; that's good";}
			print ".\n";
		}
		else {print "Bank $i was locked\n";}
		unless (semop($semid, pack("sss", $i, 1, &IPC_NOWAIT))) {print "Bank $i wouldn't unlock\n";}
	}



	$semid = semget(0x27150, 1, &IPC_CREAT | 0666 );
        die "Can't get semaphore: $!\n" unless defined($semid);
	for ($i=0; $i<1; $i++) {
		if (semop($semid, pack("sss", $i, -1, &IPC_NOWAIT))) {
			$j=1;
			while (semop($semid, pack("sss", $i, -1, &IPC_NOWAIT))) {$j++;}
			print "ATM $i was unlocked by $j";
			if ($j==1) {print "; that's good";}
			print ".\n";
		}
		else {print "ATM $i was locked\n";}
		unless (semop($semid, pack("sss", $i, 1, &IPC_NOWAIT)))
			{print "ATM $i wouldn't unlock\n";}
	}

	$semid = semget(0x27160, 1, &IPC_CREAT | 0666 );
        die "Can't get semaphore: $!\n" unless defined($semid);
	for ($i=0; $i<1; $i++) {
		if (semop($semid, pack("sss", $i, -1, &IPC_NOWAIT))) {
			$j=1;
			while (semop($semid, pack("sss", $i, -1, &IPC_NOWAIT))) {$j++;}
			print "ATM $i was unlocked by $j";
			if ($j==1) {print "; that's good";}
			print ".\n";
		}
		else {print "ATM $i was locked\n";}
		unless (semop($semid, pack("sss", $i, 1, &IPC_NOWAIT)))
			{print "ATM $i wouldn't unlock\n";}
	}

