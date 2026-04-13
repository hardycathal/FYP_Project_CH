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

    def reset(self) -> dict[str, Any]:
        self._send_command({"cmd": "reset"})
        return self.step(self.ACTION_IDLE)

    def step(self, action: int) -> dict[str, Any]:
        return self._send_command({"cmd": "step", "action": int(action)})

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

    def __enter__(self) -> "GodotEnv":
        self.connect()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()
