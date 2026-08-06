from fastapi import APIRouter

from .service import create_order

router = APIRouter()


@router.post("/orders")
async def post_order(payload):
    return await create_order(payload)
