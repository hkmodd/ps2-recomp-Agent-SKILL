# Reference: The PS2Recomp Pipeline & TOML Config
> Use this when working with the analyzer, editing the `game.toml`, or running the recompiler.

The PS2Recomp project functions via a 3-stage pipeline: **Analyzer** -> **Recompiler** -> **Runtime**.

## 1. ps2_analyzer
The analyzer takes a PS2 ELF (and optional Ghidra CSV) and outputs a `game.toml` configuration file.
**Goal:** Identify boundaries for every function in the executable to feed into the recompiler.

### Operation Modes
1. **With Symbols (DWARF):** Ideal. Perfect boundaries and function names.
2. **Stripped (No Symbols):** Uses a heuristic `jal` scanner. Starts at entrypoint and follows `jal` (Jump And Link) instructions to find functions. Often misses orphaned functions or jump tables.
3. **Ghidra Feed:** If the heuristic fails, you can analyze the ELF in Ghidra, export the function map to a CSV, and run `ps2_analyzer` passing the CSV.

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
"Stubs" are functions the recompiler will **NOT** translate to C++. Instead, any `jal` to this address will be replaced by a call to a registered C++ handler.
"Skips" are functions to actively ignore and not recompile at all (e.g. bootstrapper code).
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

PS2Recomp generates **thousands** of C++ files (29,000+ for large games). The build toolchain choice has a **massive** impact on compile time:

| Toolchain            | Generator                    | Approx. Full Build Time | Notes                             |
| -------------------- | ---------------------------- | ----------------------- | --------------------------------- |
| **Clang-CL + Ninja** | `-G Ninja` + clang-cl        | **~1 hour**             | ⚡ Best. Install via VS Installer. |
| MSVC + Ninja         | `-G Ninja`                   | ~3-5 hours              | Good. Ninja parallelizes well.    |
| MSVC + VS Solution   | `-G "Visual Studio 17 2022"` | ~20-25 hours            | ❌ Avoid. Serial bottleneck.       |

### How to Install Clang + Ninja (via Visual Studio Installer)
1. Open **Visual Studio Installer** → Modify your VS 2022 installation.
2. Go to the **Individual Components** tab.
3. Search for and enable:
   - `C++ Clang Compiler for Windows`
   - `C++ CMake tools for Windows` (includes Ninja)
4. Click **Modify** and wait for installation.
5. Restart your terminal. `clang-cl --version` and `ninja --version` should both work.

The `build_daemon.ps1` script auto-detects the best available toolchain. If it falls back to MSVC + VS Solution, the agent MUST warn the user to install Clang/Ninja.

### CMake Configuration for Clang+Ninja
```bash
# Inside the vcvars64.bat environment:
cmake -S . -B build -G Ninja -DCMAKE_C_COMPILER=clang-cl -DCMAKE_CXX_COMPILER=clang-cl
cmake --build build --config Debug
```

### Important: Reconfiguring an Existing Build
If the project was previously configured with a different generator (e.g., Visual Studio), you **must delete the `build/` directory** before reconfiguring with Ninja:
```powershell
Remove-Item -Recurse -Force .\ps2xRuntime\build
# Then re-run build_daemon.ps1 — it will auto-detect and reconfigure
```
