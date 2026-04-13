import random
from statistics import mean

from godot_env import GodotEnv


NUM_EPISODES = 10
MAX_STEPS_PER_EPISODE = 200


def run_episode(env: GodotEnv) -> dict:
    observation, info = env.reset()
    total_reward = 0.0
    steps = 0
    done = False

    while not done and steps < MAX_STEPS_PER_EPISODE:
        action = random.randint(0, 4)
        observation, reward, done, info = env.step(action)
        total_reward += reward
        steps += 1

    return {
        "steps": steps,
        "total_reward": total_reward,
        "done": done,
        "final_info": info,
        "observation_size": len(observation),
    }


def main() -> None:
    summaries = []

    with GodotEnv() as env:
        for episode in range(NUM_EPISODES):
            summary = run_episode(env)
            summaries.append(summary)
            print(
                "episode=%d steps=%d total_reward=%.3f done=%s prep=%s obs=%d"
                % (
                    episode,
                    summary["steps"],
                    summary["total_reward"],
                    summary["done"],
                    summary["final_info"].get("in_preparation", False),
                    summary["observation_size"],
                )
            )

    rewards = [item["total_reward"] for item in summaries]
    lengths = [item["steps"] for item in summaries]

    print("--- rollout summary ---")
    print("episodes:", len(summaries))
    print("avg_reward: %.3f" % mean(rewards))
    print("avg_length: %.2f" % mean(lengths))
    print("min_reward: %.3f" % min(rewards))
    print("max_reward: %.3f" % max(rewards))


if __name__ == "__main__":
    main()
