"""
笔记本管理 - CRUD + 从其他模块添加内容

需实现的接口：
- GET  /api/v1/notebook：笔记本列表（支持标签筛选）
- POST /api/v1/notebook：创建笔记本（title、content、tags）
- GET  /api/v1/notebook/{id}：获取单个笔记本
- PUT  /api/v1/notebook/{id}：更新笔记本
- DELETE /api/v1/notebook/{id}：删除笔记本
- POST /api/v1/notebook/{id}/add：从 solver/research/question 等模块快速添加内容（source、content、ref_id）
"""
from pathlib import Path
from typing import Optional
from fastapi import APIRouter, HTTPException

from backend.models.schemas import (
    SuccessResponse,
    ErrorResponse,
    NotebookCreate,
    NotebookUpdate,
    NotebookAddRequest,
)

DATA_ROOT = Path(__file__).resolve().parent.parent.parent / "data"
NOTEBOOKS_DIR = DATA_ROOT / "user" / "notebooks"

router = APIRouter()


@router.get("", response_model=SuccessResponse, summary="笔记本列表")
async def notebook_list(tag: Optional[str] = None):
    """返回笔记本列表，可选按 tag 筛选。MVP 从 data/user/notebooks/ 或 JSON 索引读取。"""
    # TODO: 列出所有笔记本；若 tag 则过滤
    return SuccessResponse(data=[])


@router.post("", response_model=SuccessResponse, summary="创建笔记本")
async def notebook_create(body: NotebookCreate):
    """创建新笔记本，持久化到文件或 JSON。"""
    # TODO: 生成 id，写入 NOTEBOOKS_DIR / {id}.json
    return SuccessResponse(data={"id": "", "title": body.title})


@router.get("/{id}", response_model=SuccessResponse, summary="获取笔记本")
async def notebook_get(id: str):
    """返回单个笔记本详情。"""
    # TODO: 读取 NOTEBOOKS_DIR / {id}.json，不存在则 404
    return SuccessResponse(data={})


@router.put("/{id}", response_model=SuccessResponse, summary="更新笔记本")
async def notebook_update(id: str, body: NotebookUpdate):
    """更新 title/content/tags。"""
    # TODO: 读-改-写
    return SuccessResponse(data={})


@router.delete("/{id}", response_model=SuccessResponse, summary="删除笔记本")
async def notebook_delete(id: str):
    """删除笔记本。"""
    # TODO: 删除对应文件
    return SuccessResponse(data={"deleted": True})


@router.post("/{id}/add", response_model=SuccessResponse, summary="添加内容到笔记本")
async def notebook_add(id: str, body: NotebookAddRequest):
    """从 solver/research/question 等模块追加 content 到笔记本，可选 ref_id 关联。"""
    # TODO: 读取笔记本，append 一条 { source, content, ref_id }，写回
    return SuccessResponse(data={})
