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


DEFAULT_SEEKER_MODEL_PATH = Path("models") / "DualTraining" / "ppo_seeker.zip"
DEFAULT_HIDER_MODEL_PATH = Path("models") / "DualTraining" / "ppo_hider.zip"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Watch a trained seeker and hider policy play against each other in Godot."
    )
    parser.add_argument(
        "--seeker-model",
        default=str(DEFAULT_SEEKER_MODEL_PATH),
        help="Path to the seeker PPO .zip model.",
    )
    parser.add_argument(
        "--hider-model",
        default=str(DEFAULT_HIDER_MODEL_PATH),
        help="Path to the hider PPO .zip model.",
    )
    parser.add_argument("--host", default="127.0.0.1", help="Godot bridge host")
    parser.add_argument("--port", type=int, default=19000, help="Godot bridge port")
    parser.add_argument("--episodes", type=int, default=100, help="Number of episodes to run")
    parser.add_argument(
        "--max-steps",
        type=int,
        default=400,
        help="Maximum steps per episode before forcing a reset",
    )
    parser.add_argument(
        "--stochastic",
        action="store_true",
        help="Sample actions from both policies instead of deterministic inference",
    )
    return parser.parse_args()


def resolve_model_path(model_arg: str, label: str) -> Path:
    model_path = Path(model_arg)
    if not model_path.exists():
        raise SystemExit(f"{label} model file not found: {model_path}")
    if model_path.suffix.lower() != ".zip":
        raise SystemExit(f"Expected a Stable-Baselines3 .zip model file: {model_path}")
    return model_path


def main() -> None:
    args = parse_args()
    seeker_path = resolve_model_path(args.seeker_model, "Seeker")
    hider_path = resolve_model_path(args.hider_model, "Hider")

    print(f"Loading seeker model: {seeker_path}")
    seeker_model = PPO.load(str(seeker_path))

    print(f"Loading hider model: {hider_path}")
    hider_model = PPO.load(str(hider_path))

    deterministic = not args.stochastic

    with GodotEnv(host=args.host, port=args.port) as env:
        for episode_idx in range(args.episodes):
            seeker_obs, hider_obs, info = env.reset_both()
            total_seeker_reward = 0.0
            total_hider_reward = 0.0
            steps = 0

            for step_idx in range(args.max_steps):
                seeker_action, _ = seeker_model.predict(seeker_obs, deterministic=deterministic)
                hider_action, _ = hider_model.predict(hider_obs, deterministic=deterministic)

                seeker_obs, hider_obs, seeker_reward, hider_reward, done, info = env.step_both(
                    int(seeker_action),
                    int(hider_action),
                )

                total_seeker_reward += seeker_reward
                total_hider_reward += hider_reward
                steps = step_idx + 1

                if done:
                    break

            caught = info.get("caught_hider", False)
            print(
                "episode=%d steps=%d seeker_reward=%.3f hider_reward=%.3f caught=%s"
                % (
                    episode_idx + 1,
                    steps,
                    total_seeker_reward,
                    total_hider_reward,
                    caught,
                )
            )


if __name__ == "__main__":
    main()
