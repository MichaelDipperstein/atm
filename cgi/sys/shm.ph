if (!defined &_SYS_SHM_H) {
    eval 'sub _SYS_SHM_H {1;}';
#    require 'sys/ipc.ph';
#    if (defined &__cplusplus) {
#    }
#    if ((defined( &_KERNEL) || defined( &_KMEMUSER))) {
#	eval 'sub SHMLBA { &PAGESIZE;}';
#    }
#    else {
#	require 'sys/unistd.ph';
#	eval 'sub SHMLBA {( &_sysconf( &_SC_PAGESIZE));}';
#    }
    eval 'sub SHM_R {0400;}';
    eval 'sub SHM_W {0200;}';
    eval 'sub SHM_RDONLY {010000;}';
    eval 'sub SHM_RND {020000;}';
    eval 'sub SHM_SHARE_MMU {040000;}';
#    if (defined( &_KERNEL) || defined( &_KMEMUSER)) {
#	require 'sys/t_lock.ph';
#    }
#    else {
#	if (defined( &_XOPEN_SOURCE)) {
#	}
#	else {
#	}
#    }
#    if (defined( &__EXTENSIONS__) || (!defined( &_POSIX_C_SOURCE) && !defined( &_XOPEN_SOURCE))) {
#    }
    eval 'sub SHM_LOCK {3;}';
    eval 'sub SHM_UNLOCK {4;}';
#    if (defined( &_KERNEL)) {
#    }
#    else {
#	if (defined( &__STDC__)) {
#	    if (defined( &_XOPEN_SOURCE) && ((defined(&_XOPEN_VERSION) ? &_XOPEN_VERSION : 0) - 0 == 4)) {
#	    }
#	    else {
#	    }
#	}
#	else {
#	}
#    }
#    if (defined( &__EXTENSIONS__) || (!defined( &_POSIX_C_SOURCE) && !defined( &_XOPEN_SOURCE))) {
#    }
#    if (defined &_KERNEL) {
#    }
#    if (defined &__cplusplus) {
#    }
}
1;
