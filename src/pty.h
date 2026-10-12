#ifndef PTY_C_H
#define PTY_C_H

#include <fcntl.h>
#include <stdlib.h>

int posix_openpt(int flags);
int grantpt(int fd);
int unlockpt(int fd);

#endif
