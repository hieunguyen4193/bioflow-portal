from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from app.core.database import engine, Base
from app.api import auth, files, jobs, pipelines, explore, admin
import app.models.user  # noqa: F401 – register ORM models
import app.models.job   # noqa: F401
import app.models.project_access  # noqa: F401


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # No migration framework in place yet; patch existing deployments in-place.
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMP"))
    yield


app = FastAPI(title="BioFlow Portal", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(files.router)
app.include_router(jobs.router)
app.include_router(pipelines.router)
app.include_router(explore.router)
app.include_router(admin.router)
