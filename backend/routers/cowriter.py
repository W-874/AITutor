"""
协同写作 - 文本改写与 TTS 朗读（MVP 可选）

需实现的接口：
- POST /api/v1/cowriter/rewrite：文本改写/扩展/缩短/加注释
  - 请求体：text、action（rewrite|expand|shorten|annotate）、options
  - 返回改写结果，可选用短流式
- POST /api/v1/cowriter/tts：TTS 朗读，返回音频 URL 或 base64
"""
from fastapi import APIRouter

from backend.models.schemas import (
    SuccessResponse,
    CowriterRewriteRequest,
    CowriterTTSRequest,
)
from backend.services import llm

router = APIRouter()


@router.post(
    "/rewrite",
    response_model=SuccessResponse,
    summary="文本改写/扩展/缩短/加注释",
)
async def cowriter_rewrite(body: CowriterRewriteRequest):
    """
    根据 action 调用 LLM 对 text 进行改写、扩展、缩短或加注释；
    可选返回流式片段（short stream）。
    """
    # TODO: prompt = 根据 body.action 构造；llm.chat(...) 返回结果
    return SuccessResponse(data={"text": ""})


@router.post(
    "/tts",
    response_model=SuccessResponse,
    summary="TTS 朗读",
)
async def cowriter_tts(body: CowriterTTSRequest):
    """
    调用 TTS 服务（如 Azure Speech、OpenAI TTS）生成音频；
    返回静态文件 URL（存 data/outputs/）或 base64 音频数据。
    """
    # TODO: 生成音频 → 保存到 data/outputs/{user_id}/ 或返回 base64
    return SuccessResponse(data={"url": "", "base64": None})
