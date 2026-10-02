"""Strict shared Darwin runtime-image metadata contract for native angle tools.

Linux callers retain their existing ELF/file contracts. Darwin provenance is
observed in each native process, never inferred from platform or an on-disk path.
"""
import copy
import hashlib
from pathlib import Path
import re

DARWIN_PROFILES = {'darwin-macho-file-v1', 'darwin-macho-shared-cache-v1'}
DARWIN_LOADER_NAMES = ('DYLD_INSERT_LIBRARIES', 'DYLD_LIBRARY_PATH',
    'DYLD_FRAMEWORK_PATH', 'DYLD_FALLBACK_LIBRARY_PATH',
    'DYLD_FALLBACK_FRAMEWORK_PATH', 'DYLD_VERSIONED_LIBRARY_PATH',
    'DYLD_VERSIONED_FRAMEWORK_PATH', 'DYLD_ROOT_PATH', 'DYLD_IMAGE_SUFFIX',
    'DYLD_SHARED_REGION', 'DYLD_SHARED_CACHE_DIR', 'DYLD_SHARED_CACHE_DONT_VALIDATE',
    'DYLD_FORCE_FLAT_NAMESPACE', 'DYLD_BIND_AT_LAUNCH')
IMAGE_FIELDS = {'profile', 'format', 'architecture', 'endian', 'cpu_type', 'cpu_subtype',
    'image_uuid', 'storage', 'path', 'realpath', 'stat', 'cache_uuid',
    'cache_membership', 'cache_flag', 'text', 'symbol_offset', 'observations'}


def _integer(value, minimum=0, maximum=(1 << 64)-1):
    return type(value) is int and minimum <= value <= maximum


def _hex(value, size):
    return type(value) is str and re.fullmatch('[0-9a-f]{'+str(size)+'}', value) is not None


def validate_image(image):
    if type(image) is not dict or set(image) != IMAGE_FIELDS:
        raise ValueError('Malformed Darwin runtime image')
    if type(image['profile']) is not str or image['profile'] not in DARWIN_PROFILES or image['format'] != 'mach-o-64' or image['endian'] != 'little':
        raise ValueError('Unsupported Darwin runtime image profile')
    cpus = {'x86_64': (0x1000007, {3, 8}), 'aarch64': (0x100000c, {0, 1, 2})}
    if type(image['architecture']) is not str or image['architecture'] not in cpus:
        raise ValueError('Unsupported Darwin image architecture')
    cpu, subtypes = cpus[image['architecture']]
    if type(image['cpu_type']) is not int or image['cpu_type'] != cpu or not _integer(image['cpu_subtype'], maximum=0xffffffff) or image['cpu_subtype'] & 0xffffff not in subtypes:
        raise ValueError('Unsupported Mach-O CPU identity')
    if not _hex(image['image_uuid'], 32) or image['image_uuid'] == '0'*32:
        raise ValueError('Missing loaded Mach-O UUID')
    if type(image['path']) is not str or not Path(image['path']).is_absolute():
        raise ValueError('Missing loaded Darwin library path')
    text = image['text']
    if type(text) is not dict or set(text) != {'segment', 'section', 'vmaddr', 'size', 'sha256', 'protection'}:
        raise ValueError('Malformed mapped code identity')
    if (text['segment'], text['section'], text['protection']) != ('__TEXT', '__text', 'read-execute'):
        raise ValueError('Unproven immutable mapped code')
    if not _integer(text['vmaddr']) or not _integer(text['size'], 1, 256*1024*1024) or text['vmaddr'] + text['size'] >= 1 << 64 or not _hex(text['sha256'], 64):
        raise ValueError('Malformed bounded mapped-code digest')
    if not _integer(image['symbol_offset'], maximum=text['size']-1):
        raise ValueError('Actual function is outside the hashed code section')
    addresses = image['observations']
    if type(addresses) is not dict or set(addresses) != {'image_base', 'text_address', 'symbol_address'}:
        raise ValueError('Missing process address observations')
    if any(type(v) is not str or re.fullmatch('0x[0-9a-f]{1,16}', v) is None or int(v,16) == 0 for v in addresses.values()):
        raise ValueError('Malformed process address observation')
    if int(addresses['text_address'],16) < int(addresses['image_base'],16) or int(addresses['text_address'],16) + text['size'] >= 1 << 64:
        raise ValueError('Impossible mapped code addresses')
    if int(addresses['symbol_address'],16) != int(addresses['text_address'],16) + image['symbol_offset']:
        raise ValueError('Loaded symbol/code address mismatch')
    if image['profile'] == 'darwin-macho-shared-cache-v1':
        if image['storage'] != 'dyld-shared-cache' or image['cache_membership'] is not True or image['cache_flag'] is not True:
            raise ValueError('Unproven active shared-cache membership')
        if not _hex(image['cache_uuid'],32) or image['cache_uuid'] == '0'*32:
            raise ValueError('Missing active dyld shared-cache UUID')
        if image['realpath'] is not None or image['stat'] is not None:
            raise ValueError('Cache image confused with ordinary file')
    else:
        if image['storage'] != 'file' or image['cache_membership'] is not False or image['cache_flag'] is not False or image['cache_uuid'] is not None:
            raise ValueError('Ambiguous Darwin file/cache identity')
        if type(image['realpath']) is not str or not Path(image['realpath']).is_absolute():
            raise ValueError('Missing Darwin file realpath')
        if type(image['stat']) is not list or len(image['stat']) != 5 or any(not _integer(v) for v in image['stat']) or image['stat'][4] >= 10**9:
            raise ValueError('Malformed Darwin file stat')
    return image


def stable_image(image):
    """Only process virtual addresses are ASLR-dependent; remove nothing else."""
    result = copy.deepcopy(validate_image(image))
    del result['observations']
    return result


def enrich_image(image, track=None):
    """Retain mapped-code SHA256 always, and verify ordinary-file identity too."""
    identity = stable_image(image)
    if image['storage'] == 'file':
        path = Path(image['realpath'])
        if Path(image['path']).resolve(strict=True) != path or path.resolve(strict=True) != path or not path.is_file():
            raise ValueError('Loaded Darwin library realpath mismatch')
        stat = path.stat()
        observed = [stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns//10**9, stat.st_mtime_ns%10**9]
        if observed != image['stat']:
            raise ValueError('Loaded Darwin file changed after process observation')
        identity['file_sha256'] = track(path) if track else hashlib.sha256(path.read_bytes()).hexdigest()
        # Verify stat again after reading the entire ordinary file.
        stat = path.stat()
        if [stat.st_dev,stat.st_ino,stat.st_size,stat.st_mtime_ns//10**9,stat.st_mtime_ns%10**9] != observed:
            raise ValueError('Darwin file changed while hashing')
    return identity


def validate_images(images, paths=None):
    if type(images) is not dict or set(images) != {'atan2_library','fma_library'}:
        raise ValueError('Missing qualified Darwin runtime image identities')
    for name, image in images.items():
        validate_image(image)
        if paths is not None and image['path'] != paths[name]:
            raise ValueError('Native pointer library path mismatch')
    if images['atan2_library']['architecture'] != images['fma_library']['architecture']:
        raise ValueError('Mixed Darwin image architectures')
    return images


def stable_images(images):
    return {name:stable_image(image) for name,image in validate_images(images).items()}


def enrich_images(images):
    return {name:enrich_image(image) for name,image in validate_images(images).items()}
