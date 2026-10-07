"""The Alembic migration must build the same schema the app expects."""
from alembic.config import Config
from sqlalchemy import create_engine, inspect

from alembic import command


def test_alembic_upgrade_and_downgrade(tmp_path, monkeypatch):
    db_file = tmp_path / "migr.db"
    url = f"sqlite:///{db_file}"
    cfg = Config("alembic.ini")
    cfg.set_main_option("sqlalchemy.url", url)
    command.upgrade(cfg, "head")
    cols = {c["name"] for c in inspect(create_engine(url)).get_columns("books")}
    assert {"id", "title", "author", "status", "pages", "rating"} <= cols
    command.downgrade(cfg, "base")
    assert "books" not in inspect(create_engine(url)).get_table_names()
