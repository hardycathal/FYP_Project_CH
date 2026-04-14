from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

from godot_env import GodotEnv

try:
    import gymnasium as gym
    from gymnasium import spaces
except ImportError as exc:
    raise SystemExit(
        "gymnasium is required. Install with: pip install gymnasium"
    ) from exc

try:
    from stable_baselines3 import PPO
    from stable_baselines3.common.callbacks import CheckpointCallback
except ImportError as exc:
    raise SystemExit(
        "stable-baselines3 is required. Install with: pip install stable-baselines3"
    ) from exc


OBS_SIZE = 42
NUM_ACTIONS = 5
TOTAL_TIMESTEPS = 500_000
MODEL_DIR = Path("Python") / "models"
LOG_DIR = Path("Python") / "logs"
CHECKPOINT_DIR = MODEL_DIR / "checkpoints"
CHECKPOINT_FREQ = 10_000
FINAL_MODEL_PATH = MODEL_DIR / "base_model.zip"


class GodotGymEnv(gym.Env):
    metadata = {"render_modes": []}

    def __init__(self, host: str = "127.0.0.1", port: int = 19000) -> None:
        super().__init__()
        self.client = GodotEnv(host=host, port=port)
        self.observation_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(OBS_SIZE,),
            dtype=np.float32,
        )
        self.action_space = spaces.Discrete(NUM_ACTIONS)

    def reset(self, *, seed: int | None = None, options: dict | None = None):
        super().reset(seed=seed)
        observation, info = self.client.reset()
        return np.asarray(observation, dtype=np.float32), info

    def step(self, action: int):
        observation, reward, done, info = self.client.step(int(action))
        obs = np.asarray(observation, dtype=np.float32)
        terminated = bool(done)
        truncated = False
        return obs, float(reward), terminated, truncated, info

    def close(self) -> None:
        self.client.close()
        super().close()


def main() -> None:
    args = _parse_args()
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)

    env = GodotGymEnv()
    checkpoint_callback = CheckpointCallback(
        save_freq=CHECKPOINT_FREQ,
        save_path=str(CHECKPOINT_DIR),
        name_prefix="ppo_seeker",
    )

    resume_path = None if args.from_scratch else _find_resume_path()
    if resume_path is not None:
        print(f"Resuming training from: {resume_path}")
        model = PPO.load(str(resume_path), env=env)
        model.tensorboard_log = str(LOG_DIR)
    else:
        model = PPO(
            policy="MlpPolicy",
            env=env,
            verbose=1,
            tensorboard_log=str(LOG_DIR),
            n_steps=2048,
            batch_size=64,
            learning_rate=3e-4,
            gamma=0.99,
            gae_lambda=0.95,
            ent_coef=0.01,
            target_kl=0.01,
        )

    model.learn(
        total_timesteps=TOTAL_TIMESTEPS,
        progress_bar=True,
        callback=checkpoint_callback,
    )
    model.save(str(FINAL_MODEL_PATH))
    env.close()


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train the seeker PPO policy.")
    parser.add_argument(
        "--from-scratch",
        action="store_true",
        help="Ignore saved models/checkpoints and start a new PPO model.",
    )
    return parser.parse_args()


def _find_resume_path() -> Path | None:
    if FINAL_MODEL_PATH.exists():
        return FINAL_MODEL_PATH

    checkpoints = sorted(
        CHECKPOINT_DIR.glob("ppo_seeker_*_steps.zip"),
        key=_extract_step_count,
    )
    if checkpoints:
        return checkpoints[-1]
    return None


def _extract_step_count(path: Path) -> int:
    parts = path.stem.split("_")
    for part in reversed(parts):
        if part.isdigit():
            return int(part)
    return -1


if __name__ == "__main__":
    main()
