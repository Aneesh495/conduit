#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

int cgroup_write_file(const char *cgroup_path, const char *filename, const char *value) {
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", cgroup_path, filename);

    int fd = open(path, O_WRONLY | O_TRUNC);
    if (fd < 0) {
        return -1;
    }

    ssize_t len = (ssize_t)strlen(value);
    ssize_t written = write(fd, value, (size_t)len);
    close(fd);

    return (written == len) ? 0 : -1;
}

int cgroup_attach_pid(const char *cgroup_path, pid_t pid) {
    char pid_str[32];
    snprintf(pid_str, sizeof(pid_str), "%d\n", (int)pid);
    return cgroup_write_file(cgroup_path, "cgroup.procs", pid_str);
}
