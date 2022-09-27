#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <sys/select.h>
#include <termios.h>

#if defined(__APPLE__)
#include <util.h>
#elif defined(__linux__)
#include <pty.h>
#endif

static struct termios orig_termios;
static int raw_mode_active = 0;
static pid_t child_pid = -1;
static int master_fd = -1;

static void restore_terminal(void) {
    if (raw_mode_active) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
        raw_mode_active = 0;
    }
}

static void sigwinch_handler(int sig) {
    (void)sig;
    if (master_fd >= 0) {
        struct winsize ws;
        if (ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) >= 0) {
            ioctl(master_fd, TIOCSWINSZ, &ws);
        }
    }
}

static void sigchld_handler(int sig) {
    (void)sig;
    int status;
    while (waitpid(-1, &status, WNOHANG) > 0) {}
}

int run_pty_bridge(char *const argv[]) {
    struct winsize ws;
    struct winsize *ws_ptr = NULL;

    if (isatty(STDIN_FILENO)) {
        if (tcgetattr(STDIN_FILENO, &orig_termios) == 0) {
            struct termios raw = orig_termios;
            cfmakeraw(&raw);
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
            raw_mode_active = 1;
            atexit(restore_terminal);
        }
        if (ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) >= 0) {
            ws_ptr = &ws;
        }
    }

    signal(SIGWINCH, sigwinch_handler);
    signal(SIGCHLD, sigchld_handler);

    child_pid = forkpty(&master_fd, NULL, NULL, ws_ptr);
    if (child_pid < 0) {
        restore_terminal();
        perror("conduit-shim: forkpty failed");
        return 1;
    }

    if (child_pid == 0) {
        // In child process
        execvp(argv[0], argv);
        perror("conduit-shim: execvp failed in child");
        _exit(127);
    }

    // In parent process: bidirectional pump between STDIN/STDOUT and master_fd
    fd_set read_fds;
    char buffer[4096];
    ssize_t nbytes;

    while (1) {
        FD_ZERO(&read_fds);
        FD_SET(STDIN_FILENO, &read_fds);
        FD_SET(master_fd, &read_fds);

        int max_fd = (STDIN_FILENO > master_fd) ? STDIN_FILENO : master_fd;
        int activity = select(max_fd + 1, &read_fds, NULL, NULL, NULL);

        if (activity < 0) {
            if (errno == EINTR) continue;
            break;
        }

        if (FD_ISSET(STDIN_FILENO, &read_fds)) {
            nbytes = read(STDIN_FILENO, buffer, sizeof(buffer));
            if (nbytes <= 0) break;
            if (write(master_fd, buffer, (size_t)nbytes) < 0) break;
        }

        if (FD_ISSET(master_fd, &read_fds)) {
            nbytes = read(master_fd, buffer, sizeof(buffer));
            if (nbytes <= 0) break;
            if (write(STDOUT_FILENO, buffer, (size_t)nbytes) < 0) break;
        }
    }

    restore_terminal();
    int status = 0;
    waitpid(child_pid, &status, 0);

    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return 0;
}
