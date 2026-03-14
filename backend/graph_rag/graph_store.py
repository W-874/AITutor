"""
GraphRAG 图存储：将图持久化到本地文件（JSON），不依赖内存常驻。
路径：data/graph_rag/{kb_id}/graph.json
"""
from pathlib import Path
from typing import Any, Dict, List, Optional

from backend.config import get_settings


def _graph_dir(kb_id: str) -> Path:
    return get_settings().data_root / "graph_rag" / kb_id


def _graph_path(kb_id: str) -> Path:
    return _graph_dir(kb_id) / get_settings().graph_rag.graph_filename


def save_graph(kb_id: str, nodes: List[Dict[str, Any]], edges: List[Dict[str, Any]]) -> None:
    """
    将节点与边保存为 JSON。
    nodes: [{"id", "name", "type", "description?", "chunk_ids"?}, ...]
    edges: [{"source", "target", "relation", "weight?"}, ...]
    """
    path = _graph_path(kb_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    import json
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"nodes": nodes, "edges": edges}, f, ensure_ascii=False, indent=2)


def load_graph(kb_id: str) -> tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """加载图，返回 (nodes, edges)。若文件不存在返回 ([], [])。"""
    path = _graph_path(kb_id)
    if not path.exists():
        return [], []
    import json
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("nodes", []), data.get("edges", [])
