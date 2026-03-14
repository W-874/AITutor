"""
GraphRAG 模块：从知识库构建实体关系图，基于图做检索与摘要。
- 建图：从 chunk 用 LLM 抽取实体与关系，持久化到本地
- 查询：根据 query 定位相关子图，再调用 LLM 生成摘要/答案
"""
from backend.graph_rag.graph_store import load_graph, save_graph
from backend.graph_rag.graph_builder import build_graph_from_chunks, build_and_save_graph
from backend.graph_rag.query import graph_rag_query

__all__ = ["load_graph", "save_graph", "build_graph_from_chunks", "graph_rag_query"]
