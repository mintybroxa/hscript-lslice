/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
 /* UPDATED MACRO
 */
package hscript;

import haxe.macro.Expr;
import hscript.Expr.Error;
#if hscriptPos
import hscript.Expr.ErrorDef;
#end

class Macro {
    var p:Position;
    final binops:Map<String,Binop> = [];
    final unops:Map<String,Unop> = [];

    public function new(pos:Position) {
        p = pos;
        initBinops();
        initUnops();
    }

    inline function map<T,R>(arr:Array<T>, fn:T->R):Array<R> {
        return [for (i in arr) fn(i)];
    }

    function initBinops() {
        for (c in Type.getEnumConstructs(Binop)) {
            if (c == "OpAssignOp") continue;
            var op = Type.createEnum(Binop, c);
            var assign = false;
            final str = switch (op) {
                case OpAdd: assign = true; "+";
                case OpSub: assign = true; "-";
                case OpMult: assign = true; "*";
                case OpDiv: assign = true; "/";
                case OpMod: assign = true; "%";
                case OpAnd: assign = true; "&";
                case OpOr: assign = true; "|";
                case OpXor: assign = true; "^";
                case OpShl: assign = true; "<<";
                case OpShr: assign = true; ">>";
                case OpUShr: assign = true; ">>>";
                case OpAssign: "=";
                case OpEq: "==";
                case OpNotEq: "!=";
                case OpGt: ">";
                case OpGte: ">=";
                case OpLt: "<";
                case OpLte: "<=";
                case OpBoolAnd: "&&";
                case OpBoolOr: "||";
                case OpInterval: "...";
                case OpArrow: "=>";
                #if (haxe_ver >= 4) 
                case OpIn: "in"; 
                #end
                case OpAssignOp(_): continue;
            };
            binops.set(str, op);
            if (assign) binops.set(str + "=", OpAssignOp(op));
        }
    }

    function initUnops() {
        for (c in Type.getEnumConstructs(Unop)) {
            final op = Type.createEnum(Unop, c);
            final str = switch (op) {
                case OpNot: "!";
                case OpNeg: "-";
                case OpNegBits: "~";
                case OpIncrement: "++";
                case OpDecrement: "--";
                #if (haxe_ver >= 4.2)
                case OpSpread: continue;
                #end
            };
            unops.set(str, op);
        }
    }

    function convertType(t:Expr.CType):ComplexType {
        return switch (t) {
            case CTOpt(sub): TOptional(convertType(sub));
            case CTPath(pack, args):
                final params = args == null ? [] : args.map(arg -> switch (arg) {
                    case CTExpr(e): TPExpr(convert(e));
                    default: TPType(convertType(arg));
                });
                TPath({
                    pack: pack.copy(),
                    name: pack.pop(),
                    params: params,
                    sub: null
                });
            case CTParent(sub): TParent(convertType(sub));
            case CTFun(args, ret):
                TFunction(args.map(convertType), convertType(ret));
            case CTNamed(name, sub):
                #if (haxe_ver >= 4) 
                TNamed(name, convertType(sub)); 
                #else 
                convertType(sub);
                #end
            case CTAnon(fields):
                TAnonymous([
                    for (f in fields) {
                        name: f.name,
                        meta: f.meta == null ? [] : [
                            for (m in f.meta) {
                                name: m.name,
                                params: m.params == null ? [] : m.params.map(convert),
                                pos: p
                            }
                        ],
                        doc: null,
                        access: [],
                        kind: FVar(convertType(f.t), null),
                        pos: p
                    }
                ]);
            case CTExpr(_):
                throw "Unsupported CTExpr in convertType";
        }
    }

    public function convert(e:hscript.Expr):Expr {
        return {
            expr: switch (#if hscriptPos e.e #else e #end) {
                case EConst(c):
                    EConst(switch(c) {
                        case CInt(v): CInt(Std.string(v));
                        case CFloat(f): CFloat(Std.string(f));
                        case CString(s): CString(s);
                    });
                case EIdent(v):
                    EConst(CIdent(v));
                case EVar(n, t, e):
                    EVars([{
                        name: n,
                        expr: e == null ? null : convert(e),
                        type: t == null ? null : convertType(t)
                    }]);
                case EParent(sub): EParenthesis(convert(sub));
                case EBlock(el): EBlock(el.map(convert));
                case EField(e, f): EField(convert(e), f);
                case EBinop(op, e1, e2):
                    final b = binops.get(op);
                    if (b == null) throw 'Invalid binary operator "$op"';
                    EBinop(b, convert(e1), convert(e2));
                case EUnop(op, prefix, e):
                    final u = unops.get(op);
                    if (u == null) throw 'Invalid unary operator "$op"';
                    EUnop(u, !prefix, convert(e));
                case ECall(e, params): ECall(convert(e), params.map(convert));
                case EIf(c, e1, e2):
                    EIf(convert(c), convert(e1), e2 == null ? null : convert(e2));
                case EWhile(c, body): EWhile(convert(c), convert(body), true);
                case EDoWhile(c, body): EWhile(convert(c), convert(body), false);
                case EFor(v, it, body):
                    final p2 = makePos(e);
                    EFor({
                        expr: EBinop(OpIn, {
                            expr: EConst(CIdent(v)),
                            pos: p2
                        }, convert(it)),
                        pos: p2
                    }, convert(body));
                case EForGen(it, body): EFor(convert(it), convert(body));
                case EBreak: EBreak;
                case EContinue: EContinue;
                case EFunction(args, body, name, ret):
                    final fnArgs = args.map(a -> {
                        name: a.name,
                        type: a.t == null ? null : convertType(a.t),
                        opt: false,
                        value: null
                    });
                    EFunction(#if haxe4 name != null ? FNamed(name, false) : FAnonymous #else name #end, {
                        params: [],
                        args: fnArgs,
                        expr: convert(body),
                        ret: ret == null ? null : convertType(ret)
                    });
                case EReturn(e): EReturn(e == null ? null : convert(e));
                case EArray(e, index): EArray(convert(e), convert(index));
                case EArrayDecl(el): EArrayDecl(el.map(convert));
                case ENew(cl, params):
                    final pack = cl.split(".");
                    ENew({
                        pack: pack.copy(),
                        name: pack.pop(),
                        params: [],
                        sub: null
                    }, params.map(convert));
                case EThrow(e): EThrow(convert(e));
                case ETry(body, v, t, catchExpr):
                    ETry(convert(body), [{
                        type: convertType(t),
                        name: v,
                        expr: convert(catchExpr)
                    }]);
                case EObject(fields):
                    EObjectDecl([for (f in fields) { field: f.name, expr: convert(f.e) }]);
                case ETernary(cond, e1, e2):
                    ETernary(convert(cond), convert(e1), convert(e2));
                case ESwitch(e, cases, edef):
                    ESwitch(convert(e), [for (c in cases) {
                        values: c.values.map(convert),
                        expr: convert(c.expr)
                    }], edef == null ? null : convert(edef));
                case EMeta(name, params, esub):
                    EMeta({
                        name: name,
                        params: params == null ? [] : params.map(convert),
                        pos: makePos(e)
                    }, convert(esub));
                case ECheckType(e, t): ECheckType(convert(e), convertType(t));
            },
            pos: makePos(e)
        }
    }

    inline function makePos(e:hscript.Expr):Position {
        #if (!macro && hscriptPos)
        return { file: p.file, min: e.pmin, max: e.pmax };
        #else
        return p;
        #end
    }
}
