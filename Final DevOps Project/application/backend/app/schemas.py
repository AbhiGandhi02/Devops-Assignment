from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Status = Literal["want_to_read", "reading", "finished"]


class BookIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    author: str = Field(min_length=1, max_length=120)
    status: Status = "want_to_read"
    pages: int = Field(default=0, ge=0, le=20000)
    rating: int | None = Field(default=None, ge=1, le=5)


class BookUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    author: str | None = Field(default=None, min_length=1, max_length=120)
    status: Status | None = None
    pages: int | None = Field(default=None, ge=0, le=20000)
    rating: int | None = Field(default=None, ge=1, le=5)


class BookOut(BookIn):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime
    updated_at: datetime


class Stats(BaseModel):
    total: int
    by_status: dict[str, int]
    pages_read: int
    average_rating: float | None
