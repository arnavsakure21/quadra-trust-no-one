# QUADRA 🎮

### Four Players. One Mission. No One Escapes Alone.

**QUADRA** is a 2D, top-down sci-fi cooperative escape game built with **Godot 4 and GDScript**. Four players are trapped inside a futuristic laboratory and must work together, solve puzzles, restore power, and escape before time runs out.

Each player has a unique role and ability. Success depends on teamwork, communication, and using everyone's strengths to overcome the laboratory's security systems and environmental hazards.

---

## 🚀 Game Overview

* **Genre:** Cooperative multiplayer, puzzle, sci-fi escape
* **Players:** 4
* **Perspective:** 2D top-down
* **Engine:** Godot 4.x
* **Language:** GDScript
* **Networking:** Godot High-Level Multiplayer API with ENet
* **Match Duration:** 10 minutes
* **Platform:** PC (initial development target)

### The Mission

You and three teammates are trapped inside a high-security research laboratory. The facility is losing power, security systems are active, and the exit remains locked.

Work together to restore electricity, bypass security, uncover hidden clues, and reach the exit before the countdown reaches zero.

**One player cannot do everything. Every role matters.**

---

## 🧑‍🚀 Meet the Team

Each character has a distinct role designed to encourage cooperation.

| Character | Role     | Special Ability                                                                    |
| --------- | -------- | ---------------------------------------------------------------------------------- |
| 🔵 Blue   | Hacker   | Interacts with electronic panels, bypasses security, and unlocks security systems. |
| 🟢 Green  | Engineer | Repairs the generator, restores power, and activates broken machinery.             |
| 🟡 Yellow | Scout    | Reveals hidden clues, identifies nearby interactable objects, and detects traps.   |
| 🔴 Red    | Guardian | Deploys a temporary protective shield to help teammates survive dangerous areas.   |

Players must coordinate their abilities to progress through the laboratory and complete the mission.

---

## 🧩 Core Gameplay

### ⚡ Restore the Power

The laboratory's generator is offline. The Engineer must repair the machinery and help restore electricity to essential systems.

### 🔐 Bypass Security

Electronic doors and security systems block the team's progress. The Hacker must access control panels and disable or bypass security.

### 🔎 Discover Hidden Clues

Important information is concealed throughout the laboratory. The Scout helps reveal clues and uncover the code required to progress.

### 🛡️ Protect Your Teammates

Environmental hazards make exploration dangerous. The Guardian provides temporary protection, helping the team navigate hazardous sections.

### 🚪 Escape Together

Complete the required objectives, unlock the exit, and get the team to safety before the timer reaches zero.

---

## 🗺️ The Laboratory

The game is set inside a futuristic research facility containing interconnected areas to explore.

Planned and designed environments include:

* Generator room
* Security checkpoints and electronic doors
* Control panels and machinery
* Hidden clues and puzzle areas
* Environmental hazards
* Player spawn points
* Locked exit room

The laboratory is designed to support a short, replayable match in which players must balance exploration, puzzle-solving, and time management.

---

## ⏱️ Match Rules

* Each match has a **10-minute countdown**.
* Players cooperate to complete the required objectives.
* Character abilities have cooldowns to encourage strategic use.
* Players can be threatened by environmental hazards.
* The team wins when the objectives are complete and the players reach the exit before time expires.
* If the countdown reaches zero before the team escapes, the mission ends in defeat.
* A results screen and restart flow are part of the intended match experience.

---

## 🌐 Multiplayer

QUADRA is designed around real cooperative multiplayer rather than a simulated four-player experience.

The planned multiplayer architecture uses:

* Godot's high-level multiplayer API
* ENet for network communication
* Host-and-join sessions
* Four player slots with distinct character roles
* Synchronized player movement and gameplay state
* Host-authoritative validation of important interactions
* Multiplayer puzzle progression and match-state synchronization
* Connection status and disconnect handling

The initial networking target is LAN and direct-IP play. Internet matchmaking, relay services, and production-grade public matchmaking are outside the initial scope unless implemented separately.

---

## 🛠️ Technology Stack

| Technology            | Purpose                                    |
| --------------------- | ------------------------------------------ |
| Godot 4.x             | Game engine                                |
| GDScript              | Gameplay and game logic                    |
| Godot Multiplayer API | Multiplayer architecture                   |
| ENet                  | Network transport                          |
| Godot 2D tools        | Scenes, collisions, visual effects, and UI |
| Git and GitHub        | Version control and collaboration          |

The project aims to use native Godot features and original, procedurally created visuals wherever practical, minimizing unnecessary third-party dependencies.

---

## 🎮 Getting Started

### Prerequisites

* [Godot Engine 4.x](https://godotengine.org/download/)
* [Git](https://git-scm.com/downloads), if cloning the repository

### Clone the Repository

```bash
git clone https://github.com/arnavsakure21/quadra-trust-no-one.git
```

Enter the project directory:

```bash
cd quadra-trust-no-one
```

### Open the Game

1. Launch Godot 4.x.
2. Select **Import** or **Import Existing Project**.
3. Navigate to the cloned repository.
4. Select `project.godot`.
5. Open the project and run it using the Play button.

**Note:** The exact launch flow depends on the current implementation. Multiplayer hosting, joining, and all puzzle mechanics should be verified in the project before being considered fully playable.

---

## 📁 Project Structure

```text
quadra-trust-no-one/
├── project.godot
├── README.md
├── scenes/
│   └── main.tscn
└── scripts/
    ├── game.gd
    └── player_actor.gd
```

The project may evolve as additional scenes, scripts, multiplayer components, and game systems are added.

---

## 🗺️ Development Roadmap

* [ ] Core player movement and laboratory exploration
* [ ] Four distinct playable character roles
* [ ] Generator restoration puzzle
* [ ] Security panel and door puzzle
* [ ] Hidden clue and code puzzle
* [ ] Environmental hazards and protective abilities
* [ ] Match timer and objective tracking
* [ ] Victory, defeat, and restart flow
* [ ] Four-player host-and-join multiplayer
* [ ] Network synchronization and disconnect handling
* [ ] Gameplay testing and polish

*Checklist items should be updated as features are implemented and tested.*

---

## 👥 Teamwork Is the Mechanic

QUADRA explores how role-based cooperation can turn puzzle-solving into a shared challenge. Each player has a different responsibility, but the mission only succeeds when those responsibilities come together.

The goal is simple: make communication essential, teamwork rewarding, and every escape memorable.

---

## 📜 License

No license has been specified yet. Please contact the project maintainers before redistributing or reusing the code.
