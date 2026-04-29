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


OBS_SIZE = 57
NUM_ACTIONS = 5
MODEL_DIR = Path("Python") / "models" / "DualTraining"
SEEKER_LOG_DIR = Path("Python") / "logs_dual_seeker"
HIDER_LOG_DIR = Path("Python") / "logs_dual_hider"
SEEKER_CHECKPOINT_DIR = MODEL_DIR / "seeker_checkpoints"
HIDER_CHECKPOINT_DIR = MODEL_DIR / "hider_checkpoints"
SEEKER_MODEL_PATH = MODEL_DIR / "ppo_seeker.zip"
HIDER_MODEL_PATH = MODEL_DIR / "ppo_hider.zip"
SEEKER_SEED_PATH = Path("Python") / "models" / "ppo_seeker.zip"
HIDER_SEED_PATH = Path("Python") / "models" / "ppo_hider.zip"


class RandomPolicy:
    def predict(self, _observation, deterministic: bool = True):
        return np.array(np.random.randint(0, NUM_ACTIONS)), None


class DualRoleEnv(gym.Env):
    metadata = {"render_modes": []}

    def __init__(
        self,
        role: str,
        opponent_model: PPO | RandomPolicy,
        host: str = "127.0.0.1",
        port: int = 19000,
        deterministic_opponent: bool = True,
    ) -> None:
        super().__init__()
        if role not in {"seeker", "hider"}:
            raise ValueError(f"Unsupported role: {role}")

        self.role = role
        self.opponent_model = opponent_model
        self.deterministic_opponent = deterministic_opponent
        self.client = GodotEnv(host=host, port=port)
        self._latest_seeker_obs: np.ndarray | None = None
        self._latest_hider_obs: np.ndarray | None = None

        self.observation_space = spaces.Box(
            low=-1.0,
            high=1.0,
            shape=(OBS_SIZE,),
            dtype=np.float32,
        )
        self.action_space = spaces.Discrete(NUM_ACTIONS)

    def reset(self, *, seed: int | None = None, options: dict | None = None):
        super().reset(seed=seed)
        seeker_obs, hider_obs, info = self.client.reset_both()
        self._latest_seeker_obs = np.asarray(seeker_obs, dtype=np.float32)
        self._latest_hider_obs = np.asarray(hider_obs, dtype=np.float32)

        if self.role == "seeker":
            return self._latest_seeker_obs.copy(), info
        return self._latest_hider_obs.copy(), info

    def step(self, action: int):
        if self._latest_seeker_obs is None or self._latest_hider_obs is None:
            raise RuntimeError("Environment stepped before reset()")

        if self.role == "seeker":
            hider_action, _state = self.opponent_model.predict(
                self._latest_hider_obs,
                deterministic=self.deterministic_opponent,
            )
            seeker_obs, hider_obs, seeker_reward, _hider_reward, done, info = self.client.step_both(
                int(action),
                int(hider_action),
            )
            obs = np.asarray(seeker_obs, dtype=np.float32)
            reward = float(seeker_reward)
        else:
            seeker_action, _state = self.opponent_model.predict(
                self._latest_seeker_obs,
                deterministic=self.deterministic_opponent,
            )
            seeker_obs, hider_obs, _seeker_reward, hider_reward, done, info = self.client.step_both(
                int(seeker_action),
                int(action),
            )
            obs = np.asarray(hider_obs, dtype=np.float32)
            reward = float(hider_reward)

        self._latest_seeker_obs = np.asarray(seeker_obs, dtype=np.float32)
        self._latest_hider_obs = np.asarray(hider_obs, dtype=np.float32)
        terminated = bool(done)
        truncated = False
        return obs, reward, terminated, truncated, info

    def close(self) -> None:
        self.client.close()
        super().close()


def main() -> None:
    args = parse_args()

    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    SEEKER_LOG_DIR.mkdir(parents=True, exist_ok=True)
    HIDER_LOG_DIR.mkdir(parents=True, exist_ok=True)
    SEEKER_CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
    HIDER_CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)

    # Track paths rather than model objects — reload with env each round to avoid n_envs mismatch
    if args.from_scratch:
        seeker_path: Path | None = None
        hider_path: Path | None = None
    else:
        seeker_path = find_resume_path(SEEKER_MODEL_PATH, SEEKER_CHECKPOINT_DIR) or (
            SEEKER_SEED_PATH if SEEKER_SEED_PATH.exists() else None
        )
        hider_path = find_resume_path(HIDER_MODEL_PATH, HIDER_CHECKPOINT_DIR) or (
            HIDER_SEED_PATH if HIDER_SEED_PATH.exists() else None
        )

    if seeker_path:
        print(f"Loading seeker from: {seeker_path}")
    else:
        print("Starting seeker from scratch.")
    if hider_path:
        print(f"Loading hider from: {hider_path}")
    else:
        print("Starting hider from scratch.")

    for round_idx in range(args.rounds):
        # --- Train seeker ---
        print(f"=== Round {round_idx + 1}/{args.rounds}: train seeker ===")
        hider_opponent = PPO.load(str(hider_path)) if hider_path else RandomPolicy()
        seeker_env = DualRoleEnv(
            role="seeker",
            opponent_model=hider_opponent,
            host=args.host,
            port=args.port,
            deterministic_opponent=not args.stochastic_opponent,
        )
        if seeker_path is not None:
            seeker_model = PPO.load(str(seeker_path), env=seeker_env)
        else:
            seeker_model = _new_model(seeker_env, SEEKER_LOG_DIR)
        seeker_model.tensorboard_log = str(SEEKER_LOG_DIR)
        seeker_model.learn(
            total_timesteps=args.round_timesteps,
            progress_bar=True,
            reset_num_timesteps=False,
            callback=CheckpointCallback(
                save_freq=args.checkpoint_freq,
                save_path=str(SEEKER_CHECKPOINT_DIR),
                name_prefix="ppo_dual_seeker",
            ),
        )
        seeker_model.save(str(SEEKER_MODEL_PATH))
        seeker_path = SEEKER_MODEL_PATH
        seeker_env.close()

        # --- Train hider ---
        print(f"=== Round {round_idx + 1}/{args.rounds}: train hider ===")
        seeker_opponent = PPO.load(str(seeker_path))
        hider_env = DualRoleEnv(
            role="hider",
            opponent_model=seeker_opponent,
            host=args.host,
            port=args.port,
            deterministic_opponent=not args.stochastic_opponent,
        )
        if hider_path is not None:
            hider_model = PPO.load(str(hider_path), env=hider_env)
        else:
            hider_model = _new_model(hider_env, HIDER_LOG_DIR)
        hider_model.tensorboard_log = str(HIDER_LOG_DIR)
        hider_model.learn(
            total_timesteps=args.round_timesteps,
            progress_bar=True,
            reset_num_timesteps=False,
            callback=CheckpointCallback(
                save_freq=args.checkpoint_freq,
                save_path=str(HIDER_CHECKPOINT_DIR),
                name_prefix="ppo_dual_hider",
            ),
        )
        hider_model.save(str(HIDER_MODEL_PATH))
        hider_path = HIDER_MODEL_PATH
        hider_env.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Alternate seeker and hider PPO training rounds in the same two-agent environment."
    )
    parser.add_argument("--from-scratch", action="store_true", help="Start both models from scratch.")
    parser.add_argument("--host", default="127.0.0.1", help="Godot bridge host")
    parser.add_argument("--port", type=int, default=19000, help="Godot bridge port")
    parser.add_argument("--rounds", type=int, default=10, help="Number of alternating training rounds")
    parser.add_argument(
        "--round-timesteps",
        type=int,
        default=50_000,
        help="Timesteps to train each role per round",
    )
    parser.add_argument(
        "--checkpoint-freq",
        type=int,
        default=10_000,
        help="Checkpoint frequency within each training round",
    )
    parser.add_argument(
        "--stochastic-opponent",
        action="store_true",
        help="Use stochastic actions for the frozen opponent policy instead of deterministic inference.",
    )
    return parser.parse_args()


def _new_model(env: gym.Env, log_dir: Path) -> PPO:
    return PPO(
        policy="MlpPolicy",
        env=env,
        verbose=1,
        tensorboard_log=str(log_dir),
        n_steps=2048,
        batch_size=512,
        learning_rate=1e-4,
        gamma=0.99,
        gae_lambda=0.95,
        ent_coef=0.01,
        target_kl=0.01,
    )


def find_resume_path(model_path: Path, checkpoint_dir: Path) -> Path | None:
    if model_path.exists():
        return model_path

    checkpoints = sorted(
        checkpoint_dir.glob("*.zip"),
        key=extract_step_count,
    )
    if checkpoints:
        return checkpoints[-1]
    return None


def extract_step_count(path: Path) -> int:
    parts = path.stem.split("_")
    for part in reversed(parts):
        if part.isdigit():
            return int(part)
    return -1


if __name__ == "__main__":
    main()
