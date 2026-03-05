# Reference: ps2xRuntime & C++ Implementation
> Use this when working in the `ps2xRuntime` directory, fixing syscalls, writing stubs, or writing Game Overrides.

The `ps2xRuntime` library is the environment executing the generated C++ code. It provides the memory model, CPU context, MMIO routing, and native SDK implementations.

## 1. The Core Loop
The execution of the game begins and remains in a very tight, highly optimized loop.
When `jal` instructions are encountered in MIPS, the generated code uses a table lookup to call the corresponding C++ function pointer. 

## 2. Memory Model
The PS2 has 32MB of main RAM starting at `0x00000000`.
In `ps2xRuntime`, memory is generally handled as a large flat `uint8_t` array.
*Crucial*: Because PS2 games assume physical memory maps, the runtime traps reads/writes to specific ranges and routes them. Let's look at MMIO routing:

### MMIO (Memory Mapped I/O)
When the game tries to read or write to addresses like `0x10000000` (IOP) or `0x12000000` (GS), normal memory access would segfault or return garbage.
The runtime handles these through explicit getters/setters in the `R5900Context` or macro-inlined memory accesses.

## 3. Syscalls (System Calls)
A `SYSCALL` instruction jumps to the BIOS exception handler. Sony provides hundreds of syscalls for threading, semaphores, interrupt handlers, and hardware initialization.
**File:** `ps2xRuntime/src/lib/ps2_syscalls.cpp`

If a game executes an unimplemented syscall, the runtime prints `[Syscall TODO]` and usually crashes. 
*Fixing it:*
1. Identify the Syscall ID from the log (e.g., `Syscall 0x02 executing`).
2. Search online (ps2dev documentation) or the hardware bible to see what Syscall `0x02` is (`GsPutDrawEnv`).
3. Add a case statement in `ps2_syscalls.cpp` handler switch.
4. Implement the logic, reading arguments from `ctx.gpr[4]` (a0), `ctx.gpr[5]` (a1), etc.

## 4. Writing C++ Stubs
When you bind an address in `game.toml` to a `handler`, you must implement that handler in C++.

### The Triage Strategy
When reverse engineering stripped games, you'll encounter hundreds of `Warning: Unimplemented PS2 stub called`. 
Instead of writing real implementations immediately, we create "Triage Stubs":
```cpp
void ret0(R5900Context& ctx) { ctx.gpr[2].words[0] = 0; } // Returns 0
void ret1(R5900Context& ctx) { ctx.gpr[2].words[0] = 1; } // Returns 1
void reta0(R5900Context& ctx) { ctx.gpr[2].words[0] = ctx.gpr[4].words[0]; } // Returns Arg0
```
Try binding unknown functions to `ret0` or `ret1`. Does the game boot further? If so, you've bypassed a check. You can figure out *what* check it was later using Ghidra.

### Writing Real Implementations (`sceCdRead` example)
When you know what a function does, emulate it natively. Example: intercepting a CD-ROM texture load.
```cpp
void my_sceCdRead(R5900Context& ctx) {
    uint32_t lsn = ctx.gpr[4].words[0]; // a0: Logical Sector Number
    uint32_t sectors = ctx.gpr[5].words[0]; // a1: Number of sectors
    uint32_t buffer_ptr = ctx.gpr[6].words[0]; // a2: Destination address in EE RAM

    // Native C++ logic to read from PC file system instead of PS2 DVD...
    // MyFileSystem::Read(lsn, sectors, memory.GetPointer(buffer_ptr));

    ctx.gpr[2].words[0] = 1; // Return 1 (success)
}
```

## 5. Game Overrides (`Game_Overrides.txt` concept)
You should keep game-specific hacks *out* of the core `ps2_syscalls.cpp` or generic SDK headers to avoid breaking other games.

Instead, create a C++ file for the specific game (e.g. `swe3_overrides.cpp` in `ps2xRuntime/src/runner/`).
Register your overrides against the game's ELF metadata (basename, entry, crc32).

**The API:**
```cpp
#include "game_overrides.h"
#include "ps2_runtime.h"

namespace {
    void applyMyGameOverrides(PS2Runtime &runtime) {
        // Direct bind to existing stub/handler
        ps2_game_overrides::bindAddressHandler(runtime, 0x00123456u, "sceCdRead");
        
        // Custom implementation wrapper
        runtime.registerFunction(0x001D9410u,
            [](uint8_t *rdram, R5900Context *ctx, PS2Runtime *rt) {
                const uint32_t entryPc = ctx->pc;
                // do stuff
                ctx->gpr[2].words[0] = 0; // return 0
                
                // CRITICAL SAFETY FOR RAW WRAPPERS:
                if (ctx->pc == entryPc) {
                    ctx->pc = getRegU32(ctx, 31); // advance PC via ra
                }
            });
    }
}

PS2_REGISTER_GAME_OVERRIDE(
    "my-game-us",      // name
    "SLUS_XXXX.XX",    // elfName
    0x00100008u,       // entry point (0 avoids match)
    0u,                // crc32 (0 avoids match)
    applyMyGameOverrides
);
```
> **CRITICAL WARNING:** When using `bindAddressHandler(...)`, if the backend raw handler doesn't naturally advance `ctx->pc` (like many simple hooks), it will infinitely loop re-dispatching the exact same PC. If that happens, use `runtime.registerFunction` and advance the PC manually using `getRegU32(ctx, 31)` (the return address)!

## 6. Vectorization and SIMD Intrinsics
PS2 math relies heavily on 128-bit vectorization.
The runtime expects heavy use of SSE/AVX intrinsics (`_mm_add_epi32`, `_mm_mul_ps`) when manually replacing VU0/MMI geometry calculations. Do NOT write naive scalar loops for math-heavy stubs; it will destroy frame rates.
