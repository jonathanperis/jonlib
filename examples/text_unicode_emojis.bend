# raylib [text] example - unicode emojis, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_unicode_emojis.c (zlib/libpng,
# Copyright (c) 2019-2025 Vlad Adrian (@demizdor) and Ramon Santamaria
# (@raysan5)); see LICENSES/raylib.txt.
#
# Thirty-two random emoji drawn as glyphs of a font; a click on one shows a
# random message in one of eleven languages in a bubble, wrapped by words
# with the example's DrawTextBoxed, in a second font (a third one for
# Chinese, Korean and Japanese). SPACE draws new emoji. The three fonts are
# BMFont files with their PNG atlases (LoadFont). The emoji table is the
# example's 180 codepoints (it keeps them as 4-byte strings and draws each
# with DrawTextEx, which for one character is DrawTextCodepoint) and the
# messages are its UTF-8 bytes. DrawTextBoxed is ported for wordWrap true,
# the only way the example calls it, and nothing is selected (selectLength
# 0): its indexes are byte indexes, as in the example, since its line-break
# arithmetic adds the current character's byte count to them. The loop is
# bounded (16 steps a character); a text that needed more would be refused.
# raylib seeds the generator from time(NULL) in InitWindow; here the seed is
# a setup argument.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# emoji[i]: its codepoint (emojiCodepoints at index), its message and color.
type Emoji is Data:
  Emoji{code: U32, message: U32, color: U32}

# messages[i].
type Message is Data:
  Message{text: String, language: String}

# A character of a message: its codepoint, its width in the font
# (advanceX, or recs.width when that is 0), its byte count and the index of
# its last byte.
type Glyph is Data:
  Glyph{code: U32, width: F32, bytes: U32, last: U32}

# valid: the fonts loaded and no refusal so far. hovered and selected are
# emoji indexes (none: 4294967295) with hoveredPos and selectedPos; base and
# wide are the baseSize of fontDefault and fontAsian, tall fontEmoji's.
type State is Type:
  State{valid: Bool, rng: J.Random.State, emoji: +List<Emoji>, hovered: U32, selected: U32, hovered_at: M.Vector2, selected_at: M.Vector2, plain: J.Font, asian: J.Font, symbols: J.Font}

# DrawTextBoxed's loop variables: state == MEASURE_STATE, startLine and endLine (byte indexes; 4294967295 is -1),
# textOffsetX, textOffsetY; done after the last character or the break.
type Cursor is Data:
  Cursor{measuring: Bool, start: U32, end: U32, x: F32, y: F32, done: Bool}

# rest: the characters from i; line: those of the line being measured or drawn.
type Loop is Type:
  Loop{cursor: Cursor, rest: +List<Glyph>, line: +List<Glyph>, frame: J.Frame, font: J.Font}

# The hovered emoji found while drawing: hovered and hoveredPos.
type Hover is Data:
  Hover{index: U32, at: M.Vector2}

# emojiCodepoints: the 180 emoji.
def emojis() -> +List<U32>:
  [127744, 128512, 128514, 129315, 128515, 128518, 128521, 128523, 128526, 128525, 128536, 128535,
   128537, 128538, 128578, 129303, 129321, 129300, 129320, 128528, 128529, 128566, 128580, 128527,
   128547, 128549, 128558, 129296, 128559, 128554, 128555, 128564, 128524, 128539, 128541, 129316,
   128530, 128533, 128579, 129297, 128562, 128577, 128534, 128542, 128543, 128548, 128546, 128557,
   128550, 128553, 129327, 128556, 128560, 128561, 128563, 129322, 128565, 128545, 128544, 129324,
   128567, 129298, 129301, 129314, 129326, 129319, 128519, 129312, 129323, 129325, 129488, 129299,
   128520, 128127, 128121, 128122, 128128, 128123, 128125, 128126, 129302, 128169, 128570, 128568,
   128569, 128571, 128573, 128576, 128575, 127806, 127807, 127808, 127811, 127815, 127827, 129373,
   127813, 129381, 129361, 127814, 129364, 129365, 127805, 127798, 129362, 129382, 127812, 129372,
   127792, 127838, 129360, 129366, 129384, 129374, 129472, 127830, 127831, 129385, 129363, 127828,
   127839, 127829, 127789, 129386, 127790, 127791, 129369, 129370, 127859, 129368, 127858, 129379,
   129367, 127871, 129387, 127857, 127832, 127837, 127840, 127842, 127845, 127841, 129375, 129377,
   127846, 127850, 127874, 127856, 129383, 127851, 127855, 127868, 129371, 127861, 127862, 127870,
   127863, 127867, 129346, 129347, 129380, 129378, 128065, 128069, 128068, 128139, 128152, 128147,
   128151, 128153, 128155, 129505, 128156, 128420, 128157, 128159, 128140, 128164, 128162, 128163]

def message(index: U32) -> Message:
  match index:
    case 0: Message{"Falsches \u{c3}\u{9c}ben von Xylophonmusik qu\u{c3}\u{a4}lt jeden gr\u{c3}\u{b6}\u{c3}\u{9f}eren Zwerg", "German"}
    case 1: Message{"Bei\u{c3}\u{9f} nicht in die Hand, die dich f\u{c3}\u{bc}ttert.", "German"}
    case 2: Message{"Au\u{c3}\u{9f}erordentliche \u{c3}\u{9c}bel erfordern au\u{c3}\u{9f}erordentliche Mittel.", "German"}
    case 3: Message{"\u{d4}\u{bf}\u{d6}\u{80}\u{d5}\u{b6}\u{d5}\u{a1}\u{d5}\u{b4} \u{d5}\u{a1}\u{d5}\u{ba}\u{d5}\u{a1}\u{d5}\u{af}\u{d5}\u{ab} \u{d5}\u{b8}\u{d6}\u{82}\u{d5}\u{bf}\u{d5}\u{a5}\u{d5}\u{ac} \u{d6}\u{87} \u{d5}\u{ab}\u{d5}\u{b6}\u{d5}\u{ae}\u{d5}\u{ab} \u{d5}\u{a1}\u{d5}\u{b6}\u{d5}\u{b0}\u{d5}\u{a1}\u{d5}\u{b6}\u{d5}\u{a3}\u{d5}\u{ab}\u{d5}\u{bd}\u{d5}\u{bf} \u{d5}\u{b9}\u{d5}\u{a8}\u{d5}\u{b6}\u{d5}\u{a5}\u{d6}\u{80}", "Armenian"}
    case 4: Message{"\u{d4}\u{b5}\u{d6}\u{80}\u{d5}\u{a2} \u{d5}\u{b8}\u{d6}\u{80} \u{d5}\u{af}\u{d5}\u{a1}\u{d6}\u{81}\u{d5}\u{ab}\u{d5}\u{b6}\u{d5}\u{a8} \u{d5}\u{a5}\u{d5}\u{af}\u{d5}\u{a1}\u{d6}\u{82} \u{d5}\u{a1}\u{d5}\u{b6}\u{d5}\u{bf}\u{d5}\u{a1}\u{d5}\u{bc}, \u{d5}\u{ae}\u{d5}\u{a1}\u{d5}\u{bc}\u{d5}\u{a5}\u{d6}\u{80}\u{d5}\u{a8} \u{d5}\u{a1}\u{d5}\u{bd}\u{d5}\u{a1}\u{d6}\u{81}\u{d5}\u{ab}\u{d5}\u{b6}... \u{c2}\u{ab}\u{d4}\u{bf}\u{d5}\u{b8}\u{d5}\u{bf}\u{d5}\u{a8} \u{d5}\u{b4}\u{d5}\u{a5}\u{d6}\u{80}\u{d5}\u{b8}\u{d5}\u{b6}\u{d6}\u{81}\u{d5}\u{ab}\u{d6}\u{81} \u{d5}\u{a7}:\u{c2}\u{bb}", "Armenian"}
    case 5: Message{"\u{d4}\u{b3}\u{d5}\u{a1}\u{d5}\u{bc}\u{d5}\u{a8}\u{d5}\u{9d} \u{d5}\u{a3}\u{d5}\u{a1}\u{d6}\u{80}\u{d5}\u{b6}\u{d5}\u{a1}\u{d5}\u{b6}, \u{d5}\u{b1}\u{d5}\u{ab}\u{d6}\u{82}\u{d5}\u{b6}\u{d5}\u{a8}\u{d5}\u{9d} \u{d5}\u{b1}\u{d5}\u{b4}\u{d5}\u{bc}\u{d5}\u{a1}\u{d5}\u{b6}", "Armenian"}
    case 6: Message{"Je\u{c5}\u{bc}u kl\u{c4}\u{85}tw, sp\u{c5}\u{82}\u{c3}\u{b3}d\u{c5}\u{ba} Finom cz\u{c4}\u{99}\u{c5}\u{9b}\u{c4}\u{87} gry ha\u{c5}\u{84}b!", "Polish"}
    case 7: Message{"Dobrymi ch\u{c4}\u{99}ciami jest piek\u{c5}\u{82}o wybrukowane.", "Polish"}
    case 8: Message{"\u{c3}\u{8e}\u{c8}\u{9b}i mul\u{c8}\u{9b}umesc c\u{c4}\u{83} ai ales raylib.\n\u{c8}\u{98}i sper s\u{c4}\u{83} ai o zi bun\u{c4}\u{83}!", "Romanian"}
    case 9: Message{"\u{d0}\u{ad}\u{d1}\u{85}, \u{d1}\u{87}\u{d1}\u{83}\u{d0}\u{b6}\u{d0}\u{b0}\u{d0}\u{ba}, \u{d0}\u{be}\u{d0}\u{b1}\u{d1}\u{89}\u{d0}\u{b8}\u{d0}\u{b9} \u{d1}\u{81}\u{d1}\u{8a}\u{d1}\u{91}\u{d0}\u{bc} \u{d1}\u{86}\u{d0}\u{b5}\u{d0}\u{bd} \u{d1}\u{88}\u{d0}\u{bb}\u{d1}\u{8f}\u{d0}\u{bf} (\u{d1}\u{8e}\u{d1}\u{84}\u{d1}\u{82}\u{d1}\u{8c}) \u{d0}\u{b2}\u{d0}\u{b4}\u{d1}\u{80}\u{d1}\u{8b}\u{d0}\u{b7}\u{d0}\u{b3}!", "Russian"}
    case 10: Message{"\u{d0}\u{af} \u{d0}\u{bb}\u{d1}\u{8e}\u{d0}\u{b1}\u{d0}\u{bb}\u{d1}\u{8e} raylib!", "Russian"}
    case 11: Message{"\u{d0}\u{9c}\u{d0}\u{be}\u{d0}\u{bb}\u{d1}\u{87}\u{d0}\u{b8}, \u{d1}\u{81}\u{d0}\u{ba}\u{d1}\u{80}\u{d1}\u{8b}\u{d0}\u{b2}\u{d0}\u{b0}\u{d0}\u{b9}\u{d1}\u{81}\u{d1}\u{8f} \u{d0}\u{b8} \u{d1}\u{82}\u{d0}\u{b0}\u{d0}\u{b8}\n\u{d0}\u{98} \u{d1}\u{87}\u{d1}\u{83}\u{d0}\u{b2}\u{d1}\u{81}\u{d1}\u{82}\u{d0}\u{b2}\u{d0}\u{b0} \u{d0}\u{b8} \u{d0}\u{bc}\u{d0}\u{b5}\u{d1}\u{87}\u{d1}\u{82}\u{d1}\u{8b} \u{d1}\u{81}\u{d0}\u{b2}\u{d0}\u{be}\u{d0}\u{b8} \u{e2}\u{80}\u{93}\n\u{d0}\u{9f}\u{d1}\u{83}\u{d1}\u{81}\u{d0}\u{ba}\u{d0}\u{b0}\u{d0}\u{b9} \u{d0}\u{b2} \u{d0}\u{b4}\u{d1}\u{83}\u{d1}\u{88}\u{d0}\u{b5}\u{d0}\u{b2}\u{d0}\u{bd}\u{d0}\u{be}\u{d0}\u{b9} \u{d0}\u{b3}\u{d0}\u{bb}\u{d1}\u{83}\u{d0}\u{b1}\u{d0}\u{b8}\u{d0}\u{bd}\u{d0}\u{b5}\n\u{d0}\u{98} \u{d0}\u{b2}\u{d1}\u{81}\u{d1}\u{85}\u{d0}\u{be}\u{d0}\u{b4}\u{d1}\u{8f}\u{d1}\u{82} \u{d0}\u{b8} \u{d0}\u{b7}\u{d0}\u{b0}\u{d0}\u{b9}\u{d0}\u{b4}\u{d1}\u{83}\u{d1}\u{82} \u{d0}\u{be}\u{d0}\u{bd}\u{d0}\u{b5}\n\u{d0}\u{9a}\u{d0}\u{b0}\u{d0}\u{ba} \u{d0}\u{b7}\u{d0}\u{b2}\u{d0}\u{b5}\u{d0}\u{b7}\u{d0}\u{b4}\u{d1}\u{8b} \u{d1}\u{8f}\u{d1}\u{81}\u{d0}\u{bd}\u{d1}\u{8b}\u{d0}\u{b5} \u{d0}\u{b2} \u{d0}\u{bd}\u{d0}\u{be}\u{d1}\u{87}\u{d0}\u{b8}-\n\u{d0}\u{9b}\u{d1}\u{8e}\u{d0}\u{b1}\u{d1}\u{83}\u{d0}\u{b9}\u{d1}\u{81}\u{d1}\u{8f} \u{d0}\u{b8}\u{d0}\u{bc}\u{d0}\u{b8} \u{e2}\u{80}\u{93} \u{d0}\u{b8} \u{d0}\u{bc}\u{d0}\u{be}\u{d0}\u{bb}\u{d1}\u{87}\u{d0}\u{b8}.", "Russian"}
    case 12: Message{"Voix ambigu\u{c3}\u{ab} d\u{e2}\u{80}\u{99}un c\u{c5}\u{93}ur qui au z\u{c3}\u{a9}phyr pr\u{c3}\u{a9}f\u{c3}\u{a8}re les jattes de kiwi", "French"}
    case 13: Message{"Benjam\u{c3}\u{ad}n pidi\u{c3}\u{b3} una bebida de kiwi y fresa; No\u{c3}\u{a9}, sin verg\u{c3}\u{bc}enza, la m\u{c3}\u{a1}s exquisita champa\u{c3}\u{b1}a del men\u{c3}\u{ba}.", "Spanish"}
    case 14: Message{"\u{ce}\u{a4}\u{ce}\u{b1}\u{cf}\u{87}\u{ce}\u{af}\u{cf}\u{83}\u{cf}\u{84}\u{ce}\u{b7} \u{ce}\u{b1}\u{ce}\u{bb}\u{cf}\u{8e}\u{cf}\u{80}\u{ce}\u{b7}\u{ce}\u{be} \u{ce}\u{b2}\u{ce}\u{b1}\u{cf}\u{86}\u{ce}\u{ae}\u{cf}\u{82} \u{cf}\u{88}\u{ce}\u{b7}\u{ce}\u{bc}\u{ce}\u{ad}\u{ce}\u{bd}\u{ce}\u{b7} \u{ce}\u{b3}\u{ce}\u{b7}, \u{ce}\u{b4}\u{cf}\u{81}\u{ce}\u{b1}\u{cf}\u{83}\u{ce}\u{ba}\u{ce}\u{b5}\u{ce}\u{bb}\u{ce}\u{af}\u{ce}\u{b6}\u{ce}\u{b5}\u{ce}\u{b9} \u{cf}\u{85}\u{cf}\u{80}\u{ce}\u{ad}\u{cf}\u{81} \u{ce}\u{bd}\u{cf}\u{89}\u{ce}\u{b8}\u{cf}\u{81}\u{ce}\u{bf}\u{cf}\u{8d} \u{ce}\u{ba}\u{cf}\u{85}\u{ce}\u{bd}\u{cf}\u{8c}\u{cf}\u{82}", "Greek"}
    case 15: Message{"\u{ce}\u{97} \u{ce}\u{ba}\u{ce}\u{b1}\u{ce}\u{bb}\u{cf}\u{8d}\u{cf}\u{84}\u{ce}\u{b5}\u{cf}\u{81}\u{ce}\u{b7} \u{ce}\u{ac}\u{ce}\u{bc}\u{cf}\u{85}\u{ce}\u{bd}\u{ce}\u{b1} \u{ce}\u{b5}\u{ce}\u{af}\u{ce}\u{bd}\u{ce}\u{b1}\u{ce}\u{b9} \u{ce}\u{b7} \u{ce}\u{b5}\u{cf}\u{80}\u{ce}\u{af}\u{ce}\u{b8}\u{ce}\u{b5}\u{cf}\u{83}\u{ce}\u{b7}.", "Greek"}
    case 16: Message{"\u{ce}\u{a7}\u{cf}\u{81}\u{cf}\u{8c}\u{ce}\u{bd}\u{ce}\u{b9}\u{ce}\u{b1} \u{ce}\u{ba}\u{ce}\u{b1}\u{ce}\u{b9} \u{ce}\u{b6}\u{ce}\u{b1}\u{ce}\u{bc}\u{ce}\u{ac}\u{ce}\u{bd}\u{ce}\u{b9}\u{ce}\u{b1}!", "Greek"}
    case 17: Message{"\u{ce}\u{a0}\u{cf}\u{8e}\u{cf}\u{82} \u{cf}\u{84}\u{ce}\u{b1} \u{cf}\u{80}\u{ce}\u{b1}\u{cf}\u{82} \u{cf}\u{83}\u{ce}\u{ae}\u{ce}\u{bc}\u{ce}\u{b5}\u{cf}\u{81}\u{ce}\u{b1};", "Greek"}
    case 18: Message{"\u{e6}\u{88}\u{91}\u{e8}\u{83}\u{bd}\u{e5}\u{90}\u{9e}\u{e4}\u{b8}\u{8b}\u{e7}\u{8e}\u{bb}\u{e7}\u{92}\u{83}\u{e8}\u{80}\u{8c}\u{e4}\u{b8}\u{8d}\u{e4}\u{bc}\u{a4}\u{e8}\u{ba}\u{ab}\u{e4}\u{bd}\u{93}\u{e3}\u{80}\u{82}", "Chinese"}
    case 19: Message{"\u{e4}\u{bd}\u{a0}\u{e5}\u{90}\u{83}\u{e4}\u{ba}\u{86}\u{e5}\u{90}\u{97}\u{ef}\u{bc}\u{9f}", "Chinese"}
    case 20: Message{"\u{e4}\u{b8}\u{8d}\u{e4}\u{bd}\u{9c}\u{e4}\u{b8}\u{8d}\u{e6}\u{ad}\u{bb}\u{e3}\u{80}\u{82}", "Chinese"}
    case 21: Message{"\u{e6}\u{9c}\u{80}\u{e8}\u{bf}\u{91}\u{e5}\u{a5}\u{bd}\u{e5}\u{90}\u{97}\u{ef}\u{bc}\u{9f}", "Chinese"}
    case 22: Message{"\u{e5}\u{a1}\u{9e}\u{e7}\u{bf}\u{81}\u{e5}\u{a4}\u{b1}\u{e9}\u{a9}\u{ac}\u{ef}\u{bc}\u{8c}\u{e7}\u{84}\u{89}\u{e7}\u{9f}\u{a5}\u{e9}\u{9d}\u{9e}\u{e7}\u{a6}\u{8f}\u{e3}\u{80}\u{82}", "Chinese"}
    case 23: Message{"\u{e5}\u{8d}\u{83}\u{e5}\u{86}\u{9b}\u{e6}\u{98}\u{93}\u{e5}\u{be}\u{97}, \u{e4}\u{b8}\u{80}\u{e5}\u{b0}\u{86}\u{e9}\u{9a}\u{be}\u{e6}\u{b1}\u{82}", "Chinese"}
    case 24: Message{"\u{e4}\u{b8}\u{87}\u{e4}\u{ba}\u{8b}\u{e5}\u{bc}\u{80}\u{e5}\u{a4}\u{b4}\u{e9}\u{9a}\u{be}\u{e3}\u{80}\u{82}", "Chinese"}
    case 25: Message{"\u{e9}\u{a3}\u{8e}\u{e6}\u{97}\u{a0}\u{e5}\u{b8}\u{b8}\u{e9}\u{a1}\u{ba}\u{ef}\u{bc}\u{8c}\u{e5}\u{85}\u{b5}\u{e6}\u{97}\u{a0}\u{e5}\u{b8}\u{b8}\u{e8}\u{83}\u{9c}\u{e3}\u{80}\u{82}", "Chinese"}
    case 26: Message{"\u{e6}\u{b4}\u{bb}\u{e5}\u{88}\u{b0}\u{e8}\u{80}\u{81}\u{ef}\u{bc}\u{8c}\u{e5}\u{ad}\u{a6}\u{e5}\u{88}\u{b0}\u{e8}\u{80}\u{81}\u{e3}\u{80}\u{82}", "Chinese"}
    case 27: Message{"\u{e4}\u{b8}\u{80}\u{e8}\u{a8}\u{80}\u{e6}\u{97}\u{a2}\u{e5}\u{87}\u{ba}\u{ef}\u{bc}\u{8c}\u{e9}\u{a9}\u{b7}\u{e9}\u{a9}\u{ac}\u{e9}\u{9a}\u{be}\u{e8}\u{bf}\u{bd}\u{e3}\u{80}\u{82}", "Chinese"}
    case 28: Message{"\u{e8}\u{b7}\u{af}\u{e9}\u{81}\u{a5}\u{e7}\u{9f}\u{a5}\u{e9}\u{a9}\u{ac}\u{e5}\u{8a}\u{9b}\u{ef}\u{bc}\u{8c}\u{e6}\u{97}\u{a5}\u{e4}\u{b9}\u{85}\u{e8}\u{a7}\u{81}\u{e4}\u{ba}\u{ba}\u{e5}\u{bf}\u{83}", "Chinese"}
    case 29: Message{"\u{e6}\u{9c}\u{89}\u{e7}\u{90}\u{86}\u{e8}\u{b5}\u{b0}\u{e9}\u{81}\u{8d}\u{e5}\u{a4}\u{a9}\u{e4}\u{b8}\u{8b}\u{ef}\u{bc}\u{8c}\u{e6}\u{97}\u{a0}\u{e7}\u{90}\u{86}\u{e5}\u{af}\u{b8}\u{e6}\u{ad}\u{a5}\u{e9}\u{9a}\u{be}\u{e8}\u{a1}\u{8c}\u{e3}\u{80}\u{82}", "Chinese"}
    case 30: Message{"\u{e7}\u{8c}\u{bf}\u{e3}\u{82}\u{82}\u{e6}\u{9c}\u{a8}\u{e3}\u{81}\u{8b}\u{e3}\u{82}\u{89}\u{e8}\u{90}\u{bd}\u{e3}\u{81}\u{a1}\u{e3}\u{82}\u{8b}", "Japanese"}
    case 31: Message{"\u{e4}\u{ba}\u{80}\u{e3}\u{81}\u{ae}\u{e7}\u{94}\u{b2}\u{e3}\u{82}\u{88}\u{e3}\u{82}\u{8a}\u{e5}\u{b9}\u{b4}\u{e3}\u{81}\u{ae}\u{e5}\u{8a}\u{9f}", "Japanese"}
    case 32: Message{"\u{e3}\u{81}\u{86}\u{e3}\u{82}\u{89}\u{e3}\u{82}\u{84}\u{e3}\u{81}\u{be}\u{e3}\u{81}\u{97}  \u{e6}\u{80}\u{9d}\u{e3}\u{81}\u{b2}\u{e5}\u{88}\u{87}\u{e3}\u{82}\u{8b}\u{e6}\u{99}\u{82}  \u{e7}\u{8c}\u{ab}\u{e3}\u{81}\u{ae}\u{e6}\u{81}\u{8b}", "Japanese"}
    case 33: Message{"\u{e8}\u{99}\u{8e}\u{e7}\u{a9}\u{b4}\u{e3}\u{81}\u{ab}\u{e5}\u{85}\u{a5}\u{e3}\u{82}\u{89}\u{e3}\u{81}\u{9a}\u{e3}\u{82}\u{93}\u{e3}\u{81}\u{b0}\u{e8}\u{99}\u{8e}\u{e5}\u{ad}\u{90}\u{e3}\u{82}\u{92}\u{e5}\u{be}\u{97}\u{e3}\u{81}\u{9a}\u{e3}\u{80}\u{82}", "Japanese"}
    case 34: Message{"\u{e4}\u{ba}\u{8c}\u{e5}\u{85}\u{8e}\u{e3}\u{82}\u{92}\u{e8}\u{bf}\u{bd}\u{e3}\u{81}\u{86}\u{e8}\u{80}\u{85}\u{e3}\u{81}\u{af}\u{e4}\u{b8}\u{80}\u{e5}\u{85}\u{8e}\u{e3}\u{82}\u{92}\u{e3}\u{82}\u{82}\u{e5}\u{be}\u{97}\u{e3}\u{81}\u{9a}\u{e3}\u{80}\u{82}", "Japanese"}
    case 35: Message{"\u{e9}\u{a6}\u{ac}\u{e9}\u{b9}\u{bf}\u{e3}\u{81}\u{af}\u{e6}\u{ad}\u{bb}\u{e3}\u{81}\u{aa}\u{e3}\u{81}\u{aa}\u{e3}\u{81}\u{8d}\u{e3}\u{82}\u{83}\u{e6}\u{b2}\u{bb}\u{e3}\u{82}\u{89}\u{e3}\u{81}\u{aa}\u{e3}\u{81}\u{84}\u{e3}\u{80}\u{82}", "Japanese"}
    case 36: Message{"\u{e6}\u{9e}\u{af}\u{e9}\u{87}\u{8e}\u{e8}\u{b7}\u{af}\u{e3}\u{81}\u{ab}\u{e3}\u{80}\u{80}\u{e5}\u{bd}\u{b1}\u{e3}\u{81}\u{8b}\u{e3}\u{81}\u{95}\u{e3}\u{81}\u{aa}\u{e3}\u{82}\u{8a}\u{e3}\u{81}\u{a6}\u{e3}\u{80}\u{80}\u{e3}\u{82}\u{8f}\u{e3}\u{81}\u{8b}\u{e3}\u{82}\u{8c}\u{e3}\u{81}\u{91}\u{e3}\u{82}\u{8a}", "Japanese"}
    case 37: Message{"\u{e7}\u{b9}\u{b0}\u{e3}\u{82}\u{8a}\u{e8}\u{bf}\u{94}\u{e3}\u{81}\u{97}\u{e9}\u{ba}\u{a6}\u{e3}\u{81}\u{ae}\u{e7}\u{95}\u{9d}\u{e7}\u{b8}\u{ab}\u{e3}\u{81}\u{b5}\u{e8}\u{83}\u{a1}\u{e8}\u{9d}\u{b6}\u{e5}\u{93}\u{89}", "Japanese"}
    case 38: Message{"\u{ec}\u{95}\u{84}\u{eb}\u{93}\u{9d}\u{ed}\u{95}\u{9c} \u{eb}\u{b0}\u{94}\u{eb}\u{8b}\u{a4} \u{ec}\u{9c}\u{84}\u{ec}\u{97}\u{90} \u{ea}\u{b0}\u{88}\u{eb}\u{a7}\u{a4}\u{ea}\u{b8}\u{b0} \u{eb}\u{91}\u{90}\u{ec}\u{97}\u{87} \u{eb}\u{82}\u{a0}\u{ec}\u{95}\u{84} \u{eb}\u{8f}\u{88}\u{eb}\u{8b}\u{a4}.\n\u{eb}\u{84}\u{88}\u{ed}\u{9b}\u{8c}\u{eb}\u{84}\u{88}\u{ed}\u{9b}\u{8c} \u{ec}\u{8b}\u{9c}\u{eb}\u{a5}\u{bc} \u{ec}\u{93}\u{b4}\u{eb}\u{8b}\u{a4}. \u{eb}\u{aa}\u{a8}\u{eb}\u{a5}\u{b4}\u{eb}\u{8a}\u{94} \u{eb}\u{82}\u{98}\u{eb}\u{9d}\u{bc} \u{ea}\u{b8}\u{80}\u{ec}\u{9e}\u{90}\u{eb}\u{8b}\u{a4}.\n\u{eb}\u{84}\u{90}\u{eb}\u{94}\u{b0}\u{eb}\u{9e}\u{80} \u{ed}\u{95}\u{98}\u{eb}\u{8a}\u{98} \u{eb}\u{b3}\u{b5}\u{ed}\u{8c}\u{90}\u{ec}\u{97}\u{90} \u{eb}\u{82}\u{98}\u{eb}\u{8f}\u{84} \u{ea}\u{b0}\u{99}\u{ec}\u{9d}\u{b4} \u{ec}\u{8b}\u{9c}\u{eb}\u{a5}\u{bc} \u{ec}\u{93}\u{b4}\u{eb}\u{8b}\u{a4}.", "Korean"}
    case 39: Message{"\u{ec}\u{a0}\u{9c} \u{eb}\u{88}\u{88}\u{ec}\u{97}\u{90} \u{ec}\u{95}\u{88}\u{ea}\u{b2}\u{bd}\u{ec}\u{9d}\u{b4}\u{eb}\u{8b}\u{a4}", "Korean"}
    case 40: Message{"\u{ea}\u{bf}\u{a9} \u{eb}\u{a8}\u{b9}\u{ea}\u{b3}\u{a0} \u{ec}\u{95}\u{8c} \u{eb}\u{a8}\u{b9}\u{eb}\u{8a}\u{94}\u{eb}\u{8b}\u{a4}", "Korean"}
    case 41: Message{"\u{eb}\u{a1}\u{9c}\u{eb}\u{a7}\u{88}\u{eb}\u{8a}\u{94} \u{ed}\u{95}\u{98}\u{eb}\u{a3}\u{a8}\u{ec}\u{95}\u{84}\u{ec}\u{b9}\u{a8}\u{ec}\u{97}\u{90} \u{ec}\u{9d}\u{b4}\u{eb}\u{a3}\u{a8}\u{ec}\u{96}\u{b4}\u{ec}\u{a7}\u{84} \u{ea}\u{b2}\u{83}\u{ec}\u{9d}\u{b4} \u{ec}\u{95}\u{84}\u{eb}\u{8b}\u{88}\u{eb}\u{8b}\u{a4}", "Korean"}
    case 42: Message{"\u{ea}\u{b3}\u{a0}\u{ec}\u{83}\u{9d} \u{eb}\u{81}\u{9d}\u{ec}\u{97}\u{90} \u{eb}\u{82}\u{99}\u{ec}\u{9d}\u{b4} \u{ec}\u{98}\u{a8}\u{eb}\u{8b}\u{a4}", "Korean"}
    case 43: Message{"\u{ea}\u{b0}\u{9c}\u{ec}\u{b2}\u{9c}\u{ec}\u{97}\u{90}\u{ec}\u{84}\u{9c} \u{ec}\u{9a}\u{a9} \u{eb}\u{82}\u{9c}\u{eb}\u{8b}\u{a4}", "Korean"}
    case 44: Message{"\u{ec}\u{95}\u{88}\u{eb}\u{85}\u{95}\u{ed}\u{95}\u{98}\u{ec}\u{84}\u{b8}\u{ec}\u{9a}\u{94}?", "Korean"}
    case 45: Message{"\u{eb}\u{a7}\u{8c}\u{eb}\u{82}\u{98}\u{ec}\u{84}\u{9c} \u{eb}\u{b0}\u{98}\u{ea}\u{b0}\u{91}\u{ec}\u{8a}\u{b5}\u{eb}\u{8b}\u{88}\u{eb}\u{8b}\u{a4}", "Korean"}
    case _: Message{"\u{ed}\u{95}\u{9c}\u{ea}\u{b5}\u{ad}\u{eb}\u{a7}\u{90} \u{ed}\u{95}\u{98}\u{ec}\u{8b}\u{a4} \u{ec}\u{a4}\u{84} \u{ec}\u{95}\u{84}\u{ec}\u{84}\u{b8}\u{ec}\u{9a}\u{94}?", "Korean"}

def nth.code(list: +List<U32>) -> U32:
  match list:
    case Nil{}: 0
    case Con{+code, _}: code

def nth.emoji(list: +List<Emoji>) -> Emoji:
  match list:
    case Nil{}: Emoji{0, 0, 0}
    case Con{+item, _}: item

# emoji[index].
def emoji.at(+list: +List<Emoji>, +index: U32) -> Emoji:
  nth.emoji(List.drop(&2, Emoji, list, U32.to_nat(index)))

# Fade(ColorFromHSV((float)((start*(i + 1))%360), 0.6f, 0.85f), 0.8f).
def tint(+start: U32, +i: U32) -> U32:
  J.Color.with_alpha(J.Color.from_hsv(U32.to_f32(((start * (i + 1)) % 360 : U32)), 0.6, 0.85), 0.8)

# emoji[i].message = GetRandomValue(0, SIZEOF(messages) - 1).
def emoji.message(+i: U32, +start: U32, +code: U32, r: J.Random.State & F32) -> J.Random.State & Emoji:
  (rng, +pick) = r
  (rng, Emoji{code, F32.to_u32(pick), tint(start, i)})

# emoji[i].index = GetRandomValue(0, 179)*5.
def emoji.index(+i: U32, +start: U32, r: J.Random.State & F32) -> J.Random.State & Emoji:
  (rng, +pick) = r
  emoji.message(i, start, nth.code(List.drop(&2, U32, emojis(), U32.to_nat(F32.to_u32(pick)))), J.Random.value(rng, 0.0, (47.0 - 1.0 : F32)))

def emoji.one(+i: U32, +start: U32, rng: J.Random.State) -> J.Random.State & Emoji:
  emoji.index(i, start, J.Random.value(rng, 0.0, 179.0))

# The emoji from i on; r is the generator and emoji i (the list comes out reversed).
def fill(n: Nat, +i: U32, +start: U32, +acc: +List<Emoji>, r: J.Random.State & Emoji) -> J.Random.State & +List<Emoji>:
  match n r:
    case 0n Tuple{rng, +item}: (rng, Con{item, acc})
    case 1n+k Tuple{rng, +item}: fill(k, (i + 1 : U32), start, Con{item, acc}, emoji.one((i + 1 : U32), start, rng))

def randomized.listed(r: J.Random.State & +List<Emoji>) -> J.Random.State & +List<Emoji>:
  (rng, +reversed) = r
  (rng, List.reverse(&2, Emoji, reversed))

# RandomizeEmoji after its start = GetRandomValue(45, 360): the 32 emoji.
def randomized(r: J.Random.State & F32) -> J.Random.State & +List<Emoji>:
  (rng, +start) = r
  randomized.listed(fill(31n, 0, F32.to_u32(start), Nil{}, emoji.one(0, F32.to_u32(start), rng)))

def update.rolled(+valid: Bool, plain: J.Font, asian: J.Font, symbols: J.Font, r: J.Random.State & +List<Emoji>) -> State:
  (rng, +emoji) = r
  State{valid, rng, emoji, 4294967295, 4294967295, M.Vector2{0.0, 0.0}, M.Vector2{0.0, 0.0}, plain, asian, symbols}

# if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT) && (hovered != -1) && (hovered != selected)) the hovered emoji is selected.
def update.kept(+core: J.Core, +valid: Bool, rng: J.Random.State, +emoji: +List<Emoji>, +hovered: U32, +selected: U32, +hovered_at: M.Vector2, +selected_at: M.Vector2, plain: J.Font, asian: J.Font,
    symbols: J.Font) -> State:
  +click = J.Input.is_mouse_button_pressed(core, 0) && U32.is_ne(hovered, 4294967295) && U32.is_ne(hovered, selected)
  State{valid, rng, emoji, hovered, Bool.pick(U32, click, hovered, selected), hovered_at, Bool.pick(M.Vector2, click, hovered_at, selected_at), plain, asian, symbols}

# SPACE: RandomizeEmoji() (nothing hovered or selected).
def update.space(space: Bool, +core: J.Core, +valid: Bool, rng: J.Random.State, +emoji: +List<Emoji>, +hovered: U32, +selected: U32, +hovered_at: M.Vector2, +selected_at: M.Vector2, plain: J.Font,
    asian: J.Font, symbols: J.Font) -> State:
  match space:
    case True{}: update.rolled(valid, plain, asian, symbols, randomized(J.Random.value(rng, 45.0, 360.0)))
    case False{}: update.kept(core, valid, rng, emoji, hovered, selected, hovered_at, selected_at, plain, asian, symbols)

def update(+core: J.Core, state: State) -> J.Core & State:
  State{+valid, rng, +emoji, +hovered, +selected, +hovered_at, +selected_at, plain, asian, symbols} = state
  (core, update.space(J.Input.is_key_pressed(core, 32), core, valid, rng, emoji, hovered, selected, hovered_at, selected_at, plain, asian, symbols))

def code.of(item: Emoji) -> U32:
  Emoji{code, _, _} = item
  code

def color.of(item: Emoji) -> U32:
  Emoji{_, _, color} = item
  color

def message.of(item: Emoji) -> U32:
  Emoji{_, index, _} = item
  index

# CheckCollisionPointRec(mouse, (x, y, size, size)).
def inside(+mouse: M.Vector2, +x: F32, +y: F32, +size: F32) -> Bool:
  M.Vector2{+mx, +my} = mouse
  (mx >= x : F32) && (mx < (x + size) : F32) && (my >= y : F32) && (my < (y + size) : F32)

# The emoji from i on at position (x, y): each in its color when the mouse is on it (it is then the hovered
# one) or when it is selected, else in Fade(LIGHTGRAY, 0.4f). After emoji 8, 16 and 24 a new row starts.
def faces(list: +List<Emoji>, +i: U32, +x: F32, +y: F32, +size: F32, +mouse: M.Vector2, +selected: U32, +hover: Hover, r: J.Frame & J.Font) -> (J.Frame & J.Font) & Hover:
  match list r:
    case Nil{} Tuple{frame, font}: ((frame, font), hover)
    case Con{+item, rest} Tuple{frame, font}: faces(rest, (i + 1 : U32), Bool.pick(F32, U32.is_ne(i, 0) && U32.is_eq((i % 8 : U32), 0), 28.8, (x + (size + 28.8) : F32)),
      Bool.pick(F32, U32.is_ne(i, 0) && U32.is_eq((i % 8 : U32), 0), (y + (size + 24.25) : F32), y), size, mouse, selected, Bool.pick(Hover, inside(mouse, x, y, size), Hover{i, M.Vector2{x, y}}, hover),
      J.Draw.text_codepoint(frame, font, code.of(item), M.Vector2{x, y}, size, Bool.pick(U32, inside(mouse, x, y, size) || U32.is_eq(selected, i), color.of(item), J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.4))))

def bytes.left(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{_, _}: True{}

# for (i = 0; i < length; i++): the characters GetCodepoint finds from byte `at` on ('?' moves one byte); r is
# GetCodepoint there. Widths are filled in by measured.
def decoded(fuel: Nat, +text: String, +at: U32, more: Bool, r: U32 & U32) -> +List<Glyph>:
  match fuel more r:
    case 0n _ _: Nil{}
    case 1n+_ False{} _: Nil{}
    case 1n+k True{} Tuple{+code, +count}: Con{Glyph{code, 0.0, Bool.pick(U32, U32.is_eq(code, 63), 1, count), (at + Bool.pick(U32, U32.is_eq(code, 63), 1, count) - 1 : U32)},
      decoded(k, String.drop(text, U32.to_nat(Bool.pick(U32, U32.is_eq(code, 63), 1, count))), (at + Bool.pick(U32, U32.is_eq(code, 63), 1, count) : U32),
        bytes.left(String.drop(text, U32.to_nat(Bool.pick(U32, U32.is_eq(code, 63), 1, count)))), J.Codepoint.get(String.drop(text, U32.to_nat(Bool.pick(U32, U32.is_eq(code, 63), 1, count)))))}

def advance.of(info: Maybe<J.GlyphInfo>) -> U32:
  match info:
    case None{}: 0
    case Some{J.GlyphInfo{_, _, _, advance, _}}: advance

def width.rec(r: J.Font & J.Rectangle, +advance: U32) -> J.Font & F32:
  (font, rec) = r
  J.Rectangle{_, _, +w, _} = rec
  (font, Bool.pick(F32, U32.is_eq(advance, 0), w, U32.to_f32(advance)))

def width.info(r: J.Font & Maybe<J.GlyphInfo>, +code: U32) -> J.Font & F32:
  (font, info) = r
  width.rec(J.Font.glyph_atlas_rec(font, code), advance.of(info))

# (font.glyphs[index].advanceX == 0)? font.recs[index].width : font.glyphs[index].advanceX (scaleFactor is 1).
def width.of(font: J.Font, +code: U32) -> J.Font & F32:
  width.info(J.Font.glyph_info(font, code), code)

def head.code(list: +List<Glyph>) -> U32:
  match list:
    case Nil{}: 0
    case Con{Glyph{code, _, _, _}, _}: code

def widened(+glyph: Glyph, +width: F32) -> Glyph:
  Glyph{code, _, bytes, last} = glyph
  Glyph{code, width, bytes, last}

# The characters with their widths; r is the font and the first one's width (the list comes out reversed).
def measured(chars: +List<Glyph>, +acc: +List<Glyph>, r: J.Font & F32) -> J.Font & +List<Glyph>:
  match chars r:
    case Nil{} Tuple{font, _}: (font, acc)
    case Con{+glyph, +rest} Tuple{font, +width}: measured(rest, Con{widened(glyph, width), acc}, width.of(font, head.code(rest)))

def chosen(first: Bool, +a: +List<Glyph>, +b: +List<Glyph>) -> +List<Glyph>:
  match first:
    case True{}: a
    case False{}: b

def step.kept(+cursor: Cursor, +rest: +List<Glyph>, +line: +List<Glyph>, r: J.Frame & J.Font) -> Loop:
  (frame, font) = r
  Loop{cursor, rest, line, frame, font}

# DrawTextCodepoint(font, codepoint, (rec.x + textOffsetX, rec.y + textOffsetY), fontSize, tint).
def step.drawn(draw: Bool, +cursor: Cursor, +rest: +List<Glyph>, +line: +List<Glyph>, +code: U32, +px: F32, +py: F32, +size: F32, frame: J.Frame, font: J.Font) -> Loop:
  match draw:
    case False{}: Loop{cursor, rest, line, frame, font}
    case True{}: step.kept(cursor, rest, line, J.Draw.text_codepoint(frame, font, code, M.Vector2{px, py}, size, J.Color.WHITE()))

# One pass of the for loop on a character (i is its last byte's index).
def step.glyph(+length: U32, +rx: F32, +ry: F32, +rw: F32, +rh: F32, +size: F32, +measuring: Bool, +start: U32, +end: U32, +x: F32, +y: F32, +glyph: Glyph, +tail: +List<Glyph>,
    +line: +List<Glyph>, frame: J.Frame, font: J.Font) -> Loop:
  Glyph{+code, +width, +bytes, +last} = glyph
  +newline = U32.is_eq(code, 10)
  +blank = U32.is_eq(code, 32) || U32.is_eq(code, 9)
  # glyphWidth: zero for '\n'; the spacing (1) is added before the last byte.
  +gw = Bool.pick(F32, newline, 0.0, Bool.pick(F32, ((last + 1) < length : U32), (width + 1.0 : F32), width))
  +over = ((x + gw) > rw : F32)
  # MEASURE_STATE: endLine at a space, tab or line feed; past the width, at the last byte or at a line feed the line is drawn from startLine.
  +e1 = Bool.pick(U32, blank || newline, last, end)
  +e2 = Bool.pick(U32, U32.is_eq(e1, 4294967295) || U32.is_eq(e1, 0), last, e1)
  +e3 = Bool.pick(U32, U32.is_eq(last, e2), (e2 - bytes : U32), e2)
  +e4 = Bool.pick(U32, U32.is_eq((start + bytes : U32), e3), (last - bytes : U32), e3)
  +final = U32.is_eq((last + 1 : U32), length)
  +switch = over || final || newline
  # DRAW_STATE: the break below the height; the end of the measured line starts the next one.
  +stop = Bool.not(newline) && ((y + size) > rh : F32)
  +ended = U32.is_eq(last, end)
  +drawing = {Cursor{ended, Bool.pick(U32, ended, end, start), Bool.pick(U32, ended, 4294967295, end), Bool.pick(F32, ended, 0.0, (x + gw : F32)),
    Bool.pick(F32, ended, (y + (size + size / 2.0) : F32), y), stop} : Cursor}
  +scanned = {Cursor{Bool.not(switch), start, Bool.pick(U32, over, e4, Bool.pick(U32, final, last, e1)), Bool.pick(F32, switch, 0.0, (x + gw : F32)), y, False{}} : Cursor}
  step.drawn(Bool.not(measuring) && Bool.not(newline) && Bool.not(stop) && Bool.not(blank), Bool.pick(Cursor, measuring, scanned, drawing),
    chosen(measuring && switch, line, tail), chosen(Bool.not(measuring) && ended, tail, line), code, (rx + x : F32), (ry + y : F32), size, frame, font)

def step.rest(rest: +List<Glyph>, +length: U32, +rx: F32, +ry: F32, +rw: F32, +rh: F32, +size: F32, +measuring: Bool, +start: U32, +end: U32, +x: F32, +y: F32, +line: +List<Glyph>, frame: J.Frame,
    font: J.Font) -> Loop:
  match rest:
    case Nil{}: Loop{Cursor{measuring, start, end, x, y, True{}}, Nil{}, line, frame, font}
    case Con{+glyph, +tail}: step.glyph(length, rx, ry, rw, rh, size, measuring, start, end, x, y, glyph, tail, line, frame, font)

def finished(cursor: Cursor) -> Bool:
  Cursor{_, _, _, _, _, +done} = cursor
  done

def step.at(+length: U32, +rx: F32, +ry: F32, +rw: F32, +rh: F32, +size: F32, cursor: Cursor, +rest: +List<Glyph>, +line: +List<Glyph>, frame: J.Frame, font: J.Font) -> Loop:
  Cursor{+measuring, +start, +end, +x, +y, _} = cursor
  step.rest(rest, length, rx, ry, rw, rh, size, measuring, start, end, x, y, line, frame, font)

def step.live(done: Bool, +length: U32, +rx: F32, +ry: F32, +rw: F32, +rh: F32, +size: F32, +cursor: Cursor, +rest: +List<Glyph>, +line: +List<Glyph>, frame: J.Frame, font: J.Font) -> Loop:
  match done:
    case True{}: Loop{cursor, rest, line, frame, font}
    case False{}: step.at(length, rx, ry, rw, rh, size, cursor, rest, line, frame, font)

def step(+length: U32, +rx: F32, +ry: F32, +rw: F32, +rh: F32, +size: F32, loop: Loop) -> Loop:
  Loop{+cursor, +rest, +line, frame, font} = loop
  step.live(finished(cursor), length, rx, ry, rw, rh, size, cursor, rest, line, frame, font)

# DrawTextBoxed(font, text, rec, (float)font.baseSize, 1.0f, true, WHITE): the loop, a step per unit of fuel.
def boxed(fuel: Nat, +length: U32, +rx: F32, +ry: F32, +rw: F32, +rh: F32, +size: F32, loop: Loop) -> Loop:
  match fuel:
    case 0n: loop
    case 1n+p: boxed(p, length, rx, ry, rw, rh, size, step(length, rx, ry, rw, rh, size, loop))

def checked(done: Bool, frame: J.Frame) -> J.Frame:
  match done:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def boxed.finish(loop: Loop) -> J.Frame & J.Font:
  Loop{+cursor, _, _, frame, font} = loop
  (checked(finished(cursor), frame), font)

# (int)value for a float within int.
def whole(+value: F32) -> F32:
  Bool.pick(F32, (value < 0.0 : F32), F32.neg(U32.to_f32(F32.to_u32(F32.neg(value)))), U32.to_f32(F32.to_u32(value)))

def info.at(r: J.Font & M.Vector2, +text: String, frame: J.Frame, +right: F32, +bottom: F32) -> J.Frame:
  (_, +size) = r
  M.Vector2{+w, +h} = size
  J.Draw.text(frame, text, whole((right - w : F32)), whole(((bottom - h) - 2.0 : F32)), 10.0, J.Color.RAYWHITE())

# The info text below the message: "<language> <codepoints> characters <bytes> bytes" in the default font, right aligned.
def info.drawn(text: Maybe<String>, frame: J.Frame, +right: F32, +bottom: F32) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{+t}: info.at(J.Font.measure_text_ex(J.Font.default(), t, 10.0, 1.0), t, frame, right, bottom)

def bubble.info(r: J.Frame & J.Font, +text: String, +language: String, +x: F32, +y: F32, +w: F32, +h: F32) -> J.Frame & J.Font:
  (frame, font) = r
  (info.drawn(J.Text.format("%s %u characters %i bytes", [J.TextString{language}, J.TextInt{J.Codepoint.count(text)}, J.TextInt{J.Text.length(text)}]), frame,
    ((x + 20.0 / 2.0) + (w - 20.0) : F32), (y + h : F32)), font)

# The chat bubble's text and info: the boxed message, then the info line.
def bubble.text(r: J.Font & +List<Glyph>, +text: String, +language: String, +x: F32, +y: F32, +w: F32, +h: F32, +size: F32, frame: J.Frame) -> J.Frame & J.Font:
  (font, +reversed) = r
  bubble.info(boxed.finish(boxed(U32.to_nat((16 * J.Text.length(text) : U32)), J.Text.length(text), (x + 20.0 / 2.0 : F32), (y + 30.0 / 2.0 : F32), (w - 20.0 : F32), h, size,
    Loop{Cursor{True{}, 4294967295, 4294967295, 0.0, 0.0, False{}}, List.reverse(&2, Glyph, reversed), List.reverse(&2, Glyph, reversed), frame, font})), text, language, x, y, w, h)

# The bubble at msgRect (x, y, w, h) with its triangle (a, b, c): DrawRectangleRec, DrawTriangle, the text.
def bubble.measured(+chars: +List<Glyph>, +text: String, +language: String, +x: F32, +y: F32, +w: F32, +h: F32, +size: F32, frame: J.Frame, font: J.Font) -> J.Frame & J.Font:
  bubble.text(measured(chars, Nil{}, width.of(font, head.code(chars))), text, language, x, y, w, h, size, frame)

def bubble.drawn(+x: F32, +y: F32, +w: F32, +h: F32, +a: M.Vector2, +b: M.Vector2, +c: M.Vector2, +color: U32, +text: String, +language: String, +size: F32, frame: J.Frame, font: J.Font) -> J.Frame & J.Font:
  bubble.measured(decoded(U32.to_nat(J.Text.length(text)), text, 0, bytes.left(text), J.Codepoint.get(text)), text, language, x, y, w, h, size,
    J.Draw.triangle(J.Draw.rectangle_rec(frame, J.Rectangle{x, y, w, h}, color), a, b, c, color), font)

# msgRect from the text's size and selectedPos, kept inside the screen: a bubble that would leave the top goes
# below the emoji, with its triangle turned.
def bubble.placed(+sx: F32, +sy: F32, +w0: F32, +h0: F32, +color: U32, +text: String, +language: String, +size: F32, frame: J.Frame, font: J.Font) -> J.Frame & J.Font:
  +tall = Bool.pick(F32, (w0 > 300.0 : F32), (h0 * (w0 / 300.0) : F32), h0)
  +wide = Bool.pick(F32, (w0 > 300.0 : F32), 300.0, Bool.pick(F32, (w0 < 160.0 : F32), 160.0, w0))
  +w = (2.0 * 20.0 + wide : F32)
  +h = (2.0 * 30.0 + tall : F32)
  +x0 = (sx - 38.8 : F32)
  +y0 = (sy - h : F32)
  +x1 = Bool.pick(F32, (x0 < 10.0 : F32), (x0 + 28.0 : F32), x0)
  +below = (y0 < 10.0 : F32)
  +y1 = Bool.pick(F32, below, (sy + 84.0 : F32), y0)
  +x2 = Bool.pick(F32, ((x1 + w) > 800.0 : F32), (x1 - (((x1 + w) - 800.0) + 10.0) : F32), x1)
  +edge = Bool.pick(F32, below, y1, (y0 + h : F32))
  +tip = Bool.pick(F32, below, (edge - 10.0 : F32), (edge + 10.0 : F32))
  bubble.drawn(x2, y1, w, h, Bool.pick(M.Vector2, below, M.Vector2{(sx + 8.0 : F32), tip}, M.Vector2{sx, edge}), Bool.pick(M.Vector2, below, M.Vector2{sx, edge}, M.Vector2{(sx + 8.0 : F32), tip}),
    M.Vector2{(sx + 10.0 : F32), edge}, color, text, language, size, frame, font)

# sz = MeasureTextEx(*font, messages[message].text, (float)font->baseSize, 1.0f).
def bubble.sized(r: J.Font & M.Vector2, +at: M.Vector2, +color: U32, +text: String, +language: String, +size: F32, frame: J.Frame) -> J.Frame & J.Font:
  (font, +extent) = r
  M.Vector2{+w, +h} = extent
  M.Vector2{+sx, +sy} = at
  bubble.placed(sx, sy, w, h, color, text, language, size, frame, font)

def base.of(font: J.Font) -> J.Font & F32:
  J.Font{+base, padding, glyphs, texture, atlas} = font
  (J.Font{base, padding, glyphs, texture, atlas}, U32.to_f32(base))

def bubble.font(r: J.Font & F32, +at: M.Vector2, +color: U32, +text: String, +language: String, frame: J.Frame) -> J.Frame & J.Font:
  (font, +size) = r
  bubble.sized(J.Font.measure_text_ex(font, text, size, 1.0), at, color, text, language, size, frame)

def bubble.message(+found: Message, +color: U32, +at: M.Vector2, frame: J.Frame, font: J.Font) -> J.Frame & J.Font:
  Message{+text, +language} = found
  bubble.font(base.of(font), at, color, text, language, frame)

# The message of the selected emoji in the font given.
def bubble(+item: Emoji, +at: M.Vector2, frame: J.Frame, font: J.Font) -> J.Frame & J.Font:
  bubble.message(message(message.of(item)), color.of(item), at, frame, font)

# The fonts for the asian languages: Chinese, Korean and Japanese.
def cjk(+found: Message) -> Bool:
  Message{_, +language} = found
  J.Text.is_equal(language, "Chinese") || J.Text.is_equal(language, "Korean") || J.Text.is_equal(language, "Japanese")

def texts(frame: J.Frame) -> J.Frame:
  J.Draw.text(J.Draw.text(frame, "These emojis have something to tell you, click each to find out!", 75.0, 410.0, 20.0, J.Color.GRAY()),
    "Each emoji is a unicode character from a font, not a texture... Press [SPACEBAR] to refresh", 158.0, 434.0, 10.0, J.Color.GRAY())

def draw.plain(+core: J.Core, rng: J.Random.State, +emoji: +List<Emoji>, +hover: Hover, +selected: U32, +selected_at: M.Vector2, asian: J.Font, symbols: J.Font, r: J.Frame & J.Font) -> J.Core & (State & J.Frame):
  Hover{+index, +at} = hover
  (frame, plain) = r
  (core, (State{True{}, rng, emoji, index, selected, at, selected_at, plain, asian, symbols}, texts(frame)))

def draw.asian(+core: J.Core, rng: J.Random.State, +emoji: +List<Emoji>, +hover: Hover, +selected: U32, +selected_at: M.Vector2, plain: J.Font, symbols: J.Font, r: J.Frame & J.Font) -> J.Core & (State & J.Frame):
  Hover{+index, +at} = hover
  (frame, asian) = r
  (core, (State{True{}, rng, emoji, index, selected, at, selected_at, plain, asian, symbols}, texts(frame)))

# if (selected != -1) the message in fontDefault, or fontAsian for the asian languages. kind 0: none; 1: fontDefault; 2: fontAsian.
def draw.message(kind: U32, +core: J.Core, rng: J.Random.State, +emoji: +List<Emoji>, +hover: Hover, +selected: U32, +selected_at: M.Vector2, plain: J.Font, asian: J.Font, symbols: J.Font,
    frame: J.Frame) -> J.Core & (State & J.Frame):
  match kind:
    case 0: draw.plain(core, rng, emoji, hover, selected, selected_at, asian, symbols, (frame, plain))
    case 1: draw.plain(core, rng, emoji, hover, selected, selected_at, asian, symbols, bubble(emoji.at(emoji, selected), selected_at, frame, plain))
    case _: draw.asian(core, rng, emoji, hover, selected, selected_at, plain, symbols, bubble(emoji.at(emoji, selected), selected_at, frame, asian))

def draw.chosen(none: Bool, +core: J.Core, rng: J.Random.State, +emoji: +List<Emoji>, +hover: Hover, +selected: U32, +selected_at: M.Vector2, plain: J.Font, asian: J.Font, symbols: J.Font,
    frame: J.Frame) -> J.Core & (State & J.Frame):
  match none:
    case True{}: draw.message(0, core, rng, emoji, hover, selected, selected_at, plain, asian, symbols, frame)
    case False{}: draw.message(Bool.pick(U32, cjk(message(message.of(emoji.at(emoji, selected)))), 2, 1), core, rng, emoji, hover, selected, selected_at, plain, asian, symbols, frame)

def draw.hovered(+core: J.Core, rng: J.Random.State, +emoji: +List<Emoji>, +selected: U32, +selected_at: M.Vector2, plain: J.Font, asian: J.Font, +hover: Hover, pair: J.Frame & J.Font) -> J.Core & (State & J.Frame):
  (frame, symbols) = pair
  draw.chosen(U32.is_eq(selected, 4294967295), core, rng, emoji, hover, selected, selected_at, plain, asian, symbols, frame)

def draw.faces(+core: J.Core, rng: J.Random.State, +emoji: +List<Emoji>, +selected: U32, +selected_at: M.Vector2, plain: J.Font, asian: J.Font, r: (J.Frame & J.Font) & Hover) -> J.Core & (State & J.Frame):
  (pair, +hover) = r
  draw.hovered(core, rng, emoji, selected, selected_at, plain, asian, hover, pair)

# ClearBackground(RAYWHITE); the emoji from (28.8, 10) at fontEmoji's baseSize.
def draw.sized(+core: J.Core, rng: J.Random.State, +emoji: +List<Emoji>, +selected: U32, +selected_at: M.Vector2, plain: J.Font, asian: J.Font, frame: J.Frame, r: J.Font & F32) -> J.Core & (State & J.Frame):
  (symbols, +size) = r
  draw.faces(core, rng, emoji, selected, selected_at, plain, asian, faces(emoji, 0, 28.8, 10.0, size, J.Input.get_mouse_position(core), selected, Hover{4294967295, M.Vector2{0.0, 0.0}},
    (J.Frame.clear_background(frame, J.Color.RAYWHITE()), symbols)))

def draw.at(valid: Bool, +core: J.Core, rng: J.Random.State, +emoji: +List<Emoji>, +hovered: U32, +selected: U32, +hovered_at: M.Vector2, +selected_at: M.Vector2, plain: J.Font, asian: J.Font,
    symbols: J.Font, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid:
    case False{}: (core, (State{False{}, rng, emoji, hovered, selected, hovered_at, selected_at, plain, asian, symbols}, J.Frame.refuse(frame)))
    case True{}: draw.sized(core, rng, emoji, selected, selected_at, plain, asian, frame, base.of(symbols))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, rng, +emoji, +hovered, +selected, +hovered_at, +selected_at, plain, asian, symbols} = state
  draw.at(valid, core, rng, emoji, hovered, selected, hovered_at, selected_at, plain, asian, symbols, frame)

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def font.some(font: Maybe<J.Font>) -> J.Font & Bool:
  match font:
    case None{}: (J.Font.default(), False{})
    case Some{f}: (f, True{})

def font.of(result: Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> J.Font & Bool:
  match result:
    case Fail{_}: (J.Font.default(), False{})
    case Done{font}: font.some(font)

# RandomizeEmoji(); SetTargetFPS(60).
def setup.done(+core: J.Core, frame: J.Frame, +valid: Bool, plain: J.Font, asian: J.Font, symbols: J.Font, r: J.Random.State & +List<Emoji>) -> J.Core & (J.Frame & State):
  (rng, +emoji) = r
  (J.Core.set_target_fps(core, 60), (frame, State{valid, rng, emoji, 4294967295, 4294967295, M.Vector2{0.0, 0.0}, M.Vector2{0.0, 0.0}, plain, asian, symbols}))

def setup.third(+seed: U32, +core: J.Core, +valid: Bool, plain: J.Font, asian: J.Font, frame: J.Frame, r: J.Font & Bool) -> J.Core & (J.Frame & State):
  (symbols, +ok) = r
  setup.done(core, frame, valid && ok, plain, asian, symbols, randomized(J.Random.value(J.Random.seed(seed), 45.0, 360.0)))

def setup.symbols(+seed: U32, +core: J.Core, +valid: Bool, plain: J.Font, asian: J.Font, r: J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> J.Core & (J.Frame & State):
  (frame, result) = r
  setup.third(seed, core, valid, plain, asian, frame, font.of(result))

# fontEmoji = LoadFont("resources/symbola.fnt").
def setup.second(+seed: U32, +dir: String, +core: J.Core, +valid: Bool, plain: J.Font, frame: J.Frame, r: J.Font & Bool) -> IO(J.Core & (J.Frame & State)):
  (asian, +ok) = r
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Core & (J.Frame & State), J.Font.load(frame, dir ++ "resources/symbola.fnt"),
    loaded => IO.pure(J.Core & (J.Frame & State), setup.symbols(seed, core, valid && ok, plain, asian, loaded)))

def setup.asian(+seed: U32, +dir: String, +core: J.Core, +valid: Bool, plain: J.Font, r: J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  setup.second(seed, dir, core, valid, plain, frame, font.of(result))

# fontAsian = LoadFont("resources/noto_cjk.fnt").
def setup.first(+seed: U32, +dir: String, +core: J.Core, frame: J.Frame, r: J.Font & Bool) -> IO(J.Core & (J.Frame & State)):
  (plain, +ok) = r
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Core & (J.Frame & State), J.Font.load(frame, dir ++ "resources/noto_cjk.fnt"),
    loaded => setup.asian(seed, dir, core, ok, plain, loaded))

def setup.plain(+seed: U32, +dir: String, +core: J.Core, r: J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>) -> IO(J.Core & (J.Frame & State)):
  (frame, result) = r
  setup.first(seed, dir, core, frame, font.of(result))

# After SetConfigFlags(FLAG_MSAA_4X_HINT | FLAG_VSYNC_HINT), InitWindow(800, 450) and SetRandomSeed(seed):
# fontDefault = LoadFont("resources/dejavu.fnt") and the other two, the emoji, SetTargetFPS(60).
def setup(+seed: U32, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Result<&1, &1, J.Surface.IOError, Maybe<J.Font>>, J.Core & (J.Frame & State), J.Font.load(frame, dir ++ "resources/dejavu.fnt"), loaded => setup.plain(seed, dir, core, loaded))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, 96, "raylib [text] example - unicode emojis", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(0, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
