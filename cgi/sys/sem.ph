if (!defined &_SYS_SEM_H) {
    eval 'sub _SYS_SEM_H {1;}';
#    require 'sys/ipc.ph';
#    if (defined &__cplusplus) {
#    }
    eval 'sub SEM_A {0200;}';
    eval 'sub SEM_R {0400;}';
    eval 'sub SEM_UNDO {010000;}';
    eval 'sub GETNCNT {3;}';
    eval 'sub GETPID {4;}';
    eval 'sub GETVAL {5;}';
    eval 'sub GETALL {6;}';
    eval 'sub GETZCNT {7;}';
    eval 'sub SETVAL {8;}';
    eval 'sub SETALL {9;}';
#    if (defined( &_KERNEL) || defined( &_KMEMUSER)) {
#	require 'sys/t_lock.ph';
#    }
#    else {
#    }
#    if (defined( &__EXTENSIONS__) || !defined( &_XOPEN_SOURCE)) {
#    }
#    if (!defined( &_KERNEL)) {
#	if (defined( &__STDC__)) {
#	}
#	else {
#	}
#    }
#    if (defined &_KERNEL) {
#    }
#    if (defined &__cplusplus) {
#    }
}
1;
