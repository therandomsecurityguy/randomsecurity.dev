---
author: = "dc"
title: "Secure Memory Encryption Testing"
date: 2020-12-14T13:45:18-06:00
tags: ["Hardware", "Encryption", "Memory", "Data Center", "C"]
---

Earlier this year, I presented at the [Linux Security Summit](https://www.youtube.com/watch?v=ubTDZ7w4l_8) on how we've implemented secure memory encryption within our AMD EPYC edge machines. Enabling this feature is something that is fairly easy to do, but testing that it works was something that I briefly discussed during the presentation, but also something that I want to elaborate on further here. Before I get into the actual test, I'll give a brief overview of what memory encryption is doing in the background.

## Secure Memory Encryption

Secure memory encryption (SME) works by marking individual pages of memory as encrypted using standard x86 page tables. A page that is marked encrypted will be automatically decrypted when read from DRAM and encrypted when written to DRAM. Hardware-wise, this is achieved via an on-die 32-bit ARM Cortex A5 CPU that provides cryptographic functionality for secure key generation/key management and an inline (memory controller) encryption engine that is responsible for encryption/decryption.

### How It works

SME requires enabling a model specific register, which is a control register responsible for executing x86 instruction sets, `MSR 0xC001_0010[SMEE]`. This enables the ability to set a page table entry encryption bit.

* 0 = memory encryption features are disabled
* 1 = memory encryption features are enabled

Support for SME can be determined through the `0x8000001f` CPUID function. Bit 0 indicates support for SME.

### Validating

You can validate that SME is active through the `dmesg` output at boot:
```
randsec@amdtest:~$ sudo dmesg | grep SME
[    2.884688] AMD Secure Memory Encryption (SME) active
```
You can view the EAX register contents using the `cpuid` utility to show support for the instruction in processor:

```
randsec@amdtest:~$ sudo cpuid -r -1 -l 0x8000001f
CPU:
   0x8000001f 0x00: eax=0x0001000f ebx=0x0000016f ecx=0x000001fd edx=0x00000001
```

And validate that bit 23 in the MSR is present:

```
randsec@amdtest:~$ sudo modprobe msr
randsec@amdtest::~$ sudo rdmsr 0xC0010010
f40000
```

Passing the `mem_encrypt=on` argument via kernel command line at boot will enable SME. To enable SME transparently, unbeknownst to the operating system, you can enable Transparent Secure Memory Encryption (TSME) in your BIOS (provided the flag is enabled):

![](/images/tsme-enabled.png)

With memory encryption enabled, we test...

## Testing

The following test uses regular SME and a kernel module that does the following:

* Allocates a page of memory
* Zeros out the allocated memory
* Issues `set_memory_decrypted()`` call against allocated memory
* Checks if the allocated memory is still zeros:
  - If SME is enabled, memory will still be zeros
  - If SME is disabled, memory will not be zeros

`set_memory_decrypted()`` is called to remove the encryption bit associated with the buffer under test. This will not actually decrypt the contents of the memory buffer, but will just mark it as not encrypted. This can then be used to compare against the reference buffer and determine the state of secure memory encryption.

```
root@amdtest:/home/randomsec/sme-test# insmod ./secure-mem-encrypt-test.ko
insmod: ERROR: could not insert module ./secure-mem-encrypt-test.ko: Resource temporarily unavailable
```

Loading the kernel module will fail intentionally so that the module doesn’t have to be unloaded before re-running the test.

```
root@amdtest:/home/randomsec/sme-test# dmesg
[16213.377907] Memory Encryption: SME is active
[16213.390866] Memory Encryption: Buffer (first 64 bytes -    C-bit): 00000000: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
[16213.390867] Memory Encryption: Buffer (first 64 bytes -    C-bit): 00000010: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
[16213.390868] Memory Encryption: Buffer (first 64 bytes -    C-bit): 00000020: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
[16213.390869] Memory Encryption: Buffer (first 64 bytes -    C-bit): 00000030: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................
[16213.390986] Memory Encryption: Buffer (first 64 bytes - no C-bit): 00000000: 17 b7 88 17 04 00 b8 cc 16 fe 94 e4 8b 6a ce e1  .............j..
[16213.390987] Memory Encryption: Buffer (first 64 bytes - no C-bit): 00000010: ff 00 52 41 51 c9 01 82 cc 36 6e e1 94 69 5a ad  ..RAQ....6n..iZ.
[16213.390987] Memory Encryption: Buffer (first 64 bytes - no C-bit): 00000020: bc 1c fe 29 b0 11 ae 03 a4 e2 d0 2b 06 44 27 e6  ...).......+.D'.
[16213.390988] Memory Encryption: Buffer (first 64 bytes - no C-bit): 00000030: e5 dc 17 9c bd 00 01 77 f4 b7 78 40 f1 11 71 3d  .......w..x@..q=
[16213.390988] Memory Encryption: SME is not active
```

Even with the module failure, we can see the contents of the memory buffer. We can view the module output to console, where we can see the print out of the hex dump. The print out shows the beginning of the buffer before the call to `set_memory_decrypted()` (that checks buffer, buffer reference, and page size is still set to 0) and after (where the buffers do not match).

## References

[https://www.kernel.org/doc/html/latest/x86/amd-memory-encryption.html](https://www.kernel.org/doc/html/latest/x86/amd-memory-encryption.html)

## Code

Kernel module used for testing can be found below:

[https://github.com/therandomsecurityguy/secure-memory-encryption-test](https://github.com/therandomsecurityguy/secure-memory-encryption-test)
