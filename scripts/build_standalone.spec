# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec for Zabbix MCP Server standalone binary.

Supports both --onedir (default) and --onefile modes via the
BUILD_ONEFILE environment variable, set by build_standalone.sh.

Maintained in version control — update hidden imports here when new
dependencies cause runtime ImportErrors in the frozen binary.
"""

import os
from PyInstaller.utils.hooks import collect_all, collect_submodules, collect_data_files

block_cipher = None
onefile = os.environ.get('BUILD_ONEFILE', '0') == '1'

# --- Collect all package data, binaries, and hidden imports upfront ---

extra_datas = []
extra_binaries = []
extra_hiddenimports = [
    'dotenv',
]

# Full packages that rely on dynamic imports or compiled extensions.
# Add entries here when the frozen binary fails with ImportError at runtime.
for pkg in [
    'pydantic',
    'pydantic_core',
    'fastmcp',
    'zabbix_utils',
    'certifi',
    'anyio',
    'httpx',
    'httpcore',
    'starlette',
    'uvicorn',
    'sse_starlette',
    'h11',
]:
    tmp_datas, tmp_binaries, tmp_hiddenimports = collect_all(pkg)
    extra_datas += tmp_datas
    extra_binaries += tmp_binaries
    extra_hiddenimports += tmp_hiddenimports

# mcp package needs special handling: mcp.cli requires 'typer' (optional dep)
# which we don't ship. Collect everything except the CLI submodule.
extra_hiddenimports += collect_submodules('mcp', filter=lambda name: 'mcp.cli' not in name)
extra_datas += collect_data_files('mcp')

# --- Analysis ---

a = Analysis(
    ['start_server.py'],
    pathex=[os.path.join(os.path.dirname(os.path.abspath(SPECPATH)), 'src')],
    binaries=extra_binaries,
    datas=extra_datas,
    hiddenimports=extra_hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['mcp.cli'],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

if onefile:
    # --onefile: everything packed into a single executable
    exe = EXE(
        pyz,
        a.scripts,
        a.binaries,
        a.datas,
        [],
        name='zabbix-mcp-server',
        debug=False,
        bootloader_ignore_signals=False,
        strip=True,
        upx=False,
        console=True,
    )
else:
    # --onedir: executable + _internal directory (faster startup)
    exe = EXE(
        pyz,
        a.scripts,
        [],
        exclude_binaries=True,
        name='zabbix-mcp-server',
        debug=False,
        bootloader_ignore_signals=False,
        strip=True,
        upx=False,
        console=True,
    )

    coll = COLLECT(
        exe,
        a.binaries,
        a.datas,
        strip=True,
        upx=False,
        name='zabbix-mcp-server',
    )
