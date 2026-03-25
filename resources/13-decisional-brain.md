# Decisional Brain — The Reasoning Engine

> **Purpose:** This document teaches you HOW TO THINK, not what to do. The SKILL has procedures, flowcharts, and fix taxonomies. This document is the **conscious reasoning loop** that connects them — the "why" behind every action.

---

## §1 The Reasoning Loop

Execute this loop for EVERY problem. No shortcuts, no skipping steps.

```
┌─────────────────────────────────────────────────────────────┐
│                    THE LOOP                                  │
│                                                             │
│   ┌──────────┐                                              │
│   │ OBSERVE  │ ← What is the symptom?                       │
│   └────┬─────┘   (exact error, crash PC, visual glitch,     │
│        │          hang, wrong output, missing feature)       │
│        ▼                                                    │
│   ┌──────────┐                                              │
│   │  LOCATE  │ ← Where in the architecture?                 │
│   └────┬─────┘   (which layer: MIPS translation? Runtime?   │
│        │          PS2 hardware? Host OS? Overlay loading?)   │
│        ▼                                                    │
│   ┌──────────────┐                                          │
│   │  UNDERSTAND  │ ← Why does the ORIGINAL PS2 code work?   │
│   └────┬─────────┘   (Ghidra: decompile the MIPS.           │
│        │              PCSX2 MCP: see the running state.      │
│        │              What does this function ACTUALLY do?)  │
│        ▼                                                    │
│   ┌──────────┐                                              │
│   │  DECIDE  │ ← Which ONE of the 4 tools fixes this?       │
│   └────┬─────┘   TOML / Runtime C++ / Override / Recompiler │
│        │         If you can't pick ONE → you didn't finish   │
│        │         UNDERSTAND. Go back.                        │
│        ▼                                                    │
│   ┌──────────┐                                              │
│   │  VERIFY  │ ← Did the fix work?                          │
│   └────┬─────┘   Build → Run → Compare.                     │
│        │         If still broken → back to OBSERVE           │
│        │         with NEW DATA, not the same guess.          │
│        │                                                    │
│        └─── If verified → update PS2_PROJECT_STATE.md       │
│             with Learned Pattern: "X causes Y, fix with Z"  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### The Golden Rule

**If you cannot explain WHY your fix is correct in one sentence, you are guessing.** Go back to UNDERSTAND.

---

## §2 The "Why" Checklist

Before writing ANY fix, answer these four questions. If you can't answer all four, you are NOT ready to write code.

| # | Question | Bad Answer | Good Answer |
|---|----------|-----------|-------------|
| 1 | **Why does this crash/bug happen?** | "There's a null pointer" | "Function `sub_1E25A0` reads from address stored in `a0`, but the recomp passes `0` because the calling convention for 128-bit args isn't handled" |
| 2 | **What did the original PS2 code expect here?** | "I don't know, I'll stub it" | "GhydraMCP shows the MIPS loads a pointer from `gp+0x3A40` which is initialized by `sub_100200` during boot — the runtime never calls that init function" |
| 3 | **Why does my fix address the root cause?** | "It stops the crash" | "Adding the init call in `ps2Init()` populates the global pointer table, so `sub_1E25A0` gets the correct address instead of null" |
| 4 | **What will break if my fix is wrong?** | "Nothing" | "If the offset is wrong, every function using `gp+0x3A40` will read garbage — that's ~15 functions in the subsystem. Watch for cascading crashes." |

---

## §3 Diagnosis Escalation Ladder

When facing a bug, escalate through these levels IN ORDER. Each level gives you more information. Most bugs are solved at levels 1-2. Complex bugs need levels 3-4.

```
Level 1: STDOUT/STDERR
   │  Read the crash output. Look for:
   │  • Crash address → map to function (Ghidra)
   │  • Error message → tells you what's missing
   │  • Assertion text → tells you what went wrong
   │  • Stack trace → tells you the call chain
   │
   │  Solved? → Fix and verify.
   │  Not enough info? → Level 2.
   ▼
Level 2: SUBSYSTEM MAP
   │  From 10-agent-guardrails.md §3.4:
   │  Which Runtime file handles this address range?
   │  Which PS2 subsystem is involved? (DMA? GS? VIF? SPU2?)
   │  Read the relevant source file → understand current implementation.
   │
   │  Solved? → Fix and verify.
   │  Know WHAT but not WHY? → Level 3.
   ▼
Level 3: GHIDRA MCP (Static Analysis)
   │  mcp_ghydra_functions_decompile(address)
   │  → Read the ORIGINAL MIPS function.
   │  → What does it actually do?
   │  → What registers/memory does it read/write?
   │  → What does it call?
   │  mcp_ghydra_xrefs_list(to_addr) → who calls this?
   │  mcp_ghydra_data_list_strings(filter) → context clues
   │
   │  Solved? → Fix and verify.
   │  Know the code but not the runtime state? → Level 4.
   ▼
Level 4: PCSX2 MCP (Runtime A/B Comparison)
   │  See 12-pcsx2-mcp-playbook.md §3 for the full workflow.
   │  1. Breakpoint in PCSX2 at the problem address
   │  2. Read registers + memory = ground truth
   │  3. Compare with recomp behavior
   │  4. First divergence = root cause
   │
   │  Solved? → Fix and verify.
   │  STILL stuck after all 4 levels? → Circuit Breaker.
   ▼
Level 5: CIRCUIT BREAKER
   Load the relevant db-*.md file (ask db-ps2-index.md to route).
   If still stuck after loading reference material → ASK THE USER.
   Present what you know, what you tried, what you suspect.
   Do NOT keep looping without new information.
```

---

## §4 Decision Patterns — When to Use Each Tool

### TOML (`game.toml`)

**Use when:** The problem is in how the recompiler TRANSLATES the function, not in what the function DOES.

| Signal | TOML Action |
|--------|------------|
| Function crashes immediately on entry | `stub` — it's likely init code that's not needed in recomp |
| Function is an infinite polling loop | `skip` or `nop` — the PS2 hardware being polled doesn't exist |
| Function does direct hardware I/O that's handled elsewhere | `nop` — already covered by Runtime |
| Syscall vector is wrong | `patch` — fix the address |

**Anti-signal:** If the function does GAMEPLAY LOGIC (not hardware), stubbing is hiding a bug.

### Runtime C++ (`src/lib/*.cpp`)

**Use when:** The recompiled code is calling PS2 hardware that doesn't exist on the host.

| Signal | Runtime Action |
|--------|---------------|
| Crash in DMA/VIF/GIF/GS code | Implement the hardware interface in Runtime |
| Missing syscall | Add to syscall table |
| Function expects PS2 memory layout | Implement memory-mapped I/O handler |
| Audio/input/filesystem access | Implement host-side translation |

**Anti-signal:** If the crash is in game LOGIC (math, AI, physics), the Runtime doesn't help.

### Game Override (`src/lib/overrides/*.cpp`)

**Use when:** A specific function's RECOMPILED C++ is semantically wrong or can't work on x64.

| Signal | Override Action |
|--------|----------------|
| Function uses 128-bit registers that the recompiler can't handle | Write C++ equivalent using the original MIPS semantics |
| Function has self-modifying code | Reimplement the computed behavior |
| Function relies on precise PS2 timing | Write host-equivalent with different timing |
| Decompiled MIPS shows clear purpose but recompiled C++ is garbled | Clean reimplementation |

**Anti-signal:** If you're overriding more than ~5 functions for the same subsystem, you probably need a Runtime implementation instead.

### Recompiler (`ps2_recomp`)

**Use when:** The recompiler itself needs to re-process the ELF.

| Signal | Recompiler Action |
|--------|-------------------|
| New ELF/overlay discovered | Recompile with updated TOML |
| TOML changed (stubs, patches) | Rerun to regenerate runners |
| Address ranges updated | Recompile affected ranges |

**Anti-signal:** Never rerun the recompiler "just to see if it helps." It takes a full rebuild after.

---

## §5 Anti-Patterns — Thinking Mistakes

These are the cognitive traps that waste hours. Recognize them, stop, correct.

### "This looks like the same bug as before"

**WRONG.** Every crash is unique until you VERIFY it's the same root cause. Same crash address ≠ same bug. Different call chains can reach the same instruction with different state.

**Fix:** Read the registers/stack. If the state is different from last time, it's a new bug.

### "The fix worked for another function, so I'll apply it here too"

**WRONG.** Each function has different semantics. A stub that's correct for a boot-time init function is WRONG for a gameplay update function.

**Fix:** Go through the reasoning loop for THIS function. UNDERSTAND what it does before choosing the fix.

### "I'll just stub this and move on"

**WRONG** (unless it's genuinely unreachable code). Stubbing gameplay code hides bugs that will resurface later as mysterious glitches, crashes in unrelated areas, or missing game features.

**Fix:** Before stubbing, verify with Ghidra what the function does. If it's called during gameplay, it matters. Find the real fix.

### "It compiles, so it works"

**WRONG.** Compiling proves syntax. Running proves behavior. COMPARING proves correctness.

**Fix:** Build → Run → Read output → Compare with expected behavior. Only THEN claim it works.

### "I'll add more logging and try again"

**WRONG** (after the first round). If one round of logging didn't diagnose it, more logging won't either. You need a different diagnostic approach.

**Fix:** Escalate to the next level in the Diagnosis Ladder. Level 1 (stdout) failed? Use Level 2 (subsystem map). Level 2 failed? Use Level 3 (Ghidra). Level 3 failed? Use Level 4 (PCSX2 MCP A/B comparison).

### "I'm confident I know the answer without checking"

**THE MOST DANGEROUS TRAP.** Confidence without verification = hallucination risk. The SKILL says this explicitly: *"When confident without verification → Re-read source."*

**Fix:** Check. Always check. Read the actual code, run the actual binary, compare the actual state. Then be confident.
