from fastapi import HTTPException
from fastapi.routing import APIRouter

from app.core.success_response import success_response
from app.db.db_config import check_database_connection
from app.db.pg_runtime_store import check_runtime_store_connection

health_router = APIRouter(prefix="/health")

@health_router.get("/live", tags=["健康检查"], summary="健康检查")
async def get_health_application_status():
    """健康检查-存活"""
    return success_response(
        message="health application status",
        data={
            "status": "ok"
        }
    )

@health_router.get("/ready", tags=["健康检查"], summary="健康检查")
async def get_health_readiness():
    """健康检查-就绪"""
    database_status = await check_database_connection()
    runtime_store_status = await check_runtime_store_connection()
    if database_status and runtime_store_status:
        return success_response(
            message="health readiness status",
            data={
                "status": "ok"
            }
        )
    else:
        raise HTTPException(status_code=503, detail="PostgreSQL连接或运行态存储检查失败")

