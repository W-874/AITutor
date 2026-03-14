"""
自动创意生成 - 从笔记本内容生成研究 idea（MVP 可选）

需实现的接口：
- POST /api/v1/ideagen/generate：从笔记本内容生成研究 idea
  - 请求体：notebook_id；可选用 WebSocket 流式返回想法列表
"""
import json
from fastapi import APIRouter, WebSocket

from backend.models.schemas import IdeagenGenerateRequest
from backend.services import llm

router = APIRouter()


@router.post(
    "/generate",
    response_model=dict,
    summary="从笔记本生成研究创意",
)
async def ideagen_generate(body: IdeagenGenerateRequest):
    """
    读取笔记本内容，用 LLM 生成若干研究 idea；
    可选用 WebSocket 流式返回，或一次性返回列表。
    """
    # TODO: 取笔记本；llm.chat("根据以下笔记生成研究创意...")；解析为列表
    return {"success": True, "ideas": []}
