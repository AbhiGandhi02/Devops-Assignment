"""create books table

Revision ID: 0001
Revises:
Create Date: 2026-10-07
"""
import sqlalchemy as sa

from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "books",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("author", sa.String(120), nullable=False),
        sa.Column("status", sa.String(20), nullable=False, server_default="want_to_read"),
        sa.Column("pages", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("rating", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_books_status", "books", ["status"])


def downgrade() -> None:
    op.drop_index("ix_books_status", table_name="books")
    op.drop_table("books")
