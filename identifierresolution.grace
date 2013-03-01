#pragma DefaultVisibility=public
import "io" as io
import "sys" as sys
import "ast" as ast
import "util" as util
import "xmodule" as xmodule
import "mgcollections" as collections
import "mirrors" as mirrors

class Scope.new(parent') {
    def elements = collections.map.new
    def elementScopes = collections.map.new
    def parent = parent'
    var hasParent := true
    var variety := "block"
    var name := ""
    method add(n) {
        elements.put(n, "method")
    }
    method add(n)as(k) {
        elements.put(n, k)
    }
    method contains(n) {
        elements.contains(n)
    }
    method do(b) {
        b.apply(self)
        if (hasParent) then {
            parent.do(b)
        }
    }
    method getKind(n) {
        elements.get(n)
    }
    method bindAs(n) {
        parent.elementScopes.put(n, self)
    }
    method getScope(n) {
        if (elementScopes.contains(n)) then {
            return elementScopes.get(n)
        }
        return Scope.new(self)
    }
    method new {
        Scope.new(self)
    }
}

def builtinObj = Scope.new(object { })
builtinObj.variety := "top"
builtinObj.hasParent := false
def preludeObj = Scope.new(builtinObj)
preludeObj.variety := "dialect"
def moduleObj = Scope.new(preludeObj)
moduleObj.variety := "module"
var scope := moduleObj

method pushScope {
    scope := scope.new
}
method popScope {
    scope := scope.parent
}
method haveBinding(nm) {
    var cur := scope
    while {cur.hasParent} do {
        if (cur.contains(nm)) then {
            return true
        }
        cur := cur.parent
    }
    if (cur.contains(nm)) then {
        return true
    }
    return false
}

method getNameKind(nm) {
    scope.do {s->
        if (s.contains(nm)) then {
            return s.getKind(nm)
        }
    }
    return "undefined"
}

method getNameScope(nm) {
    scope.do {s->
        if (s.contains(nm)) then {
            return s
        }
    }
    return "undefined"
}

method findDeepMethod(name) {
    var mem := ast.identifierNode.new("self", false)
    scope.do { s->
        if (s.contains(name)) then {
            if (s.variety == "dialect") then {
                return ast.memberNode.new(name,
                    ast.identifierNode.new("prelude", false))
            }
            return ast.memberNode.new(name, mem)
        }
        match(s.variety)
            case { "object" -> mem := ast.memberNode.new("outer", mem) }
            case { "class" -> 
                mem := ast.memberNode.new("outer", mem)
                mem := ast.memberNode.new("outer", mem)
                }
            case { _ -> }
    }
    // Not found - leave it alone
    return ast.identifierNode.new(name, false)
}

method findDeepScope'(node, scope') {
    if (node.kind == "identifier") then {
        if (node.value == "self") then {
            var s := scope'
            while {s.hasParent} do {
                if (s.variety == "object") then {
                    return s
                }
                if (s.variety == "class") then {
                    return s
                }
                if (s.variety == "module") then {
                    return s
                }
                s := s.parent
            }
        }
        scope'.do {s->
            if (s.contains(node.value)) then {
                return s.getScope(node.value)
            }
        }
        return scope'.getScope(node.value)
    }
    if (node.kind == "member") then {
        def tmp = findDeepScope'(node.in, scope')
        if (node.value == "outer") then {
            return tmp.parent
        }
        return tmp.getScope(node.value)
    }
    if (node.kind == "call") then {
        return findDeepScope'(node.value, scope')
    }
    return Scope.new(scope')
}

method findDeepScope(node) {
    findDeepScope'(node, scope)
}

method rewritematchblockterm(arg) {
    if (arg.kind == "num") then {
        return [arg, []]
    }
    if (arg.kind == "string") then {
        return [arg, []]
    }
    if (arg.kind == "boolean") then {
        return [arg, []]
    }
    if ((arg.kind == "call").andAlso {arg.value.value.substringFrom(1)to(6)
        == "prefix"}) then {
        return [arg, []]
    }
    if (arg.kind == "call") then {
        def bindings = []
        def subpats = []
        for (arg.with) do { part ->
            for (part.args) do { a ->
                def tmp = rewritematchblockterm(a)
                subpats.push(tmp[1])
                for (tmp[2]) do {b->
                    bindings.push(b)
                }
            }
        }
        def callpat = ast.callNode.new(
            ast.memberNode.new(
                "new",
                ast.memberNode.new("MatchAndDestructuringPattern",
                    ast.identifierNode.new("prelude", false)
                )
            ),
            [ast.callWithPart.new("new", [arg.value, ast.arrayNode.new(subpats)])]
        )
        return [callpat, bindings]
    }
    if (arg.kind == "identifier") then {
        def varpat = ast.callNode.new(
            ast.memberNode.new(
                "new",
                ast.memberNode.new("VariablePattern",
                    ast.identifierNode.new("prelude", false)
                )
            ),
            [ast.callWithPart.new("new", [ast.stringNode.new(arg.value)])]
        )
        if (arg.dtype != false) then {
            if (arg.dtype.kind == "identifier") then {
                return [ast.callNode.new(
                    ast.memberNode.new(
                        "new",
                        ast.memberNode.new("AndPattern",
                            ast.identifierNode.new("prelude", false)
                        )
                    ),
                    [ast.callWithPart.new("new", [varpat, arg.dtype])]
                ), [arg]]
            }
            def tmp = rewritematchblockterm(arg.dtype)
            def bindings = [arg]
            for (tmp[2]) do {b->
                bindings.push(b)
            }
            def bindingpat = ast.callNode.new(
                ast.memberNode.new(
                    "new",
                    ast.memberNode.new("AndPattern",
                        ast.identifierNode.new("prelude", false)
                    )
                ),
                [ast.callWithPart.new("new", [varpat, tmp[1]])]
            )
            return [bindingpat, bindings]
        }
        return [varpat, [arg]]
    }
    if (arg.kind == "type") then {
        return [arg, []]
    }
}
method rewritematchblock(blk) {
    def arg = blk.params[1]
    var pattern := false
    var newparams := collections.list.new
    for (blk.params) do { p ->
        newparams.push(p)
    }
    if ((arg.kind == "num") || (arg.kind == "string") ||
        (arg.kind == "boolean")) then {
        def tmp = rewritematchblockterm(arg)
        pattern := tmp[1]
        newparams := tmp[2]
    }
    if (arg.kind == "identifier") then {
        def varpat = ast.callNode.new(
            ast.memberNode.new(
                "new",
                ast.memberNode.new("VariablePattern",
                    ast.identifierNode.new("prelude", false)
                )
            ),
            [ast.callWithPart.new("new", [ast.stringNode.new(arg.value)])]
        )
        if (arg.dtype != false) then {
            match (arg.dtype.kind)
                case { "identifier" ->
                    pattern := ast.callNode.new(
                        ast.memberNode.new("new",
                            ast.memberNode.new("AndPattern",
                                ast.identifierNode.new("prelude", false)
                                )
                            ),
                        [ast.callWithPart.new("new", [varpat, arg.dtype])])
                } case { "op" ->
                    pattern := ast.callNode.new(
                        ast.memberNode.new("new",
                            ast.memberNode.new("AndPattern",
                                ast.identifierNode.new("prelude", false)
                                )
                            ),
                        [ast.callWithPart.new("new", [varpat, arg.dtype])])
                } case { _ ->
                    def tmp = rewritematchblockterm(arg.dtype)
                    def bindingpat = ast.callNode.new(
                        ast.memberNode.new("new",
                            ast.memberNode.new("AndPattern",
                                ast.identifierNode.new("prelude", false)
                                )
                            ),
                        [ast.callWithPart.new("new", [varpat, tmp[1]])]
                    )
                    pattern := bindingpat
                    for (tmp[2]) do {p->
                        newparams.push(p)
                    }
                }
            pattern := resolveIdentifiers(pattern)
        } else {
            if (false != blk.matchingPattern) then {
                if (blk.matchingPattern.value == arg.value) then {
                    pattern := resolveIdentifiers(arg)
                    newparams := []
                }
            }
        }
    } else {
        if (false != blk.matchingPattern) then {
            if (blk.matchingPattern.value == arg.value) then {
                pattern := resolveIdentifiers(arg)
                newparams := []
            }
        }
    }
    def newblk = ast.blockNode.new(newparams, blk.body)
    newblk.matchingPattern := pattern
    newblk.line := blk.line
    return newblk
}

method resolveIdentifier(node) {
    if (node.kind != "identifier") then {
        return node
    }
    var nm := node.value
    util.setline(node.line)
    if (haveBinding(nm).not) then {
        scope.do {s->
            print(s.elements)
        }
        util.syntax_error("use of undefined identifier {nm}")
    }
    if (nm == "outer") then {
        return ast.memberNode.new("outer", ast.identifierNode.new("self", false))
    }
    if (nm == "self") then {
        return node
    }
    if (getNameKind(nm) == "method") then {
        // Bare method call with no arguments
        def meth = findDeepMethod(nm)
        return ast.callNode.new(meth, [ast.callWithPart.new(meth.value)])
    }
    node
}

method resolveIdentifiersActual(node) {
    util.setline(node.line)
    if (node == false) then {
        return node
    }
    if (node.kind == "identifier") then {
        return resolveIdentifier(node)
    }
    if (node.kind == "import") then {
        scope.add(node.value) as "def"
    }
    if (node.kind == "call") then {
        if (node.value.kind == "call") then {
            def tmp = ast.callNode.new(node.value.value, node.with)
            tmp.line := node.line
            return tmp
        }
    }
    if (node.kind == "block") then {
        if (node.params.size == 1) then {
            return rewritematchblock(node)
        }
    }
    if (node.kind == "bind") then {
        if (node.dest.kind == "call") then {
            def tmp = ast.bindNode.new(node.dest.value, node.value)
            tmp.line := node.line
            return tmp
        }
        if (node.dest.kind == "identifier") then {
            if (getNameKind(node.dest.value) == "def") then {
                util.syntax_error "reassignment to constant {node.dest.value}"
            }
        }
    }
    node
}
method resolveIdentifiers(topNode) {
    // Recursively replace bare identifiers with their fully-qualified
    // equivalents.
    if (topNode == false) then {
        return topNode
    }
    topNode.map { n -> resolveIdentifiersActual(n) } before { node ->
        if (node.kind == "class") then {
            scope.add(node.name.value) as "def"
            def classScope = Scope.new(scope)
            classScope.add(node.constructor.value)
            classScope.bindAs(node.name.value)
            pushScope
            classScope.elementScopes.put(node.constructor.value, scope)
            scope.variety := "class"
            for (node.signature) do {s->
                for (s.params) do {p->
                    scope.add(p.value)as "def"
                }
                if (false != s.vararg) then {
                    scope.add(s.vararg.value) as "def"
                }
            }
            for (node.value) do {n->
                if (n.kind == "method") then {
                    scope.add(n.value.value)
                }
                if (n.kind == "var") then {
                    scope.add(n.name.value)
                    scope.add(n.name.value ++ ":=")
                }
                if (n.kind == "def") then {
                    scope.add(n.name.value)
                }
                if (n.kind == "inherits") then {
                    def parent = resolveIdentifiers(n.value)
                    def parentScope = findDeepScope(parent)
                    for (parentScope.elements) do {e->
                        scope.add(e)
                    }
                }
            }
        }
        if (node.kind == "object") then {
            pushScope
            scope.variety := "object"
            for (node.value) do {n->
                if (n.kind == "method") then {
                    scope.add(n.value.value)
                }
                if (n.kind == "var") then {
                    scope.add(n.name.value)
                    scope.add(n.name.value ++ ":=")
                }
                if (n.kind == "def") then {
                    scope.add(n.name.value)
                }
                if (n.kind == "inherits") then {
                    def parent = resolveIdentifiers(n.value)
                    def parentScope = findDeepScope(parent)
                    for (parentScope.elements) do {e->
                        scope.add(e)
                    }
                }
            }
        }
        if (node.kind == "block") then {
            pushScope
            var tmp := node
            if (node.params.size == 1) then {
                tmp := rewritematchblock(tmp)
            }
            for (tmp.params) do {p->
                scope.add(p.value)as "def"
            }
        }
        if (node.kind == "type") then {
            scope.add(node.value) as "def"
            pushScope
            scope.variety := "type"
            for (node.generics) do {n->
                scope.add(n.value) as "def"
            }
        }
        if (node.kind == "methodtype") then {
            scope.add(node.value)
            pushScope
            for (node.signature) do {s->
                for (s.params) do {p->
                    scope.add(p.value)as "def"
                }
                if (false != s.vararg) then {
                    scope.add(s.vararg.value) as "def"
                }
            }
        }
        if (node.kind == "method") then {
            scope.add(node.value.value)
            pushScope
            scope.variety := "method"
            scope.name := node.value.value
            for (node.signature) do {s->
                for (s.params) do {p->
                    scope.add(p.value)as "def"
                }
                if (false != s.vararg) then {
                    scope.add(s.vararg.value) as "def"
                }
            }
        }
        if (node.kind == "vardec") then {
            if ((scope.variety != "object") && (scope.variety != "class")) then {
                scope.add(node.name.value)as "var"
            } else {
                scope.add(node.name.value)
            }
        }
        if (node.kind == "defdec") then {
            if ((scope.variety != "object") && (scope.variety != "class")) then {
                scope.add(node.name.value)as "def"
            } else {
                scope.add(node.name.value)
            }
        }
        if (node.kind == "defdec") then {
            if ((scope.variety != "object") && (scope.variety != "class")) then {
                scope.add(node.name.value)as "def"
            } else {
                scope.add(node.name.value)
            }
        }
    } after { node ->
        if (node.kind == "class") then {
            node.data := scope
            popScope
        }
        if (node.kind == "object") then {
            if (scope.parent.variety == "method") then {
                scope.parent.parent.elementScopes.put(scope.parent.name,
                    scope)
            }
            node.data := scope
            popScope
        }
        if (node.kind == "block") then {
            popScope
        }
        if (node.kind == "method") then {
            popScope
        }
        if (node.kind == "methodtype") then {
            popScope
        }
        if (node.kind == "type") then {
            popScope
        }
        if (node.kind == "defdec") then {
            if (node.value.kind == "object") then {
                scope.elementScopes.put(node.name.value, node.value.data)
            }
        }
    }
}

method resolve(values) {
    util.log_verbose "resolving identifiers."
    preludeObj.add "for()do"
    preludeObj.add "while()do"
    preludeObj.add "print"
    builtinObj.add "Dynamic" as "def"
    builtinObj.add "String" as "def"
    builtinObj.add "Number" as "def"
    builtinObj.add "Boolean" as "def"
    builtinObj.add "Done" as "def"
    builtinObj.add "true" as "def"
    builtinObj.add "false" as "def"
    builtinObj.add "self" as "def"
    builtinObj.add "super" as "def"
    builtinObj.add "outer" as "def"
    builtinObj.add "readable" as "def"
    builtinObj.add "writable" as "def"
    builtinObj.add "public" as "def"
    builtinObj.add "prelude" as "def"
    builtinObj.add "_prelude" as "def"
    // Historical - should be removed eventually
    builtinObj.add "Unit" as "def"
    builtinObj.add "void" as "def"
    builtinObj.add "nothing" as "def"
    builtinObj.add "platform" as "def"
    builtinObj.add "HashMap" as "def"
    builtinObj.add "escapestring" as "method"
    builtinObj.add "length" as "method"
    if (!util.extensions.contains("NativePrelude")) then {
        var hadDialect := false
        for (values) do {val->
            if (val.kind == "dialect") then {
                hadDialect := true
                def data = xmodule.parseGCT(val.value, "/nosuchfile")
                if (data.contains("public")) then {
                    for (data.get("public")) do {mn->
                        preludeObj.add(mn)
                    }
                }
                if (data.contains("confidential")) then {
                    for (data.get("confidential")) do {mn->
                        preludeObj.add(mn)
                    }
                }
            }
        }
        if (!hadDialect) then {
            for (prelude._methods) do {mn->
                preludeObj.add(mn)
            }
        }
    }
    def vals = collections.list.new
    for (values) do { n ->
        if (n.kind == "method") then {
            scope.add(n.value.value)
        }
        if ((n.kind == "class") || (n.kind == "def")) then {
            scope.add(n.name.value) as "def"
        }
        if (n.kind == "var") then {
            scope.add(n.name.value) as "var"
        }
        if (n.kind == "type") then {
            scope.add(n.value)
        }
    }
    for (values) do { v ->
        def v' = resolveIdentifiers(v)
        vals.push(v')
        if (v'.kind == "method") then {
            if (moduleObj.elementScopes.contains(v'.value.value)) then {
                v'.properties.put("fresh", moduleObj.getScope(v'.value.value))
            }
        }
    }
    vals
}