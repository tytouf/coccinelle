(*
 * Copyright 2012, INRIA
 * Julia Lawall, Gilles Muller
 * Copyright 2010-2011, INRIA, University of Copenhagen
 * Julia Lawall, Rene Rydhof Hansen, Gilles Muller, Nicolas Palix
 * Copyright 2005-2009, Ecole des Mines de Nantes, University of Copenhagen
 * Yoann Padioleau, Julia Lawall, Rene Rydhof Hansen, Henrik Stuart, Gilles Muller, Nicolas Palix
 * This file is part of Coccinelle.
 *
 * Coccinelle is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, according to version 2 of the License.
 *
 * Coccinelle is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Coccinelle.  If not, see <http://www.gnu.org/licenses/>.
 *
 * The authors reserve the right to distribute this or future versions of
 * Coccinelle under other licenses.
 *)


# 0 "./ast0_cocci.ml"
module Ast = Ast_cocci
module TC = Type_cocci

(* --------------------------------------------------------------------- *)
(* Modified code *)

type arity = OPT | UNIQUE | NONE

type token_info =
    { tline_start : int; tline_end : int;
      left_offset : int; right_offset : int }
let default_token_info =
  { tline_start = -1; tline_end = -1; left_offset = -1; right_offset = -1 }

(* MIXED is like CONTEXT, since sometimes MIXED things have to revert to
CONTEXT - see insert_plus.ml *)

type mcodekind =
    MINUS       of (Ast.anything Ast.replacement * token_info) ref
  | PLUS        of Ast.count
  | CONTEXT     of (Ast.anything Ast.befaft * token_info * token_info) ref
  | MIXED       of (Ast.anything Ast.befaft * token_info * token_info) ref

type position_info = { line_start : int; line_end : int;
		       logical_start : int; logical_end : int;
		       column : int; offset : int; }

type info = { pos_info : position_info;
	      attachable_start : bool; attachable_end : bool;
	      mcode_start : mcodekind list; mcode_end : mcodekind list;
	      (* the following are only for + code *)
	      strings_before : (Ast.added_string * position_info) list;
	      strings_after : (Ast.added_string * position_info) list;
	      isSymbolIdent : bool; (* is the token a symbol identifier or not *) }

(* adjacency index is incremented when we skip over dots or nest delimiters
it is used in deciding how much to remove, when two adjacent code tokens are
removed. *)
type adjacency = int

type fake_mcode = info * mcodekind * adjacency

type 'a mcode =
    'a * arity * info * mcodekind * anything list ref (* pos, - only *) *
      adjacency (* adjacency_index *)
(* int ref is an index *)
and 'a wrap =
    { node : 'a;
      info : info;
      index : int ref;
      mcodekind : mcodekind ref;
      exp_ty : TC.typeC option ref; (* only for expressions *)
      bef_aft : dots_bef_aft; (* only for statements *)
      true_if_arg : bool; (* true if "arg_exp", only for exprs *)
      true_if_test : bool; (* true if "test position", only for exprs *)
      true_if_test_exp : bool;(* true if "test_exp from iso", only for exprs *)
      (*nonempty if this represents the use of an iso*)
      iso_info : (string*anything) list }

and dots_bef_aft =
    NoDots | AddingBetweenDots of statement | DroppingBetweenDots of statement

(* for iso metavariables, true if they can only match nonmodified terms with
   all metavariables unitary
   for SP metavariables, true if the metavariable is unitary (valid up to
   isomorphism phase only)
   In SP, the only options are impure and context
*)
and pure = Impure | Pure | Context | PureContext (* pure and only context *)

(* --------------------------------------------------------------------- *)
(* --------------------------------------------------------------------- *)
(* Dots *)

and 'a base_dots =
    DOTS of 'a list
  | CIRCLES of 'a list
  | STARS of 'a list

and 'a dots = 'a base_dots wrap

(* --------------------------------------------------------------------- *)
(* Identifier *)

and base_ident =
    Id            of string mcode
  | MetaId        of Ast.meta_name mcode * Ast.idconstraint * Ast.seed * pure
  | MetaFunc      of Ast.meta_name mcode * Ast.idconstraint * pure
  | MetaLocalFunc of Ast.meta_name mcode * Ast.idconstraint * pure
  | AsIdent       of ident * ident (* as ident, always metavar *)
  | DisjId        of string mcode * ident list *
                     string mcode list (* the |s *) * string mcode
  | OptIdent      of ident
  | UniqueIdent   of ident

and ident = base_ident wrap

(* --------------------------------------------------------------------- *)
(* Expression *)

and base_expression =
    Ident          of ident
  | Constant       of Ast.constant mcode
  | FunCall        of expression * string mcode (* ( *) *
                      expression dots * string mcode (* ) *)
  | Assignment     of expression * Ast.assignOp mcode * expression *
	              bool (* true if it can match an initialization *)
  | Sequence       of expression * string mcode (* , *) * expression
  | CondExpr       of expression * string mcode (* ? *) * expression option *
	              string mcode (* : *) * expression
  | Postfix        of expression * Ast.fixOp mcode
  | Infix          of expression * Ast.fixOp mcode
  | Unary          of expression * Ast.unaryOp mcode
  | Binary         of expression * Ast.binaryOp mcode * expression
  | Nested         of expression * Ast.binaryOp mcode * expression
  | Paren          of string mcode (* ( *) * expression *
                      string mcode (* ) *)
  | ArrayAccess    of expression * string mcode (* [ *) * expression *
	              string mcode (* ] *)
  | RecordAccess   of expression * string mcode (* . *) * ident
  | RecordPtAccess of expression * string mcode (* -> *) * ident
  | Cast           of string mcode (* ( *) * typeC * string mcode (* ) *) *
                      expression
  | SizeOfExpr     of string mcode (* sizeof *) * expression
  | SizeOfType     of string mcode (* sizeof *) * string mcode (* ( *) *
                      typeC * string mcode (* ) *)
  | TypeExp        of typeC (* type name used as an expression, only in args *)
  | Constructor    of string mcode (* ( *) * typeC * string mcode (* ) *) *
	              initialiser
  | MetaErr        of Ast.meta_name mcode * constraints * pure
  | MetaExpr       of Ast.meta_name mcode * constraints *
	              TC.typeC list option * Ast.form * pure
  | MetaExprList   of Ast.meta_name mcode (* only in arg lists *) *
	              listlen * pure
  | AsExpr         of expression * expression (* as expr, always metavar *)
  | EComma         of string mcode (* only in arg lists *)
  | DisjExpr       of string mcode * expression list *
	              string mcode list (* the |s *) * string mcode
  | NestExpr       of string mcode * expression dots * string mcode *
	              expression option * Ast.multi
  | Edots          of string mcode (* ... *) * expression option
  | Ecircles       of string mcode (* ooo *) * expression option
  | Estars         of string mcode (* *** *) * expression option
  | OptExp         of expression
  | UniqueExp      of expression

and expression = base_expression wrap

and constraints =
    NoConstraint
  | NotIdCstrt     of Ast.reconstraint
  | NotExpCstrt    of expression list
  | SubExpCstrt    of Ast.meta_name list

and listlen =
    MetaListLen of Ast.meta_name mcode
  | CstListLen of int
  | AnyListLen

(* --------------------------------------------------------------------- *)
(* Types *)

and base_typeC =
    ConstVol        of Ast.const_vol mcode * typeC
  | BaseType        of Ast.baseType * string mcode list
  | Signed          of Ast.sign mcode * typeC option
  | Pointer         of typeC * string mcode (* * *)
  | FunctionPointer of typeC *
	          string mcode(* ( *)*string mcode(* * *)*string mcode(* ) *)*
                  string mcode (* ( *)*parameter_list*string mcode(* ) *)
  | FunctionType    of typeC option *
	               string mcode (* ( *) * parameter_list *
                       string mcode (* ) *)
  | Array           of typeC * string mcode (* [ *) *
	               expression option * string mcode (* ] *)
  | EnumName        of string mcode (*enum*) * ident option (* name *)
  | EnumDef  of typeC (* either StructUnionName or metavar *) *
	string mcode (* { *) * expression dots * string mcode (* } *)
  | StructUnionName of Ast.structUnion mcode * ident option (* name *)
  | StructUnionDef  of typeC (* either StructUnionName or metavar *) *
	string mcode (* { *) * declaration dots * string mcode (* } *)
  | TypeName        of string mcode
  | MetaType        of Ast.meta_name mcode * pure
  | AsType          of typeC * typeC (* as type, always metavar *)
  | DisjType        of string mcode * typeC list * (* only after iso *)
                       string mcode list (* the |s *)  * string mcode
  | OptType         of typeC
  | UniqueType      of typeC

and typeC = base_typeC wrap

(* --------------------------------------------------------------------- *)
(* Variable declaration *)
(* Even if the Cocci program specifies a list of declarations, they are
   split out into multiple declarations of a single variable each. *)

and base_declaration =
    MetaDecl of Ast.meta_name mcode * pure (* variables *)
    (* the following are kept separate from MetaDecls because ultimately
       they don't match the same thin at all.  Consider whether there
       should be a separate type for fields, as in the C AST *)
  | MetaField of Ast.meta_name mcode * pure (* structure fields *)
  | MetaFieldList of Ast.meta_name mcode * listlen * pure (* structure fields *)
  | AsDecl        of declaration * declaration
  | Init of Ast.storage mcode option * typeC * ident * string mcode (*=*) *
	initialiser * string mcode (*;*)
  | UnInit of Ast.storage mcode option * typeC * ident * string mcode (* ; *)
  | TyDecl of typeC * string mcode (* ; *)
  | MacroDecl of ident (* name *) * string mcode (* ( *) *
        expression dots * string mcode (* ) *) * string mcode (* ; *)
  | MacroDeclInit of ident (* name *) * string mcode (* ( *) *
        expression dots * string mcode (* ) *) * string mcode (*=*) *
	initialiser * string mcode (* ; *)
  | Typedef of string mcode (* typedef *) * typeC * typeC * string mcode (*;*)
  | DisjDecl   of string mcode * declaration list *
                  string mcode list (* the |s *)  * string mcode
  (* Ddots is for a structure declaration *)
  | Ddots      of string mcode (* ... *) * declaration option (* whencode *)
  | OptDecl    of declaration
  | UniqueDecl of declaration

and declaration = base_declaration wrap

(* --------------------------------------------------------------------- *)
(* Initializers *)

and base_initialiser =
    MetaInit of Ast.meta_name mcode * pure
  | MetaInitList of Ast.meta_name mcode * listlen * pure
  | AsInit of initialiser * initialiser (* as init, always metavar *)
  | InitExpr of expression
  | InitList of string mcode (*{*) * initialiser_list * string mcode (*}*) *
	(* true if ordered, as for array, false if unordered, as for struct *)
	bool
  | InitGccExt of
      designator list (* name *) * string mcode (*=*) *
	initialiser (* gccext: *)
  | InitGccName of ident (* name *) * string mcode (*:*) *
	initialiser
  | IComma of string mcode (* , *)
  | Idots  of string mcode (* ... *) * initialiser option (* whencode *)
  | OptIni    of initialiser
  | UniqueIni of initialiser

and designator =
    DesignatorField of string mcode (* . *) * ident
  | DesignatorIndex of string mcode (* [ *) * expression * string mcode (* ] *)
  | DesignatorRange of
      string mcode (* [ *) * expression * string mcode (* ... *) *
      expression * string mcode (* ] *)

and initialiser = base_initialiser wrap

and initialiser_list = initialiser dots

(* --------------------------------------------------------------------- *)
(* Parameter *)

and base_parameterTypeDef =
    VoidParam     of typeC
  | Param         of typeC * ident option
  | MetaParam     of Ast.meta_name mcode * pure
  | MetaParamList of Ast.meta_name mcode * listlen * pure
  | AsParam       of parameterTypeDef * expression (* expr, always metavar *)
  | PComma        of string mcode
  | Pdots         of string mcode (* ... *)
  | Pcircles      of string mcode (* ooo *)
  | OptParam      of parameterTypeDef
  | UniqueParam   of parameterTypeDef

and parameterTypeDef = base_parameterTypeDef wrap

and parameter_list = parameterTypeDef dots

(* --------------------------------------------------------------------- *)
(* #define Parameters *)

and base_define_param =
    DParam        of ident
  | DPComma       of string mcode
  | DPdots        of string mcode (* ... *)
  | DPcircles     of string mcode (* ooo *)
  | OptDParam     of define_param
  | UniqueDParam  of define_param

and define_param = base_define_param wrap

and base_define_parameters =
    NoParams
  | DParams      of string mcode(*( *) * define_param dots * string mcode(* )*)

and define_parameters = base_define_parameters wrap

(* --------------------------------------------------------------------- *)
(* Statement*)

and base_statement =
    (*Decl and FunDecl don't need adjacency.  Delete all comments in any case*)
    Decl          of (info * mcodekind) (* before the decl *) * declaration
  | Seq           of string mcode (* { *) * statement dots *
 	             string mcode (* } *)
  | ExprStatement of expression option * string mcode (*;*)
  | IfThen        of string mcode (* if *) * string mcode (* ( *) *
	             expression * string mcode (* ) *) *
	             statement * fake_mcode (* after info *)
  | IfThenElse    of string mcode (* if *) * string mcode (* ( *) *
	             expression * string mcode (* ) *) *
	             statement * string mcode (* else *) * statement *
	             fake_mcode (* after info *)
  | While         of string mcode (* while *) * string mcode (* ( *) *
	             expression * string mcode (* ) *) *
	             statement * fake_mcode (* after info *)
  | Do            of string mcode (* do *) * statement *
                     string mcode (* while *) * string mcode (* ( *) *
	             expression * string mcode (* ) *) *
                     string mcode (* ; *)
  | For           of string mcode (* for *) * string mcode (* ( *) * forinfo *
	             expression option * string mcode (*;*) *
                     expression option * string mcode (* ) *) * statement *
	             fake_mcode (* after info *)
  | Iterator      of ident (* name *) * string mcode (* ( *) *
	             expression dots * string mcode (* ) *) *
	             statement * fake_mcode (* after info *)
  | Switch        of string mcode (* switch *) * string mcode (* ( *) *
	             expression * string mcode (* ) *) * string mcode (* { *) *
	             statement (*decl*) dots *
	             case_line dots * string mcode (* } *)
  | Break         of string mcode (* break *) * string mcode (* ; *)
  | Continue      of string mcode (* continue *) * string mcode (* ; *)
  | Label         of ident * string mcode (* : *)
  | Goto          of string mcode (* goto *) * ident * string mcode (* ; *)
  | Return        of string mcode (* return *) * string mcode (* ; *)
  | ReturnExpr    of string mcode (* return *) * expression *
	             string mcode (* ; *)
  | MetaStmt      of Ast.meta_name mcode * pure
  | MetaStmtList  of Ast.meta_name mcode(*only in statement lists*) * pure
  | AsStmt        of statement * statement (* as statement, always metavar *)
  | Exp           of expression  (* only in dotted statement lists *)
  | TopExp        of expression (* for macros body *)
  | Ty            of typeC (* only at top level *)
  | TopInit       of initialiser (* only at top level *)
  | Disj          of string mcode * statement dots list *
	             string mcode list (* the |s *)  * string mcode
  | Nest          of string mcode * statement dots * string mcode *
	             (statement dots,statement) whencode list * Ast.multi
  | Dots          of string mcode (* ... *) *
                     (statement dots,statement) whencode list
  | Circles       of string mcode (* ooo *) *
	             (statement dots,statement) whencode list
  | Stars         of string mcode (* *** *) *
	             (statement dots,statement) whencode list
  | FunDecl of (info * mcodekind) (* before the function decl *) *
	fninfo list * ident (* name *) *
	string mcode (* ( *) * parameter_list * string mcode (* ) *) *
	string mcode (* { *) * statement dots *
	string mcode (* } *)
  | Include of string mcode (* #include *) * Ast.inc_file mcode (* file *)
  | Undef of string mcode (* #define *) * ident (* name *)
  | Define of string mcode (* #define *) * ident (* name *) *
	define_parameters (*params*) * statement dots
  | OptStm   of statement
  | UniqueStm of statement

and base_forinfo =
    ForExp of expression option * string mcode (*;*)
  | ForDecl of (info * mcodekind) (* before the decl *) * declaration

and forinfo = base_forinfo wrap

and fninfo =
    FStorage of Ast.storage mcode
  | FType of typeC
  | FInline of string mcode
  | FAttr of string mcode

and ('a,'b) whencode =
    WhenNot of 'a
  | WhenAlways of 'b
  | WhenModifier of Ast.when_modifier
  | WhenNotTrue of expression
  | WhenNotFalse of expression

and statement = base_statement wrap

and base_case_line =
    Default of string mcode (* default *) * string mcode (*:*) * statement dots
  | Case of string mcode (* case *) * expression * string mcode (*:*) *
	statement dots
  | DisjCase of string mcode * case_line list *
	string mcode list (* the |s *) * string mcode
  | OptCase of case_line

and case_line = base_case_line wrap

(* --------------------------------------------------------------------- *)
(* Positions *)

and meta_pos =
    MetaPos of Ast.meta_name mcode * Ast.meta_name list * Ast.meta_collect

(* --------------------------------------------------------------------- *)
(* Top-level code *)

and base_top_level =
    NONDECL of statement
  | TOPCODE of statement dots
  | CODE of statement dots
  | FILEINFO of string mcode (* old file *) * string mcode (* new file *)
  | ERRORWORDS of expression list
  | OTHER of statement (* temporary, disappears after top_level.ml *)

and top_level = base_top_level wrap
and rule = top_level list

and parsed_rule =
    CocciRule of
      (rule * Ast.metavar list *
	 (string list * string list * Ast.dependency * string * Ast.exists)) *
	(rule * Ast.metavar list) * Ast.ruletype
  | ScriptRule of string (* name *) *
      string * Ast.dependency *
	(Ast.script_meta_name * Ast.meta_name * Ast.metavar) list *
	Ast.meta_name list (*script vars*) *
	string
  | InitialScriptRule of  string (* name *) *string * Ast.dependency * string
  | FinalScriptRule of  string (* name *) *string * Ast.dependency * string

(* --------------------------------------------------------------------- *)

and dependency =
    Dep of string (* rule applies for the current binding *)
  | AntiDep of dependency (* rule doesn't apply for the current binding *)
  | EverDep of string (* rule applies for some binding *)
  | NeverDep of string (* rule never applies for any binding *)
  | AndDep of dependency * dependency
  | OrDep of dependency * dependency
  | NoDep | FailDep

(* --------------------------------------------------------------------- *)

and anything =
    DotsExprTag of expression dots
  | DotsInitTag of initialiser dots
  | DotsParamTag of parameterTypeDef dots
  | DotsStmtTag of statement dots
  | DotsDeclTag of declaration dots
  | DotsCaseTag of case_line dots
  | IdentTag of ident
  | ExprTag of expression
  | ArgExprTag of expression  (* for isos *)
  | TestExprTag of expression (* for isos *)
  | TypeCTag of typeC
  | ParamTag of parameterTypeDef
  | InitTag of initialiser
  | DeclTag of declaration
  | StmtTag of statement
  | ForInfoTag of forinfo
  | CaseLineTag of case_line
  | TopTag of top_level
  | IsoWhenTag of Ast.when_modifier
  | IsoWhenTTag of expression
  | IsoWhenFTag of expression
  | MetaPosTag of meta_pos
  | HiddenVarTag of anything list (* in iso_compile/pattern only *)

let dotsExpr x = DotsExprTag x
let dotsParam x = DotsParamTag x
let dotsInit x = DotsInitTag x
let dotsStmt x = DotsStmtTag x
let dotsDecl x = DotsDeclTag x
let dotsCase x = DotsCaseTag x
let ident x = IdentTag x
let expr x = ExprTag x
let typeC x = TypeCTag x
let param x = ParamTag x
let ini x = InitTag x
let decl x = DeclTag x
let stmt x = StmtTag x
let forinfo x = ForInfoTag x
let case_line x = CaseLineTag x
let top x = TopTag x

(* --------------------------------------------------------------------- *)
(* Avoid cluttering the parser.  Calculated in compute_lines.ml. *)

let pos_info =
  { line_start = -1; line_end = -1;
    logical_start = -1; logical_end = -1;
    column = -1; offset = -1; }

let default_info _ = (* why is this a function? *)
  { pos_info = pos_info;
    attachable_start = true; attachable_end = true;
    mcode_start = []; mcode_end = [];
    strings_before = []; strings_after = []; isSymbolIdent = false; }

let default_befaft _ =
  MIXED(ref (Ast.NOTHING,default_token_info,default_token_info))
let context_befaft _ =
  CONTEXT(ref (Ast.NOTHING,default_token_info,default_token_info))
	  let minus_befaft _ = MINUS(ref (Ast.NOREPLACEMENT,default_token_info))

let wrap x =
  { node = x;
    info = default_info();
    index = ref (-1);
    mcodekind = ref (default_befaft());
    exp_ty = ref None;
    bef_aft = NoDots;
    true_if_arg = false;
    true_if_test = false;
    true_if_test_exp = false;
    iso_info = [] }
let context_wrap x =
  { node = x;
    info = default_info();
    index = ref (-1);
    mcodekind = ref (context_befaft());
    exp_ty = ref None;
    bef_aft = NoDots;
    true_if_arg = false;
    true_if_test = false;
    true_if_test_exp = false;
    iso_info = [] }
let unwrap x = x.node
let unwrap_mcode (x,_,_,_,_,_) = x
let rewrap model x = { model with node = x }
let rewrap_mcode (_,arity,info,mcodekind,pos,adj) x =
  (x,arity,info,mcodekind,pos,adj)
let copywrap model x =
  { model with node = x; index = ref !(model.index);
    mcodekind = ref !(model.mcodekind); exp_ty = ref !(model.exp_ty)}
let get_pos (_,_,_,_,x,_) = !x
let get_pos_ref (_,_,_,_,x,_) = x
let set_pos pos (m,arity,info,mcodekind,_,adj) =
  (m,arity,info,mcodekind,ref pos,adj)
let get_info x      = x.info
let set_info x info = {x with info = info}
let get_line x      = x.info.pos_info.line_start
let get_line_end x  = x.info.pos_info.line_end
let get_index x     = !(x.index)
let set_index x i   = x.index := i
let get_mcodekind x = !(x.mcodekind)
let get_mcode_mcodekind (_,_,_,mcodekind,_,_) = mcodekind
let get_mcodekind_ref x = x.mcodekind
let set_mcodekind x mk  = x.mcodekind := mk
let set_type x t        = x.exp_ty := t
let get_type x          = !(x.exp_ty)
let get_dots_bef_aft x  = x.bef_aft
let set_dots_bef_aft x dots_bef_aft = {x with bef_aft = dots_bef_aft}
let get_arg_exp x       = x.true_if_arg
let set_arg_exp x       = {x with true_if_arg = true}
let get_test_pos x      = x.true_if_test
let set_test_pos x      = {x with true_if_test = true}
let get_test_exp x      = x.true_if_test_exp
let set_test_exp x      = {x with true_if_test_exp = true}
let get_iso x           = x.iso_info
let set_iso x i = if !Flag.track_iso_usage then {x with iso_info = i} else x
let set_mcode_data data (_,ar,info,mc,pos,adj) = (data,ar,info,mc,pos,adj)

(* --------------------------------------------------------------------- *)

let rec meta_pos_name = function
    HiddenVarTag(vars) ->
	(* totally fake, just drop the rest, only for isos *)
      meta_pos_name (List.hd vars)
  | MetaPosTag(MetaPos(name,constraints,_)) -> name
  | IdentTag(i) ->
      (match unwrap i with
	MetaId(name,constraints,seed,pure) -> name
      | _ -> failwith "bad metavariable")
  | ExprTag(e) ->
      (match unwrap e with
	MetaExpr(name,constraints,ty,form,pure) -> name
      | MetaExprList(name,len,pure) -> name
      | _ -> failwith "bad metavariable")
  | TypeCTag(t) ->
      (match unwrap t with
	MetaType(name,pure) -> name
      | _ -> failwith "bad metavariable")
  | DeclTag(d) ->
      (match unwrap d with
	MetaDecl(name,pure) -> name
      | _ -> failwith "bad metavariable")
  | InitTag(i) ->
      (match unwrap i with
	MetaInit(name,pure) -> name
      | _ -> failwith "bad metavariable")
  | StmtTag(s) ->
      (match unwrap s with
	MetaStmt(name,pure) -> name
      | _ -> failwith "bad metavariable")
  | _ -> failwith "bad metavariable"

(* --------------------------------------------------------------------- *)

(* unique indices, for mcode and tree nodes *)
let index_counter = ref 0
let fresh_index _ = let cur = !index_counter in index_counter := cur + 1; cur

(* --------------------------------------------------------------------- *)

let undots d =
  match unwrap d with
  | DOTS    e -> e
  | CIRCLES e -> e
  | STARS   e -> e

(* --------------------------------------------------------------------- *)

let rec ast0_type_to_type ty =
  match unwrap ty with
    ConstVol(cv,ty) -> TC.ConstVol(const_vol cv,ast0_type_to_type ty)
  | BaseType(bty,strings) ->
      TC.BaseType(baseType bty)
  | Signed(sgn,None) ->
      TC.SignedT(sign sgn,None)
  | Signed(sgn,Some ty) ->
      let bty = ast0_type_to_type ty in
      TC.SignedT(sign sgn,Some bty)
  | Pointer(ty,_) -> TC.Pointer(ast0_type_to_type ty)
  | FunctionPointer(ty,_,_,_,_,params,_) ->
      TC.FunctionPointer(ast0_type_to_type ty)
  | FunctionType _ -> TC.Unknown (*failwith "not supported"*)
  | Array(ety,_,_,_) -> TC.Array(ast0_type_to_type ety)
  | EnumName(su,Some tag) ->
      (match unwrap tag with
	Id(tag) ->
	  TC.EnumName(TC.Name(unwrap_mcode tag))
      | MetaId(tag,_,_,_) ->
	  (Common.pr2_once
	     "warning: enum with a metavariable name detected.";
	   Common.pr2_once
	     "For type checking assuming the name of the metavariable is the name of the type\n";
	   TC.EnumName(TC.MV(unwrap_mcode tag,TC.Unitary,false)))
      | _ -> failwith "unexpected enum type name")
  | EnumName(su,None) -> TC.EnumName TC.NoName
  | EnumDef(ty,_,_,_) -> ast0_type_to_type ty
  | StructUnionName(su,Some tag) ->
      (match unwrap tag with
	Id(tag) ->
	  TC.StructUnionName(structUnion su,TC.Name(unwrap_mcode tag))
      | MetaId(tag,Ast.IdNoConstraint,_,_) ->
	  (Common.pr2_once
	     "warning: struct/union with a metavariable name detected.";
	   Common.pr2_once
	     "For type checking assuming the name of the metavariable is the name of the type\n";
	   TC.StructUnionName(structUnion su,
			      TC.MV(unwrap_mcode tag,TC.Unitary,false)))
      | MetaId(tag,_,_,_) ->
	  (* would have to duplicate the type in type_cocci.ml?
	     perhaps polymorphism would help? *)
	  failwith "constraints not supported on struct type name"
      | _ -> failwith "unexpected struct/union type name")
  | StructUnionName(su,None) -> TC.StructUnionName(structUnion su,TC.NoName)
  | StructUnionDef(ty,_,_,_) -> ast0_type_to_type ty
  | TypeName(name) -> TC.TypeName(unwrap_mcode name)
  | MetaType(name,_) ->
      TC.MetaType(unwrap_mcode name,TC.Unitary,false)
  | AsType(ty,asty) -> failwith "not created yet"
  | DisjType(_,types,_,_) ->
      Common.pr2_once
	"disjtype not supported in smpl type inference, assuming unknown";
      TC.Unknown
  | OptType(ty) | UniqueType(ty) ->
      ast0_type_to_type ty

and baseType = function
    Ast.VoidType -> TC.VoidType
  | Ast.CharType -> TC.CharType
  | Ast.ShortType -> TC.ShortType
  | Ast.ShortIntType -> TC.ShortIntType
  | Ast.IntType -> TC.IntType
  | Ast.DoubleType -> TC.DoubleType
  | Ast.LongDoubleType -> TC.LongDoubleType
  | Ast.FloatType -> TC.FloatType
  | Ast.LongType -> TC.LongType
  | Ast.LongIntType -> TC.LongIntType
  | Ast.LongLongType -> TC.LongLongType
  | Ast.LongLongIntType -> TC.LongLongIntType
  | Ast.SizeType -> TC.SizeType
  | Ast.SSizeType -> TC.SSizeType
  | Ast.PtrDiffType -> TC.PtrDiffType

and structUnion t =
  match unwrap_mcode t with
    Ast.Struct -> TC.Struct
  | Ast.Union -> TC.Union

and sign t =
  match unwrap_mcode t with
    Ast.Signed -> TC.Signed
  | Ast.Unsigned -> TC.Unsigned

and const_vol t =
  match unwrap_mcode t with
    Ast.Const -> TC.Const
  | Ast.Volatile -> TC.Volatile

(* --------------------------------------------------------------------- *)
(* this function is a rather minimal attempt.  the problem is that information
has been lost.  but since it is only used for metavariable types in the isos,
perhaps it doesn't matter *)
and make_mcode x = (x,NONE,default_info(),context_befaft(),ref [],-1)
let make_mcode_info x info = (x,NONE,info,context_befaft(),ref [],-1)
and make_minus_mcode x =
  (x,NONE,default_info(),minus_befaft(),ref [],-1)

exception TyConv

let rec reverse_type ty =
  match ty with
    TC.ConstVol(cv,ty) ->
      ConstVol(reverse_const_vol cv,context_wrap(reverse_type ty))
  | TC.BaseType(bty) ->
      BaseType(reverse_baseType bty,[(* not used *)])
  | TC.SignedT(sgn,None) -> Signed(reverse_sign sgn,None)
  | TC.SignedT(sgn,Some bty) ->
      Signed(reverse_sign sgn,Some (context_wrap(reverse_type ty)))
  | TC.Pointer(ty) ->
      Pointer(context_wrap(reverse_type ty),make_mcode "*")
  | TC.EnumName(TC.MV(name,_,_)) ->
      EnumName
	(make_mcode "enum",
	 Some (context_wrap(MetaId(make_mcode name,Ast.IdNoConstraint,Ast.NoVal,
				   Impure))))
  | TC.EnumName(TC.Name tag) ->
      EnumName(make_mcode "enum",Some(context_wrap(Id(make_mcode tag))))
  | TC.StructUnionName(su,TC.MV(name,_,_)) ->
      (* not right?... *)
      StructUnionName
	(reverse_structUnion su,
	 Some(context_wrap(MetaId(make_mcode name,Ast.IdNoConstraint,Ast.NoVal,
				  Impure(*not really right*)))))
  |  TC.StructUnionName(su,TC.Name tag) ->
      StructUnionName
	(reverse_structUnion su,
	 Some (context_wrap(Id(make_mcode tag))))
  | TC.TypeName(name) -> TypeName(make_mcode name)
  | TC.MetaType(name,_,_) ->
      MetaType(make_mcode name,Impure(*not really right*))
  | _ -> raise TyConv

and reverse_baseType = function
    TC.VoidType -> Ast.VoidType
  | TC.CharType -> Ast.CharType
  | TC.BoolType -> Ast.IntType
  | TC.ShortType -> Ast.ShortType
  | TC.ShortIntType -> Ast.ShortIntType
  | TC.IntType -> Ast.IntType
  | TC.DoubleType -> Ast.DoubleType
  | TC.LongDoubleType -> Ast.LongDoubleType
  | TC.FloatType -> Ast.FloatType
  | TC.LongType -> Ast.LongType
  | TC.LongIntType -> Ast.LongIntType
  | TC.LongLongType -> Ast.LongLongType
  | TC.LongLongIntType -> Ast.LongLongIntType
  | TC.SizeType -> Ast.SizeType
  | TC.SSizeType -> Ast.SSizeType
  | TC.PtrDiffType -> Ast.PtrDiffType


and reverse_structUnion t =
  make_mcode
    (match t with
      TC.Struct -> Ast.Struct
    | TC.Union -> Ast.Union)

and reverse_sign t =
  make_mcode
    (match t with
      TC.Signed -> Ast.Signed
    | TC.Unsigned -> Ast.Unsigned)

and reverse_const_vol t =
  make_mcode
    (match t with
      TC.Const -> Ast.Const
    | TC.Volatile -> Ast.Volatile)

(* --------------------------------------------------------------------- *)

let lub_pure x y =
  match (x,y) with
    (Impure,_) | (_,Impure) -> Impure
  | (Pure,Context) | (Context,Pure) -> Impure
  | (Pure,_) | (_,Pure) -> Pure
  | (_,Context) | (Context,_) -> Context
  | _ -> PureContext

(* --------------------------------------------------------------------- *)

let rule_name = ref "" (* for the convenience of the parser *)
