if (!defined &_SYS_IPC_H) {
    eval 'sub _SYS_IPC_H {1;}';
#    require 'sys/types.ph';
#    if (defined &__cplusplus) {
#    }
#    if (defined( &_KERNEL) || defined( &_KMEMUSER)) {
#    }
    eval 'sub IPC_ALLOC {0100000;}';
    eval 'sub IPC_CREAT {0001000;}';
    eval 'sub IPC_EXCL {0002000;}';
    eval 'sub IPC_NOWAIT {0004000;}';
#    eval 'sub IPC_PRIVATE {( &key_t)0;}';
    eval 'sub IPC_RMID {10;}';
    eval 'sub IPC_SET {11;}';
    eval 'sub IPC_STAT {12;}';
#    if (defined( &_KERNEL) || defined( &_KMEMUSER)) {
#	eval 'sub IPC_O_RMID {0;}';
#	eval 'sub IPC_O_SET {1;}';
#	eval 'sub IPC_O_STAT {2;}';
#    }
#    if (defined( &__STDC__) && !defined( &_KERNEL) && !defined( &_XOPEN_SOURCE)) {
#    }
#    if (defined( &_KERNEL)) {
#    }
#    if (defined &__cplusplus) {
#    }
}
1;
