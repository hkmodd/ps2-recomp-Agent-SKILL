# PS2 Recomp — Project State
> Auto-maintained by agent. DO NOT DELETE. Read at session start, update after every major action.

## Game Info
- **Title**: <!-- e.g. Star Wars Episode III -->
- **Region**: <!-- NTSC-U / PAL / NTSC-J -->
- **ELF Name**: <!-- e.g. SLUS_210.01 or SLES_527.37 -->
- **ISO Path**: <!-- absolute path to extracted ISO -->
- **ELF Path**: <!-- absolute path to main ELF binary -->
- **Multi-Binary**: <!-- yes/no — some games have multiple ELFs -->
- **Has Symbols**: <!-- yes/no/partial — affects analysis strategy -->

## Environment Setup
- **Ghidra Install Path**: <!-- The folder containing ghidraRun.bat (e.g., C:\ghidra_11.4.2_PUBLIC) -->

## Current Phase
<!-- Update this to reflect exactly where the project stands.
     Valid phases in order:
     PHASE_SETUP          — PS2Recomp repo not yet cloned/configured
     PHASE_ISO_EXTRACT    — Need to extract ELF from ISO
     PHASE_ELF_ANALYSIS   — Running ps2_analyzer or Ghidra analysis
     PHASE_TOML_CONFIG    — Editing TOML config (stubs, skip, patches)
     PHASE_RECOMPILATION  — Running ps2_recomp to generate C++
     PHASE_CPP_REVIEW     — Reviewing generated C++ for unhandled opcodes
     PHASE_RUNTIME_BUILD  — Compiling ps2xRuntime and headless testing
     PHASE_IO_MODULE      — Game trying to load assets, CD/file I/O
     PHASE_MENU_REACH     — Reaching main menu
     PHASE_GAMEPLAY       — In-game behavior and rendering
-->
PHASE_SETUP

## Build Configuration
- **CMake Generator**: <!-- e.g. Ninja (preferred) or Visual Studio 17 2022 -->
- **C++ Compiler**: <!-- clang-cl (preferred) or MSVC cl -->
- **Build Type**: <!-- Debug / Release / RelWithDebInfo -->
- **TOML Path**: <!-- path to game.toml -->
- **Ghidra CSV Path**: <!-- path to exported function map, if any -->
- **single_file_output**: <!-- true/false -->

## Resolved Stubs
<!-- Track every stub binding. Leave rows empty if none. -->
| Address | Handler | Binding Method | Status | Notes |
| ------- | ------- | -------------- | ------ | ----- |
|         |         |                |        |       |

## Resolved Syscalls
<!-- Track every syscall implementation -->
| Syscall ID | Implementation | File | Status |
| ---------- | -------------- | ---- | ------ |
|            |                |      |        |

## Temporary Triage Stubs
<!-- ret0/ret1/reta0 stubs that still need real implementation -->
| Address | Triage Type | Caller Context | Priority | Notes |
| ------- | ----------- | -------------- | -------- | ----- |
|         |             |                |          |       |

## Unhandled Opcodes
<!-- Instructions the recompiler could not translate -->
| Address | Opcode | Type | Resolution |
| ------- | ------ | ---- | ---------- |
|         |        |      |            |

## Known Issues
- [ ] <!-- Active issue description -->

## Session Log
<!-- Append new entries at the top. Each entry: date, actions, discoveries, current blocker -->
### <!-- YYYY-MM-DD -->
- **Actions**: 
- **Discovered**: 
- **Current Blocker**: 
