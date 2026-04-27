"""
Unit tests for GodotEnv — the TCP socket bridge client.
All tests mock the socket so no running Godot instance is required.
"""

import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch, PropertyMock

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))
from godot_env import GodotEnv


# ─── Helpers ─────────────────────────────────────────────────────────────────

SEEKER_OBS = [float(i) for i in range(56)] + [0.5]   # 57 features
HIDER_OBS  = [float(i) for i in range(56)] + [0.25]  # 57 features

def _make_response(**fields) -> bytes:
    """Encode a JSON response the same way Godot would send it."""
    return (json.dumps(fields) + "\n").encode("utf-8")

def _reset_response() -> bytes:
    return _make_response(
        ok=True,
        result={
            "seeker_observation": SEEKER_OBS,
            "hider_observation": HIDER_OBS,
            "info": {},
        },
    )

def _step_response(seeker_reward=1.0, hider_reward=-1.0, done=False) -> bytes:
    return _make_response(
        ok=True,
        result={
            "seeker_observation": SEEKER_OBS,
            "hider_observation": HIDER_OBS,
            "seeker_reward": seeker_reward,
            "hider_reward": hider_reward,
            "done": done,
            "info": {"episode_step": 1},
        },
    )

def _make_env_with_mock_socket(response_bytes: bytes) -> tuple[GodotEnv, MagicMock]:
    """Return a GodotEnv whose internal socket is mocked to return response_bytes."""
    env = GodotEnv()
    mock_sock = MagicMock()
    mock_sock.recv.return_value = response_bytes
    env.sock = mock_sock
    env._recv_buffer = bytearray()
    return env, mock_sock


# ─── GodotEnv.connect ────────────────────────────────────────────────────────

class TestConnect:
    def test_connect_creates_socket(self):
        with patch("socket.create_connection") as mock_create:
            mock_create.return_value = MagicMock()
            env = GodotEnv()
            env.connect()
            mock_create.assert_called_once_with(("127.0.0.1", 19000), timeout=5.0)

    def test_connect_is_idempotent(self):
        """Calling connect twice should not open a second socket."""
        with patch("socket.create_connection") as mock_create:
            mock_create.return_value = MagicMock()
            env = GodotEnv()
            env.connect()
            env.connect()
            assert mock_create.call_count == 1

    def test_close_clears_socket(self):
        with patch("socket.create_connection") as mock_create:
            mock_create.return_value = MagicMock()
            env = GodotEnv()
            env.connect()
            env.close()
            assert env.sock is None


# ─── GodotEnv.reset_both ─────────────────────────────────────────────────────

class TestResetBoth:
    def test_returns_correct_observation_lengths(self):
        env, _ = _make_env_with_mock_socket(_reset_response())
        seeker_obs, hider_obs, info = env.reset_both()
        assert len(seeker_obs) == 57
        assert len(hider_obs) == 57

    def test_sends_reset_command(self):
        env, mock_sock = _make_env_with_mock_socket(_reset_response())
        env.reset_both()
        sent = mock_sock.sendall.call_args[0][0].decode()
        payload = json.loads(sent.strip())
        assert payload["cmd"] == "reset"

    def test_info_is_dict(self):
        env, _ = _make_env_with_mock_socket(_reset_response())
        _, _, info = env.reset_both()
        assert isinstance(info, dict)

    def test_seeker_obs_values_match(self):
        env, _ = _make_env_with_mock_socket(_reset_response())
        seeker_obs, _, _ = env.reset_both()
        assert seeker_obs == SEEKER_OBS


# ─── GodotEnv.step_both ──────────────────────────────────────────────────────

class TestStepBoth:
    def test_returns_six_values(self):
        env, _ = _make_env_with_mock_socket(_step_response())
        result = env.step_both(1, 2)
        assert len(result) == 6

    def test_sends_correct_actions(self):
        env, mock_sock = _make_env_with_mock_socket(_step_response())
        env.step_both(3, 4)
        sent = mock_sock.sendall.call_args[0][0].decode()
        payload = json.loads(sent.strip())
        assert payload["cmd"] == "step"
        assert payload["seeker_action"] == 3
        assert payload["hider_action"] == 4

    def test_rewards_are_floats(self):
        env, _ = _make_env_with_mock_socket(_step_response(seeker_reward=2.5, hider_reward=-2.5))
        _, _, seeker_reward, hider_reward, _, _ = env.step_both(0, 0)
        assert isinstance(seeker_reward, float)
        assert isinstance(hider_reward, float)

    def test_reward_values_correct(self):
        env, _ = _make_env_with_mock_socket(_step_response(seeker_reward=5.0, hider_reward=-5.0))
        _, _, seeker_reward, hider_reward, _, _ = env.step_both(0, 0)
        assert seeker_reward == 5.0
        assert hider_reward == -5.0

    def test_done_is_bool(self):
        env, _ = _make_env_with_mock_socket(_step_response(done=True))
        _, _, _, _, done, _ = env.step_both(0, 0)
        assert isinstance(done, bool)
        assert done is True

    def test_not_done_by_default(self):
        env, _ = _make_env_with_mock_socket(_step_response(done=False))
        _, _, _, _, done, _ = env.step_both(0, 0)
        assert done is False


# ─── GodotEnv.step (seeker-only wrapper) ─────────────────────────────────────

class TestStep:
    def test_step_returns_four_values(self):
        env, _ = _make_env_with_mock_socket(_step_response())
        result = env.step(1)
        assert len(result) == 4

    def test_step_sends_idle_hider_action(self):
        env, mock_sock = _make_env_with_mock_socket(_step_response())
        env.step(2)
        sent = mock_sock.sendall.call_args[0][0].decode()
        payload = json.loads(sent.strip())
        assert payload["hider_action"] == GodotEnv.ACTION_IDLE


# ─── GodotEnv error handling ─────────────────────────────────────────────────

class TestErrorHandling:
    def test_raises_on_ok_false(self):
        bad_response = _make_response(ok=False, error="something_went_wrong")
        env, _ = _make_env_with_mock_socket(bad_response)
        with pytest.raises(RuntimeError, match="Bridge command failed"):
            env.reset_both()

    def test_raises_on_missing_result(self):
        bad_response = _make_response(ok=True)  # no "result" key
        env, _ = _make_env_with_mock_socket(bad_response)
        with pytest.raises(RuntimeError, match="missing result payload"):
            env.reset_both()

    def test_raises_on_socket_closed(self):
        env = GodotEnv()
        mock_sock = MagicMock()
        mock_sock.recv.return_value = b""  # empty = closed
        env.sock = mock_sock
        env._recv_buffer = bytearray()
        with pytest.raises(ConnectionError, match="Socket closed"):
            env.reset_both()


# ─── GodotEnv context manager ────────────────────────────────────────────────

class TestContextManager:
    def test_context_manager_connects_and_closes(self):
        with patch("socket.create_connection") as mock_create:
            mock_sock = MagicMock()
            mock_create.return_value = mock_sock
            env = GodotEnv()
            with env:
                assert env.sock is not None
            assert env.sock is None
