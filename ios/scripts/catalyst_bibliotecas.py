#!/usr/bin/env python3
"""Prepara las bibliotecas del motor de video (AetherEngine) para la app de Mac de verdad (Mac Catalyst).

FFmpegBuild, LibDovi y LibTrueHD traen sus binarios para iPhone, iPad, Mac, TV y Vision Pro, pero no para Mac
Catalyst. Este script copia cada paquete a `ios/Vendor/catalyst/<paquete>` y le agrega a cada xcframework una rebanada
`ios-arm64-maccatalyst`, hecha con la de macOS (arm64) marcada como Mac Catalyst con `vtool`. El código de máquina es
el mismo (arm64, mismas bibliotecas del sistema); solo cambia la etiqueta de plataforma que revisan el enlazador y dyld.

`project.catalyst.yml` apunta a esas copias en vez de a GitHub. Se corre otra vez cada que suba la versión de
AetherEngine (o si se borra `ios/Vendor/`).

Uso:
    python3 ios/scripts/catalyst_bibliotecas.py [carpeta de checkouts de SwiftPM]

La carpeta de checkouts es la de una compilación normal de la app (por omisión
`/tmp/dd-orbital-release/SourcePackages/checkouts`); si no existe, primero compila o corre
`xcodebuild -resolvePackageDependencies -derivedDataPath /tmp/dd-orbital-release` en `ios/App`.
"""

from __future__ import annotations

import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

PACKAGES = ["FFmpegBuild", "LibDovi", "LibTrueHD"]
SOURCE_SLICE = "macos-arm64_x86_64"
TARGET_SLICE = "ios-arm64-maccatalyst"
# Mac Catalyst 18.0 = la base de iOS 18 de la app (macOS 15).
MIN_VERSION = "18.0"
SDK_VERSION = "27.0"

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "ios" / "Vendor" / "catalyst"


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def retarget(binary: Path) -> None:
    """Deja solo arm64 y marca el archivo (dylib u objeto) como Mac Catalyst."""
    thin = binary.with_name(binary.name + ".thin")
    archs = subprocess.run(["lipo", "-archs", str(binary)], capture_output=True, text=True, check=True).stdout.split()
    if len(archs) > 1:
        run("lipo", "-thin", "arm64", str(binary), "-output", str(thin))
        thin.replace(binary)
    run("vtool", "-set-build-version", "maccatalyst", MIN_VERSION, SDK_VERSION, "-replace",
        "-output", str(thin), str(binary))
    thin.replace(binary)


def version(text: str) -> int:
    major, minor = (int(x) for x in text.split("."))
    return major << 16 | minor << 8


def patch_object(obj: Path) -> None:
    """Un objeto (.o) arm64 de una biblioteca estática: `vtool` no cabe en sus comandos de carga (no traen espacio de
    sobra), así que se cambia en su lugar el campo de plataforma de LC_BUILD_VERSION, que ocupa lo mismo."""
    data = bytearray(obj.read_bytes())
    magic, _cpu, _sub, _type, ncmds, _size, _flags, _reserved = struct.unpack_from("<8I", data, 0)
    if magic != 0xFEEDFACF:
        sys.exit(f"{obj}: no es un objeto Mach-O de 64 bits")
    offset, found = 32, False
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<2I", data, offset)
        if cmd == 0x32:   # LC_BUILD_VERSION: platform, minos, sdk
            struct.pack_into("<3I", data, offset + 8, 6, version(MIN_VERSION), version(SDK_VERSION))   # 6 = MACCATALYST
            found = True
        elif cmd in (0x24, 0x25, 0x2F, 0x30):   # LC_VERSION_MIN_*: no tiene forma de decir Mac Catalyst
            sys.exit(f"{obj}: trae LC_VERSION_MIN, no LC_BUILD_VERSION")
        offset += cmdsize
    if not found:
        sys.exit(f"{obj}: sin LC_BUILD_VERSION")
    obj.write_bytes(data)


def retarget_archive(archive: Path) -> None:
    """Una biblioteca estática: cada objeto se marca por separado y se vuelve a juntar."""
    thin = archive.with_name("thin-" + archive.name)
    run("lipo", "-thin", "arm64", str(archive), "-output", str(thin))
    with tempfile.TemporaryDirectory() as tmp:
        names = subprocess.run(["ar", "t", str(thin)], capture_output=True, text=True, check=True).stdout.split()
        if len(names) != len(set(names)):
            sys.exit(f"{archive}: hay objetos con el mismo nombre; ar x los pisaría")
        subprocess.run(["ar", "x", str(thin)], cwd=tmp, check=True)
        objects = [Path(tmp) / n for n in names if n.endswith(".o")]
        for obj in objects:
            patch_object(obj)
        thin.unlink()
        archive.unlink()
        run("libtool", "-static", "-no_warning_for_no_symbols", "-o", str(archive), *map(str, objects))


def add_slice(xcframework: Path) -> None:
    info_path = xcframework / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    libraries = [lib for lib in info["AvailableLibraries"] if lib["LibraryIdentifier"] != TARGET_SLICE]
    source = next(lib for lib in libraries if lib["LibraryIdentifier"] == SOURCE_SLICE)

    src_dir, dst_dir = xcframework / SOURCE_SLICE, xcframework / TARGET_SLICE
    shutil.rmtree(dst_dir, ignore_errors=True)
    shutil.copytree(src_dir, dst_dir, symlinks=True)
    shutil.rmtree(dst_dir / "dSYMs", ignore_errors=True)   # los símbolos de depuración son de la rebanada de macOS

    library = dst_dir / source["LibraryPath"]
    if library.suffix == ".framework":
        name = library.stem
        retarget((library / "Versions" / "A" / name).resolve() if (library / "Versions").exists() else library / name)
        run("codesign", "--force", "--sign", "-", "--timestamp=none", str(library))
    else:
        retarget_archive(library)

    entry = {k: v for k, v in source.items() if k not in ("DebugSymbolsPath",)}
    entry.update(LibraryIdentifier=TARGET_SLICE, SupportedPlatform="ios", SupportedPlatformVariant="maccatalyst",
                 SupportedArchitectures=["arm64"])
    info["AvailableLibraries"] = libraries + [entry]
    info_path.write_bytes(plistlib.dumps(info))


def main() -> None:
    checkouts = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/dd-orbital-release/SourcePackages/checkouts")
    if not checkouts.is_dir():
        sys.exit(f"No encuentro {checkouts}: compila la app normal una vez o pásame la carpeta de checkouts.")
    OUT.mkdir(parents=True, exist_ok=True)
    for package in PACKAGES:
        src, dst = checkouts / package, OUT / package
        shutil.rmtree(dst, ignore_errors=True)
        shutil.copytree(src, dst, symlinks=True, ignore=shutil.ignore_patterns(".git"))
        run("chmod", "-R", "u+w", str(dst))   # los checkouts de SwiftPM vienen de solo lectura
        for xcframework in sorted(dst.rglob("*.xcframework")):
            add_slice(xcframework)
            print(f"listo: {xcframework.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
