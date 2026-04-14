from __future__ import annotations

import argparse
from pathlib import Path

from godot_env import GodotEnv

try:
    from stable_baselines3 import PPO
except ImportError as exc:
    raise SystemExit(
        "stable-baselines3 is required. Install with: pip install stable-baselines3"
    ) from exc


DEFAULT_MODEL_PATH = Path("Python") / "models" / "ppo_seeker.zip"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Watch a trained PPO seeker policy play in the live Godot environment."
    )
    parser.add_argument(
        "model",
        nargs="?",
        default=str(DEFAULT_MODEL_PATH),
        help="Path to a PPO .zip model. Defaults to Python/models/ppo_seeker.zip",
    )
    parser.add_argument("--host", default="127.0.0.1", help="Godot bridge host")
    parser.add_argument("--port", type=int, default=19000, help="Godot bridge port")
    parser.add_argument("--episodes", type=int, default=10, help="Number of episodes to run")
    parser.add_argument(
        "--max-steps",
        type=int,
        default=400,
        help="Maximum steps per episode before forcing a reset",
    )
    parser.add_argument(
        "--stochastic",
        action="store_true",
        help="Sample actions from the policy instead of using deterministic inference",
    )
    return parser.parse_args()


def resolve_model_path(model_arg: str) -> Path:
    model_path = Path(model_arg)
    if not model_path.exists():
        raise SystemExit(f"Model file not found: {model_path}")
    if model_path.suffix.lower() != ".zip":
        raise SystemExit(f"Expected a Stable-Baselines3 .zip model file: {model_path}")
    return model_path


def main() -> None:
    args = parse_args()
    model_path = resolve_model_path(args.model)

    print(f"Loading model: {model_path}")
    model = PPO.load(str(model_path))

    with GodotEnv(host=args.host, port=args.port) as env:
        for episode_idx in range(args.episodes):
            observation, info = env.reset()
            total_reward = 0.0

            for step_idx in range(args.max_steps):
                action, _state = model.predict(observation, deterministic=not args.stochastic)
                observation, reward, done, info = env.step(int(action))
                total_reward += reward

                if done:
                    break

            print(
                "episode=%d steps=%d total_reward=%.3f sees_hider=%s prep=%s"
                % (
                    episode_idx + 1,
                    step_idx + 1,
                    total_reward,
                    info.get("sees_hider", False),
                    info.get("in_preparation", False),
                )
            )


if __name__ == "__main__":
    main()
