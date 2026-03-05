# PS2 Recomp Mastery — User Guide

Welcome to the **PS2 Recomp Mastery Skill**. This is not a standard prompt template; it is a complex, hyper-structured Operating System for LLM Agents (like Antigravity or Cursor). It gives them the architectural knowledge, the procedural workflow, and the persistent memory required to autonomously reverse engineer and recompile PlayStation 2 games.

This guide explains how *you*, the human driver, should use this skill to extract maximum performance from the AI.

---

## ⚠️ The Paradigm Shift: How to Treat the Agent

Before using this, you must change how you interact with the LLM. 
**Do not treat it as a chatbot. Treat it as a Junior Reverse Engineer working on your machine.**

1. **It is Autonomous:** The agent has scripts to compile C++ code headlessly (`build_daemon.ps1`) and to run the game to harvest crash logs (`log_reaper.py`). Let it use them. Do not compile for it unless it specifically asks.
2. **It has Persistent Memory:** The agent will create a `PS2_PROJECT_STATE.md` file in your root directory. This is its "external hippocampus". It allows you to pause a session on Monday, start a new chat on Thursday, point to the state file, and the agent will resume exactly where it left off without forgetting what registers it was analyzing.
3. **It has Circuit Breakers:** If the agent gets stuck in a loop (failing the same crash 3 times), it is programmed to physically stop, read hardware documentation, or ask for your help. It will not burn your tokens infinitely.

---

## 🛠️ Prerequisites (Your PC Setup)

For the agent to work flawlessly, your machine must have the following ready:

1. **Visual Studio 2022 (C++ Desktop Workload)**: Required for the MSBuild native tools. The `build_daemon.ps1` looks for `vcvars64.bat`.
   - **⚠️ CRITICAL: You MUST install Clang and Ninja.** Open the Visual Studio Installer, go to "Individual Components", and enable **"C++ Clang Compiler for Windows"** and **"C++ CMake tools for Windows"**. `build_daemon.ps1` will literally refuse to run without them.
2. **CMake**: Ensure CMake is installed and available in your PATH. (Usually bundled with the VS CMake tools above).
3. **Python 3.x**: Required for the `log_reaper.py`, `pdf_grep.py`, and `pdf_extract_image.py` scripts. Install the PDF parser via: `pip install PyMuPDF pymupdf4llm`
3. **Ghidra 11.4.2**:
   - Installed with the [EmotionEngine Reloaded Plugin](https://github.com/chaoticgd/ghidra-emotionengine-reloaded).
   - Installed with the [**GhydraMCP**](https://github.com/starsong-consulting/GhydraMCP) extension running on port 8192 (CodeBrowser must be open with the ELF).
   - **Crucial**: Ensure `mcp_config.json` inside your AI environment (Cursor/Antigravity) is configured to connect to the local GhydraMCP server. This allows the *Agent* to drive Ghidra, not you!

---

## 🚀 How to Start a Session

### 1. File Placement
Ensure the `ps2-recomp-Agent-SKILL/` folder (or `ps2-recomp-Agent-SKILL-main/` if downloaded as ZIP) is placed inside your root PS2Recomp workspace, alongside the `ps2xRecomp` and `ps2xRuntime` directories.

### 2. Scenario A: The Clean Slate (Brand New Project)
If you are starting a game completely from scratch, open your AI IDE (Cursor/Antigravity) and use this **EXACT PROMPT** to begin:

```text
Load the skill `ps2-recomp-Agent-SKILL`. I need to port [GAME NAME]. 
The ISO is located at `[ABSOLUTE PATH TO ISO]`. Start at Phase 0. 
```

### 3. Scenario B: The Adoption (Mid-way Manual Progress)
If you started porting a game *manually* (e.g., you already extracted the ELF, maybe set up Ghidra, or generated a basic `game.toml`), but you don't have a `PS2_PROJECT_STATE.md` file yet, use this prompt to let the Agent infer your progress:

```text
Load the skill `ps2-recomp-Agent-SKILL`. I am porting [GAME NAME].
I have already made some manual progress. Please inspect my working directory, locate my ELF/TOML/logs if they exist, infer my current Phase, generate a `PS2_PROJECT_STATE.md` file reflecting reality, and tell me what we should do next.
```

### 4. Scenario C: The Warm Resume (New Chat / Context Reset)
LLM Agents eventually run out of memory (context degradation) if a chat gets too long. If the Agent starts acting lobotomized or forgetting basic instructions, **open a brand new chat window** and use this prompt to safely hook back into the persistent memory:

```text
Load the skill `ps2-recomp-Agent-SKILL`. We are working on [GAME NAME]. 
Read the `PS2_PROJECT_STATE.md` file to infer the current Phase, 
and resume work autonomously from there.
```

---

## 🤝 How to Collaborate (The Human-in-the-Loop)

While the agent is highly autonomous, PS2 reverse engineering requires your eyes:

- **Monitor `PS2_PROJECT_STATE.md`**: Open this file in split-screen. You will see the agent filling out tables of resolved stubs, triage attempts, and unhandled opcodes in real-time. If it hallucinated something, correct the Markdown file directly. The agent will read your correction on the next refresh.
- **Beware Context Degradation**: If you have been chatting for hours and the Agent asks stupid questions, its context window is full. Stop immediately. Open a new chat and use **Scenario C** to resume. The Agent is programmed to warn you when it feels this happening.
- **Ensure Ghidra is Ready**: The agent drives Ghidra, but *you* must open Ghidra, perform the initial auto-analysis on the game's ELF, and leave the CodeBrowser window open with the GhydraMCP plugin running.
- **Do not interrupt the Build Daemon**: When the agent runs `build_daemon.ps1`, let it finish. It might take 10-20 seconds. The agent will read the MSVC output and fix syntax errors itself.

---

## 🚨 Troubleshooting

* **The Agent asks me to compile the game:** Tell it: "No, read your Skill. You must use `ps2-recomp-Agent-SKILL/scripts/build_daemon.ps1`."
* **The Agent is guessing blindly and crashing:** Tell it: "Stai violando il Circuit Breaker. Implementa il Dynamic Probing (Telemetria Empirica) come descritto nel tuo Playbook per leggere i valori dei registri."
* **The Agent forgets an address:** Tell it: "Fai un Context Refresh. Leggi il `PS2_PROJECT_STATE.md`."
---

## 🙏 Acknowledgements & Credits

This AI Skill directly leverages the revolutionary [**PS2Recomp**](https://github.com/ran-j/PS2Recomp) project created by **ran-j**. PS2Recomp is a monumental milestone in PlayStation 2 preservation and static recompilation. This AI workflow is built strictly *around* his open-source pipeline to automate the heavy lifting of reverse engineering. Huge thanks to ran-j and all contributors pushing the boundaries of the PS2 scene!

---

*Created by the Antigravity Deepmind System for flawless PS2 porting.*
