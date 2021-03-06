(* Copyright 2013 Matthieu Lemerre *)

(* This module implements the TDOP-based parser of L definitions. *)

(*p \include{../../../doc/grammardefs} *)

open Common;;
open Token.With_info;;

(****************************************************************)
(*s Definitions and declarations (except definitions of modules). *)

(* \begin{grammar}
   \item $\call{def} ::= \tok{def}_{\textrm{\textvisiblespace}}^{\textrm{\textvisiblespace}}\ \call{id}\ {}^{\textrm{\textvisiblespace}}\tok{=}^{\backslash{}n}\ \call{expression}$
   \end{grammar} *)
let parse_def stream =
  let def = Token.Stream.next stream in
  expect def Kwd.def ~after_min:Sep.Normal ~after_max:Sep.Normal;
  let patt = Expression.parse_expression stream in
  expect (Token.Stream.next stream) Kwd.equals ~before_max:Sep.Normal ~after_max:Sep.Strong;
  let exp = Expression.parse_expression stream in
  { P.func = P.Token def;
    P.arguments = [patt;exp];
    P.location = P.between_tok_term def exp }
;;

(* \begin{grammar}
   \item $\call{declare} ::= \tok{declare}_{\textrm{\textvisiblespace}}^{\textrm{\textvisiblespace}}\ \call{id}\tok{::}\call{type}$
   \end{grammar}

   Note: declare is temporary. Will surely be replaced with "def
   id::type." *)
let parse_declare stream =
  let declare = Token.Stream.next stream in
  expect declare Kwd.declare ~after_min: Sep.Normal ~after_max:Sep.Normal;
  let id = Token.Stream.next stream in
  expect_id id;
  expect (Token.Stream.next stream) Kwd.doublecolon ~before_max:Sep.Stuck ~after_max:Sep.Stuck;
  let typ = Path.parse_type stream in
  { P.func = P.Token declare;
    P.arguments = [P.single id;typ];
    P.location = P.between_tok_term declare typ }

let r_parse_module_definition = ref (fun _ -> assert false);;

(* \begin{grammar}
   \item $\call{definition} ::= \\
   \alt \call{def}\\
   \alt \call{declare}\\
   \alt \call{module\_definition}$
   \end{grammar} *)
let parse_definition stream =
  let {token=first_token} = Token.Stream.peek stream in
  match first_token with
    | k when k = Kwd.def -> parse_def stream
    | k when k = Kwd.declare -> parse_declare stream
    | k when k = Kwd.module_ -> !r_parse_module_definition stream
    | _ -> let exp = Expression.parse_expression stream in
           { P.func = P.Custom "expr";
             P.arguments = [ exp ];
             P.location = exp.P.location
           }
;;


(****************************************************************)
(*s "data" declarations. *)

(* Type arguments to constructors. Arguments are optionally named,
   i.e. each argument may be of the form [type] or [ident::type]. Note
   that the [Constructor()] construct is not allowed; to have no
   arguments, one has to write just [Constructor]. *)
(* \begin{grammar}
  \item $\call{constructor\_argument} ::=
    ( \call{id} \tok{::}^\nleftrightarrow \alt \epsilon)\ \call{type}$
  \item $\call{constructor\_arguments} ::=\\
   \quad\tok{(}^{\backslash{}n} \call{constructor\_argument}\ ( {}^{\textrm{\textvisiblespace}}\tok{,}^{\backslash{}n}\ {constructor\_argument} )* {}^{\backslash{}n}\tok{)}$
  \end{grammar} *)
let parse_constructor_arguments stream =
  let lparen = Token.Stream.next stream in
  expect lparen Kwd.lparen ~after_max:Sep.Strong;
  let parse_one_argument stream =
    let maybe_arg = Token.Stream.peek stream in
    let maybe_dcolon = Token.Stream.peek_nth stream 1 in
    match maybe_arg.token with
    | Token.Ident x when maybe_dcolon.token = Kwd.doublecolon ->
      Token.Stream.junk stream; Token.Stream.junk stream;
      expect maybe_dcolon Kwd.doublecolon ~before_max:Sep.Stuck ~after_max:Sep.Stuck;
      let typ = Path.parse_type stream in
      P.infix_binary_op (P.single maybe_arg) maybe_dcolon typ
    | _ -> Path.parse_type stream
  in
  let l = parse_comma_separated_list stream parse_one_argument in
  let rparen = Token.Stream.next stream in
  expect rparen Kwd.rparen ~before_max:Sep.Strong;
  P.delimited_list lparen l rparen
;;

(* \begin{grammar}
   \item $\call{constructor} ::= \call{upper\_id}\call{constructor\_arguments}$
   \end{grammar} *)
let parse_constructor stream =
  let tok = Token.Stream.next stream in
  expect_id tok;
  if ((Token.Stream.peek stream).token = Kwd.lparen)
  then let arguments = parse_constructor_arguments stream in
       { P.func = P.Token tok;
         P.arguments = [arguments];
         P.location = P.between_tok_term tok arguments}
  else P.single tok
;;

(*\begin{grammar}
  \item $\call{data} ::= \tok{data}^{\textrm{\textvisiblespace}}\ \tok{\{}^{\backslash{}n} \call{constructor} ({}_{\backslash{}n} \call{constructor} )* {}^{\backslash{}n}\tok{\}}$
  \end{grammar} *)
let parse_data stream =
  let parse_constructors stream =
    let tok = Token.Stream.next stream in
    expect tok Kwd.lbrace ~after_max:Sep.Strong;
    let first = parse_constructor stream in
    let rest = ref [] in
    while (Token.Stream.peek stream).token <> Kwd.rbrace do
      expect_strong_separation stream;
      rest := (parse_constructor stream)::!rest;
    done ;
    let end_tok = Token.Stream.next stream in
    expect end_tok Kwd.rbrace ~before_max:Sep.Strong;
    P.delimited_list tok (first::(List.rev !rest)) end_tok
  in
  let data = Token.Stream.next stream in
  (*i MAYBE: Change after_max to Stuck here? i*)
  expect data Kwd.data ~after_max:Sep.Normal;
  let constructors = parse_constructors stream in
  { P.func = P.Token data;
    P.arguments = [constructors];
    P.location = P.between_tok_term data constructors }

;;

(****************************************************************)
(*s Definition of modules.  *)

(* \begin{grammar}
   \item $\call{module\_implementation} ::= \tok{\{}^{\backslash{}n} (\epsilon \alt
   \call{definition}\ ({}_{\backslash{}n}\call{definition})* ) {}^{\backslash{}n}\tok{\}}$
   \end{grammar} *)
let parse_module_implementation stream =
  let lbrace = Token.Stream.next stream in
  expect lbrace Kwd.lbrace ~after_max:Sep.Strong;
  if (Token.Stream.peek stream).token = Kwd.rbrace
  then let rbrace = Token.Stream.next stream in
       expect rbrace Kwd.rbrace ~before_max:Sep.Strong;
       P.delimited_list lbrace [] rbrace
  else
    let def = parse_definition stream in
    let defs = ref [def] in
    while((Token.Stream.peek stream).token <> Kwd.rbrace) do
      expect_strong_separation stream;
      let def = parse_definition stream in
      defs := def::!defs;
    done;
    let rbrace = Token.Stream.next stream in
    expect rbrace Kwd.rbrace ~before_max:Sep.Strong;
    let modul = P.delimited_list lbrace (List.rev !defs) rbrace in
    modul
;;

(* \begin{grammar}
   \item $\call{module\_expr} ::=\\
   \alt \call{module\_implementation}\\
   \alt \call{data}\\
   \alt \call{path\_allow\_type\_constr}$
   \end{grammar} *)
let parse_module_expr stream =
  match (Token.Stream.peek stream) with
  | t when t.token = Kwd.lbrace -> parse_module_implementation stream
  | t when t.token = Kwd.data -> parse_data stream
  | _ -> Path.parse_path_allow_type_constr stream
;;

(* \begin{grammar}
   \item $\call{module\_def\_args} ::= \tok{<}^{\backslash{}n} \call{upper\_id}
   ({}^{\textrm{\textvisiblespace}}\tok{,}^{\backslash{}n} \call{upper\_id})* {}^{\backslash{}n}\tok{>}$\\
   \item $\call{module\_definition} ::=
   \tok{module}_{\textrm{\textvisiblespace}}^{\textrm{\textvisiblespace}}\ \call{upper\_id}\call{module\_def\_args}?\ {}^{\textrm{\textvisiblespace}}\tok{=}^{\backslash{}n}\ \call{module\_expr}$
   \end{grammar}

   Note that we do not allow empty list of module args. It does not
   really makes sense when all functors are applicative. *)
let parse_module_definition stream =
  let module_def_args stream =
    let lt = Token.Stream.next stream in
    expect lt Kwd.lt ~after_max:Sep.Strong;
    let l =
      parse_comma_separated_list stream
        (fun stream -> let id = Token.Stream.next stream in
                       expect_id id; P.single id) in
    let gt = Token.Stream.next stream in
    expect gt Kwd.gt ~before_max:Sep.Strong;
    P.delimited_list lt l gt
  in
  let modul_tok = Token.Stream.next stream in
  expect modul_tok  Kwd.module_ ~after_min:Sep.Normal ~after_max:Sep.Normal;
  let module_ = Token.Stream.next stream in
  expect_id module_;
  let module_ = P.single module_ in
  let module_args =
    if((Token.Stream.peek stream).token = Kwd.lt)
    then let args = module_def_args stream in
         { P.func = P.Custom "modapply";
           P.arguments = [ module_; args ];
           P.location = P.between_terms module_ args }
    else module_
  in
  expect (Token.Stream.next stream) Kwd.equals
    ~before_max:Sep.Normal ~after_max:Sep.Strong;
  let body = parse_module_expr stream in
  { P.func = P.Token modul_tok;
    P.arguments = [module_args; body ];
    P.location = P.between_tok_term modul_tok body
  }
;;

r_parse_module_definition := parse_module_definition;;

(****************************************************************)
(*s External interface for the parser.  *)
let maybe_parse_term stream =
  if (Token.Stream.peek stream).token = Token.End
  then None
  else Some(parse_definition stream)

let definition_stream stream =
  Stream.from (fun _ -> maybe_parse_term stream)
