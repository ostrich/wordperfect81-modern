/*
 * Corel WordPerfect 8 for Linux crashes in the old libc5 startup path on a
 * modern host before application code runs. Replacing this early hook with a
 * no-op is enough to let the binary continue to normal startup.
 */
void __libc_init(int argc, char **argv, char **envp) {
  (void)argc;
  (void)argv;
  (void)envp;
}
