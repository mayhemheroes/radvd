/* Baked-in ASan defaults for the fuzz binaries. STRONG symbol on purpose: a weak
 * definition loses to the sanitizer runtime's own default, LSan then aborts under
 * Mayhem's ptrace-based coverage tracer (one tracer per process) and every input
 * exits 1 before an edge is recorded. Leak detection is useless for fuzzing anyway. */
const char *__asan_default_options(void) { return "detect_leaks=0"; }
const char *__lsan_default_options(void) { return "detect_leaks=0"; }
