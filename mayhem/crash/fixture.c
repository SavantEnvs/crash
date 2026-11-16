/* Namelist stand-in for crash: an ET_EXEC x86_64 ELF with DWARF type info for struct task_struct,
   which is all crash --minimal needs from a "kernel" before it opens the dump file. */
struct task_struct {
	int pid;
	long state;
	char comm[16];
};

struct task_struct init_task = { 0, 0, "swapper/0" };
const char linux_banner[] = "Linux version 5.14.0 (mayhem@fixture) #1 SMP";

int main(void) { return 0; }
