"""
GraphRAG 查询：根据 query 找到相关实体与子图，用 LLM 基于子图上下文生成回答。
- 加载图，用关键词或 embedding 匹配实体（MVP 可用简单关键词匹配）
- 从匹配实体做 BFS/DFS 扩展得到子图
- 将子图（节点+边描述）拼成上下文，调用 LLM 生成答案
"""
from typing import Any, Dict, List, Tuple

from backend.config import get_settings
from backend.graph_rag.graph_store import load_graph
from backend.services import llm


def _collect_subgraph(
    nodes: List[Dict],
    edges: List[Dict],
    seed_node_ids: List[str],
    max_nodes: int,
) -> Tuple[List[Dict], List[Dict]]:
    """从 seed 节点 BFS 扩展，返回子图的 nodes 与 edges。"""
    node_by_id = {n["id"]: n for n in nodes}
    out_edges = {e["source"]: [] for e in edges}
    for e in edges:
        out_edges.setdefault(e["source"], []).append(e)
    sub_nodes = []
    sub_edges = []
    seen = set(seed_node_ids)
    queue = list(seed_node_ids)
    while queue and len(seen) < max_nodes:
        nid = queue.pop(0)
        if nid in node_by_id:
            sub_nodes.append(node_by_id[nid])
        for e in out_edges.get(nid, []):
            sub_edges.append(e)
            tid = e["target"]
            if tid not in seen:
                seen.add(tid)
                queue.append(tid)
    return sub_nodes, sub_edges


def _match_entities_to_query(nodes: List[Dict], query: str) -> List[str]:
    """简单关键词匹配：query 中的词若出现在实体 name 中则选中该实体 id。"""
    q_lower = query.lower().strip()
    if not q_lower:
        return []
    matched = []
    for n in nodes:
        name = (n.get("name") or "").lower()
        if name and name in q_lower or q_lower in name:
            matched.append(n["id"])
    if not matched:
        # 若无匹配则取前几个节点作为 seed（MVP 简化）
        matched = [n["id"] for n in nodes[: get_settings().graph_rag.community_summary_max_nodes]]
    return matched


def _format_subgraph_context(nodes: List[Dict], edges: List[Dict]) -> str:
    """将子图格式化为给 LLM 的上下文文本。"""
    lines = ["实体："]
    for n in nodes:
        lines.append(f"- {n.get('name', '')}（{n.get('type', '')}）：{n.get('description', '')}")
    lines.append("\n关系：")
    node_names = {n["id"]: n.get("name", n["id"]) for n in nodes}
    for e in edges:
        s = node_names.get(e["source"], e["source"])
        t = node_names.get(e["target"], e["target"])
        lines.append(f"- {s} --[{e.get('relation', '')}]--> {t}")
    return "\n".join(lines)


async def graph_rag_query(kb_id: str, question: str) -> str:
    """
    执行 GraphRAG 查询：加载图 → 匹配实体 → 扩展子图 → 组织上下文 → LLM 生成答案。
    """
    nodes, edges = load_graph(kb_id)
    if not nodes:
        return "当前知识库尚未构建图，无法进行 GraphRAG 查询。"
    cfg = get_settings().graph_rag
    seed_ids = _match_entities_to_query(nodes, question)
    sub_nodes, sub_edges = _collect_subgraph(nodes, edges, seed_ids, cfg.community_summary_max_nodes)
    context = _format_subgraph_context(sub_nodes, sub_edges)
    prompt = f"""基于以下知识图谱片段回答问题。若图中信息不足，可简要说明。

知识图谱片段：
{context}

问题：{question}

请直接给出简洁答案。"""
    result = await llm.chat([{"role": "user", "content": prompt}], stream=False)
    return result if isinstance(result, str) else ""
