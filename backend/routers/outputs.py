"""
输出文件下载 - 静态文件服务（MVP 必须）

需实现的接口：
- GET /api/outputs/{user_id}/{filename}：下载生成的报告、音频等
  - 实际文件存储在 data/outputs/{user_id}/{filename}
"""
from pathlib import Path
from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

DATA_ROOT = Path(__file__).resolve().parent.parent.parent / "data"
OUTPUTS_DIR = DATA_ROOT / "outputs"

router = APIRouter()


@router.get(
    "/{user_id}/{filename}",
    summary="下载用户生成的文件",
)
async def get_output_file(user_id: str, filename: str):
    """
    返回 data/outputs/{user_id}/{filename} 的文件；
    若不存在返回 404。用于报告、音频等下载。
    """
    path = OUTPUTS_DIR / user_id / filename
    if not path.is_file():
        raise HTTPException(status_code=404, detail="文件不存在")
    return FileResponse(path, filename=filename)
