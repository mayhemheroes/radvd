// OSS-Fuzz harness for radvd's config parser (projects/radvd/fuzz_config.c),
// ported for Mayhem. readin_config() only takes a file path, so the input is
// staged to a temp file under /dev/shm — the only writable path while Mayhem
// collects coverage (the image, including /tmp, is mounted read-only).

#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/ip6.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "radvd.h"

// Mock functions needed for linking
int sock = -1;

int LL_DEBUG_LOG = 0;
int log_method = L_STDERR;
char *conf_file = NULL;
char *pname = "fuzz_config";

// Mock logging functions to avoid cluttering output
void dlog(int level, int flevel, char const *fmt, ...) {}
void flog(int level, char const *fmt, ...) {}
void set_debuglevel(int level) {}
int get_debuglevel(void) { return 0; }

struct Interface *readin_config(char const *path);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    char filename[] = "/dev/shm/fuzz-config-XXXXXX";
    int fd = mkstemp(filename);
    if (fd < 0) {
        return 0;
    }
    write(fd, data, size);
    close(fd);

    struct Interface *ifaces = readin_config(filename);

    if (ifaces) {
        free_ifaces(ifaces);
    }

    unlink(filename);
    return 0;
}
