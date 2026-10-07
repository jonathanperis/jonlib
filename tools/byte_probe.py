"""Bounded byte-result serialization shared by binary codec probes."""
import json


def parse_results(text):
    results=[]
    current=[]
    for line in text.splitlines():
        row=json.loads(line)
        if row is None:
            if current:raise ValueError('Failure inside an unfinished byte result')
            results.append(None)
        elif row=='end':
            results.append(current)
            current=[]
        elif isinstance(row,list) and 1<=len(row)<=256 and all(type(value) is int and 0<=value<=255 for value in row):
            current.extend(row)
        else:
            raise ValueError('Malformed byte output chunk')
    if current:raise ValueError('Unterminated byte result')
    return results


# C side of the same protocol: byte() streams values in <=256-element JSON
# chunks, word() emits a little-endian U32 and end() closes one result.
C_EMITTER = '\n'.join([
    'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
    'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
    'static void end(void){if(used){puts("]");used=0;}puts("\\"end\\"");}',
])


BEND_EMITTER='''def chunk.put(full: Bool, partial: List<U32>, chunks: List<List<U32>>) -> List<U32> & List<List<U32>>:
  match full:
    case False{}: (partial, chunks)
    case True{}: (Nil{}, Con{List.reverse(&1, U32, partial), chunks})
def chunk.finish(partial: List<U32>, chunks: List<List<U32>>) -> List<List<U32>>:
  match partial:
    case Nil{}: List.reverse(&1, List<U32>, chunks)
    case _: List.reverse(&1, List<U32>, Con{List.reverse(&1, U32, partial), chunks})
def chunked(~q: Quant, bytes: List<q, U32>, +count: U32, state: List<U32> & List<List<U32>>) -> List<List<U32>>:
  match bytes state:
    case Nil{} Tuple{partial, chunks}: chunk.finish(partial, chunks)
    case Con{byte, rest} Tuple{partial, chunks}:
      chunked(~q, rest, ((count + 1) % 256 : U32), chunk.put(U32.is_eq(count, 255), Con{byte, partial}, chunks))
def emit_chunks(chunks: List<List<U32>>) -> IO(Unit):
  match chunks:
    case Nil{}: IO.print("\\"end\\"")
    case Con{chunk, rest}:
      do IO<Unit>:
        IO.print(List.show(~&1, ~U32, ~U32.show, chunk))
        emit_chunks(rest)
def emit_bytes(~q: Quant, bytes: List<q, U32>) -> IO(Unit):
  emit_chunks(chunked(~q, bytes, 0, (Nil{}, Nil{})))
'''

# Surface results (programs importing jonlib as J): image() emits a stored
# J.Surface as format, width and height words then its raw sample bytes, the
# layout of C_IMAGE; a failed Result prints null.
SURFACE_EMITTER = BEND_EMITTER + '''def word_bytes(n: Nat, +word: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: values
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), values})
def prepend(reversed: List<U32>, values: List<U32>) -> List<U32>:
  match reversed:
    case Nil{}: values
    case Con{value, rest}: prepend(rest, Con{value, values})
def exported(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = data
  emit_bytes(~&1, prepend(word_bytes(4n, height, word_bytes(4n, width, word_bytes(4n, format, Nil{}))), bytes))
def image(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("null")
    case Done{surface}: exported(J.Surface.export(surface))
'''

C_IMAGE = C_EMITTER + '\n' + ('static void image(Image im){word(im.format);word(im.width);word(im.height);unsigned char *p=im.data;'
                              'int n=GetPixelDataSize(im.width,im.height,im.format);for(int i=0;i<n;i++)byte(p[i]);end();}')
