from .repository import save_order


async def create_order(payload):
    result = save_order(payload)
    result.notify_owner()
    return result
