import json
import random
import time
from godot_env import GodotEnv

NUM_STEPS = 20


def main() -> None:
    with GodotEnv() as env:
        reset = env.reset()
        print("reset:", reset)

        for i in range(NUM_STEPS):
            action = random.randint(0, 4)
            response = env.step(action)
            print(f"step {i} action={action}:", response)
            result = response.get("result", {})
            if result.get("done"):
                print("episode finished, resetting")
                reset = env.reset()
                print("reset:", reset)
            time.sleep(0.05)


if __name__ == "__main__":
    main()
