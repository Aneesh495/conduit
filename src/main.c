#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern int run_pty_bridge(char *const argv[]);
extern int run_linux_isolate(const char *rootfs, const char *hostname, char *const argv[]);
extern int cgroup_attach_pid(const char *cgroup_path, int pid);
extern int cgroup_write_file(const char *cgroup_path, const char *filename, const char *value);

static void print_usage(const char *prog) {
    fprintf(stderr, "Usage: %s <subcommand> [args...]\n", prog);
    fprintf(stderr, "Subcommands:\n");
    fprintf(stderr, "  pty <command...>\n");
    fprintf(stderr, "  isolate --rootfs <dir> --hostname <name> [--] <command...>\n");
    fprintf(stderr, "  cgroup-attach <cgroup_path> <pid>\n");
    fprintf(stderr, "  cgroup-limit <cgroup_path> <control_file> <value>\n");
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    const char *subcmd = argv[1];

    if (strcmp(subcmd, "pty") == 0) {
        if (argc < 3) {
            fprintf(stderr, "error: pty subcommand requires a target executable\n");
            return 1;
        }
        return run_pty_bridge(&argv[2]);
    } else if (strcmp(subcmd, "isolate") == 0) {
        const char *rootfs = NULL;
        const char *hostname = "conduit";
        int cmd_idx = -1;

        for (int i = 2; i < argc; i++) {
            if (strcmp(argv[i], "--rootfs") == 0 && i + 1 < argc) {
                rootfs = argv[++i];
            } else if (strcmp(argv[i], "--hostname") == 0 && i + 1 < argc) {
                hostname = argv[++i];
            } else if (strcmp(argv[i], "--") == 0 && i + 1 < argc) {
                cmd_idx = i + 1;
                break;
            } else if (argv[i][0] != '-') {
                cmd_idx = i;
                break;
            }
        }

        if (cmd_idx < 0) {
            fprintf(stderr, "error: isolate subcommand requires a target command\n");
            return 1;
        }

        return run_linux_isolate(rootfs, hostname, &argv[cmd_idx]);
    } else if (strcmp(subcmd, "cgroup-attach") == 0) {
        if (argc < 4) {
            fprintf(stderr, "error: cgroup-attach requires <path> <pid>\n");
            return 1;
        }
        return cgroup_attach_pid(argv[2], atoi(argv[3]));
    } else if (strcmp(subcmd, "cgroup-limit") == 0) {
        if (argc < 5) {
            fprintf(stderr, "error: cgroup-limit requires <path> <file> <val>\n");
            return 1;
        }
        return cgroup_write_file(argv[2], argv[3], argv[4]);
    } else {
        fprintf(stderr, "error: unknown subcommand '%s'\n", subcmd);
        print_usage(argv[0]);
        return 1;
    }
}
