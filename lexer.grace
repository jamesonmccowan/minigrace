import io
import sys
import util
import unicode

var lineNumber := 1
var linePosition := 0
var startPosition := 1
var indentLevel := 0

// Return the numeric value of the single hexadecimal character c.
method hexdecchar(c) {
    var chars := ["0", "1", "2", "3", "4", "5", "6", "7", "8",
                 "9", "a", "b", "c", "d", "e", "f"]
    var ret := 0
    var i := 0
    for (chars) do {cr->
        if (cr == c) then {
            ret := i
        }
        i := i + 1
    }
    ret
}

// The various XXXTokenV are interned constant tokens to save allocation.

class IdentifierToken { s ->
    var kind := "identifier"
    var value := s
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class StringToken { s ->
    var kind := "string"
    var value := s
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class OctetsToken { s ->
    var kind := "octets"
    var value := s
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class LBraceToken {
    var kind := "lbrace"
    var value := "\{"
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class RBraceToken {
    var kind := "rbrace"
    var value := "}"
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class LParenToken {
    var kind := "lparen"
    var value := "("
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class RParenToken {
    var kind := "rparen"
    var value := ")"
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class LSquareToken {
    var kind := "lsquare"
    var value := "["
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class RSquareToken {
    var kind := "rsquare"
    var value := "]"
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class CommaToken {
    var kind := "comma"
    var value := ","
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class ColonToken {
    var kind := "colon"
    var value := ":"
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class DotToken {
    var kind := "dot"
    var value := "."
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class NumToken { v ->
    var kind := "num"
    var value := v
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class KeywordToken { v ->
    var kind := "keyword"
    var value := v
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class OpToken { v ->
    var kind := "op"
    var value := v
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class ArrowToken {
    var kind := "arrow"
    var value := "->"
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class BindToken {
    var kind := "bind"
    var value := ":="
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}
class SemicolonToken { level->
    const kind := "semicolon"
    var value := ";"
    var line := lineNumber
    var indent := indentLevel
    var linePos := startPosition
}

// When a new lexical class has begun, add to the tokens list the token
// corresponding to the previous accumulated data. mode is the previous
// lexical mode (a string), and accum the accumulated characters since that
// mode begun. Modes are:
//   n        Whitespace       i   Identifier
//   "        Quoted string    x   Octets literal
//   m        Number           o   Any operator
//   c        Comment
//   ,.{}()[] The corresponding literal character
//
// There are three special cases for mode o. If accum is "->", ":=", or "=",
// the corresponding special token is created. For mode i, a keyword token
// is created for an identifier whose name is a reserved keyword.
method modechange(tokens, mode, accum) {
    var done := false
    var tok := 0
    if ((mode /= "n") | (accum.size > 0)) then {
        if (mode == "i") then {
            tok := IdentifierToken.new(accum)
            if ((accum == "object") | (accum == "method")
                | (accum == "var") | (accum == "const")
                | (accum == "import") | (accum == "class")
                | (accum == "return") | (accum == "def")) then {
                tok := KeywordToken.new(accum)
            }
            tokens.push(tok)
            done := true
        }
        if (mode == "I") then {
            tok := IdentifierToken.new(accum)
            tokens.push(tok)
            done := true
        }
        if (mode == "\"") then {
            tok := StringToken.new(accum)
            tokens.push(tok)
            done := true
        }
        if (mode == "x") then {
            tok := OctetsToken.new(accum)
            tokens.push(tok)
            done := true
        }
        if (mode == ",") then {
            tok := CommaToken.new
            tokens.push(tok)
            done := true
        }
        if (mode == ".") then {
            tok := DotToken.new
            tokens.push(tok)
            done := true
        }
        if (mode == "\{") then {
            tok := LBraceToken.new
            tokens.push(tok)
            done := true
        }
        if (mode == "}") then {
            tok := RBraceToken.new
            tokens.push(tok)
            done := true
        }
        if (mode == "(") then {
            tok := LParenToken.new
            tokens.push(tok)
            done := true
        }
        if (mode == ")") then {
            tok := RParenToken.new
            tokens.push(tok)
            done := true
        }
        if (mode == "[") then {
            tok := LSquareToken.new
            tokens.push(tok)
            done := true
        }
        if (mode == "]") then {
            tok := RSquareToken.new
            tokens.push(tok)
            done := true
        }
        if (mode == ";") then {
            tok := SemicolonToken.new
            tokens.push(tok)
            done := true
        }
        if (mode == "m") then {
            tok := NumToken.new(accum)
            if (tokens.size > 1) then {
                if (tokens.last.kind == "dot") then {
                    tokens.pop()
                    if (tokens.last.kind == "num") then {
                        tok := tokens.pop()
                        tok.value := tok.value ++ "." ++ accum
                    } else {
                        util.syntax_error("found ." ++ accum
                            ++ ", expected term")
                    }
                }
            }
            tokens.push(tok)
            done := true
        }
        if (mode == "o") then {
            tok := OpToken.new(accum)
            if (accum == "->") then {
                tok := ArrowToken.new
            }
            if (accum == ":=") then {
                tok := BindToken.new
            }
            if (accum == ":") then {
                tok := ColonToken.new
            }
            tokens.push(tok)
            done := true
        }
        if (mode == "d") then {
            indentLevel := accum.size
            done := true
        }
        if (mode == "n") then {
            done := true
        }
        if (mode == "c") then {
            done := true
        }
        if (done) then {
            //print(mode, accum, tokens)
        } else {
            util.syntax_error("Lexing error: no handler for mode " ++ mode ++
                " with accum " ++ accum)
        }
    }
    startPosition := linePosition
}

// True if ov is a valid identifier character. Identifier characters are
// Unicode letters, Unicode numbers, apostrophe, and (currently) underscore.
method isidentifierchar(ov) {
    if (unicode.isLetter(ov) | unicode.isNumber(ov)
        | (ov == 95) | (ov == 39)) then {
        // 95 is _, 39 is '
        true
    } else {
        false
    }
}

// True if c (with codepoint ordval) is a valid operator character.
method isoperatorchar(c, ordval) {
    var ret := false
    if ((c == "-") | (c == "&") | (c == "|") | (c == ":") | (c == "%")
        | (c == "*") | (c == "/") | (c == "+") | (c == "!")) then {
        ret := true
    } elseif (unicode.isSymbolMathematical(ordval)) then {
        ret := true
    }
    ret
}

// Read the program text from util.infile and return a list of tokens.
method lexinput() {
    util.log_verbose("reading source.")
    var input := util.infile.read()

    var tokens := []
    var mode := "n"
    var newmode := mode
    var instr := false
    var inBackticks := false
    var backtickIdent := false
    var accum := ""
    var escaped := false
    var prev := ""
    var unichars := 0
    var codepoint := 0
    var interpdepth := 0
    var interpString := false
    linePosition := 0
    util.log_verbose("lexing.")
    for (input) do { c ->
        linePosition := linePosition + 1
        util.setPosition(lineNumber, linePosition)
        var ct := ""
        var ordval := c.ord // String.ord gives the codepoint
        if ((unicode.isSeparator(ordval) & (ordval /= 32) & (ordval /= 8232)) |
            (ordval == 9)) then {
            // Character is whitespace, but not an ASCII space or Unicode
            // LINE SEPARATOR, or is a tab
            util.syntax_error("illegal whitespace in input: " ++ ordval ++ ", "
                ++ unicode.name(c))
        }
        if (unicode.isControl(ordval) & (ordval /= 10) & (ordval /= 13)) then {
            // Character is a control character other than carriage return or
            // line feed.
            util.syntax_error("illegal control character in input: #{ordval}"
                ++ " on line {lineNumber} character {linePosition}.")
        }
        if (instr | inBackticks) then {

        } elseif (mode /= "c") then {
            // Not in a comment, so look for a mode.
            if ((c == " ") & (mode /= "d")) then {
                newmode := "n"
            }
            if (c == "\"") then {
                // Beginning of a string
                newmode := "\""
                instr := true
                if (prev == "x") then {
                    // Or, actually of an Octet literal
                    newmode := "x"
                    mode := "n"
                }
            }
            if (c == "`") then {
                newmode := "I"
                inBackticks := true
            }
            ct := isidentifierchar(ordval)
            if (ct) then {
                newmode := "i"
            }
            ct := ((ordval >= 48) & (ordval <=57))
            if (ct & (mode /= "i")) then {
                newmode := "m"
            }
            if (isoperatorchar(c, ordval)) then {
                newmode := "o"
            }
            if ((c == "(") | (c == ")") | (c == ",") | (c == ".")
                | (c == "\{") | (c == "}") | (c == "[") | (c == "]")
                | (c == ";")) then {
                newmode := c
            }
            if ((c == ".") & (accum == ".")) then {
                // Special handler for .. operator
                mode := "o"
                newmode := mode
            }
            if ((c == "/") & (accum == "/")) then {
                // Start of comment
                mode := "c"
                newmode := mode
            }
            if ((newmode == mode) & (mode == "n")
                & (unicode.isSeparator(ordval).not)
                & (unicode.isControl(ordval).not)) then {
                if ((unicode.isSeparator(ordval).not)
                    & (ordval /= 10) & (ordval /= 13)
                    & (ordval /= 32)) then {
                    util.syntax_error("unknown character in input: #{ordval}"
                        ++ " '{c}', {unicode.name(c)}")
                }
            }
        }
        if ((mode == "x") & (c == "\"") & (escaped.not)) then {
            // End of octet literal
            newmode := "n"
            instr := false
        }
        if ((mode == "\"") & (c == "\"") & (escaped.not)) then {
            // End of string literal
            newmode := "n"
            instr := false
            if (interpString) then {
                modechange(tokens, mode, accum)
                modechange(tokens, ")", ")")
                mode := newmode
                interpString := false
            }
        }
        if ((mode == "I") & (inBackticks) & (c == "`")) then {
            // End of backticked identifier
            newmode := "n"
            inBackticks := false
            backtickIdent := true
        }
        if (newmode /= mode) then {
            // This character is the beginning of a different lexical
            // mode - process the old one now.
            modechange(tokens, mode, accum)
            if ((newmode == "}") & (interpdepth > 0)) then {
                modechange(tokens, ")", ")")
                modechange(tokens, "o", "++")
                newmode := "\""
                instr := true
                interpdepth := interpdepth - 1
            }
            mode := newmode
            if (instr | inBackticks) then {
                // String accum should skip the opening quote, but
                // other modes' should include their first character.
                accum := ""
            } else {
                accum := c
            }
            if ((mode == "(") | (mode == ")") | (mode == "[")
                | (mode == "]") | (mode == "\{") | (mode == "}")) then {
                modechange(tokens, mode, accum)
                mode := "n"
                newmode := "n"
                accum := ""
            }
            backtickIdent := false
        } elseif (instr) then {
            if (c == "\n") then {
                if (interpdepth > 0) then {
                    util.syntax_error("Runaway string interpolation")
                } else {
                    util.syntax_error("Newlines not permitted in string literals")
                }
            }
            if (escaped) then {
                if (c == "n") then {
                    // Newline escape
                    accum := accum ++ "\u000a"
                } elseif (c == "u") then {
                    // Beginning of a four-digit Unicode escape (for a BMP
                    // codepoint).
                    unichars := 4
                    codepoint := 0
                } elseif (c == "U") then {
                    // Beginning of a six-digit Unicode escape (for a general
                    // codepoint).
                    unichars := 6
                    codepoint := 0
                } elseif (c == "t") then {
                    // Tab escape
                    accum := accum ++ "\u0009"
                } elseif (c == "r") then {
                    // Carriage return escape
                    accum := accum ++ "\u000d"
                } elseif (c == "b") then {
                    // Backspace escape
                    accum := accum ++ "\u0008"
                } elseif (c == "l") then {
                    // LINE SEPARATOR escape
                    accum := accum ++ "\u2028"
                } elseif (c == "f") then {
                    // Form feed/"page down" escape
                    accum := accum ++ "\u000c"
                } elseif (c == "e") then {
                    // Escape escape
                    accum := accum ++ "\u001b"
                } else {
                    // For any other character preceded by \, insert it
                    // literally.
                    accum := accum ++ c
                }
                escaped := false
            } elseif (c == "\\") then {
                // Begin an escape sequence
                escaped := true
            } elseif (unichars > 0) then {
                // There are still hex digits to read for a Unicode escape.
                // Use the current character as a hex digit and update the
                // codepoint being calculated with its value.
                unichars := unichars - 1
                codepoint := codepoint * 16
                codepoint := codepoint + hexdecchar(c)
                if (unichars == 0) then {
                    // At the end of the sequence construct the character
                    // in the unicode library.
                    accum := accum ++ unicode.create(codepoint)
                }
            } elseif (c == "\{") then {
                if (interpString.not) then {
                    modechange(tokens, "(", "(")
                    interpString := true
                }
                modechange(tokens, mode, accum)
                modechange(tokens, "o", "++")
                modechange(tokens, "(", "(")
                mode := "n"
                newmode := "n"
                accum := ""
                instr := false
                interpdepth := interpdepth + 1
            } else {
                accum := accum ++ c
            }
        } elseif (inBackticks) then {
            if (c == "\n") then {
                util.syntax_error("Newlines not permitted in backtick "
                    ++ "identifiers")
            }
            accum := accum ++ c
        } elseif (c == "\n") then {
            // Linebreaks terminate any open tokens
            modechange(tokens, mode, accum)
            mode := "d"
            newmode := "d"
            accum := ""
        } else {
            accum := accum ++ c
        }
        if (c == "\n") then {
            // Linebreaks increment the line counter and insert a
            // special "line" token, which the parser can use to track
            // the origin of AST nodes for later error reporting.
            lineNumber := lineNumber + 1
            linePosition := 0
            startPosition := 1
            util.setPosition(lineNumber, 0)
        }
        prev := c
    }
    modechange(tokens, mode, accum)
    tokens
}