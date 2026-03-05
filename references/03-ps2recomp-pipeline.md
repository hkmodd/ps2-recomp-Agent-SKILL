# Reference: The PS2Recomp Pipeline & TOML Config
> Use this when working with the analyzer, editing the `game.toml`, or running the recompiler.

The PS2Recomp project functions via a 3-stage pipeline: **Analyzer** -> **Recompiler** -> **Runtime**.

## 1. ps2_analyzer
The analyzer takes a PS2 ELF (and optional Ghidra CSV) and outputs a `game.toml` configuration file.
**Goal:** Identify boundaries for every function in the executable to feed into the recompiler.

### Operation Modes
1. **With Symbols (DWARF):** Ideal. Perfect boundaries and function names.
2. **Stripped (No Symbols):** Uses a native heuristic `jal` scanner. Fast, but often misses boundaries due to compiler optimizations or anti-reversing.
3. **Ghidra Feed:** For complex/protected games, analyze in Ghidra and export the CSV map using `ps2xRecomp/tools/ghidra/ExportPS2Functions.py`, then pass it via `[general] ghidra_output`.

### The Multi-Binary TOML Challenge
When a game uses a tiny launcher ELF and a massive `.BIN` core (like SW Ep 3), you **do not** put everything in one `game.toml`.
1. The launcher `SLES/SLUS` gets its own `launcher.toml`.
2. The extracted `.BIN` (once converted to an ELF structure for analysis) gets its own `core.toml`.
3. You will run `ps2_analyzer` and `ps2_recomp` *twice*, generating two distinct sets of C++ files that must be compiled together into the runtime!

*CLI Usage:*
`./build/Debug/ps2_analyzer.exe "path/to/game.elf" "base_config.toml"`

## 2. The TOML Configuration (`game.toml`)

The TOML file dictates exactly how `ps2_recomp` will translate the MIPS binary to C++.

### `[general]` Section
```toml
[general]
input = "path/to/game.elf"                # Mandatory: Path to input ELF
output = "output/"                        # Mandatory: Directory for generated C++
runtime_header = "Runtime.h"              # Header to include in generated files
code_base = 0x00100000                    # Address where code is mapped
single_file_output = false                # Set to true to speed up compilation for testing
```

### Stubs and Skips (Flat Arrays)
"Stubs" are functions the recompiler will **NOT** translate. It generates small wrapper functions that route to known runtime handlers.
"Skips" are functions to actively ignore. The recompiler treats them as intentionally unsupported and generates explicit placeholders like `ps2_stubs::TODO_NAMED("FunctionName")` returning an error-like value.
```toml
stubs = [
  "printf",
  "sceCdRead@0x00115000",   # Binds address to handler "sceCdRead"
  "ret1@0x00115500",        # Triage binding: return 1 (success)
]

skip = [
  "sub_00100008",           # Skip crt0 bootstrapper
]
```

### `[patches]` Section
Patches replace specific MIPS instructions with other MIPS instructions *before* recompilation. Easiest way to break an infinite spinlock waiting on unsupported hardware.
```toml
[patches]
instructions = [
  { address = "0x100004", value = "0x00000000" }, # Replace instruction with 'nop'
]
```

## 3. ps2_recomp
Translates the ELF into C++ code using the rules from the TOML.

*CLI Usage:*
`./build/Debug/ps2recomp.exe config.toml`

**What it generates:**
- A massive folder full of `out_xxxxx.cpp` files.
- Each MIPS function becomes a C++ function taking `R5900Context& ctx`.
- *Example Translation:*
  ```cpp
  // original: add $v0, $a0, $a1
  void sub_100050(R5900Context& ctx) {
      ctx.gpr[2].words[0] = ctx.gpr[4].words[0] + ctx.gpr[5].words[0];
  }
  ```

**The "Unhandled Opcode" Problem:**
If the recompiler hits an instruction it doesn't know how to translate (like complex COP2 macro math or weird MMI sequences), it writes a comment inside the generated C++ function:
`// Unhandled opcode at 0x123456: blah`
If execution hits this code path, the program will likely crash or behave incorrectly. These must be implemented manually via C++ Game Overrides.

*Agent Action:* You must scan the generated C++ directory for `// Unhandled opcode` and log every single occurrence in the `PS2_PROJECT_STATE.md` under **Unhandled Opcodes** before attempting to build.

## 4. Build Toolchain Optimization (CRITICAL)

PS2Recomp generates **thousands** of C++ files (29,000+ for large games). The build toolchain choice is **not optional**:

| Toolchain            | Generator                    | Approx. Full Build Time | Status                                                   |
| -------------------- | ---------------------------- | ----------------------- | -------------------------------------------------------- |
| **Clang-CL + Ninja** | `-G Ninja` + clang-cl        | **~1 hour**             | ⚡ **MANDATORY**                                          |
| MSVC + Ninja         | `-G Ninja`                   | ~3-5 hours              | ⚠️ Acceptable only temporarily                            |
| MSVC + VS Solution   | `-G "Visual Studio 17 2022"` | ~20-25 hours            | ❌ **FORBIDDEN** — `build_daemon.ps1` refuses this config |

### How to Install Clang + Ninja (via Visual Studio Installer)
1. Open **Visual Studio Installer** → Modify your VS 2022 installation.
2. Go to the **Individual Components** tab.
3. Search for and enable:
   - `C++ Clang Compiler for Windows`
   - `C++ CMake tools for Windows` (includes Ninja)
4. Click **Modify** and wait for installation.
5. Restart your terminal. `clang-cl --version` and `ninja --version` should both work.

### CMakeLists.txt Surgery (MANDATORY for Clang compatibility)
> **⚠️ HUMAN-IN-THE-LOOP REQUIRED:** The agent MUST explain the exact changes below to the user and **ask for permission** before modifying `CMakeLists.txt`.

Before building with Clang, the agent must inspect `ps2xRuntime/CMakeLists.txt` and perform these two operations:

**OPERATION A — SSE4.1 Hardware Flag Injection:**
Find the line `add_compile_definitions(USE_SSE41=ON)` and add immediately BELOW it:
```cmake
add_compile_options(-msse4.1)
```
*Why:* `add_compile_definitions` only defines a preprocessor macro. MSVC implicitly supports SSE4.1 on x64, but Clang requires the explicit `-msse4.1` flag or it will error on intrinsics like `_mm_extract_epi32`.

**OPERATION B — Unity Build & MSVC Flag Removal:**
Search for and DELETE this entire block from the `ps2EntryRunner` target (if present):
```cmake
set_target_properties(ps2EntryRunner PROPERTIES UNITY_BUILD ON UNITY_BUILD_BATCH_SIZE 16)
if(MSVC)
    target_compile_options(ps2EntryRunner PRIVATE /FS /Z7 /MP /bigobj)
endif()
```
*Why:* Unity Build merges .cpp files into combined translation units — counterproductive with Ninja's native parallelism across 29,000 files. The `/FS /Z7 /MP /bigobj` flags are MSVC-only and will cause errors with Clang.

### CMake Configuration & Build Commands
```powershell
# STEP 1: Delete any old build directory (critical if switching generators!)
# ⚠️ HITL REQUIRED: The agent MUST ask the user for permission before deleting the build/ folder.
Remove-Item -Recurse -Force .\ps2xRuntime\build

# STEP 2: Configure with Clang + Ninja (inside vcvars64.bat environment)
cmake -B build -G Ninja -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl -DCMAKE_BUILD_TYPE=Release

# STEP 3: Build with parallel threads (leave 2 cores free to prevent system freeze)
cmake --build build -j $([Environment]::ProcessorCount - 2)
```

> **IMPORTANT:** With Ninja (single-config generator), build type is set at CONFIGURE time via `-DCMAKE_BUILD_TYPE=Release`, NOT at build time via `--config`. This is different from VS Solution generators.

### The `build_daemon.ps1` Script
The `build_daemon.ps1` script handles all of the above automatically:
- Locates `vcvars64.bat` dynamically via `vswhere.exe`
- Verifies Clang-CL + Ninja are both present (REFUSES to proceed otherwise)
- Configures with Ninja + clang-cl if no `build/` directory exists
- The agent must still perform the CMakeLists.txt Surgery (Operations A and B) ONCE before the first build

