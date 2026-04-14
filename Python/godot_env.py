import json
import socket
from typing import Any


class GodotEnv:
    ACTION_IDLE = 0

    def __init__(self, host: str = "127.0.0.1", port: int = 19000, timeout: float = 5.0) -> None:
        self.host = host
        self.port = port
        self.timeout = timeout
        self.sock: socket.socket | None = None

    def connect(self) -> None:
        if self.sock is not None:
            return
        self.sock = socket.create_connection((self.host, self.port), timeout=self.timeout)

    def close(self) -> None:
        if self.sock is not None:
            self.sock.close()
            self.sock = None

    def reset(self) -> tuple[list[float], dict[str, Any]]:
        seeker_observation, _hider_observation, info = self.reset_both()
        return seeker_observation, info

    def reset_both(self) -> tuple[list[float], list[float], dict[str, Any]]:
        self._send_command({"cmd": "reset"})
        response = self._send_command(
            {
                "cmd": "step",
                "seeker_action": self.ACTION_IDLE,
                "hider_action": self.ACTION_IDLE,
            }
        )
        result = self._unwrap_response(response)
        return (
            list(result["seeker_observation"]),
            list(result["hider_observation"]),
            dict(result["info"]),
        )

    def step(self, action: int) -> tuple[list[float], float, bool, dict[str, Any]]:
        seeker_observation, _hider_observation, seeker_reward, _hider_reward, done, info = self.step_both(
            int(action),
            self.ACTION_IDLE,
        )
        return seeker_observation, seeker_reward, done, info

    def step_both(
        self,
        seeker_action: int,
        hider_action: int,
    ) -> tuple[list[float], list[float], float, float, bool, dict[str, Any]]:
        response = self._send_command(
            {
                "cmd": "step",
                "seeker_action": int(seeker_action),
                "hider_action": int(hider_action),
            }
        )
        result = self._unwrap_response(response)
        return (
            list(result["seeker_observation"]),
            list(result["hider_observation"]),
            float(result["seeker_reward"]),
            float(result["hider_reward"]),
            bool(result["done"]),
            dict(result["info"]),
        )

    def reset_raw(self) -> dict[str, Any]:
        self._send_command({"cmd": "reset"})
        return self._send_command(
            {
                "cmd": "step",
                "seeker_action": self.ACTION_IDLE,
                "hider_action": self.ACTION_IDLE,
            }
        )

    def step_raw(self, action: int) -> dict[str, Any]:
        return self._send_command(
            {
                "cmd": "step",
                "seeker_action": int(action),
                "hider_action": self.ACTION_IDLE,
            }
        )

    def step_raw_both(self, seeker_action: int, hider_action: int) -> dict[str, Any]:
        return self._send_command(
            {
                "cmd": "step",
                "seeker_action": int(seeker_action),
                "hider_action": int(hider_action),
            }
        )

    def _send_command(self, payload: dict[str, Any]) -> dict[str, Any]:
        if self.sock is None:
            self.connect()
        assert self.sock is not None
        self.sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))
        return json.loads(self._recv_line())

    def _recv_line(self) -> str:
        assert self.sock is not None
        data = bytearray()
        while True:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("Socket closed by server")
            data.extend(chunk)
            newline = data.find(b"\n")
            if newline != -1:
                return data[:newline].decode("utf-8")

    def _unwrap_response(self, response: dict[str, Any]) -> dict[str, Any]:
        if not response.get("ok", False):
            raise RuntimeError(f"Bridge command failed: {response}")
        result = response.get("result")
        if not isinstance(result, dict):
            raise RuntimeError(f"Bridge response missing result payload: {response}")
        return result

    def __enter__(self) -> "GodotEnv":
        self.connect()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()
