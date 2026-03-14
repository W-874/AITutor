"""
配置与状态：LLM/Embedding 等从 backend.config 读取与持久化。
GET/POST /api/v1/config/llm 会读写 data/user/config.json，并触发配置重载。
"""
from fastapi import APIRouter

from backend.config import get_settings, save_runtime_config
from backend.models.schemas import SuccessResponse, LLMConfig

router = APIRouter()


def _mask_api_key(key: str) -> str:
    if not key or len(key) < 8:
        return "***"
    return key[:4] + "****" + key[-4:]


@router.get(
    "/llm",
    response_model=SuccessResponse,
    summary="查看 LLM 配置",
)
async def config_llm_get():
    """返回当前 LLM 配置；api_key 脱敏显示。"""
    cfg = get_settings().llm
    data = {
        "provider": cfg.provider,
        "base_url": cfg.base_url,
        "model": cfg.model,
        "api_key": _mask_api_key(cfg.api_key) if cfg.api_key else "",
        "timeout": cfg.timeout,
    }
    return SuccessResponse(data=data)


@router.post(
    "/llm",
    response_model=SuccessResponse,
    summary="修改 LLM 配置",
)
async def config_llm_post(body: LLMConfig):
    """更新 LLM 配置并持久化到 data/user/config.json，供 services/llm 使用。"""
    updates = {"llm": body.model_dump(exclude_none=True)}
    save_runtime_config(updates)
    cfg = get_settings().llm
    return SuccessResponse(data={
        "provider": cfg.provider,
        "base_url": cfg.base_url,
        "model": cfg.model,
        "api_key": _mask_api_key(cfg.api_key) if cfg.api_key else "",
        "timeout": cfg.timeout,
    })


@router.get(
    "/embedding",
    response_model=SuccessResponse,
    summary="查看 Embedding 配置",
)
async def config_embedding_get():
    """返回当前 Embedding（Silicon Flow BGE）配置；api_key 脱敏。"""
    cfg = get_settings().embedding
    return SuccessResponse(data={
        "provider": cfg.provider,
        "base_url": cfg.base_url,
        "model": cfg.model,
        "api_key": _mask_api_key(cfg.api_key) if cfg.api_key else "",
        "batch_size": cfg.batch_size,
    })


@router.post(
    "/embedding",
    response_model=SuccessResponse,
    summary="修改 Embedding 配置",
)
async def config_embedding_post(body: dict):
    """更新 Embedding 配置并持久化。"""
    updates = {"embedding": body}
    save_runtime_config(updates)
    return SuccessResponse(data=get_settings().embedding.model_dump())
