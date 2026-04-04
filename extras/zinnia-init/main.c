#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/module.h>
#include <sys/mount.h>
#include <sys/uio.h>
#include <unistd.h>

int main(int argc, char **argv, char **envp) {
  int e;

  insertmod("/usr/share/zinnia/modules/nvme.kso", NULL);
  insertmod("/usr/share/zinnia/modules/ext2.kso", NULL);

  printf("init: Mounting ext2 root partition on /realfs\n");

  // Mount the root partition
  // TODO: Don't use a fixed uuid for this.
  e = mount("ext2", "/realfs", 0,
            "/dev/parttype-0fc63daf-8483-4772-8e79-3d69d8477de4");
  if (e)
    return e;

  printf("init: Switching to new root\n");

  // Switch root
  e = chroot("/realfs");
  if (e)
    return e;
  e = chdir("/");

  printf("init: Mounting devtmpfs on /dev\n");

  // Mount devtmpfs
  e = mount("devtmpfs", "/dev", 0, NULL);
  if (e)
    return e;

  printf("init: Running init from disk\n");

  e = execve("/init", argv, envp);
  if (e) {
    perror("execve");
    return e;
  }

  return 1;
}
