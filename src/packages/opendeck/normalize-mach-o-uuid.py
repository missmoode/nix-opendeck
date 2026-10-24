#!/usr/bin/env python3
"""Set a reproducible LC_UUID in a thin 64-bit Mach-O executable.

Hash the file before its embedded code signature, with the original LC_UUID
zeroed. This ignores both a nondeterministic linker UUID and its dependent
signature. The executable MUST be signed again after normalization.
"""

import hashlib
import struct
import sys
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
LC_UUID = 0x1B
LC_CODE_SIGNATURE = 0x1D
HEADER_SIZE = 32


def normalize(path: Path) -> str:
    with path.open("r+b") as executable:
        data = bytearray(executable.read())
        if len(data) < HEADER_SIZE or struct.unpack_from("<I", data)[0] != MH_MAGIC_64:
            raise ValueError("expected a thin, little-endian 64-bit Mach-O executable")

        command_count, commands_size = struct.unpack_from("<II", data, 16)
        commands_end = HEADER_SIZE + commands_size
        if commands_end > len(data):
            raise ValueError("Mach-O load commands extend beyond the end of the file")

        offset = HEADER_SIZE
        uuid_offset = None
        signature_offset = len(data)

        for _ in range(command_count):
            if offset + 8 > commands_end:
                raise ValueError("truncated Mach-O load command")
            command, size = struct.unpack_from("<II", data, offset)
            if size < 8 or offset + size > commands_end:
                raise ValueError("invalid Mach-O load command size")

            if command == LC_UUID:
                if size != 24 or uuid_offset is not None:
                    raise ValueError("expected exactly one 24-byte LC_UUID command")
                uuid_offset = offset + 8
            elif command == LC_CODE_SIGNATURE:
                if size < 16:
                    raise ValueError("truncated LC_CODE_SIGNATURE command")
                start, length = struct.unpack_from("<II", data, offset + 8)
                if length:
                    if start < commands_end or start + length > len(data):
                        raise ValueError("code signature is outside the Mach-O file")
                    signature_offset = min(signature_offset, start)

            offset += size

        if offset != commands_end:
            raise ValueError("Mach-O load command count and size disagree")
        if uuid_offset is None:
            raise ValueError("Mach-O executable has no LC_UUID command")

        # Hash the unsigned content, not the old UUID or signature bytes.
        data[uuid_offset : uuid_offset + 16] = b"\0" * 16
        digest = bytearray(hashlib.sha256(memoryview(data)[:signature_offset]).digest()[:16])
        # RFC 9562 UUIDv8: application-defined bits derived from SHA-256.
        digest[6] = (digest[6] & 0x0F) | 0x80
        digest[8] = (digest[8] & 0x3F) | 0x80

        executable.seek(uuid_offset)
        executable.write(digest)
        return bytes(digest).hex()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"Usage: {sys.argv[0]} MACH_O_EXECUTABLE")
    try:
        print(f"Normalized Mach-O LC_UUID: {normalize(Path(sys.argv[1]))}")
    except (OSError, ValueError) as error:
        sys.exit(f"error: could not normalize Mach-O LC_UUID: {error}")
