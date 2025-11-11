set substitute-path kernel sources/menix/kernel
file build-x86_64/builds/menix/x86_64-kernel/release/menix.kso -o 0xffffffff80000000
target remote :1234
