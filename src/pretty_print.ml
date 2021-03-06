(* Copyright 2013 Matthieu Lemerre *)

(* Pretty print L code in various output formats.
   To use, type ./src/main.run --pretty file.l
*)

module type PRINT = sig
  val newline: unit -> unit
  val space: unit -> unit
  val semicolon: unit -> unit
  val token: Token.token -> unit
end

(* This is an HTML printer.  *)
module PrintHtml = struct
  let newline() = print_string "<br />\n";;
  let space() = print_string "&nbsp;";;
  let token token =
    let string = Token.to_string token in
    let print_in_span class_ =
      print_string "<span class=\"";
      print_string class_;
      print_string "\">";
      print_string string;
      print_string "</span>"
    in
    match token with
    | Token.Int(_) -> print_in_span "mi"
    | Token.Ident(_) when
        let a = Token.to_string token in
        let c = String.get a 0 in
        let code = Char.code c in
        (Char.code 'A') <= code && code <= (Char.code 'Z') ->
      print_in_span "nv"
    | Token.Ident(_) -> print_string (Token.to_string token)
    | Token.String(_) -> print_in_span "s"
    | Token.Keyword(_) when token = Token.Keywords.arrow ->
      print_string "&rarr;"
    | Token.Keyword(_) ->
      let class_ =
        if token = Token.Keywords.let_ then "kd"
        else if token = Token.Keywords.def then "kd"
        else if token = Token.Keywords.declare then "kd"
        else if token = Token.Keywords.module_ then "kd"
        else if token = Token.Keywords.data then "kd"
        else if token = Token.Keywords.if_ then "kr"
        else if token = Token.Keywords.else_ then "kr"
        else if token = Token.Keywords.match_ then "kr"
        else "" in
      print_in_span class_
  ;;
  let semicolon() = print_string ";"

end


(* This is an ASCII printer. *)
module PrintAscii = struct
  let newline() = print_string "\n";;
  let space() = print_string " ";;
  let semicolon() = print_string ";"
  let token token =
    let string = Token.to_string token in
    print_string string;;

end

(* TODO: Add a hook in the parser to provide informations such as "is
   it allowed to cut after/before this symbol", and use spans to
   highlight the parsing algorithm. Use a parsetree with zipper for that.  *)

module Pretty(Print:PRINT) = struct

  let pretty file =
    let stream = Token.Stream.make file in
    let tok = ref (Token.Stream.next stream) in
    let cur_coords = ref (0,0) in

    let position_to_coords pos =
      let open Lexing in
      (pos.pos_lnum, pos.pos_cnum - pos.pos_bol)
    in
    (* Print \n and/or spaces until cur_coords is reached. *)
    (* Note: this is ugly, and cause comments to be forgotten. I should
       have a "next_with_spacing" in the lexer instead, that would also
       return the contents of the blank before the token. *)
    let update_coordinates (cur_line, cur_col) pos =
      let (line,col) = position_to_coords pos in
      assert ((cur_line < line) || (cur_line == line && cur_col <= col));

      let cur_line = ref cur_line and cur_col = ref cur_col in
      while !cur_line != line do
        Print.newline();
        incr cur_line;
        cur_col := 0;
      done;
      while !cur_col != col do
        Print.space();
        incr cur_col
      done;
      (line,col)
    in
    let incr_coordinates (cur_line, cur_col) string =
      (cur_line, cur_col + String.length string)
    in

    while (!tok).Token.With_info.token != Token.End do
      let (start_pos,_) = (!tok).Token.With_info.location in
      cur_coords := update_coordinates !cur_coords start_pos;
      let token = (!tok).Token.With_info.token in
      Print.token token;
      let string = (Token.to_string token) in
      cur_coords := incr_coordinates !cur_coords string;
      if !tok.Token.With_info.separation_after = Token.Separation.Explicit
      then (Print.semicolon(); cur_coords := incr_coordinates !cur_coords ";");
      tok := Token.Stream.next stream
    done
  ;;
end
;;

module PrettyHtml = Pretty(PrintHtml);;

let print_html file =
  Printf.printf "<!DOCTYPE html>
<html>
    <head>
    <meta charset=\"utf-8\">
    <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">
    <title>File %s</title>
    <link href=\"syntax.css\" rel=\"stylesheet\" media=\"screen\">
    </head>
    <body>
      <div class=\"highlight\" style=\"font-family:monospace\">
" file;
  PrettyHtml.pretty file;
  print_string "</div></body></html>"
;;
