"""
会话/任务状态管理 - MVP 使用内存 + 文件持久化

功能说明（需实现）：
- 用 dict 存储当前会话：session_id -> { messages, task_id, created_at, ... }
- 持久化：将会话 dump 到 data/user/sessions/{session_id}.json，启动时可加载
- 提供：create_session(session_id, initial_data)、get_session(session_id)、update_session(session_id, delta)、append_message(session_id, role, content)
- 用于 solver、research、guide 的对话与 stream 状态关联
"""
from pathlib import Path
from typing import Any, Optional

DATA_ROOT = Path(__file__).resolve().parent.parent.parent / "data"
SESSIONS_DIR = DATA_ROOT / "user" / "sessions"

# 内存缓存（可选）
_sessions: dict[str, dict] = {}


def _session_path(session_id: str) -> Path:
    return SESSIONS_DIR / f"{session_id}.json"


def create_session(session_id: str, initial_data: Optional[dict] = None) -> dict:
    """创建新会话，写入 JSON 文件，返回会话 dict。"""
    data = initial_data or {}
    data.setdefault("messages", [])
    _sessions[session_id] = data
    # TODO: 持久化到 _session_path(session_id)
    return data


def get_session(session_id: str) -> Optional[dict]:
    """获取会话；若内存无则从文件加载。"""
    if session_id in _sessions:
        return _sessions[session_id]
    # TODO: 从 _session_path(session_id) 读取 JSON
    return None


def update_session(session_id: str, delta: dict) -> dict:
    """更新会话字段并持久化。"""
    s = get_session(session_id) or create_session(session_id)
    s.update(delta)
    # TODO: 写回文件
    return s


def append_message(session_id: str, role: str, content: str) -> None:
    """追加一条消息到会话的 messages 列表并持久化。"""
    s = get_session(session_id) or create_session(session_id)
    s.setdefault("messages", []).append({"role": role, "content": content})
    # TODO: 写回文件
