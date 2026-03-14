"""
GraphRAG 建图：从知识库 chunk 文本中抽取实体与关系，构建图并持久化。
- 使用 LLM 对每个 chunk 做实体识别与关系抽取（可批量以节省调用）
- 去重合并实体，边为 (source_entity, target_entity, relation)
- 写入 graph_store
"""
import json
import re
from typing import Any, Dict, List, Tuple

from backend.config import get_settings
from backend.graph_rag.graph_store import save_graph
from backend.services import llm


async def _extract_entities_relations_llm(chunk_text: str) -> Tuple[List[Dict], List[Dict]]:
    """
    调用 LLM 从单段文本抽取实体与关系。
    返回 (entities, relations)，entities 为 [{"name","type","description?"}]，
    relations 为 [{"source","target","relation"}].
    """
    cfg = get_settings().graph_rag
    prompt = f"""从以下文本中抽取实体与关系。
要求：
- 实体最多 {cfg.max_entities_per_chunk} 个，关系最多 {cfg.max_relations_per_chunk} 条。
- 以 JSON 格式返回，且只返回一个 JSON 对象，不要其他说明。
格式示例：
{{"entities":[{{"name":"实体名","type":"类型"}}],"relations":[{{"source":"实体A","target":"实体B","relation":"关系描述"}}]}}

文本：
{chunk_text[:2000]}
"""
    resp = await llm.chat([{"role": "user", "content": prompt}], stream=False)
    if not resp or not isinstance(resp, str):
        return [], []
    raw = resp.strip()
    for start in ("```json", "```"):
        if raw.startswith(start):
            raw = raw[len(start):].strip()
    if raw.endswith("```"):
        raw = raw[:-3].strip()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return [], []
    return data.get("entities", []), data.get("relations", [])


def _normalize_entity_name(name: str) -> str:
    return re.sub(r"\s+", " ", (name or "").strip())[:200]


async def build_graph_from_chunks(chunks: List[Dict[str, Any]]) -> Tuple[List[Dict], List[Dict]]:
    """
    从 chunk 列表（每项含 text）逐个抽取实体与关系，合并去重后构成图。
    chunks: [{"id","text","source"}, ...]
    返回 (nodes, edges)，供 save_graph 写入。
    """
    name_to_id: Dict[str, str] = {}
    nodes: List[Dict] = []
    edges: List[Dict] = []

    for c in chunks:
        text = c.get("text", "")
        if not text.strip():
            continue
        ents, rels = await _extract_entities_relations_llm(text)
        for e in ents:
            name = _normalize_entity_name(e.get("name", ""))
            if not name or name in name_to_id:
                continue
            nid = f"e_{len(name_to_id)}"
            name_to_id[name] = nid
            nodes.append({
                "id": nid,
                "name": name,
                "type": e.get("type", "entity"),
                "description": e.get("description", ""),
            })
        for r in rels:
            s = _normalize_entity_name(r.get("source", ""))
            t = _normalize_entity_name(r.get("target", ""))
            if not s or not t or s == t:
                continue
            if s not in name_to_id or t not in name_to_id:
                continue
            edges.append({
                "source": name_to_id[s],
                "target": name_to_id[t],
                "relation": (r.get("relation") or "").strip()[:500],
            })

    return nodes, edges


async def build_and_save_graph(kb_id: str, chunks: List[Dict[str, Any]]) -> None:
    """建图并持久化到 data/graph_rag/{kb_id}/。"""
    nodes, edges = await build_graph_from_chunks(chunks)
    save_graph(kb_id, nodes, edges)
