import random
import time
from godot_env import GodotEnv

NUM_STEPS = 20


def main() -> None:
    with GodotEnv() as env:
        observation, info = env.reset()
        print("reset: obs=%d info=%s" % (len(observation), info))

        for i in range(NUM_STEPS):
            action = random.randint(0, 4)
            observation, reward, done, info = env.step(action)
            print(
                "step=%d action=%d reward=%.3f done=%s prep=%s obs=%d"
                % (i, action, reward, done, info.get("in_preparation", False), len(observation))
            )
            if done:
                print("episode finished, resetting")
                observation, info = env.reset()
                print("reset: obs=%d info=%s" % (len(observation), info))
            time.sleep(0.05)


if __name__ == "__main__":
    main()
