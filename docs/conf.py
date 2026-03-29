from __future__ import annotations

project = "FleetPrompt"
author = "Travis Burandt"
copyright = "2026, FleetPrompt"
release = "latest"
version = release

extensions = ["myst_parser"]

exclude_patterns = [
    "_build",
    "Thumbs.db",
    ".DS_Store",
]

source_suffix = {
    ".rst": "restructuredtext",
    ".md": "markdown",
}

root_doc = "index"
language = "en"

myst_heading_anchors = 3
myst_enable_extensions = [
    "colon_fence",
    "deflist",
]

html_theme = "alabaster"
html_title = "FleetPrompt Documentation"
