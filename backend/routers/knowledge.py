"""
知识库管理：上传 → 解析 → 切块 → BGE embedding + BM25 索引，本地持久化。
列表与状态从 RAG 服务读取（Chroma + BM25 存于 data/knowledge_bases/{kb_id}/）。
"""
import uuid
from pathlib import Path

from fastapi import APIRouter, BackgroundTasks, File, UploadFile, HTTPException

from backend.config import get_settings
from backend.models.schemas import (
    SuccessResponse,
    ErrorResponse,
    KnowledgeUploadResponse,
    KnowledgeStatusResponse,
)
from backend.services import rag
from backend.graph_rag import build_and_save_graph

router = APIRouter()

ALLOWED_EXT = {".pdf", ".txt", ".md", ".markdown"}


@router.post(
    "/upload",
    response_model=SuccessResponse,
    responses={400: {"model": ErrorResponse}},
    summary="上传文件到知识库",
)
async def knowledge_upload(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
):
    """
    上传单个文件：保存到 data/knowledge_bases/{kb_id}/，后台执行切块、BGE embedding、Chroma 与 BM25 持久化。
    若启用 GraphRAG，会在 RAG 建库完成后异步构建图并持久化。
    """
    fn = (file.filename or "unnamed").strip()
    suf = Path(fn).suffix.lower()
    if suf not in ALLOWED_EXT:
        raise HTTPException(status_code=400, detail=f"仅支持 {ALLOWED_EXT}，当前为 {suf}")
    kb_id = str(uuid.uuid4())
    data_root = get_settings().data_root
    kb_path = data_root / get_settings().rag.persist_chroma_path / kb_id
    kb_path.mkdir(parents=True, exist_ok=True)
    save_path = kb_path / fn
    content = await file.read()
    with open(save_path, "wb") as f:
        f.write(content)

    def run_ingest():
        import asyncio
        async def _run():
            result = await rag.create_knowledge_base(kb_id, [save_path], name=Path(fn).stem)
            if result.get("status") == "ready" and get_settings().graph_rag.enabled:
                meta_path = kb_path / "chunks_meta.json"
                if meta_path.exists():
                    import json
                    with open(meta_path, "r", encoding="utf-8") as f:
                        chunks = json.load(f)
                    await build_and_save_graph(kb_id, chunks)
        asyncio.run(_run())

    background_tasks.add_task(run_ingest)
    return SuccessResponse(
        data=KnowledgeUploadResponse(kb_id=kb_id, task_id=kb_id),
    )


@router.get(
    "/list",
    response_model=SuccessResponse,
    summary="获取知识库列表",
)
async def knowledge_list():
    """返回所有知识库的 kb_id、name、status、chunks_count（从本地持久化目录读取）。"""
    data = rag.list_knowledge_bases()
    return SuccessResponse(data=data)


@router.get(
    "/{kb_id}/status",
    response_model=SuccessResponse,
    responses={404: {"model": ErrorResponse}},
    summary="查询知识库处理进度",
)
async def knowledge_status(kb_id: str):
    """返回 status（processing/ready/failed）、progress、chunks_count。"""
    data = rag.get_kb_status(kb_id)
    if data.get("status") == "not_found":
        raise HTTPException(status_code=404, detail="知识库不存在")
    return SuccessResponse(data=data)
