import logging
import os
from logging.handlers import RotatingFileHandler

from Config import cfg

_LOGGERS: dict[str, logging.Logger] = {}

_FORMATTER = logging.Formatter(
    fmt="%(asctime)s | %(levelname)-8s | %(name)-25s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)


def _build_console_handler() -> logging.StreamHandler:
    handler = logging.StreamHandler()
    handler.setFormatter(_FORMATTER)
    return handler


def _build_file_handler() -> RotatingFileHandler:
    log_dir = os.path.dirname(cfg.log_file_path)
    if log_dir:
        os.makedirs(log_dir, exist_ok=True)
    handler = RotatingFileHandler(
        filename=cfg.log_file_path,
        maxBytes=cfg.log_max_bytes,
        backupCount=cfg.log_backup_count,
        encoding="utf-8",
    )
    handler.setFormatter(_FORMATTER)
    return handler


def get_logger(name: str) -> logging.Logger:
    if name in _LOGGERS:
        return _LOGGERS[name]

    logger = logging.getLogger(name)
    numeric_level = getattr(logging, cfg.log_level.upper(), logging.INFO)
    logger.setLevel(numeric_level)
    logger.propagate = False

    if cfg.log_to_console:
        logger.addHandler(_build_console_handler())

    if cfg.log_to_file:
        logger.addHandler(_build_file_handler())

    _LOGGERS[name] = logger
    return logger
