#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

#if defined(__linux__)
#include <sched.h>
#include <sys/mount.h>
#include <sys/syscall.h>
#include <sys/prctl.h>

static int pivot_root_syscall(const char *new_root, const char *put_old) {
    return syscall(SYS_pivot_root, new_root, put_old);
}

int run_linux_isolate(const char *rootfs, const char *hostname, char *const argv[]) {
    // Unshare mount, uts, ipc, pid
    int flags = CLONE_NEWNS | CLONE_NEWUTS | CLONE_NEWIPC | CLONE_NEWPID;
    if (unshare(flags) != 0) {
        perror("conduit-shim: unshare failed");
        return 1;
    }

    // Set container hostname
    if (hostname && sethostname(hostname, strlen(hostname)) != 0) {
        perror("conduit-shim: sethostname failed");
    }

    // Change rootfs
    if (rootfs) {
        // Change root directory
        if (chroot(rootfs) != 0) {
            perror("conduit-shim: chroot failed");
            return 1;
        }
        if (chdir("/") != 0) {
            perror("conduit-shim: chdir failed");
            return 1;
        }
    }

    // Die if parent dies
    prctl(PR_SET_PDEATHSIG, 9);

    execvp(argv[0], argv);
    perror("conduit-shim: execvp failed");
    return 127;
}

#else

int run_linux_isolate(const char *rootfs, const char *hostname, char *const argv[]) {
    (void)rootfs;
    (void)hostname;
    (void)argv;
    fprintf(stderr, "conduit-shim: linux namespace isolation is only supported on Linux kernels\n");
    return 1;
}

#endif
