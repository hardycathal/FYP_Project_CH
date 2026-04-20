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
    from stable_baselines3.common.monitor import Monitor
except ImportError as exc:
    raise SystemExit(
        "stable-baselines3 is required. Install with: pip install stable-baselines3"
    ) from exc


OBS_SIZE = 57
NUM_ACTIONS = 5
TOTAL_TIMESTEPS = 1_000_000
MODEL_DIR = Path("Python") / "models" / "HiderTraining"
LOG_DIR = Path("Python") / "logs" / "HiderTraining"
CHECKPOINT_DIR = MODEL_DIR / "checkpoints"
CHECKPOINT_FREQ = 10_000
FINAL_MODEL_PATH = MODEL_DIR / "hider_ppo.zip"
DEFAULT_SEEKER_MODEL_PATH = Path("Python") / "models" / "base_model.zip"


class GodotHiderGymEnv(gym.Env):
    metadata = {"render_modes": []}

    def __init__(
        self,
        seeker_model_path: Path,
        host: str = "127.0.0.1",
        port: int = 19000,
        deterministic_seeker: bool = True,
    ) -> None:
        super().__init__()
        self.client = GodotEnv(host=host, port=port)
        self.seeker_model = PPO.load(str(seeker_model_path))
        self.deterministic_seeker = deterministic_seeker
        self._latest_seeker_observation: np.ndarray | None = None

        self.observation_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(OBS_SIZE,),
            dtype=np.float32,
        )
        self.action_space = spaces.Discrete(NUM_ACTIONS)

    def reset(self, *, seed: int | None = None, options: dict | None = None):
        super().reset(seed=seed)
        seeker_observation, hider_observation, info = self.client.reset_both()
        self._latest_seeker_observation = np.asarray(seeker_observation, dtype=np.float32)
        return np.asarray(hider_observation, dtype=np.float32), info

    def step(self, action: int):
        if self._latest_seeker_observation is None:
            raise RuntimeError("Environment stepped before reset()")

        seeker_action, _state = self.seeker_model.predict(
            self._latest_seeker_observation,
            deterministic=self.deterministic_seeker,
        )

        seeker_observation, hider_observation, _seeker_reward, hider_reward, done, info = self.client.step_both(
            int(seeker_action),
            int(action),
        )

        self._latest_seeker_observation = np.asarray(seeker_observation, dtype=np.float32)
        obs = np.asarray(hider_observation, dtype=np.float32)
        terminated = bool(done)
        truncated = False
        return obs, float(hider_reward), terminated, truncated, info

    def close(self) -> None:
        self.client.close()
        super().close()


def main() -> None:
    args = _parse_args()
    seeker_model_path = Path(args.seeker_model)
    if not seeker_model_path.exists():
        raise SystemExit(f"Fixed seeker model not found: {seeker_model_path}")

    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)

    env = Monitor(GodotHiderGymEnv(
        seeker_model_path=seeker_model_path,
        host=args.host,
        port=args.port,
        deterministic_seeker=not args.stochastic_seeker,
    ))

    checkpoint_callback = CheckpointCallback(
        save_freq=CHECKPOINT_FREQ,
        save_path=str(CHECKPOINT_DIR),
        name_prefix="ppo_hider",
    )

    resume_path = None if args.from_scratch else _find_resume_path()
    if resume_path is not None:
        print(f"Resuming hider training from: {resume_path}")
        model = PPO.load(str(resume_path), env=env)
        model.tensorboard_log = str(LOG_DIR)
    else:
        model = PPO(
            policy="MlpPolicy",
            env=env,
            verbose=1,
            tensorboard_log=str(LOG_DIR),
            n_steps=2048,
            batch_size=512,
            learning_rate=1e-4,
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
    parser = argparse.ArgumentParser(description="Train the hider PPO policy against a fixed seeker.")
    parser.add_argument(
        "--from-scratch",
        action="store_true",
        help="Ignore saved hider models/checkpoints and start a new PPO model.",
    )
    parser.add_argument(
        "--seeker-model",
        default=str(DEFAULT_SEEKER_MODEL_PATH),
        help="Path to the fixed seeker PPO model used as the opponent.",
    )
    parser.add_argument("--host", default="127.0.0.1", help="Godot bridge host")
    parser.add_argument("--port", type=int, default=19000, help="Godot bridge port")
    parser.add_argument(
        "--stochastic-seeker",
        action="store_true",
        help="Use stochastic actions for the fixed seeker instead of deterministic inference.",
    )
    return parser.parse_args()


def _find_resume_path() -> Path | None:
    if FINAL_MODEL_PATH.exists():
        return FINAL_MODEL_PATH

    checkpoints = sorted(
        CHECKPOINT_DIR.glob("ppo_hider_*_steps.zip"),
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
