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
        # 0/0 is an invalid operation. A nonzero dividend over zero, including
        # infinity, is a signed infinity (IEEE 754), not a NaN.
        if _zero(left):
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


def _combine(op, left, right):
    if left == FRESH or right == FRESH:
        return FRESH
    return reduce_binary(op, left, right)


def _mul(left, right):
    if left == FRESH or right == FRESH:
        return FRESH
    product = reduce_binary('mul', left, right)
    # Inlined raw multiply does not keep a NaN payload: clang can flip the
    # sign. Component Sse.mul stays on reduce_binary and keeps one payload.
    if isinstance(product, int) and quiet(product) and (quiet(left) or quiet(right) or left == FRESH or right == FRESH):
        return FRESH
    return product


def _dot(left, right):
    acc = _mul(left[0], right[0])
    for index in range(1, len(left)):
        acc = _combine('add', acc, _mul(left[index], right[index]))
    return acc


def _lerp(start, end, amount):
    return _combine('add', start, _combine('mul', amount, reduce_binary('sub', end, start)))


def _floor(word):
    if word == FRESH or (isinstance(word, int) and quiet(word)):
        return FRESH
    if isinstance(word, int) and (word & 0x7FFFFFFF) == QUIET:
        return word
    value = struct.unpack('<f', struct.pack('<I', word & 0xFFFFFFFF))[0]
    try:
        return struct.unpack('<I', struct.pack('<f', math.floor(value)))[0]
    except (OverflowError, ValueError):
        return word


def _sum_squares(left, right):
    acc = None
    for one, other in zip(left, right):
        delta = reduce_binary('sub', one, other)
        square = _combine('mul', delta, delta)
        acc = square if acc is None else _combine('add', acc, square)
    return acc


def _reflect(vector, normal):
    dot = _dot(vector, normal)
    out = []
    for component, axis in zip(vector, normal):
        scaled = _combine('mul', _combine('mul', axis, 0x40000000), dot)
        out.append(_combine('sub', component, scaled))
    return out


def _hamilton(x, y, z, w, a, b, c, d):
    def expr(parts):
        acc = _mul(parts[0][0], parts[0][1])
        for op, left, right in parts[1:]:
            acc = _combine(op, acc, _mul(left, right))
        return acc
    return [
        expr([(x, d), ('add', w, a), ('add', y, c), ('sub', z, b)]),
        expr([(y, d), ('add', w, b), ('add', z, a), ('sub', x, c)]),
        expr([(z, d), ('add', w, c), ('add', x, b), ('sub', y, a)]),
        expr([(w, d), ('sub', x, a), ('sub', y, b), ('sub', z, c)]),
    ]


def _q_invert(x, y, z, w):
    square = _dot((x, y, z, w), (x, y, z, w))
    if square in (0, SIGN):
        return [x, y, z, w]
    inverse = FRESH if square == FRESH or (isinstance(square, int) and quiet(square)) else reduce_binary('div', 0x3F800000, square)
    def negate(value):
        if value == FRESH:
            return FRESH
        return value ^ SIGN
    return [_combine('mul', x, negate(inverse)), _combine('mul', y, negate(inverse)),
            _combine('mul', z, negate(inverse)), _combine('mul', w, inverse)]


def _q_nlerp(args):
    width = (len(args) - 1) // 2
    amount = args[-1]
    lerped = [_lerp(args[index], args[width + index], amount) for index in range(width)]
    if any(item == FRESH or (isinstance(item, int) and quiet(item)) for item in lerped):
        return [FRESH] * width
    return None


def result_kind(name, args):
    """Per-result kind. None means every bit stays in the comparison.

    Component operations use the Sse model. Sums, products, interpolation and
    quaternion formulas follow the Jonmath association. FRESH is a quiet NaN
    whose sign is not fixed.
    """
    if name == 'normalize' and len(args) != 3:
        return None
    if modeled(name):
        return _pairs(name, args)
    if name == 'lerp' and len(args) == 3:
        return _lerp(*args)
    if name in ('lerp', 'q_lerp'):
        width = (len(args) - 1) // 2
        amount = args[-1]
        return [_lerp(args[index], args[width + index], amount) for index in range(width)]
    if name == 'remap':
        value, start, end, out_start, out_end = args
        ratio = _combine('div', reduce_binary('sub', value, start), reduce_binary('sub', end, start))
        return _combine('add', _combine('mul', ratio, reduce_binary('sub', out_end, out_start)), out_start)
    if name == 'wrap':
        value, lower, upper = args
        span = reduce_binary('sub', upper, lower)
        quotient = _combine('div', reduce_binary('sub', value, lower), span)
        return _combine('sub', value, _combine('mul', span, _floor(quotient)))
    if name == 'dot':
        width = len(args) // 2
        return _dot(args[:width], args[width:])
    if name == 'cross' and len(args) == 4:
        x, y, u, v = args
        return _combine('sub', _mul(x, v), _mul(y, u))
    if name == 'cross' and len(args) == 6:
        x, y, z, u, v, w = args
        return [
            _combine('sub', _mul(y, w), _mul(z, v)),
            _combine('sub', _mul(z, u), _mul(x, w)),
            _combine('sub', _mul(x, v), _mul(y, u)),
        ]
    if name == 'reflect':
        width = len(args) // 2
        return _reflect(args[:width], args[width:])
    if name == 'distance_sqr':
        width = len(args) // 2
        return _sum_squares(args[:width], args[width:])
    if name == 'distance':
        width = len(args) // 2
        square = _sum_squares(args[:width], args[width:])
        if square == FRESH or (isinstance(square, int) and quiet(square)):
            return FRESH
        return None
    if name == 'q_multiply':
        return _hamilton(*args)
    if name == 'q_invert':
        return _q_invert(*args[:4])
    if name == 'q_nlerp':
        return _q_nlerp(args)
    return None


def canonical(name, args, value):
    """Fold a fresh quiet NaN to the canonical positive payload. Other bits stay."""
    kind = result_kind(name, args)
    return _fold(value, kind)


def _fold(value, kind):
    if kind is None:
        return value
    if isinstance(value, list):
        kinds = kind if isinstance(kind, list) else [kind] * len(value)
        if len(kinds) != len(value):
            return value
        return [_fold(item, one) for item, one in zip(value, kinds)]
    if isinstance(kind, list):
        if len(kind) != 1:
            return value
        kind = kind[0]
    if kind == FRESH and isinstance(value, int) and quiet(value):
        return 0x7FC00000
    return value
