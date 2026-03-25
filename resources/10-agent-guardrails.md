# Reference: Agent Guardrails & Self-Correction Protocols
> Load this when you make a repeated mistake, hit the Circuit Breaker (3 Strike Rule), or need to self-diagnose behavioral drift.

## 1. Agent Mistake Taxonomy — Your Own Failure Modes

These are NOT PS2 bugs. These are mistakes YOU (the agent) make repeatedly. Learn them:

| Your Mistake | Why It Happens | Prevention |
|-------------|---------------|------------|
| Editing a `.h` file "just to add one field" | You forget the 30K recompilation cost | §PROHIBITION #3 — ALWAYS check. If in doubt, it's a .h and you can't touch it. |
| Creating temp scripts in project root | No cleanup protocol was encoded (now it is: prohibition #11) | Put ALL temp files in `/tmp/`. Clean up before ending. |
| Reading a huge log file in one shot | You forget context is finite (~200K tokens) | Max 200 lines per read. Use `OutputCharacterCount=5000`. |
| Appending to the same log file across runs | You forget previous runs accumulate | Overwrite every time. Better: read from stdout directly. |
| Not re-reading the state file | You trust your memory (your memory is HALLUCINATION-PRONE) | Follow the Mandatory Trigger table. |
| Confident without verification | Classic LLM hallucination pattern | Verify. Build. Run. Read output. THEN claim success. |
| Trying 3+ fixes for the same crash without diagnosis | Guessing instead of reasoning | 3 Strike Rule exists — USE it. Load the db file. |
| Leaving game processes running | Forgot to kill the game after testing | Always `Terminate` via `send_command_input` after reading output. |
| Writing a fix without reading the state file first | Context drift — you forgot the current state | Mandatory Trigger: "Before writing ANY C++ code" → re-read state file. |

---

## 2. Upstream Awareness — PS2Recomp Is a Living Tool

PS2Recomp is under **active development**. It has open bugs. You WILL encounter situations where the tool itself produces incorrect output. This is normal — don't hack around it, handle it methodically.

**Known issue categories** (check `https://github.com/ran-j/PS2Recomp/issues`):
- **Codegen bugs** — Wrong C++ emitted for certain MIPS patterns (branch thunks, mixed VU0/MMI)
- **Missing syscalls** — Syscall numbers the recompiler doesn't know about (0x5b, 0x6, etc.)
- **Output bloat** — Functions generating far more C++ than expected
- **Missing stubs** — PS2 SDK functions with no default binding

**When to suspect a tool bug (not your code):**
1. The generated `out_*.cpp` has obviously wrong C++ (e.g., dead code loops, unreachable returns, wrong operand order)
2. A MIPS instruction gets translated to something that makes no architectural sense
3. The recompiler crashes or silently skips functions
4. The same pattern works for one function but fails for another similar function

**Protocol when you find an upstream issue:**

```
1. CONFIRM: Is this really a tool bug? Compare the Ghidra disassembly of the original
   MIPS with the generated C++. If the C++ doesn't match the MIPS semantics, it's the tool.

2. WORK AROUND CLEANLY: Don't patch the generated file. Instead:
   - TOML: stub or skip the broken function
   - Game Override: replace the broken function with a correct C++ implementation
   - TOML patch: NOP out the broken instruction(s)

3. DOCUMENT: Add a note to PS2_PROJECT_STATE.md under a "## Known Upstream Issues" header:
   - Which function / address is affected
   - What the recompiler generates vs. what the MIPS actually does
   - What workaround you applied
   - Link to the GitHub issue if one exists (or suggest opening one)
```

**Do NOT:** silently work around tool bugs without documenting them. The user may want to report them upstream, and future sessions need to know which workarounds are "permanent" vs "waiting for a tool fix."

---

## 3. Problem Resolution — The Core Reasoning Engine

> Every crash, every build error, every logic bug must pass through this decision framework.
> If you skip it, you WILL end up manually patching generated .cpp files — which is ALWAYS wrong.

### 3.1 The Fix Taxonomy — Your 4 Tools

You have exactly **4 tools** to fix anything. There is no 5th option. If you can't map a problem to one of these, you don't understand the problem yet.

| # | Tool | What it does | When to use | Files touched |
|---|------|-------------|-------------|---------------|
| 1 | **TOML Config** | Declarative: stubs, skips, patches, nops | Function should be skipped, stubbed (ret0/ret1), or nop'd out. No C++ needed. | `game.toml` |
| 2 | **Runtime C++** | Implements PS2 hardware in native code | Syscalls, DMA, GS, SPU, memory allocation, file I/O, timer, threading | `ps2xRuntime/src/lib/*.cpp` |
| 3 | **Game Override** | Per-game C++ function replacing recompiled code | A recompiled function produces wrong behavior that can't be fixed at the runtime layer. Registered via `PS2_REGISTER_GAME_OVERRIDE`. | `ps2xRuntime/src/lib/game_overrides.cpp` |
| 4 | **Re-run Recompiler** | Regenerate runner code from updated TOML | TOML stubs/patches changed, or new binary needs recompilation | `ps2_recomp` CLI → `output/*.cpp` |

**NEVER**: edit `runner/*.cpp`, write inline assembly hacks, or bypass the architecture. If none of the 4 tools fit, STOP and ask the user.

### 3.2 The Decision Flowchart

```
PROBLEM ENCOUNTERED
│
├─ BUILD ERROR (compilation/link fails)
│  ├─ Error is in runner/*.cpp?
│  │  ├─ Unhandled opcode → TOML patch (nop the instruction) or re-run recompiler
│  │  ├─ Missing symbol → Add stub in TOML, or implement in Runtime C++
│  │  └─ NEVER edit the runner file directly
│  ├─ Error is in src/lib/*.cpp?
│  │  └─ Fix in Runtime C++ (this is YOUR code)
│  └─ Linker error (undefined reference)?
│     ├─ It's a PS2 SDK function → Stub in TOML or implement in Runtime C++
│     └─ It's a Windows API → Fix includes/libs in CMake
│
├─ RUNTIME CRASH (exe crashes during execution)
│  ├─ Read the crash address/PC
│  ├─ Is the address inside the recompiled ELF range?
│  │  ├─ YES → Recompiled game code hit something unhandled
│  │  │  ├─ Unimplemented syscall → Implement in Runtime C++ (src/lib/)
│  │  │  ├─ Calls a stub that returns wrong value → Change TOML stub type or write Game Override
│  │  │  ├─ Hardware register access → Implement in Runtime C++ (GS/DMA/SPU layer)
│  │  │  └─ Infinite loop / setup code → TOML skip or patch
│  │  └─ NO → Address is OUTSIDE the recompiled range
│  │     ├─ It's a secondary binary → Recompile that binary (Phase 1 again)
│  │     ├─ It's a PS2 BIOS call → Runtime C++ syscall handler
│  │     └─ It's a wild pointer → Investigate the CALLER, not the target
│  └─ No crash address? (hang, infinite loop)
│     ├─ Attach debugger or add trace logging in Runtime C++
│     └─ Identify the loop → TOML skip/patch or Game Override
│
├─ WRONG BEHAVIOR (no crash, but game does wrong thing)
│  ├─ Graphics wrong → Runtime C++ GS implementation
│  ├─ Audio wrong → Runtime C++ SPU implementation
│  ├─ File not found → Runtime C++ file I/O path mapping
│  ├─ Game logic wrong → Game Override for the specific function
│  └─ Performance issue → Profile, then optimize Runtime C++
│
└─ UNKNOWN / CAN'T DIAGNOSE
   ├─ DON'T GUESS. Add trace logging to narrow the subsystem.
   ├─ Use Ghidra to understand what the original MIPS code was doing.
   └─ Ask the user for guidance.
```

### 3.3 Root Cause Protocol — 5 Questions Before Writing Code

Before writing ANY fix, answer these 5 questions **in order**. If you can't answer one, STOP — you need more information.

1. **WHAT failed?** (exact error, crash address, symptom)
2. **WHERE in the architecture?** (runner code? runtime layer? OS interface? game logic?)
3. **WHY did it fail?** (missing implementation? wrong assumption? unhandled case?)
4. **WHICH tool fixes this?** (TOML / Runtime C++ / Game Override / Recompiler — exactly ONE)
5. **WHAT could break?** (your fix affects what other systems? regression risk?)

If your answer to question 4 is "edit the runner .cpp" → **your answer to question 2 is WRONG.** Go back.

### 3.4 Red Flags — You're in the Wrong Layer

If you catch yourself doing any of these, STOP IMMEDIATELY:

| 🚩 Red Flag | Why it's wrong | Correct approach |
|-------------|----------------|------------------|
| Opening `runner/out_*.cpp` to edit it | Runner code is auto-generated. Your edit will be overwritten. | Fix via TOML stub, Runtime C++, or Game Override |
| Writing `#ifdef` in runner code | You're trying to conditionalize generated code | Write a Game Override that replaces the function entirely |
| Copy-pasting MIPS disassembly into C++ | You're reimplementing what the recompiler already did | Understand WHY the recompiled version doesn't work, fix the ROOT cause |
| Adding `if (address == 0xXXXXXX) return;` in the runtime | You're patching a symptom, not the cause | Use TOML to stub/skip the function, or implement the missing subsystem |
| Creating "adapter" functions between runner calls | You're fighting the calling convention | The recompiler handles calling conventions. If it's wrong, fix the TOML config. |
| Spending >10 minutes on a single crash without a diagnosis | You're guessing, not reasoning | Follow the Decision Flowchart. Use Ghidra for context. Ask the user. |

### 3.5 Subsystem Map — Know Your Layers

When a crash involves PS2 hardware, you need to know which Runtime C++ file handles it.
**These are the REAL file names in `ps2xRuntime/src/lib/`:**

| PS2 Subsystem | Address Range / Identifier | Runtime File(s) | Typical Symptoms |
|---------------|----------------------------|-----------------|------------------|
| **EE Core** (main CPU) | Recompiled code range | `ps2_runtime.cpp` + Runner code | Crashes in game logic |
| **GS** (Graphics) | `0x12000000-0x12001FFF` | `ps2_gs_gpu.cpp`, `ps2_gs_rasterizer.cpp` | Black screen, wrong rendering |
| **VU0/VU1** (Vector Units) | Inline in EE code | `ps2_vu1.cpp` + Runner (recompiled) | Wrong geometry, broken transforms |
| **VIF1** (VU Interface) | `0x10003C00-0x10003FFF` | `ps2_vif1_interpreter.cpp` | VU data not arriving, bad geometry |
| **GIF** (GS Interface) | `0x10003000-0x100037FF` | `ps2_gif_arbiter.cpp` | GS commands not reaching renderer |
| **SPU2** (Audio) | IOP side | `ps2_audio.cpp`, `ps2_audio_vag.cpp` | No sound, crashes on audio init |
| **IOP** (I/O Processor) | RPC calls, modules | `ps2_iop.cpp`, `ps2_iop_audio.cpp` | Hang during boot, module load fails |
| **Pad** (Controller) | `0x1F801xxx` | `ps2_pad.cpp` | No input, wrong buttons |
| **Syscalls** | `syscall` instruction | `ps2_syscalls.cpp` | Unimplemented syscall → crash |
| **Stubs** | Stubbed functions | `ps2_stubs.cpp` | Missing SDK function → log + return 0 |
| **Memory** | Kernel calls, TLB | `ps2_memory.cpp` | Segfault, invalid pointer |
| **Game Overrides** | Specific functions per-game | `game_overrides.cpp` | Recompiled function behaves wrong |

---

## 4. Adversarial Split + Verification-First — Mandatory for Code Changes

You are an LLM. You WILL hallucinate. You WILL confuse similar patterns. You WILL forget things from 50 tool calls ago. Accept this and COMPENSATE with structure:

### The 3 Rules of Epistemic Humility:

1. **Never claim without evidence.**
   - ❌ "This function returns 0" → Did you READ the code? Or are you remembering from 30 tool calls ago?
   - ✅ "Let me verify — `view_file` on the function → yes, line 47 returns 0"

2. **Never assume from pattern.**
   - ❌ "The other syscalls use this pattern, so this one must too"
   - ✅ "Let me check db-syscalls.md for this specific syscall number"

3. **If you're >80% sure without recent verification, you're probably wrong.**
   - High confidence without recent evidence = hallucination risk
   - Re-read the source. Re-read the reference. THEN be confident.

### Adversarial 3-Step Structure:

Before writing ANY C++ fix, override, or stub, you MUST execute:

1. **PROPOSE:** Draft your solution — which address to hook, what C++ logic, which file. State your hypothesis about *why* this fixes the crash.
2. **ATTACK:** Immediately switch stance. Try to destroy your own proposal:
   - Does the address exceed PS2's 32MB RDRAM (0x01FFFFFF)?
   - Are you suppressing a crash that will just cause silent corruption later?
   - Are you modifying a `runner/*.cpp` file instead of the runtime layer?
   - Does this break any previous milestone in the state file?
   - **Did you actually READ the relevant code, or are you assuming from memory?**
   - **Have you loaded the relevant db file for this subsystem?**
3. **EXECUTE:** Only after the attack finds no fatal flaws, output the final code and commands.

### Verification Ladder (EVERY fix must climb this):

1. ✍️ Write the fix
2. 🔨 BUILD it (read full output, verify exit code 0)
3. 🎮 RUN it (read stdout via `command_status`, verify behavior changed)
4. ✅ COMPARE to expected behavior (what SHOULD happen? does it?)
5. 📝 Only THEN update PS2_PROJECT_STATE.md with success/failure

**If you skip any step, your claim of "fixed" is a hallucination.** Build output or it didn't happen.

Skip this ONLY for trivial reads, greps, or state file updates. For **any code modification**, this structure is mandatory.

---

## 5. Circuit Breaker — 3 Strike Rule

If you attempt the same `compile → test → fail → guess → compile` loop **3 times** for the same crash:

1. **STOP.** Do not guess again.
2. Re-read `PS2_PROJECT_STATE.md`.
3. **LOAD the relevant knowledge database** using the Knowledge-Seeking Reflex table below. You MUST do this before strike 3 — never attempt a third fix without loading the reference.
4. Consult `resources/09-ps2tek.md` or use GhydraMCP.
5. **PCSX2 MCP A/B Comparison.** If PCSX2 is available, use `12-pcsx2-mcp-playbook.md` §3 to compare real PS2 state vs. recompiled output. The first register/memory divergence IS the root cause.
6. Search the web for community workarounds.
7. If still stuck: format a specific technical question and **ask the user**.

---

## 6. Knowledge-Seeking Reflex — When to Consult Documentation

You have 230+ KB of PS2 hardware documentation at your disposal. The boot loads pipeline and runtime references (03, 04). Everything else is **on-demand** — but you MUST know WHEN to reach for it.

**Trigger table — if you encounter X, LOAD Y:**

| Encounter | Load | Why |
|-----------|------|-----|
| Unknown syscall number | `db-syscalls.md` | Full syscall table with params |
| Unknown SDK function (sif*, sce*, etc.) | `db-sdk-functions.md` | SDK stub signatures |
| Hardware register address (0x1000xxxx) | `db-registers.md` | Register map by subsystem |
| Memory address confusion | `db-memory-map.md` | EE address space layout |
| Unknown MIPS instruction | `db-isa.md` | R5900 instruction encoding |
| VU0/VU1 instruction | `db-vu-instructions.md` | VU instruction reference |
| GS/DMA/VIF/GIF behavior | `resources/09-ps2tek.md` via `08` | Holy grail hardware doc |
| Need architecture overview | `db-ps2-architecture.md` | Full PS2 system diagram |
| Need to find the RIGHT file | `db-ps2-index.md` | Master router |
| Need visual diagram | `resources/images/IMAGE_CATALOG.md` | 80 classified images |
| Multi-binary / overlay issue | `db-overlay-patterns.md` | Overlay detection & multi-TOML |
| Runtime crash (need register state) | `12-pcsx2-mcp-playbook.md` | PCSX2 breakpoints, A/B comparison |
| Stuck after 2 failed fixes | `13-decisional-brain.md` | Reasoning loop, anti-patterns |
| Need to compare real PS2 vs recomp | `12-pcsx2-mcp-playbook.md` §3 | A/B comparison workflow |

**The rule**: If you're about to write code that touches PS2 hardware and you haven't loaded the relevant db file THIS SESSION → **STOP and load it first**. Never implement from memory. Always verify against the reference.

**Circuit Breaker integration**: On strike 2 of the 3-strike rule, you **MUST** load the relevant db file before your third attempt. This is not optional.
