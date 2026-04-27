"""
Unit tests for DualRoleEnv and helpers in train_dual_ppo.py.
GodotEnv is mocked so no Godot instance is needed.
"""

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch
import tempfile

import pytest
import numpy as np

sys.path.insert(0, str(Path(__file__).parent.parent))

from train_dual_ppo import DualRoleEnv, RandomPolicy, extract_step_count, find_resume_path

OBS_SIZE = 57
SEEKER_OBS = np.zeros(OBS_SIZE, dtype=np.float32).tolist()
HIDER_OBS  = np.ones(OBS_SIZE, dtype=np.float32).tolist()


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _make_mock_client(seeker_obs=None, hider_obs=None, done=False):
    """Return a mocked GodotEnv client."""
    client = MagicMock()
    client.reset_both.return_value = (
        seeker_obs or SEEKER_OBS,
        hider_obs or HIDER_OBS,
        {},
    )
    client.step_both.return_value = (
        seeker_obs or SEEKER_OBS,
        hider_obs or HIDER_OBS,
        1.0,   # seeker_reward
        -1.0,  # hider_reward
        done,
        {"episode_step": 1},
    )
    return client

def _make_env(role: str, done=False) -> DualRoleEnv:
    opponent = MagicMock()
    opponent.predict.return_value = (np.array(0), None)
    env = DualRoleEnv.__new__(DualRoleEnv)
    env.role = role
    env.opponent_model = opponent
    env.deterministic_opponent = True
    env.client = _make_mock_client(done=done)
    env._latest_seeker_obs = None
    env._latest_hider_obs = None

    import gymnasium as gym
    from gymnasium import spaces
    env.observation_space = spaces.Box(low=-1.0, high=1.0, shape=(OBS_SIZE,), dtype=np.float32)
    env.action_space = spaces.Discrete(5)
    return env


# ─── Observation and action spaces ───────────────────────────────────────────

class TestSpaces:
    def test_observation_space_shape(self):
        with patch("train_dual_ppo.GodotEnv"):
            opponent = MagicMock()
            env = DualRoleEnv(role="seeker", opponent_model=opponent)
        assert env.observation_space.shape == (OBS_SIZE,)

    def test_action_space_size(self):
        with patch("train_dual_ppo.GodotEnv"):
            opponent = MagicMock()
            env = DualRoleEnv(role="seeker", opponent_model=opponent)
        assert env.action_space.n == 5

    def test_invalid_role_raises(self):
        with patch("train_dual_ppo.GodotEnv"):
            with pytest.raises(ValueError, match="Unsupported role"):
                DualRoleEnv(role="spectator", opponent_model=MagicMock())


# ─── Reset ────────────────────────────────────────────────────────────────────

class TestReset:
    def test_seeker_reset_returns_seeker_obs(self):
        env = _make_env("seeker")
        obs, info = env.reset()
        assert obs.shape == (OBS_SIZE,)
        assert np.allclose(obs, np.zeros(OBS_SIZE))

    def test_hider_reset_returns_hider_obs(self):
        env = _make_env("hider")
        obs, info = env.reset()
        assert obs.shape == (OBS_SIZE,)
        assert np.allclose(obs, np.ones(OBS_SIZE))

    def test_reset_calls_reset_both(self):
        env = _make_env("seeker")
        env.reset()
        env.client.reset_both.assert_called_once()

    def test_reset_returns_info_dict(self):
        env = _make_env("seeker")
        _, info = env.reset()
        assert isinstance(info, dict)


# ─── Step ─────────────────────────────────────────────────────────────────────

class TestStep:
    def test_seeker_step_returns_seeker_reward(self):
        env = _make_env("seeker")
        env.reset()
        obs, reward, terminated, truncated, info = env.step(1)
        assert reward == 1.0

    def test_hider_step_returns_hider_reward(self):
        env = _make_env("hider")
        env.reset()
        obs, reward, terminated, truncated, info = env.step(1)
        assert reward == -1.0

    def test_step_before_reset_raises(self):
        env = _make_env("seeker")
        # _latest_seeker_obs is None — should raise
        with pytest.raises(RuntimeError, match="stepped before reset"):
            env.step(0)

    def test_obs_shape_after_step(self):
        env = _make_env("seeker")
        env.reset()
        obs, *_ = env.step(0)
        assert obs.shape == (OBS_SIZE,)

    def test_done_propagates(self):
        env = _make_env("seeker", done=True)
        env.reset()
        _, _, terminated, truncated, _ = env.step(0)
        assert terminated is True
        assert truncated is False

    def test_opponent_predict_called_on_step(self):
        env = _make_env("seeker")
        env.reset()
        env.step(2)
        env.opponent_model.predict.assert_called_once()

    def test_seeker_passes_own_action(self):
        env = _make_env("seeker")
        env.reset()
        env.step(3)
        call_args = env.client.step_both.call_args[0]
        assert call_args[0] == 3  # seeker_action

    def test_hider_passes_own_action(self):
        env = _make_env("hider")
        env.reset()
        env.step(4)
        call_args = env.client.step_both.call_args[0]
        assert call_args[1] == 4  # hider_action


# ─── RandomPolicy ─────────────────────────────────────────────────────────────

class TestRandomPolicy:
    def test_predict_returns_valid_action(self):
        policy = RandomPolicy()
        for _ in range(20):
            action, state = policy.predict(np.zeros(OBS_SIZE))
            assert 0 <= int(action) < 5
            assert state is None


# ─── extract_step_count ───────────────────────────────────────────────────────

class TestExtractStepCount:
    def test_extracts_from_standard_checkpoint_name(self):
        p = Path("ppo_dual_seeker_50000_steps.zip")
        assert extract_step_count(p) == 50000

    def test_extracts_larger_number(self):
        p = Path("ppo_dual_hider_1000000_steps.zip")
        assert extract_step_count(p) == 1000000

    def test_returns_minus_one_for_no_digits(self):
        p = Path("model_no_digits.zip")
        assert extract_step_count(p) == -1


# ─── find_resume_path ─────────────────────────────────────────────────────────

class TestFindResumePath:
    def test_returns_model_path_if_exists(self, tmp_path):
        model = tmp_path / "ppo_seeker.zip"
        model.touch()
        result = find_resume_path(model, tmp_path / "checkpoints")
        assert result == model

    def test_returns_latest_checkpoint_if_no_model(self, tmp_path):
        ckpt_dir = tmp_path / "checkpoints"
        ckpt_dir.mkdir()
        (ckpt_dir / "ppo_10000_steps.zip").touch()
        (ckpt_dir / "ppo_50000_steps.zip").touch()
        (ckpt_dir / "ppo_30000_steps.zip").touch()
        result = find_resume_path(tmp_path / "missing.zip", ckpt_dir)
        assert result.name == "ppo_50000_steps.zip"

    def test_returns_none_if_nothing_exists(self, tmp_path):
        result = find_resume_path(tmp_path / "missing.zip", tmp_path / "empty")
        assert result is None
