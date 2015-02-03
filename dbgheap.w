Catching memory overwrites
  dbgheap1.cpp
  Finding bugs with a debugger
  Finding bugs without the debugger
    mapfilt.exe
Making a better bug-trap
  heap errors
    double-deletes
    delete uninitialized pointers
    accessing deleted memory
    memory leaks
    malloc+free+realloc/new+delete/new[]+delete[]
    multiple heaps
  tracing callers
  tracing

Statistic
Conclusion


[figure:membug.gif]
1:Hunting memory bugs
Have you ever hunted a memory overwrite bug? If you have you know how hard they
can be to track down. Every programmers nightmare is when such a bug suddenly
creps up in a large project.

The runtime libraries included with most compilers include a debug-version of
the heap management functions but they usually first detect the overwrite after
it has happened. Would it not be nice if you could detect the overwrite when it
happens?

In the following sections I will implement a complete debugging/tracing library
which will significantly reduce the time you spend tracing heap management bugs.
I will not tell you how to avoid heap errors only how to detect and find them.

Note: I primarily use Watcom C/C++, but the tools have also been tested with
VAC++ 3.0. The sources may contain information on what you have to do and/or
change if you use VAC++. All sources should be easy to adapt to other compilers
(BC/2, EMX, Metaware...)

2:Catching memory overwrites
OS/2 implements protection of the memory. An example is that writing to an area
containing the code for the program will trap. eg:
code:
void foo() {
  ...
}
...
char *p=(char*)foo;
strcpy(p,"hello world");
:ecode
This code will trap due to OS/2's memory protection. The area where the code is
is marked as read-only/execute-only.

OS/2 has an API to allocate and deallocate memory (DosAllocMem()/DosFreeMem()),
but also an API to change the protection of a memory block: DosSetMem(). The
protection (or "attributes") can be set individually for each page. A page is
4K.

The most common form of memory overwrite is to allocate too few bytes, usually
due to an off-by-one error, eg:
code:
char *p=(char)malloc(11);
strcpy(p,"hello world");
:ecode
This code allocates 10 bytes but puts a 12-byte string (remember the terminating
NUL) into it. The program may work, and worse: the program may crash several
hours later in a completly unrelated function.

By replacing the standard heap management functions with our own functions we
can take full control of how the memory is allocated.

I will only use three attributes of memory protection features: unknown,
committed and uncomitted.
 * unknown
 = If we have never allocated a page in any way the virtual addresses are
unknown. Accessing such a page causes a trap.
 * comitted
 = When a page is accessible (read/write) it is committed. Note: whether OS/2
really has reserved a physical piece of memory doesn't matter.
 * uncomitted (or "reserved")
 = It is also possible to only reserve range of virtual addresses without
physical memory being reserved. Accessing such a page causes a trap.

Now back to catching memory overwrites. If we could allocate exactly 11 bytes an
ensure that accessing memory outside the 11 bytes would cause a trap it would be
a lot easier to find where the memory overwrite happens.

This can be done without too much trouble. By reserving enough pages to hold the
requested number of bytes + 1 page and only committing the requested number of
bytes and returning a pointer into the area so that accesses beyond the
requested number of bytes cases a trap, we can catch memory overwrites in
seconds instead of hunting them for days.

[figure:membug1.gif]

Note that each allocation uses at least 8K address space and at least 4K memory.
Since OS/2 DosAllocMem() only allocates memory below 512MB you can only make
512MB/8K = 65536 allocations. It is even worse on some version of OS/2
(documentation says Warp3 and Warp4 server) where allocations reserves at least
64K address space (512M/64K = 8192 allocations). So if your program makes many
allocations it may run out of address space. But that way you can also examine
how well your program handles low memory conditions.

3:dbgheap1.cpp
The full source is in dbgheap1.cpp. dbgheap1.cpp implements replacements for
new/delete/new[]/delete[]/malloc/free/realloc/calloc that uses the mechanism
described in the previous section.

Here are a few highlights:
code:
struct chunk_header {
        unsigned chunk_size;            //# of comitted bytes
        unsigned block_size;            //heap block size (requested size)
        unsigned block_offset;          //offset from start of block to
user-)pointer
};
:ecode
Each chunk of memory starts with a chunk_header. The chunk header contains
information that we need when the chunk is to be DosFreeMem()'ed. It also
contains redundant information so we can check for overwrites of the
chunk_header.

Nexts comes a (maybe zero) number of bytes that are unused. These are filled
with FILL_BYTE (0xfe) so they can also be checked for overwrites.

Then comes the area where the 'user' memory is. It is positioned so that the end
of that area is aligned with the end of a page.

Then comes the important thing: an uncommitted page. If the program tries to use
more bytes that were allocated it will trap.

When the memory is to be freed, the freemem() first converts the "user"-pointer
(which points somewhere into a page) to a page-aligned pointer.

Then overwrite of the chunk_header is checked:
code:
if(chp->block_offset != chp->chunk_size-chp->block_size) {
        exit(0);
}
:ecode
Redundancy helps debugging.

Then the "user"-pointer is checked. We only accept the exact same pointer that
were returned from allocmem():
code:
if(p != pchunk+chp->block_offset) {
        exit(0);
}
:ecode

Then the unused area that (hopefully) contains FILL_BYTE is checked:
code:
for(unsigned char *checkp=((unsigned char*)pchunk)+sizeof(chunk_header);
    checkp<p;
    checkp++)
{
        if(*checkp != FILL_BYTE)
                exit(0);
}
:ecode

Then the standard heap management functions are replaced: new/delete,
new[]/delete[] and malloc/free/realloc/calloc. The replacements just calls
allocmem() / freemem(). (Except realloc() which is a bit more complicated)


The end of dbgheap1.cpp contains a test stub:
:code
int main() {
        char *p = new char[12];
        strcpy(p,"Hello world");                  //ok
        strcpy(p,"Hello my friend. What's your name?"); //error
        delete[] p;
        return 0;
}
:ecode
12 bytes are allocated. Then a 12-byte string is copied to the allocated memory.
This should work. Then a longer string is copied to the memory. This will cause
the program to trap when strcpy() crosses the page boundary and tries to write
to the uncommitted page.

Gotcha!

3:Finding bugs with a debugger
Try compiling dbgheap1.cpp and run the program from within you debugger.

When I do this using WDW (Watcoms debugger) it says: "A task exception has
occurred: general protection fault" and then it leaves me in an assembler view
of the naughty instruction in strcpy(). Knowing that strcpy() does not contain
the bug I then select to trace the call stack "Code|Calls". hmmm-hmmm-hmmm. It
seems that strcpy() was called from line 143 in main() in dbgheap1.cpp. What a
surprise :-)

3:Finding bugs without the debugger
What if you did not run the program from within you debugger?

OS/2 roughly says: "A program has generated bla bla bla...". Select "show help"
then it says:
code:
A program has generated a general protection fault at 0001041a
DBGHEAP1.EXE 0001:0000041a"
:ecode

This is usually not very helpful. But not any more. The program has accessed the
virtual address 0001041a. The code that did that was in DBGHEAP1.EXE, object
0001, offset 0000041a. Where is that?

When called within Watcoms IDE Watcom's linker by default generates a .MAP file
(wcl386 needs /fm). (VAC++ needs ICC /Fm or ILINK /MAP). This map file is
unsorted but is contains most of the information you need to pinpoint the error.

I have included a small program that extracts the interesting lines in Watcoms
.MAP file and sorts them by object+address (code for VAC++s' MAP files are
#ifdef'ed away) Try running:
code:
mapfilt dbgheap1.map map.tmp
:ecode

Now search for 0001:0000041a:
code:
0001:000003a0  exit_
0001:000003cc+ _exit_
0001:000003f1  memcpy_
0001:00000416  strcpy_
0001:00000436  _cstart_
:ecode

The error obviously occurred in the function strcpy_. So now you know that the
problem is a call to strcpy().

I will use the MAPFILT program later.

2:Making a better bug-trap
[figure:membug2.gif]
The program dbgheap1.cpp catches most memory overwrites. But what about other
bugs?

3:Classes of heap errors
There exists several bugs concerning heap management:
[To editor/converters: make the following a definition-list]
Double-free:
Sometimes the bug is that the program tries to free a memory block that has
already beed freed. The error can be the first free og the last free. If the
error is the first free we need some sort of history to find out who did that.

Freeing uninitialized pointers:
Sometimes a program tries to free memory using a pointer that has not been
assigned a value.

Accessing freed memory:
It is an error to access a memory block after it has freed. This can be
difficult to detect since the memory block may have been used again.

Memory leaks:
Not freeing memory but just "forgetting it" is sometimes acceptable in very
small programs (mapfilt.cpp is an example) but in programs that run for long
periods of time this can be a major trouble. Imagine if a server program leaked
10 byte for every file accesss. How long would it take before SWAPPER.DAT would
have grown to 200MB and the server had to be shut down? Not very long.

Mix of heap management functions:
Memory allocated with heap management (malloc/free/realloc) cannot be
deallocated with C++ heap management (new/delete) and vice versa. Moreover C++
single-object heap management (new/delete) cannot be mixed with C++ array heap
managment (new[]/delete[]).

Multiple heaps:
If you program consists of an .EXE and a .DLL, memory allocated in the DLL may
be in a different heap that memory allocated in the .EXE. Some compilers support
freeing what has been allocated in another module, but it is very bad pratice,
since this could change in the next version of compiler or by the way the
modules were linked.

By extending the capabilities of the debug-heap we can catch all these
hard-to-find bugs.

3:Tracing callers
As you may have noted in an earlier section trapping inside allocmem() or
freemem() is not very informative. It would be a big improvement if we knew who
called malloc/free/new/delete/...

This information is on the stack but it is extremely difficult to locate. It not
only depends on the compiler but also wether or not debugging information is
generated, which optimization level you are using and the version of the
compiler.

This can only be done 100% error-free in assembler.

This opens up another (but smaller) can of worms. Then we have to deal with name
decoration, calling conventions and mangled names. Furtunatly both Watcom and
VisualAge contains information on most of these questions. callpeek.asm
(callpeek.vac for VAC++) contains very simple implementations of
new/delete/malloc/... that simply grabs SS:[ESP] and jumps/calls to the real
procedure dbg_new/dbg_delete/dbg_malloc/... in dbgheap2.cpp

3:Tracing
In order to post-mortem find out why the debug-heap-management found an error
(and to create nifty things later on) the heap operations must be logged. I
decided to log to a named pipe \pipe\tracemon since gives flexibility later on.
tracemon.cpp implements a named-pipe server that simply writes whatever it gets
through the named pipe to a file and standard output.

dbgheap2.cpp logs several things:
[note to editor or converters: make the following a definition-list]
TID
Multi-threaded heap errors can be a lot tougher to track down than
single-threaded ones. Including the TID allows you to deect which thread
allocated the memory and which thread freed the memory.
Heap
In order to detect multiple-heaps errors the heap has to be logged. The heap
identification is simply the address of a static variable in dbgheap2. Since a
.EXE and a .DLL which both have dbgheap2.cpp linked in statically will have
separate static variables this is unique.
Operation
This can be malloc()/free()/new/delete/new[]/delete[].
Caller
This would also be nice.
Address range
This does not include the extra uncomitted page.
User pointer
The pointer that user-code sees/uses.
Size
The size of the allocation.

3:A few notes on dbgheap2.cpp
dbgheap2.cpp is derived from dbgheap1.cpp. These are the non-trivial changes:
 - The housekeeping structure chunk_header has been extended with two members:
mgrclass and heap to track management class and heap.
 - A set of logging functions: log_operation(), log_range(), log_norange(),
log_userptr(), log_operationfailure() and log_operationsuccess().
 - heap_panic (located in callpeek.asm) is called when a heap error is detected.
heap_panic() issues an interrupt 3 which gets the attention of the debugger if
the program has been run from within one, or causes OS/2 to display an error
message and terminate the program.
 - freemem() does not deallocate the memory any longer is just decommits it to
ensure that the memory is not reused and guarantees that "access to freed
memory"-errors cause a trap.


3:Testing
Create a program from callpeek.asm, dbgheap2.cpp and bugs.cpp. For instance:
code:
Watcom:
  wcl386 /s /fm bugs.cpp callpeek.asm dbgheap2.cpp
VAC++:
  alp callpeek.vac
  icc /Fm /B"NOE" bugs.cpp callpeek.obj dbgheap2.cpp
:ecode
Watcom needs to have stack checks turned off (/s), since malloc() is called
early in the initialization when the stack has not been completely initialized.
VAC++ linker (/B"/NOE") needs the /NOEXTDICTIONARY otherwise it complains about
duplicated symbols (malloc()/free()/...)

Note: you can change the #ifdefs in bugs.cpp to test each bug type.

Start tracemon:
code:
start /f tracemon
:ecode

Launch your debugger.

Start bugs.EXE

Just press 'GO'

TRAP!

Which kind of trap occurs and where the debugger leave you depends on the bug.

"double-free", "free uninitialized pointers", "Mix of heap management" and
"multiple heaps" is detected by dbgheap2.cpp and leaves you inside heap_panic().
Switch to tracemon.EXE (which you remembered to start, didn't you?) and read the
last message. Then let the debugger display the call stack.

"accessing deleted memory" and "memory overwrite" (past the end of the block)
causes an "access violation" trap where the bugs is.

"memory overwrite" (before the block) is detected when freemem() is called.

3:Memory leaks
Detecting memory leaks can only be done after the program has stopped. The
algorithm is simple: just find allocations that were not freed.

leakfind.cpp does exactly this.

Try changing bugs.cpp to use the "memory leak" portion. Compile and link
bugs.EXE, restart tracemon and run bugs.EXE.
After bugs.EXE has finished running the log should contain something like this
(expect the header):
code:
TID      Heap     op.      Caller   Range             Usrptr   Bytes
00000001 00020024 malloc() 00010c67 00080000-00080fff 00080ffc 00000004
00000001 00020024 malloc() 00010ca2 00090000-00090fff 00090fba 00000046
00000001 00020024 malloc() 0001139a 000a0000-000a0fff 000a0f60 000000a0
00000001 00020024 new[]    00010032 000b0000-000b0fff 000b0ff6 0000000a
00000001 00020024 new[]    0001003f 000c0000-000c0fff 000c0ff6 0000000a
00000001 00020024 delete[] 00010050 000b0000-000b0fff 000b0ff6 0000000a
:ecode
The leaks are easy to spot in this small log but for large logs they are not.

Run leakfind:
code:
leakfind tracemon.log
:ecode
and leakfind says:
code:
Leaks:
00000001 00020024 malloc() 00010c67 00080000-00080fff 00080ffc 00000004
00000001 00020024 malloc() 00010ca2 00090000-00090fff 00090fba 00000046
00000001 00020024 malloc() 0001139a 000a0000-000a0fff 000a0f60 000000a0
00000001 00020024 new[]    0001003f 000c0000-000c0fff 000c0ff6 0000000a
:ecode
The first three allocation are made by Watcoms runtime-library and there is
nothing we can do about them. The last one is more interesting. The caller is
0001003f. Knowing that Watcom puts code into object 0001 and that object 0001 is
loaded at 00010000 helps a lot. So the problem is at 0001:0000003f

Using mapfilt.exe bugs.map bugs.lst gives us this:
code:
0000:00001234  __DOSseg__
0001:00000003  ___begtext
0001:00000010  main_
0001:000007d0  dbg_new_
:ecode
The large gap between mail_ and dbg_new_ is consumed by static functions in
dbgheap2.cpp. Watcoms linker by default does not generate map entries for static
functions. But 0001:0000003f is suspiciously near main_. Let's have a look at
main() in bugs.cpp:
code:
void main(void) {
        char *p1=new char[10];
        char *p2=new char[10];
        *p2='\A';
        delete[] p1;
}
:ecode
Of course! p2 is not freed! What a surprise! <G>

2:Statistics
The log generated by dbgheap2.cpp can be used not only for debugging but also
performance tuning. heapstat.cpp generates a simple statistic. "heapstat
tracemon.log" gives a result like this:
code:
Heap statistics:
Size<=     Operations  Peak
         4          0      0
         8          0      0
        16          2      2
       256          1      1
      1024          1      1
      4096          3      3
     32768          0      0
     65536          0      0
4294967295          0      0
  Size  Count
     10     2
     39     1
    388     1
   4096     3
:ecode
heapstat.cpp tells you for some preselected values how many allocations there
were of that size and maximum number of allocation that were at any time. It
also shows size and count for individual sizes

This information can be used for performance tuning. Example 1: if there are
extremely many allocations of a particular (small) size, it may be worthwhile to
program a special-purpose allocator for that size. Example 2: If almost all
allocations are larger than 16384 bytes it might be faster to code your own
allocator that uses DosAllocMem() directly.

2:Conclusion
[figure:membug3.gif]
Good knowledge of what OS/2 can do combined with a few simple tools can be a
very powerful. In fact, the tools described in this article can do more than
most (all?) commercial heap-debug tools. And it's free!

What is missing? the capability to read debug-info to better pinpoint who called
malloc/new/delete/..., automating starting/stopping tracemon. ...ooh yes and a
sluggish GUI interface, limiting the tool to 1 or 2 compilers, a $600 bill and a
3-inch thick manual.

This is left as an exercise to the reader <G>

That's all folk.
