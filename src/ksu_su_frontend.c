#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <unistd.h>

/* KernelSU v3.2.5 uapi/supercall.h. */
#define KSU_INSTALL_MAGIC1 0xDEADBEEF
#define KSU_INSTALL_MAGIC2 0xCAFEBABE
#define KSU_IOCTL_GRANT_ROOT _IOC(_IOC_NONE, 'K', 1, 0)

#define KSU_DAEMON_PATH "/data/adb/ksud"
#define KSU_FALLBACK_PATH "/data/local/tmp/ksud-b5q-kdp-v2"

extern char **environ;

static int grant_root(void) {
  int fd = -1;

  /* The reboot kprobe installs a cloexec KernelSU control fd on return. */
  (void)syscall(SYS_reboot, KSU_INSTALL_MAGIC1, KSU_INSTALL_MAGIC2, 0, &fd);
  if (fd < 0) {
    fprintf(stderr, "su: KernelSU control fd unavailable: %s\n",
            strerror(errno));
    return -1;
  }

  if (ioctl(fd, KSU_IOCTL_GRANT_ROOT, 0) < 0) {
    int saved_errno = errno;
    close(fd);
    errno = saved_errno;
    fprintf(stderr, "su: KernelSU denied root: %s\n", strerror(errno));
    return -1;
  }

  close(fd);
  return 0;
}

int main(int argc, char **argv) {
  (void)argc;

  if (getuid() != 0 && grant_root() != 0) {
    return 1;
  }

  /* ksud's complete su-compatible parser is selected by argv[0]. */
  argv[0] = "su";
  execve(KSU_DAEMON_PATH, argv, environ);

  /* Keep the per-firmware matched daemon usable if Manager refreshed ksud. */
  execve(KSU_FALLBACK_PATH, argv, environ);
  fprintf(stderr, "su: cannot execute KernelSU daemon: %s\n", strerror(errno));
  return 127;
}
