from contextlib import contextmanager

import mysql.connector

from .config import settings


def connect(*, select_database: bool = True):
    options = {
        "host": settings.host,
        "port": settings.port,
        "user": settings.user,
        "password": settings.password,
        "autocommit": False,
    }
    if select_database:
        options["database"] = settings.database
    return mysql.connector.connect(**options)


@contextmanager
def read_connection():
    connection = connect()
    try:
        yield connection
    finally:
        connection.close()


@contextmanager
def transaction():
    connection = connect()
    try:
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()
