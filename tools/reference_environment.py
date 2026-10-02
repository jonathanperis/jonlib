"""Explicit native-reference child environment; never mutate the Python parent.

Only named loader variables are recorded. The full environment snapshot is kept
in memory and passed as a replacement, never serialized into evidence reports.
"""
import os
import json
from types import MappingProxyType

if __package__:
    from . import runtime_image
else:
    import runtime_image

POLICIES = ('inherited', 'clean-loader')
LINUX_LOADER_NAMES = ('LD_PRELOAD', 'LD_LIBRARY_PATH', 'LD_AUDIT', 'LD_BIND_NOW',
                      'GLIBC_TUNABLES', 'LD_HWCAP_MASK', 'LD_ASSUME_KERNEL')
LOADER_NAMES = LINUX_LOADER_NAMES + runtime_image.DARWIN_LOADER_NAMES


def add_argument(parser):
    parser.add_argument('--reference-loader-policy', choices=POLICIES, default='inherited',
                        help='native reference/compiler child loader environment (default: inherited)')


def loader_context(environment):
    return {name: environment.get(name) for name in LOADER_NAMES}


class ReferenceEnvironment:
    def __init__(self, policy='inherited'):
        if type(policy) is not str or policy not in POLICIES:
            raise ValueError('Unknown reference loader policy')
        parent = dict(os.environ)
        self._parent_loader = MappingProxyType(loader_context(parent))
        child = parent.copy()
        if policy == 'clean-loader':
            for name in LOADER_NAMES:
                child.pop(name, None)
        self._child = MappingProxyType(child)
        self._policy = policy

    def receipt(self):
        return dict(schema=1, policy=self._policy,
                    scope='native-reference-and-compiler-children-only',
                    parent_loader=dict(self._parent_loader),
                    effective_child_loader=loader_context(self._child))

    def assert_unchanged(self):
        if loader_context(os.environ) != dict(self._parent_loader):
            raise ValueError('Parent reference loader context drift')
        if self._policy not in POLICIES:
            raise ValueError('Unknown reference loader policy')
        expected = dict(self._parent_loader) if self._policy == 'inherited' else dict.fromkeys(LOADER_NAMES)
        if loader_context(self._child) != expected:
            raise ValueError('Effective reference child loader context drift')

    def child(self):
        self.assert_unchanged()
        return dict(self._child)

    def require_clear(self, names=LOADER_NAMES):
        self.assert_unchanged()
        if any(self._child.get(name) is not None for name in names):
            raise ValueError('Loader overrides are outside the supported profile')

    def assert_receipt(self, receipt):
        self.assert_unchanged()
        if type(receipt) is not dict or json.dumps(receipt, sort_keys=True) != json.dumps(self.receipt(), sort_keys=True):
            raise ValueError('Mixed reference child environment policies or contexts')


def select(environment=None, policy='inherited'):
    if environment is None:
        return ReferenceEnvironment(policy)
    if type(environment) is not ReferenceEnvironment or policy != 'inherited':
        raise ValueError('Conflicting or unsupported reference child environment')
    environment.assert_unchanged()
    return environment
