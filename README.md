# Reinforcement Learning for Hide-and-Seek

**BEng (Hons) Software & Electronic Engineering — Final Year Project**
Cathal Hardy · G00424572 · Atlantic Technological University · 2025/2026

> Two agents — a seeker and a hider — learn to compete in a 3D arena using Proximal Policy Optimisation (PPO). No strategies are hard-coded. Behaviours emerge entirely from reward signals and self-play.

---

## Overview

This project builds a complete reinforcement learning pipeline for a two-agent hide-and-seek game. The game environment runs in **Godot 4** and communicates with a **Python training process** via a custom TCP bridge. Training uses **Stable-Baselines3 (PPO)** through a **Gymnasium-compatible** wrapper.

The seeker and hider are trained in stages using a curriculum, finishing with dual self-play where both agents train against each other simultaneously.

---

## Architecture

```
┌─────────────────────────────────┐
│         Python Training          │
│  GodotEnv │ Gymnasium │ PPO/SB3  │
└──────────────┬──────────────────┘
               │  step / reset (JSON over TCP)
               │  obs, reward, done
┌──────────────▼──────────────────┐
│           TCP Bridge             │
│   Commands: reset / step         │
│   Responses: obs / reward / done │
└──────────────┬──────────────────┘
               │  apply action
┌──────────────▼──────────────────┐
│            Godot 4               │
│  Game Loop │ Physics │ Rewards   │
└─────────────────────────────────┘
```

Each agent observes a **57-dimensional vector** including:
- Velocity and facing direction
- Self position (normalised)
- 16 LIDAR rays — 360° wall and obstacle detection
- 23 vision cone rays — 135° forward arc, opponent detection only
- Opponent detected flag and features when visible
- Carrying box flag and episode progress

Actions are discrete: **forward, backward, turn left, turn right**.

---

## Training Curriculum

| Stage | Description | Notes |
|---|---|---|
| Stage 0 | Fixed spawns | Seeker learns basic pursuit |
| Stage 1 | Random spawns | Forces generalisation |
| Stage 2 | Walls + obstacles | Navigation around barriers |
| Hider | Trained vs frozen seeker | Learns evasion |
| Dual | Both agents, alternating | Adversarial self-play |

---

## Project Structure

```
FYP_Project_CH/
├── Godot/                  # Godot 4 game project
│   ├── scenes/             # Main scene, arena, agents
│   ├── scripts/            # GDScript — agents, TCP bridge, reward calc
│   └── assets/             # 3D models, textures, animations
│
├── Python/
│   
│   ├── godot_env.py            # Gymnasium wrapper (GodotEnv)
│   ├── train_seeker_ppo.py     # Seeker curriculum training
│   ├── train_hider_ppo.py      # Hider training vs frozen seeker
│   ├── train_dual_ppo.py       # Dual self-play training
|   ├── watch_model.py          # Watch a trained agent
|   ├── watch_dual.py           # Watch both agents
|   ├── random_client.py        # Test script, sends 20 random actions
|   ├── rollout_random.py       # Test Script, runs 10 eps with random actions.
│   ├── logs_dual_seeker/       # TensorBoard logs — seeker
│   └── logs_dual_hider/        # TensorBoard logs — hider
|   └── tests/                  # Test scripts
│
├── Models/                 # Saved .zip model checkpoints
├── Presentation/           # Slide deck
├── Report/                 # Final report and figures
└── README.md
```

---

## Setup

### Requirements

- [Godot 4](https://godotengine.org/) (4.x)
- Python 3.10+
- Dependencies:

```bash
pip install stable-baselines3 gymnasium numpy torch tqdm rich tensorboard
```

### Running the Game Manually

1. Open the `Godot/` folder in Godot 4
2. Run the main scene — the game will wait for a TCP connection on port 19000

### Running Training

**Seeker curriculum:**
```bash
python Python/train_ppo.py
```

**Hider (requires a trained seeker checkpoint):**
```bash
python Python/train_hider_ppo.py
```

**Dual self-play:**
```bash
python Python/train_dual_ppo.py
```

### Viewing Training Logs

```bash
tensorboard --logdir Python/logs_dual_seeker
```

### Running a Trained Agent

```bash
python Python/watch_model.py --model Models/seeker_final.zip
python Python/watch_dual.py
```

## Tech Stack

| Component | Technology |
|---|---|
| Game engine | Godot 4 / GDScript |
| RL algorithm | PPO (Proximal Policy Optimisation) |
| Training library | Stable-Baselines3 |
| Environment interface | Gymnasium |
| Communication | TCP sockets (JSON) |
| 3D models | Rodin AI + Mixamo + Blender |

---

## Acknowledgements

Inspired by [Baker et al. (2019) — Emergent Tool Use from Multi-Agent Interaction](https://arxiv.org/abs/1909.07528) (OpenAI).

---

*Atlantic Technological University — BEng (Hons) Software & Electronic Engineering*
