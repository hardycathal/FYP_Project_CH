from __future__ import annotations

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


OBS_SIZE = 29
NUM_ACTIONS = 5
TOTAL_TIMESTEPS = 100_000
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
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)

    env = GodotGymEnv()
    checkpoint_callback = CheckpointCallback(
        save_freq=CHECKPOINT_FREQ,
        save_path=str(CHECKPOINT_DIR),
        name_prefix="ppo_seeker",
    )

    resume_path = _find_resume_path()
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
            n_steps=180,
            batch_size=60,
            learning_rate=3e-4,
            gamma=0.99,
            gae_lambda=0.95,
            ent_coef=0.01,
        )

    model.learn(
        total_timesteps=TOTAL_TIMESTEPS,
        progress_bar=True,
        callback=checkpoint_callback,
    )
    model.save(str(FINAL_MODEL_PATH))
    env.close()


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
