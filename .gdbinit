set substitute-path kernel sources/zinnia/kernel
file build-x86_64/builds/zinnia/x86_64-kernel/release/zinnia.kso -o 0xffffffff80000000
target remote :1234
