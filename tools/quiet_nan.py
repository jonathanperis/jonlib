"""Quiet-NaN comparison for invalid operations.

IEEE 754 leaves the sign of a NaN produced by an invalid operation unspecified.
Upstream builds of the pinned raymath return either quiet-NaN sign for the same
inputs depending on instruction selection. A NaN propagated from an input is
that operand's payload and stays exact. Every non-NaN result stays exact.
"""
import math
import struct

FRESH = 'fresh'
SIGN = 0x80000000
QUIET = 0x7F800000


def quiet(word):
    return isinstance(word, int) and (word & 0x7FFFFFFF) > QUIET


def _inf(word):
    return isinstance(word, int) and (word & 0x7FFFFFFF) == QUIET


def _zero(word):
    return isinstance(word, int) and (word & 0x7FFFFFFF) == 0


def _f32(op, left, right):
    def unpack(word):
        return struct.unpack('<f', struct.pack('<I', word & 0xFFFFFFFF))[0]

    def pack(value):
        try:
            return struct.unpack('<I', struct.pack('<f', value))[0]
        except OverflowError:
            return (SIGN if math.copysign(1.0, value) < 0 else 0) | QUIET

    functions = {'add': float.__add__, 'sub': float.__sub__, 'mul': float.__mul__, 'div': float.__truediv__}
    return pack(functions[op](unpack(left), unpack(right)))


def reduce_binary(op, left, right):
    """A propagated payload, FRESH for an invalid operation, or the numeric word."""
    # Which payload survives when both operands are NaN depends on the
    # instruction clang picks. A single NaN operand is returned unchanged.
    if quiet(left) and quiet(right):
        return FRESH
    if quiet(left):
        return left
    if quiet(right):
        return right
    if op == 'add' and _inf(left) and _inf(right) and (left ^ right) & SIGN:
        return FRESH
    if op == 'sub' and _inf(left) and _inf(right) and not (left ^ right) & SIGN:
        return FRESH
    if op == 'mul' and ((_zero(left) and _inf(right)) or (_inf(left) and _zero(right))):
        return FRESH
    if op == 'div' and _zero(right):
        if _zero(left) or _inf(left):
            return FRESH
        return ((left ^ right) & SIGN) | QUIET
    if op == 'div' and _inf(left) and _inf(right):
        return FRESH
    return _f32(op, left, right)


def reduce(op, left, right):
    if left == FRESH or (isinstance(left, int) and quiet(left)):
        return left
    if right == FRESH or (isinstance(right, int) and quiet(right)):
        return right
    return reduce_binary(op, left, right)


def _allows(expected, actual, kind):
    if expected == actual:
        return True
    return kind == FRESH and quiet(expected) and quiet(actual)


def _pairs(name, args):
    paired = {'add', 'subtract', 'multiply', 'divide', 'q_add', 'q_subtract', 'q_divide'}
    valued = {'add_value', 'subtract_value', 'scale', 'q_add_value', 'q_subtract_value', 'q_scale'}
    if name == 'normalize':
        return [reduce('div', reduce_binary('sub', args[0], args[1]), reduce_binary('sub', args[2], args[1]))]
    op = {
        'add': 'add', 'q_add': 'add', 'subtract': 'sub', 'q_subtract': 'sub',
        'multiply': 'mul', 'divide': 'div', 'q_divide': 'div',
        'add_value': 'add', 'q_add_value': 'add', 'subtract_value': 'sub', 'q_subtract_value': 'sub',
        'scale': 'mul', 'q_scale': 'mul',
    }[name]
    if name in paired:
        half = len(args) // 2
        return [reduce_binary(op, args[index], args[half + index]) for index in range(half)]
    if name in valued:
        return [reduce_binary(op, args[index], args[-1]) for index in range(len(args) - 1)]
    if name == 'normalize':
        return [reduce('div', reduce_binary('sub', args[0], args[1]), reduce_binary('sub', args[2], args[1]))]
    raise KeyError(name)


def modeled(name):
    return name in {
        'add', 'subtract', 'multiply', 'divide', 'add_value', 'subtract_value', 'scale',
        'q_add', 'q_subtract', 'q_divide', 'q_add_value', 'q_subtract_value', 'q_scale',
        'normalize',
    }


def acceptable(name, expected, actual, args):
    kinds = _pairs(name, args)
    if isinstance(expected, list):
        if not isinstance(actual, list) or len(expected) != len(actual) or len(kinds) != len(expected):
            return False
        return all(_allows(want, got, kind) for want, got, kind in zip(expected, actual, kinds))
    return _allows(expected, actual, kinds[0])
